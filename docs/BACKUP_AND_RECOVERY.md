# BACKUP_AND_RECOVERY.md

## 0. Estado de este documento
- Etapa del proceso: 12 — Backup y recuperación
- Estado: En análisis (propuesta completa, pendiente de tu validación)
- Última actualización: 2026-07-27
- Depende de: Etapa 2 (RPO/RTO), Etapa 5 (modelo de datos, borrado lógico), Etapa 8 (amenaza "acceso indebido a backups"), Etapa 9 (proveedor de BD)
- Bloquea: Etapa 15 (mantenimiento continuo se apoya en los simulacros aquí definidos)

## 1. Decisiones tomadas en esta etapa

| Decisión | Elegido |
|---|---|
| Mecanismo principal | PITR nativo de DigitalOcean Managed PostgreSQL (7 días) |
| Redundancia entre proveedores | `pg_dump` cifrado adicional a Hetzner Object Storage (semanal/mensual) — un segundo proveedor, no solo el nativo de DO |
| Retención en capas | Diaria (DO, 7 días) + semanal (Hetzner, 4 semanas) + mensual (Hetzner, 12 meses) |
| Cifrado del `pg_dump` externo | `age` (cifrado asimétrico simple), clave de descifrado solo en el gestor de secretos, nunca en la VPS |
| Redis | Sin backup de negocio (ya decidido en Etapa 9 — solo AOF para recuperación de caída, no continuidad) |
| Almacenamiento de objetos | Sin backup dedicado en el MVP — el bucket está prácticamente vacío hasta que V2/Futuro use S3 de verdad (informes, adjuntos); se apoya en la redundancia propia del proveedor mientras tanto |
| Estado de Terraform | Remoto (bucket de Hetzner Object Storage con locking), nunca solo en un portátil |
| Restauración selectiva por organización | Procedimiento propio (sección 6) — un PITR normal restaura *toda* la base de datos, inaceptable para recuperar los datos de una sola organización en un sistema multitenant |

## 2. Qué se respalda (y qué no)

| Elemento | ¿Se respalda? | Mecanismo |
|---|---|---|
| PostgreSQL (todo el esquema, incluida `telemetry`) | Sí | Sección 3 |
| Terraform state | Sí | Remoto con locking (Hetzner Object Storage) |
| Redis | No (solo AOF local) | Reprocesable vía reintentos/idempotencia (Etapa 6/7) |
| Object storage (S3-compatible) | No en el MVP | Prácticamente sin uso todavía; se revisita cuando V2 lo use de verdad |
| Secretos (claves JWT, credenciales) | Redundancia propia del gestor de secretos | GitHub Actions Environments ya está alojado de forma redundante por GitHub |
| Imágenes Docker | No hace falta backup — reconstruibles desde el código fuente (Git) en cualquier momento | — |

## 3. Mecanismo de backup de PostgreSQL
- **Capa 1 — PITR nativo (DigitalOcean Managed Postgres)**: WAL continuo + snapshot diario, recuperación a cualquier segundo dentro de los últimos 7 días. Cubre el RPO de `NON_FUNCTIONAL_REQUIREMENTS.md` (≤15 min negocio, ≤5 min telemetría) con margen amplio.
- **Capa 2 — `pg_dump` cifrado a Hetzner Object Storage**, independiente del proveedor de base de datos:
  - Semanal, retenido 4 semanas.
  - Mensual, retenido 12 meses.
  - Cifrado con `age` antes de subir — la clave privada de descifrado vive únicamente en el gestor de secretos (`DEPLOYMENT.md` sección 4), nunca en la VPS que ejecuta el `pg_dump`.
  - Motivo de la capa 2: si DigitalOcean tuviera un incidente que afectase a los propios backups (cuenta comprometida, fallo del proveedor), existe una copia completamente independiente en otro proveedor — nunca todo el respaldo depende de un único proveedor.

