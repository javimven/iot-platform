# THREAT_MODEL.md

## 0. Estado de este documento
- Etapa del proceso: 8 — Seguridad y modelo de amenazas
- Estado: En análisis
- Última actualización: 2026-07-27
- Depende de: `SECURITY.md` y todas las etapas anteriores (cada mitigación referenciada ya fue diseñada en su etapa correspondiente)

Formato por amenaza: escenario concreto → mitigación existente (con referencia) → riesgo residual → mitigación adicional si aplica. No se repite el detalle de cada mitigación, solo se referencia.

## 1. Robo de cuentas
- **Escenario**: un atacante obtiene o adivina la contraseña de un usuario (fuerza bruta, phishing, reutilización de contraseña filtrada en otro servicio).
- **Mitigación existente**: Argon2id (resiste cracking offline aunque se filtre la BD), rate limiting de login 5/15min por IP+email (`SECURITY.md` sección 5), refresh tokens rotativos y revocables (`ARCHITECTURE.md` sección 6).
- **Riesgo residual**: sin MFA en el MVP, una contraseña correcta basta para entrar — más grave cuanto más privilegiado el rol.
- **Mitigación adicional**: MFA TOTP para Admin de organización/plataforma, diseñado en `SECURITY.md` sección 4, a implementar en V2.

## 2. Escalada de privilegios
- **Escenario**: un Técnico o app cliente manipulada intenta ejecutar una acción reservada a Admin de organización (p. ej. cambiar el rol de otro miembro), o un miembro cualquiera intenta alcanzar un endpoint `/platform/*`.
- **Mitigación existente**: RBAC aplicado siempre en el backend vía un guard transversal (`PERMISSIONS.md` secciones 4-5), namespaces de ruta separados con verificación server-side de `isPlatformAdmin` (`API_DESIGN.md` sección 2) — nunca se confía en lo que el frontend oculta o muestra.
- **Riesgo residual**: un fallo de implementación en el guard (bug, no principio) podría abrir una brecha puntual.
- **Mitigación adicional**: batería de pruebas específica ya definida (`PERMISSIONS.md` sección 9) — se ejecuta en CI, no es una revisión manual puntual.

## 3. Acceso entre organizaciones
- **Escenario**: un usuario de la Organización A consigue leer o modificar datos de la Organización B (bug de aplicación, fuga de contexto de RLS, credencial de gateway mal configurada).
- **Mitigación existente**: tres capas independientes — filtro de aplicación por `organization_id` del JWT, RLS en PostgreSQL, ACL de EMQX por credencial (`ARCHITECTURE.md` sección 7). Corrección de esta etapa: `set_config` parametrizado evita que un valor de contexto mal saneado sea, además, un vector de inyección (`SECURITY.md` sección 1).
- **Riesgo residual**: si la variable de sesión de RLS no se fija en alguna ruta de código nueva, el efecto es "no se ve nada" (fail-closed, `DATA_MODEL.md` sección 9), no "se ve todo" — el fallo se manifiesta como error funcional visible, no como fuga silenciosa.
- **Mitigación adicional**: prueba específica ya definida (`DATA_MODEL.md` sección 12: ejecutar una consulta sin `set_config` y confirmar cero filas).

## 4. Suplantación de dispositivos
- **Escenario**: alguien intenta hacerse pasar por un gateway legítimo para inyectar datos falsos o acceder al topic de otra organización.
- **Mitigación existente**: credencial única e intransferible por gateway, TLS obligatorio, ACL con `organizationId`/`gatewayExternalId` concretos (no comodines) generada dinámicamente al autenticar (`MQTT_PROTOCOL.md` sección 4, [ADR-0002](ADR/0002-autenticacion-dispositivos-sin-mtls.md)). Los dispositivos detrás de un concentrador están además protegidos por el pre-registro de `device_id` (`MQTT_PROTOCOL.md` sección 6).
- **Riesgo residual**: sin mTLS/PKI en el MVP, el robo físico de una credencial de gateway (extraída del propio equipo en campo) permite suplantarlo hasta que se detecte y se rote — es el mayor riesgo residual de todo el sistema del lado de campo, aceptado conscientemente en [ADR-0002](ADR/0002-autenticacion-dispositivos-sin-mtls.md) por el coste de una PKI completa frente al plazo del MVP.
- **Mitigación adicional**: capacidad de rotación ya soportada (`API_DESIGN.md` sección 7); detección de anomalías de comportamiento (patrón de envío muy distinto al habitual) queda como mejora Futura, no construida ahora — relacionada con el agente de IA de `BACKLOG.md` #10.

