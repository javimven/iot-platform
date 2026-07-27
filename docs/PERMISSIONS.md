# PERMISSIONS.md

## 0. Estado de este documento
- Etapa del proceso: 4 — Modelo de permisos (RBAC detallado)
- Estado: En análisis (matriz completa, pendiente de tu validación)
- Última actualización: 2026-07-27
- Depende de: Etapas 0, 1, 3
- Bloquea: Etapa 5 (modelo de datos: tabla de alcance), Etapa 7 (guards de la API), Etapa 8 (seguridad)

## 1. Decisiones tomadas en esta etapa

| Decisión | Elegido |
|---|---|
| Alcance de los roles Técnico / Operador / Solo lectura | Restringible por instalación desde el MVP (no solo "toda la organización") |
| Admin de plataforma sobre Directorio IoT ([ADR-0005](ADR/0005-admin-plataforma-gestion-global-iot.md)) | Capacidad **global** (todas las organizaciones) sobre instalaciones/zonas/gateways/dispositivos/sensores/canales, sin ser miembro de la organización — excepción explícita y auditada al aislamiento, acotada a infraestructura (no telemetría/alertas/miembros) |
| Control de qué ve cada organización | Feature flags por organización, gestionados solo por Admin de plataforma (sección 6) |

Estas decisiones añaden piezas nuevas al modelo que no estaban previstas en la Etapa 1 en este nivel de detalle.

## 2. Modelo de alcance (scope) por instalación

- **Admin de organización**: siempre acceso a **todas** las instalaciones de su organización. No es restringible — si se necesita restringir a alguien, esa persona no debería tener este rol.
- **Técnico / Operador / Solo lectura**: acceso **por defecto a todas** las instalaciones de la organización. Un Admin de organización puede, opcionalmente, asignar a un miembro concreto un conjunto explícito de instalaciones — en cuanto un miembro tiene al menos una instalación asignada, pasa a ver **solo** esas (allowlist), en lugar de todas.
  - Este diseño es intencional: evita que una organización pequeña con una sola instalación tenga que configurar el alcance de cada miembro desde el primer día. Solo las organizaciones que lo necesiten (varias instalaciones, técnicos dedicados a fincas concretas) lo usan.
- **Granularidad: por instalación, no por zona.** Si un miembro tiene acceso a una instalación, ve todas sus zonas. Restringir a nivel de zona individual se deja para V2 si aparece la necesidad real (sección 13) — no hay indicio todavía de que un técnico deba ver una zona sí y otra no dentro de la misma finca.
- **Simplificación de modelo**: un Gateway pertenece a una única instalación (Etapa 1, sección 6, ya actualizada). Esto permite que el alcance se compruebe directamente sobre gateway/dispositivo/sensor sin tener que resolver una relación muchos-a-muchos entre gateway e instalación.
- **No es una barrera de seguridad multitenant** (eso ya está resuelto en la Etapa 3 con aplicación + RLS + ACL de broker, y no se toca aquí). El alcance por instalación es una regla de autorización **dentro** de una misma organización, igual que cualquier otro permiso de esta matriz — se aplica en la capa de aplicación (filtro en las consultas), no en PostgreSQL RLS ni en el broker MQTT.

## 3. Catálogo de acciones (permission keys)

| Grupo | Acciones |
|---|---|
| Plataforma (fuera de organización) | `platform.organizations.create`, `platform.organizations.read`, `platform.organizations.suspend`, `platform.organizations.reactivate`, `platform.audit.read` |
| Organización | `org.profile.read`, `org.profile.update` |
| Miembros | `members.read`, `members.invite`, `members.update_role`, `members.suspend`, `members.reactivate`, `members.remove` |
| Alcance de miembro | `member_scope.read`, `member_scope.assign` |
| Instalaciones | `installations.create`, `installations.read`, `installations.update`, `installations.delete` |
| Zonas | `zones.create`, `zones.read`, `zones.update`, `zones.delete` |
| Gateways | `gateways.create`, `gateways.read`, `gateways.update`, `gateways.disable`, `gateways.rotate_credential` |
| Dispositivos | `devices.create`, `devices.read`, `devices.update`, `devices.disable` |
| Sensores / canales | `sensors.create`, `sensors.read`, `sensors.update`, `sensors.delete`, `channels.read`, `channels.update_threshold` |
| Telemetría | `telemetry.read_latest`, `telemetry.read_history` |
| Alertas | `alerts.read`, `alerts.acknowledge`, `alerts.resolve` |
| Sesiones | `sessions.read_own`, `sessions.revoke_own`, `sessions.read_others`, `sessions.revoke_others` |
| Auditoría | `audit.read_full`, `audit.read_technical` |
| Features de organización | `org_features.read`, `org_features.update` |