## 4. Control de acceso a los backups
- Solo un rol operativo dedicado (no el rol de aplicación de `api`/`worker`, `DATA_MODEL.md` sección 7) puede ejecutar el `pg_dump` de la capa 2 y leer el bucket de backups.
- Restaurar (no solo leer) requiere aprobación de un Admin de plataforma — mismo nivel de control que un despliegue a producción (`DEPLOYMENT.md` sección 9), nunca una acción de un solo clic sin revisión.
- Ningún backup se restaura jamás directamente sobre la base de datos en producción sin pasar primero por una instancia aislada de verificación (sección 5).

## 5. Restauración completa (disaster recovery)
1. Se declara un incidente de pérdida/corrupción de datos (`INCIDENT_RESPONSE.md`).
2. Se restaura el PITR de DO (o, si DO no está disponible, el `pg_dump` cifrado más reciente de Hetzner) en una **instancia nueva y aislada**, nunca sobre la existente.
3. Verificación de integridad: recuento de filas de tablas clave (`organizations`, `members`, `telemetry` del último día) y comparación con las métricas de `OBSERVABILITY.md` — no se da por buena la restauración solo porque el proceso "terminó sin error".
4. Cambio de `DATABASE_URL` (secreto, `DEPLOYMENT.md` sección 4) a la instancia restaurada, redistribución a `api`/`worker`.
5. Postmortem obligatorio (`INCIDENT_RESPONSE.md` sección 6).

## 6. Restauración selectiva por organización
Un PITR estándar (sección 5) restaura **toda** la base de datos a un instante — correcto para un desastre general, pero **inaceptable** para recuperar el error de una sola organización (p. ej. un fallo de la aplicación que borró filas sin pasar por el borrado lógico) a costa de retroceder a todas las demás.
- Procedimiento: restaurar el punto anterior al incidente en una instancia aislada (igual que la sección 5), extraer únicamente las filas de la organización afectada (`pg_dump --table` con filtro por `organization_id`, o una consulta de exportación dirigida) y reinsertarlas en la base de datos en producción, respetando el orden de claves foráneas.
- Es un procedimiento manual y poco frecuente por diseño — no se automatiza en el MVP; el borrado lógico (sección 7) ya cubre el caso más común sin necesitar llegar hasta aquí.

## 7. Borrado lógico como primera línea de defensa
La mayoría de "pérdida de datos" accidental (un Admin de organización borra una instalación o un miembro por error) **no necesita** ni backup ni restauración: casi todas las tablas de negocio tienen `deleted_at` (`DATA_MODEL.md`) — recuperar es revertir esa marca, una operación de segundos, no un procedimiento de horas. El backup/restauración completo (secciones 5-6) es exclusivamente para corrupción de la base de datos, fallo del proveedor, o manipulación directa que se salte la capa de aplicación — no para el error de usuario cotidiano.

## 8. Validación de RPO/RTO
| Objetivo (Etapa 2) | Cómo se cumple |
|---|---|
| RPO ≤ 15 min (negocio) | WAL continuo de DO (capa 1) |
| RPO ≤ 5 min (telemetría) | Mismo mecanismo — telemetría vive en la misma base de datos, no necesita un camino de backup separado |
| RTO ≤ 4 horas | Validado en el simulacro mensual (sección 9); si el simulacro tarda más, es una alerta en sí misma, no solo una prueba fallida |

## 9. Simulacro mensual (mecánica completa; cadencia ya fijada en `TESTING_STRATEGY.md` sección 12)
1. Restaurar el backup más reciente (alternando capa 1/capa 2 cada vez, para probar ambas rutas) en un entorno aislado, nunca staging ni producción.
2. Cronometrar el proceso completo — debe quedar por debajo de las 4 horas de RTO.
3. Verificar integridad (recuento de filas + checksum de una muestra de `telemetry` y `audit_log`, que son las tablas de solo-inserción más sensibles a corrupción silenciosa).
4. Registrar el resultado (duración, incidencias) — si un simulacro falla o se acerca al límite de RTO, es una prioridad de la Etapa 15, no una nota para "revisar algún día".
5. **Dead man's switch** (`OBSERVABILITY.md`): el simulacro hace ping a Healthchecks.io al completarse — si no llega el ping en la ventana esperada, se alerta al equipo igual que un backup diario que no se confirmó.

