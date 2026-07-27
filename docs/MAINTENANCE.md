# MAINTENANCE.md

## 0. Estado de este documento
- Etapa del proceso: 15 — Mantenimiento y operación continua (última del proceso 0-15)
- Estado: En análisis (propuesta completa, pendiente de tu validación)
- Última actualización: 2026-07-27
- Depende de: todas las etapas anteriores — este documento no toma decisiones nuevas de arquitectura o producto, **consolida** cadencias y umbrales ya fijados en `SECURITY.md`, `DEPLOYMENT.md`, `BACKUP_AND_RECOVERY.md`, `TESTING_STRATEGY.md`, `OBSERVABILITY.md`, `NON_FUNCTIONAL_REQUIREMENTS.md` y `INCIDENT_RESPONSE.md`, y añade lo que faltaba: un calendario único y un criterio explícito de "cuándo reabrir una decisión ya tomada".
- Bloquea: nada — es la última etapa del proceso de diseño/construcción original.

## 1. Objetivo de esta etapa

Varios documentos anteriores dejaron referencias del tipo "rotación manual programada... como parte del mantenimiento operativo (Etapa 15)" (`SECURITY.md` §9) o "se revisará si la escala crece un orden de magnitud" (`NON_FUNCTIONAL_REQUIREMENTS.md` §6, §10) sin un lugar único donde aterricen. El objetivo aquí es dar ese lugar: un calendario operativo concreto y una lista de disparadores ("tripwires") que digan, sin ambigüedad, cuándo una decisión ya tomada debe reabrirse — para un equipo de 3-6 personas que no tiene un rol de SRE dedicado.

## 2. Calendario de mantenimiento recurrente

Ninguna cadencia aquí es nueva — se referencia el documento donde ya se decidió, solo se junta en un único calendario:

| Frecuencia | Tarea | Ya decidido en |
|---|---|---|
| Cada PR | Escaneo de dependencias (`npm audit`/Dependabot, `dart pub outdated`/`osv-scanner`, Trivy en imagen Docker); tests unitarios; lint/format | `SECURITY.md` §10, `TESTING_STRATEGY.md` §2 |
| Semanal | Re-ejecución del escaneo de dependencias aunque no haya PRs (dependencias transitivas con CVEs nuevas) | `SECURITY.md` §10 |
| Mensual | Simulacro de restauración de backup en entorno aislado (verificación de integridad, dentro del RTO de 4h) | `BACKUP_AND_RECOVERY.md` §9 |
| Mensual | Prueba de migración pendiente contra el último backup de producción restaurado (detecta migraciones lentas/bloqueantes con datos reales) | `TESTING_STRATEGY.md` §9 |
| Cada 90 días | Rotación manual de credenciales de infraestructura (BD, SMTP, admin de EMQX) — **no** de credenciales de gateway, que tienen su propio ciclo de vida (hash + rotación bajo demanda, `DATA_MODEL.md`) | `DEPLOYMENT.md` §9 |
| Automático, revisar mensualmente que no haya fallado | Renovación de certificados TLS (Let's Encrypt vía Caddy y vía `acme.sh`/EMQX) | `DEPLOYMENT.md` §7 |
| Trimestral | Revisión de coste de infraestructura (Hetzner + DO + Object Storage) frente al presupuesto de 100-500€/mes fijado en `NON_FUNCTIONAL_REQUIREMENTS.md` §1 — detectar desviaciones antes de que se acumulen varios meses | Nuevo en esta etapa |
| Trimestral | Revisión de los umbrales de escala de la sección 4 de este documento frente al volumen real (dispositivos activos, mensajes/s, GB de telemetría) | Nuevo en esta etapa |
| Cuando el equipo o la base de clientes cambie de forma significativa | Revisar si siguen vigentes las simplificaciones "sin equipo de guardia 24/7", "sin página de estado pública" (`INCIDENT_RESPONSE.md` §14) | `INCIDENT_RESPONSE.md` §14 |

## 3. Umbrales de escala — cuándo reabrir una decisión ya tomada

Consolidación de los "se revisará si..." repartidos por el resto de la documentación. Ninguno de estos umbrales, alcanzado, obliga a actuar de inmediato — obligan a **revisar el documento correspondiente con datos reales**, no a rediseñar preventivamente (principio ya fijado desde `ARCHITECTURE.md`: no sobre-diseñar sin necesidad medible).

| Umbral | Qué reabrir | Origen |
|---|---|---|
| Dispositivos activos > ~5.000 (10x la escala objetivo de 500) | Particionamiento de base de datos y estrategia de mensajería (`ARCHITECTURE.md`, `NON_FUNCTIONAL_REQUIREMENTS.md` §10) | `NON_FUNCTIONAL_REQUIREMENTS.md` §10 |
| Volumen de telemetría cruda muy por encima de ~20-22 GB/año estimados | Archivado a S3, compresión, o límite de retención de dato crudo (hoy: todo permanece en PostgreSQL particionado) | `NON_FUNCTIONAL_REQUIREMENTS.md` §6, `DATA_MODEL.md` §1 |
| Necesidad real de escalar el proceso `ingestion` a más de una réplica | Cambiar el topic de suscripción a `$share/ingestion/...` (shared subscription de MQTT) — cambio de configuración, no de esquema, ya compatible hacia atrás | ADR-0003 |
| Volumen de gateways/dispositivos que hace notar el coste de recorrer la tabla completa en el job de detección de offline | Añadir índice sobre `last_seen_at` | `DATA_MODEL.md` §6 |
| Aparece una razón real (no solo volumen) para necesitar funciones específicas de series temporales | Evaluar TimescaleDB vía ADR — hoy descartado solo por volumen, no por falta de otras razones | `NON_FUNCTIONAL_REQUIREMENTS.md` §4 |
| EMQX en una VPS compartida empieza a competir por recursos con `api`/`worker` | Mover EMQX a una VPS dedicada | `DEPLOYMENT.md` §2 |
| El equipo crece más allá de 3-6 personas, o hay un SLA contractual que lo exige | Guardia 24/7 formal, página de estado pública | `INCIDENT_RESPONSE.md` §14 |
| La organización cliente onboarding tiene volumen/tipo de dato que activa el Art. 37 RGPD | Nombrar un DPO formal | `PRIVACY.md` §14 |

## 4. Versionado y compatibilidad en despliegues

Ya fijado como principio transversal desde el inicio del proyecto ("compatibilidad hacia atrás en API/mensajes de dispositivo") — aquí se hace operativo:
- **API REST**: los cambios que rompan compatibilidad requieren una nueva versión de ruta (`/v2/...`) — nunca modificar el contrato de una ruta ya publicada (`API_DESIGN.md`/`OPENAPI.yaml`). Los cambios aditivos (campo nuevo opcional) no requieren nueva versión.
- **Protocolo MQTT**: cambios de payload requieren incrementar `schema_version` (`MQTT_PROTOCOL.md`) — el `ingestion` service debe seguir aceptando la versión anterior mientras existan gateways en campo que no se hayan actualizado (no hay forma de forzar una actualización remota de firmware en el alcance del MVP).
- **App Flutter**: sin control de versión mínima forzada en el MVP (no hay pantalla de "actualiza para continuar") — riesgo aceptado: una API que deje de ser compatible con una versión antigua de la app rompería a usuarios que no han actualizado. Mitigación: seguir la regla de compatibilidad hacia atrás de la API anterior en vez de depender de forzar actualizaciones.
- **Migraciones de base de datos**: siempre expansivas primero (añadir columna nullable, backfill, luego hacer NOT NULL en una migración posterior) — nunca un cambio que rompa el código desplegado en el instante entre migrar y desplegar el nuevo código (coherente con el principio de "sin downtime" de `DEPLOYMENT.md`).

## 5. Soporte y guardia (equipo de 3-6 personas)

- Sin guardia 24/7 formal en el MVP (ya decidido en `INCIDENT_RESPONSE.md`) — cualquier miembro del equipo puede declarar un incidente al detectarlo (por alerta de Healthchecks.io/UptimeRobot/Grafana o por aviso de un cliente).
- Canal único de aviso a clientes durante un incidente: email directo a los Admin de organización afectados (ya decidido, sin página de estado pública en el MVP).
- Este documento no crea un rol de "on-call" formal — sería sobre-ingeniería de proceso para el tamaño de equipo actual. Se marca como umbral de revisión en la sección 3.

## 6. Gestión de deuda técnica y backlog

- `BACKLOG.md` sigue siendo el único lugar donde se capturan ideas nuevas fuera de orden — este documento no lo sustituye.
- Revisión trimestral sugerida del backlog V2/Futuro (`BACKLOG.md`) para decidir si alguna entrada pasa a planificarse, coincidiendo con la revisión de costes de la sección 2 — mismo ritual, evita añadir una reunión más.
- Los "Gaps MVP" señalados explícitamente en `PRIVACY.md` §6 (portabilidad/acceso, anonimización de usuario) se marcan aquí como candidatos prioritarios de esa revisión trimestral, no como algo a resolver de inmediato.

## 7. Riesgos

- Sin un rol dedicado de operaciones, estas cadencias dependen de disciplina del equipo y no de automatización obligatoria (salvo el escaneo de dependencias en CI, que sí es automático) — riesgo de que "mensual"/"cada 90 días" se salten sin un recordatorio externo.
- Mitigación mínima recomendada, no implementada todavía: usar el mismo mecanismo de Healthchecks.io ya presente (`OBSERVABILITY.md`) para crear checks programados (cron) de las tareas de la sección 2 que no están ya atadas a CI — convertiría "hay que acordarse" en "algo avisa si no se hizo".

## 8. Entregables de esta etapa
- Este documento (`MAINTENANCE.md`).
- Consolidación de umbrales de escala dispersos en `ARCHITECTURE.md`, `DATA_MODEL.md`, `NON_FUNCTIONAL_REQUIREMENTS.md` y ADR-0003 en una única tabla de referencia (sección 3).

## 9. Criterios de aceptación de esta etapa
- [ ] Confirmas el calendario de la sección 2 (en particular la cadencia trimestral de revisión de coste/escala, que es nueva en esta etapa, no heredada).
- [ ] Confirmas que no se automatiza un recordatorio (Healthchecks.io cron) todavía y se acepta el riesgo de la sección 7 con disciplina manual en el MVP.

## 10. Pruebas necesarias derivadas
- Ninguna prueba de software nueva — esta etapa es de proceso operativo, no de código. Las pruebas relevantes (simulacro de backup, migración contra datos reales) ya están definidas y probadas en `BACKUP_AND_RECOVERY.md`/`TESTING_STRATEGY.md`.

## 11. Lista de tareas de esta etapa
- [x] Consolidar cadencias de mantenimiento ya decididas en un único calendario.
- [x] Consolidar umbrales de "cuándo reabrir una decisión" dispersos en varios documentos.
- [x] Definir la política de versionado/compatibilidad de despliegues de forma explícita (antes vivía implícita en el principio general del proyecto).
- [ ] Configurar los checks programados de Healthchecks.io sugeridos en la sección 7 (implementación real, no solo documentación — pendiente de infraestructura viva).

## 12. Dependencias
- Todas las etapas anteriores (0-14). No bloquea ninguna etapa posterior — es el cierre del proceso de diseño/construcción numerado en `PROJECT_STATUS.md`. El mantenimiento real, evidentemente, continúa de forma indefinida una vez el producto esté en producción.

## 13. Aspectos que se aplazan explícitamente
- Automatización de los recordatorios de mantenimiento (sección 7) — manual en el MVP.
- Rol de guardia/on-call formal — solo si el equipo o el SLA contractual lo exigen (sección 3).
- Página de estado pública — mismo criterio.

## 14. Errores frecuentes a evitar
- No confundir esta etapa con una etapa de diseño: no se toman aquí decisiones de arquitectura nuevas, solo se opera lo ya decidido y se fija cuándo reabrirlo.
- No dejar que "revisar trimestralmente" se convierta en "no revisar nunca" por falta de un disparador externo — de ahí la sugerencia de la sección 7, aunque no esté implementada todavía.
- No tratar un umbral de escala alcanzado (sección 3) como una emergencia que justifique saltarse el proceso de decisión con datos — el principio siempre ha sido revisar con datos reales, no reaccionar por pánico.
- No dar este documento por "terminado para siempre": a diferencia del resto de etapas, esta es la única pensada para reabrirse periódicamente por diseño (sección 2).

## 15. Historial de decisiones de esta etapa
- 2026-07-27: primera versión, cierra el proceso de diseño/construcción numerado (Etapa 0-15) tras completar el backend (Etapa 13) y el scaffold Flutter (Etapa 14). Consolida referencias que `SECURITY.md`, `NON_FUNCTIONAL_REQUIREMENTS.md`, `DATA_MODEL.md` y ADR-0003 ya apuntaban hacia esta etapa desde su propia creación.
