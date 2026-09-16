# ADR-0007: Admin de plataforma con lectura de telemetría de todas las organizaciones

- Estado: Aceptada
- Fecha: 2026-09-16
- Amplía: [ADR-0005](0005-admin-plataforma-gestion-global-iot.md)

## Contexto
El ADR-0005 dio al Admin de plataforma la gestión global del Directorio IoT y dejó la telemetría expresamente fuera («telemetría, alertas, miembros, sesiones y auditoría de negocio de una organización siguen totalmente fuera de alcance»). En su momento el usuario no pedía leer datos de sus clientes, solo gestionar su infraestructura.

Con la primera estación real en marcha (WSC2-N, `BACKLOG.md` #44) y la pantalla "Estaciones" desplegada en staging, el usuario, que es el Admin de plataforma, entró y recibió `403 No active organization`. Su petición, textual: «el administrador (yo), no el de la organización, debería poder ver todas las estaciones de todas las organizaciones». Es la misma razón de negocio del ADR-0005: su empresa instala y mantiene el hardware de cada cliente, y para eso necesita ver si las estaciones están enviando y qué miden.

## Decisión
El Admin de plataforma puede **leer** la telemetría de cualquier organización: las últimas lecturas de una estación y el histórico de un canal. Es una acción de plataforma nueva, `platform.telemetry.read`, con la organización explícita en la ruta, igual que la excepción de Directorio IoT:

- `GET /platform/organizations/{organizationId}/gateways/{gatewayId}/latest-readings`
- `GET /platform/organizations/{organizationId}/channels/{channelId}/readings`

**No se amplía nada más.** Alertas (leer, reconocer, resolver), miembros, sesiones y auditoría de negocio siguen fuera de su alcance. La telemetría es de solo lectura: el Admin de plataforma no escribe lecturas por ninguna vía.

En la app, "Estaciones" recorre todas las organizaciones cuando la sesión es de Admin de plataforma, con o sin organización activa, y agrupa el listado por «Organización · Finca».

## Alternativas consideradas
- **Excepción de RLS en `telemetry` y `latest_readings`** (`OR app.is_platform_admin`), como en las tablas de Directorio IoT: descartada. Abriría consultas que cruzan organizaciones en una sola transacción, y ninguna pantalla lo necesita. En su lugar, la consulta se ejecuta con `app.current_org_id` fijado a la organización de la URL. La política RLS de esas dos tablas no cambia: cada consulta sigue viendo una única organización, también para el Admin de plataforma. Quien decide que puede elegir la organización es `PermissionsGuard` (acción `platform.telemetry.read`), y el servicio lo vuelve a comprobar (solo con `isPlatformAdmin`).
- **Hacer al Admin de plataforma miembro de cada organización**: ya descartado en el ADR-0005 por la fricción de una membresía por cliente. Además, mezclaría sus acciones con las de los miembros reales en la auditoría de cada cliente.
- **Una ruta global `GET /platform/gateways`** que liste las estaciones de todas las organizaciones de una vez: aplazada. Con pocas organizaciones basta con recorrerlas desde la app con las rutas por organización que ya existen. Si el número de clientes crece, es el primer sitio donde optimizar.

## Consecuencias
- `PERMISSIONS.md`: fila nueva `platform.telemetry.read` (Admin de plataforma: Sí; roles de organización: No). La prueba derivada «un Admin de plataforma recibe 403 al leer telemetría» se mantiene para las rutas de miembro (`/channels/...`), sin organización, y deja de valer para las de plataforma.
- No se audita cada lectura, igual que las lecturas de un miembro. Si algún cliente exige transparencia sobre quién mira sus datos, auditar las lecturas del Admin de plataforma en el `audit_log` de la organización es la extensión natural (anotado como V2).
- Una sesión puede ser a la vez de Admin de plataforma y de miembro de una organización (`BACKLOG.md` #46). Desde este ADR, `login`, `selectOrganization` y `refresh` conservan la marca `isPlatformAdmin` siempre que el usuario esté en `platform_admins`. Si no, la vista de "Estaciones" cambiaría de todas las organizaciones a una sola al renovarse el token.