## 10. Riesgos
- La restauración selectiva por organización (sección 6) es manual — un error humano al reinsertar filas podría violar una restricción de integridad (Etapa 5); mitigado por hacerlo siempre primero en una instancia aislada con las mismas restricciones activas, nunca directamente en producción.
- El bucket de Hetzner Object Storage sin backup dedicado (sección 2) es aceptable solo mientras esté prácticamente vacío — si V2 empieza a guardar informes/adjuntos reales, este documento debe revisarse antes de que "no hay backup de eso" deje de ser un riesgo trivial.

## 11. Entregables de esta etapa
- Este documento (`BACKUP_AND_RECOVERY.md`).
- [`INCIDENT_RESPONSE.md`](INCIDENT_RESPONSE.md), complementario.

## 12. Criterios de aceptación de esta etapa
- Cada objetivo de RPO/RTO de la Etapa 2 tiene un mecanismo concreto que lo satisface, no una intención.
- La restauración completa y la selectiva por organización están descritas como procedimientos distintos, con criterios claros de cuándo usar cada una.
- Ningún backup depende de un único proveedor.

## 13. Pruebas necesarias derivadas
- Ejecutar el simulacro mensual completo (sección 9) y confirmar que termina dentro de las 4 horas de RTO.
- Simular la restauración selectiva de una organización de prueba sin afectar a una segunda organización de control en la misma instancia.
- Confirmar que el rol de aplicación (`api`/`worker`) no tiene permiso para leer el bucket de backups de Hetzner.
- Provocar que el simulacro mensual no se ejecute y confirmar que Healthchecks.io dispara la alerta correspondiente.

## 14. Lista de tareas de esta etapa
- [x] Diseñar el mecanismo de backup en dos capas (DO + Hetzner) con retención escalonada.
- [x] Definir restauración completa y selectiva por organización como procedimientos distintos.
- [x] Conectar el simulacro mensual con el dead man's switch de Observabilidad.
- [ ] Revisión y validación por tu parte.
- [ ] Cerrar etapa y pasar a Etapa 13 (desarrollo backend).

## 15. Dependencias
- Depende de Etapas 2, 5, 8, 9, 10, 11.
- Bloquea Etapa 15 (mantenimiento continuo revisa mensualmente el resultado de estos simulacros).

## 16. Aspectos que se aplazan explícitamente
- Backup dedicado de almacenamiento de objetos — cuando V2 lo use de verdad.
- Automatización completa de la restauración selectiva por organización — se mantiene manual mientras sea poco frecuente.

## 17. Errores frecuentes a evitar
- No restaurar nunca un backup directamente sobre producción sin pasar antes por una instancia aislada de verificación.
- No usar un PITR completo para arreglar el error de un solo usuario — el borrado lógico ya lo resuelve en segundos (sección 7).
- No dar por buena la existencia de un backup sin haberlo restaurado alguna vez — un backup nunca probado no es un backup, es una suposición.
- No dejar el estado de Terraform solo en una máquina local.

## 18. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | Backup en dos capas: PITR nativo de DO + `pg_dump` cifrado a Hetzner | Confiar solo en el backup nativo del proveedor de base de datos |
| 2026-07-27 | Restauración selectiva por organización como procedimiento propio | Restaurar siempre toda la base de datos (inaceptable en multitenant) |
| 2026-07-27 | Sin backup dedicado de almacenamiento de objetos en el MVP | Configurar un backup completo para un bucket casi vacío (coste sin beneficio actual) |