## 5. Repetición de mensajes MQTT
- **Escenario**: un mensaje de telemetría válido se recibe más de una vez (reenvío de un gateway, reconexión, o repetición deliberada).
- **Mitigación existente**: deduplicación por `(channel_id, ts_origin)` en base de datos (`DATA_MODEL.md` sección 5) — un mensaje repetido no genera una fila ni una alerta duplicada.
- **Riesgo residual**: ninguno relevante para repetición exacta; la variante "repetir con un `ts_origin` distinto para alterar el histórico" es en realidad alteración de datos, no repetición — ver amenaza 7.

## 6. Publicación en topics no autorizados
- **Escenario**: una credencial de gateway intenta publicar o suscribirse fuera de su propio prefijo de topic.
- **Mitigación existente**: ACL de EMQX con valores concretos por credencial, no patrones abiertos (`MQTT_PROTOCOL.md` sección 4) — rechazado por el broker antes de llegar a `ingestion`.
- **Riesgo residual**: ninguno adicional a la amenaza 4 (depende de la misma credencial).

## 7. Alteración de mediciones
- **Escenario**: un gateway comprometido o defectuoso envía valores fabricados pero físicamente plausibles (no se detecta por rango, `MQTT_PROTOCOL.md` sección 6).
- **Mitigación existente**: validación de rango físico por tipo de canal (descarta lo imposible), `audit_log` y `alerts` inmutables (no se puede alterar el histórico retroactivamente, `DATA_MODEL.md` sección 6).
- **Riesgo residual**: **aceptado explícitamente** — ningún sistema IoT sin hardware con elemento seguro puede distinguir "dato real" de "dato plausible pero falso" solo con validación de rango. Es una limitación estructural, no un descuido.
- **Mitigación adicional**: detección de anomalías estadísticas/IA sobre series temporales — Futuro (`BACKLOG.md` #10), no MVP.

## 8. Ejecución duplicada de comandos
- **Escenario**: un comando remoto (V2) se ejecuta dos veces por un reintento o mensaje duplicado.
- **Mitigación existente**: **diferido a V2** (`ARCHITECTURE.md` sección 10) — el patrón de idempotencia (clave de deduplicación, `Idempotency-Key`, ya usado en telemetría y en la API, `MQTT_PROTOCOL.md`/`API_DESIGN.md` sección 6) se reutilizará cuando se diseñe, no se inventa uno nuevo entonces.
- **Riesgo residual**: no aplicable todavía (funcionalidad no construida).

## 9. Filtración de secretos
- **Escenario**: una credencial de infraestructura o de dispositivo termina en el repositorio, en un log, o en una respuesta de error.
- **Mitigación existente**: gestión centralizada de secretos (`SECURITY.md` sección 7), errores sin detalle interno (`SECURITY.md` sección 13), secretos de dispositivo nunca en logs (regla explícita a aplicar en Etapa 13).
- **Riesgo residual**: error humano (commitear un `.env` por accidente) — mitigado con revisión de PR y `.gitignore`, no eliminable al 100%.
- **Mitigación adicional**: escaneo de secretos en el repositorio (p. ej. gitleaks) como paso adicional de CI — se añade al pipeline en Etapa 9.

## 10. Ataques de denegación de servicio
- **Escenario**: saturación de la API, del broker MQTT, o de la ingesta con tráfico excesivo.
- **Mitigación existente**: rate limiting por categoría (`SECURITY.md` sección 5), límite de tamaño de mensaje MQTT (8 KB, `MQTT_PROTOCOL.md` sección 6), límites de paginación y de rango de consulta (`API_DESIGN.md` secciones 5 y 8), cola con reintentos absorbiendo picos legítimos (`ARCHITECTURE.md` sección 8).
- **Riesgo residual**: protección de red de bajo nivel (volumétrica) no está cubierta por la aplicación — depende del proveedor de infraestructura.
- **Mitigación adicional**: protección DDoS a nivel de proveedor/CDN — decisión concreta en Etapa 9, no aquí.

## 11. Dependencias vulnerables
- **Escenario**: una librería de terceros (backend, frontend, o base de la imagen Docker) tiene una vulnerabilidad conocida.
- **Mitigación existente**: escaneo automatizado con política de bloqueo para crítico/alto (`SECURITY.md` sección 10).
- **Riesgo residual**: vulnerabilidades de día cero sin escaneo disponible todavía.
- **Mitigación adicional**: revisión periódica de seguridad (Etapa 15) además del escaneo continuo.

## 12. Acceso indebido a backups
- **Escenario**: alguien con acceso al almacenamiENTO de backups (no a la aplicación) restaura o extrae datos de todas las organizaciones de golpe — los backups no tienen RLS.
- **Mitigación existente (principio, mecánica completa en Etapa 12)**: backups cifrados en reposo, acceso restringido a un rol operativo distinto del rol de aplicación (principio de mínimo privilegio, `SECURITY.md` sección 2), preferentemente en una cuenta/ubicación separada de la base de datos primaria.
- **Riesgo residual**: un backup es, por naturaleza, una copia sin RLS — cualquiera con acceso a él ve todas las organizaciones. Es el motivo por el que el control de acceso al propio backup (no a la aplicación) es crítico.
- **Mitigación adicional**: se detalla el procedimiento completo (quién puede restaurar, cómo se audita un acceso a backup) en Etapa 12 (`BACKUP_AND_RECOVERY.md`).

## 13. Resumen de riesgos residuales aceptados conscientemente

| # | Riesgo | Por qué se acepta | Revisar cuando... |
|---|---|---|---|
| 4 | Sin mTLS en dispositivos | Coste de PKI vs. plazo del MVP ([ADR-0002](ADR/0002-autenticacion-dispositivos-sin-mtls.md)) | Aparezca un cliente con requisito de seguridad más estricto, o un incidente real |
| 7 | Alteración de mediciones por dispositivo comprometido | Limitación estructural de cualquier IoT sin hardware seguro | Se construya detección de anomalías (Futuro) |
| 1 | Sin MFA en MVP | Ya decidido en Etapa 0 (diferido a V2) | Se implemente V2 |
| 12 | Backup sin RLS | Es la naturaleza de un backup | Etapa 12 defina el control de acceso operativo |

## 14. Entregables de esta etapa
- Este documento (`THREAT_MODEL.md`), complementario a `SECURITY.md`.

## 15. Criterios de aceptación de esta etapa
- Las 12 categorías de amenaza pedidas explícitamente tienen escenario, mitigación y riesgo residual explícitos — ninguna quedó sin analizar.
- Todo riesgo aceptado (no mitigado del todo) está en la tabla de la sección 13, no disperso sin marcar.

## 16. Dependencias
- Depende de `SECURITY.md` y de todas las etapas 0-7.
- Alimenta Etapa 12 (procedimiento de backups) y Etapa 15 (revisión periódica de seguridad).

## 17. Aspectos que se aplazan explícitamente
- Detección de anomalías/IA sobre telemetría (amenaza 7) — Futuro.
- Procedimiento operativo completo de backups (amenaza 12) — Etapa 12.
- Amenaza 8 (comandos duplicados) no aplica hasta que exista la funcionalidad (V2).

## 18. Historial de decisiones de esta etapa

| Fecha | Decisión | Notas |
|---|---|---|
| 2026-07-27 | Riesgo de suplantación de dispositivos (sin mTLS) aceptado explícitamente como el mayor riesgo residual de campo | Ya lo señalaba el ADR-0002; aquí se formaliza como parte del modelo de amenazas, no solo de una decisión de arquitectura |
| 2026-07-27 | Alteración de mediciones por dispositivo comprometido: riesgo aceptado sin mitigación completa en MVP | Limitación estructural, no descuido |