Todas las acciones salvo el grupo "Plataforma" viven dentro del contexto de una organización activa (Etapa 3, sección 6).

## 4. Matriz completa

"Alcance" = sujeto al modelo de la sección 2 (todas las instalaciones, o solo las asignadas).

| Acción | Admin plataforma | Admin organización | Técnico | Operador | Solo lectura |
|---|---|---|---|---|---|
| `platform.organizations.*` | Sí³ | No | No | No | No |
| `platform.audit.read` | Sí | No | No | No | No |
| `org.profile.read` | No¹ | Sí | Sí | Sí | Sí |
| `org.profile.update` | No¹ | Sí | No | No | No |
| `members.read` | No¹ | Sí | No | No | No |
| `members.invite` / `update_role` / `suspend` / `reactivate` / `remove` | No¹ | Sí | No | No | No |
| `member_scope.read` / `assign` | No¹ | Sí | No | No | No |
| `installations.create` / `update` / `delete` | **Sí (global)²** | Sí | Sí | No | No |
| `installations.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `zones.create` / `update` / `delete` | Sí (global)² | Sí | Sí (alcance) | No | No |
| `zones.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `gateways.create` / `update` / `disable` / `rotate_credential` | Sí (global)² | Sí | Sí (alcance) | No | No |
| `gateways.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `devices.create` / `update` / `disable` | Sí (global)² | Sí | Sí (alcance) | No | No |
| `devices.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `sensors.create` / `update` / `delete` | Sí (global)² | Sí | Sí (alcance) | No | No |
| `sensors.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `channels.read` | Sí (global)² | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `channels.update_threshold` | Sí (global)² | Sí | Sí (alcance) | No | No |
| `telemetry.read_latest` / `read_history` | No¹ | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `alerts.read` | No¹ | Sí (todas) | Sí (alcance) | Sí (alcance) | Sí (alcance) |
| `alerts.acknowledge` / `resolve` | No¹ | Sí | Sí (alcance) | Sí (alcance) | No |
| `sessions.read_own` / `revoke_own` | Sí | Sí | Sí | Sí | Sí |
| `sessions.read_others` / `revoke_others` | No¹ | Sí | No | No | No |
| `audit.read_full` | No¹ | Sí | No | No | No |
| `audit.read_technical` | No¹ | Sí (incluida en full) | Sí | No | No |
| `org_features.read` | Sí (global) | Sí (la propia) | No | No | No |
| `org_features.update` | Sí (global) | No | No | No | No |

² Excepción introducida en esta etapa ([ADR-0005](ADR/0005-admin-plataforma-gestion-global-iot.md)): el Admin de plataforma puede gestionar el Directorio IoT (instalaciones→canales) de **cualquier** organización sin ser miembro de ella — porque en la práctica es su empresa quien instala el hardware. Queda **acotado a estas acciones**; no se extiende a telemetría, alertas, miembros ni auditoría de negocio, que siguen marcadas No¹. Toda acción bajo esta excepción se registra en el `audit_log` **de la organización afectada**, visible para su Admin de organización.

³ `platform.organizations.create` incluye, como parte de la misma acción (FUNCTIONAL_REQUIREMENTS.md §2), invitar al primer Admin de organización — internamente escribe una fila en `members`, la única vez que el Admin de plataforma lo hace. Esto **no** convierte `members.*` en accesible para el Admin de plataforma: sigue sin poder llamar a ningún endpoint de `/members` (PermissionsGuard lo bloquea igual que antes); la excepción de RLS que lo permite a nivel de base de datos (`DATA_MODEL.md`, migración 0002) solo la ejercita el código de `PlatformOrganizationsService.create()`, ningún otro camino de la aplicación.

¹ El Admin de plataforma no tiene acceso a ninguna acción dentro de una organización — ni siquiera de solo lectura — salvo su capacidad de suspender/reactivar la organización completa (`platform.organizations.suspend/reactivate`), que no requiere leer ni un solo dato de negocio de esa organización. Es la respuesta de este modelo a "¿cómo actúa el Admin de plataforma ante un incidente de seguridad en una organización sin violar el aislamiento?": puede cortar el acceso por completo, no puede fisgonear.

## 5. Mecanismo de aplicación (enforcement)
- Un decorador (`@RequirePermission('modulo.accion')`) sobre cada endpoint/resolver, comprobado por un Guard de NestJS que resuelve el rol activo del JWT (Etapa 3, sección 6) contra la matriz de la sección 4 — la matriz vive **en código** (constante versionada, revisada por PR), no en una tabla editable en el MVP, porque los permisos por rol no son configurables por organización todavía (diferido a V2, Etapa 0).
- Un segundo Guard/interceptor aplica el filtro de alcance (sección 2) sobre las consultas marcadas como "sujetas a alcance" — se implementa una vez, de forma transversal, no en cada handler.
- El módulo "Permisos" del listado original de 20 módulos se materializa como un **catálogo de solo lectura** (la tabla de la sección 3, expuesta vía `GET /me/permissions` para que el frontend Flutter sepa qué mostrar/ocultar) — nunca como una fuente de verdad editable en el MVP. Recuerda el principio ya fijado: no confiar en permisos aplicados solo desde el frontend; este endpoint es una comodidad de UI, la autorización real siempre se revalida en el backend.

## 6. Riesgos
- Si se implementa el filtro de alcance de forma inconsistente (algunas consultas lo aplican, otras no), un Técnico restringido podría ver datos de una instalación que no le corresponde — mitigado con una única capa transversal (sección 5) y con la prueba de la sección 9, no con revisión manual caso por caso.
- Denormalizar `installation_id` en tablas de bajo nivel (dispositivo, sensor, telemetría, última lectura, alerta) para que el filtro de alcance no requiera JOINs profundos en cada consulta: se decide en Etapa 5, pero se marca aquí como necesidad derivada de esta etapa.
- Un Admin de organización que se auto-asigna un alcance restringido por error se bloquearía a sí mismo — mitigado porque el Admin de organización nunca es restringible (sección 2), by design.
- La excepción del Admin de plataforma sobre Directorio IoT (ADR-0005) podría usarse para modificar la infraestructura de una organización sin que nadie de esa organización se entere — mitigado exigiendo que **toda** acción bajo esta excepción se escriba en el `audit_log` de la organización afectada (no en un log aparte); una omisión aquí sería un fallo de seguridad, no un detalle menor.

## 7. Entregables de esta etapa
- Este documento (`PERMISSIONS.md`).
- Actualización de `FUNCTIONAL_REQUIREMENTS.md` (Gateway↔Instalación, regla de integridad Zona↔Gateway).

## 8. Criterios de aceptación de esta etapa
- Cada acción agrupada en la sección 3 tiene una fila en la matriz sin ambigüedad.
- El modelo de alcance tiene un comportamiento por defecto explícito (todas las instalaciones si no hay asignación) para no obligar a configurar cada miembro desde el día 1.
- Ninguna fila de la matriz contradice las decisiones ya cerradas en la Etapa 1 (tabla de la sección 4 de `FUNCTIONAL_REQUIREMENTS.md`).

## 9. Pruebas necesarias derivadas
- Un Técnico sin alcance asignado ve todas las instalaciones de su organización; en cuanto se le asigna una, deja de ver el resto inmediatamente.
- Un Operador no puede crear ni editar una zona (solo lectura de zonas), aunque sí reconocer/resolver alertas.
- Un Admin de plataforma recibe 403 al intentar leer telemetría, alertas o miembros de cualquier organización, pero puede suspenderla.
- Un Admin de plataforma puede crear/editar un gateway o sensor de cualquier organización sin ser miembro de ella, y esa acción aparece en el `audit_log` de esa organización, visible para su Admin de organización.
- Un Admin de organización no puede leer ni modificar `org_features` de otra organización; solo el Admin de plataforma puede activarlas/desactivarlas.
- Un Técnico con alcance restringido a la Instalación A recibe 403 (no 404, para no filtrar existencia) al intentar leer o modificar un gateway de la Instalación B de la misma organización.
- El endpoint `GET /me/permissions` devuelve exactamente las acciones permitidas para el rol activo, y el backend rechaza cualquier acción no listada aunque el frontend la solicite igualmente.

## 10. Lista de tareas de esta etapa
- [x] Decidir el modelo de alcance (instalación, no zona; opt-in, no obligatorio).
- [x] Construir el catálogo de acciones y la matriz completa.
- [x] Ajustar `FUNCTIONAL_REQUIREMENTS.md` (Gateway↔Instalación).
- [ ] Revisión y validación por tu parte.
- [ ] Cerrar etapa y pasar a Etapa 5 (modelo de datos).

## 11. Dependencias
- Depende de Etapas 0, 1 y 3 (cerradas/en análisis).
- Bloquea Etapa 5 (tabla de alcance y denormalización de `installation_id`), Etapa 7 (guards de la API), Etapa 8 (revisión de seguridad de la matriz).

## 12. Aspectos que se aplazan explícitamente
- Restricción a nivel de zona individual (no solo instalación) — V2, si aparece necesidad real.
- Permisos configurables por organización más allá de los 5 roles fijos — V2 (ya decidido en Etapa 0).
- Un "modo soporte" auditado para que el Admin de plataforma pueda excepcionalmente leer **telemetría/alertas/miembros** de una organización con consentimiento explícito — Futuro. (La gestión de Directorio IoT ya no está en este cajón: se resolvió en esta etapa, ADR-0005.)
- Exigir un motivo/referencia (p. ej. ticket de soporte) al ejecutar acciones bajo la excepción del ADR-0005 — V2; hoy basta con quedar auditado.
- Catálogo definitivo de `features` gateables (informes, campañas, clima, satélite...) — se irá ampliando a medida que cada función V2/Futuro se construya; el mecanismo (sección 14) ya está listo para recibirlas.

## 13. Errores frecuentes a evitar
- No confundir el alcance por instalación (regla de negocio dentro de una organización) con el aislamiento multitenant (barrera de seguridad entre organizaciones, ya resuelta en Etapa 3) — tienen mecanismos y capas distintos.
- No aplicar el filtro de alcance en unos endpoints sí y en otros no — debe ser una capa transversal, nunca una comprobación ad-hoc copiada en cada handler.
- No dejar que la ausencia de asignación de alcance se interprete como "sin acceso" — el valor por defecto acordado es "todas las instalaciones", lo contrario rompería organizaciones pequeñas de un día para otro.
- No exponer si un recurso existe o no cuando el alcance deniega acceso (usar 403 sin detalle, no 404 disfrazado ni un 403 que confirme la existencia del recurso en otra instalación).

## 14. Features de organización (feature flags)

Mecanismo distinto del RBAC de roles (secciones 3-4): controla qué **módulos/pestañas** ve una organización, no qué puede hacer un usuario dentro de ella. Solicitado directamente por el usuario (`BACKLOG.md` #11).

- Cada función opcional (informes PDF, campañas, clima, satélite, recomendaciones...) tiene un `feature_code` en un catálogo de plataforma (tabla `features`, Etapa 5).
- `organization_features (organization_id, feature_code) → enabled` — activado/desactivado por organización. Sin fila = desactivado por defecto (una función nueva no se activa sola para nadie).
- Solo el **Admin de plataforma** puede leer/escribir esta configuración de cualquier organización (`org_features.update`, global). Un Admin de organización puede **leer** el estado de las suyas (`org_features.read`, alcance propio) para que el frontend sepa qué pestañas mostrar — nunca escribirlo.
- **Comportamiento de UI** (detalle de Etapa 14, anotado aquí porque lo pidió el usuario explícitamente): si una función está desactivada, la pestaña correspondiente se muestra **bloqueada** (visible pero inactiva, p. ej. "contrata esto para activarlo"), no oculta — es una palanca comercial de upsell, no solo una restricción.
- Esto no sustituye al RBAC de roles: un Operador dentro de una organización con "informes" activado sigue sin poder generarlos si su rol no lo permite (la matriz de la sección 4 se aplicaría igual sobre cada nueva función, cuando se diseñe en su etapa correspondiente).

## 15. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | Alcance restringible por instalación desde el MVP, por defecto "todas" si no hay asignación | Solo alcance a nivel de organización completa (sin restricción) |
| 2026-07-27 | Granularidad de alcance: por instalación, no por zona | Alcance a nivel de zona individual (descartado por falta de necesidad real conocida) |
| 2026-07-27 | Un Gateway pertenece a una única instalación | Gateway compartido entre varias instalaciones (descartado, añade complejidad sin caso de uso claro) |
| 2026-07-27 | Admin de plataforma con gestión global de Directorio IoT, acotada y auditada (ADR-0005) | Mantener aislamiento estricto (Admin de plataforma sería miembro de cada organización); "modo soporte" genérico de solo lectura |
| 2026-07-27 | Feature flags por organización, gestión exclusiva del Admin de plataforma | Que cada Admin de organización autogestione sus propias funciones activas (descartado, contradice "siempre lo voy a tener yo como administrador") |
| 2026-07-27 | Añadido `channels.read` como acción propia (Etapa 13, descubierto al implementar el endpoint de listado de canales) | Asumir que `sensors.read` cubría implícitamente la lectura de canales (dejaba el listado sin permiso explícito — un vacío real de la matriz original) |
