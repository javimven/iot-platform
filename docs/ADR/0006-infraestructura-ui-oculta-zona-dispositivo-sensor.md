# ADR-0006: La UI de "Infraestructura" oculta Zona/Dispositivo/Sensor detrás de Finca→Estación→Canal

- Estado: Aceptada
- Fecha: 2026-08-05

## Contexto

Al diseñar el primer rediseño real del frontend (Etapa 14, sistema de diseño + reestructuración a menú lateral tipo SaaS, inspirado en competidores como Aigro/IKOS), se revisó con el usuario la jerarquía completa del Directorio IoT: `Organización → Instalación → Zona → Gateway → Dispositivo → Sensor → Canal` (5 niveles bajo Organización).

El usuario indicó que, en la operación real de hoy, no existe ningún caso de concentrador LoRa con varios dispositivos remotos — todas las estaciones son de conexión directa (ver [ADR-0004](0004-unidad-de-conexion-lora-y-nbiot.md), caso 2: un gateway con exactamente un device asociado). Para él, el modelo mental correcto de cara al usuario es de 4 niveles: **Organización → Finca → Estación → Canal**, sin Zona/Parcela ni Dispositivo/Sensor como conceptos visibles.

`ADR-0004` ya había anticipado parcialmente esto en su sección de Consecuencias: para una estación de conexión directa, el aprovisionamiento "probablemente se ofrezca como un único endpoint/pantalla... que crea internamente el par gateway+device de forma transparente" — pero nunca se llegó a construir esa pantalla única, y Zona tampoco se había planteado ocultar.

Dato relevante del esquema real: `Device.zoneId` es un campo obligatorio (no nullable) — un dispositivo no puede existir sin pertenecer a una zona. Esto significa que, si Zona desaparece de la UI, algo tiene que seguir satisfaciendo esa restricción por debajo.

## Decisión

**No se toca el esquema de datos.** `installations`, `zones`, `gateways`, `devices`, `sensors`, `channels` siguen existiendo exactamente igual — sigue soportando de forma nativa un futuro concentrador LoRa con varios dispositivos remotos, sin ninguna migración cuando (si) llegue ese caso.

Lo que cambia es la **capa de presentación y aprovisionamiento**:

1. La pantalla "Infraestructura" (antes "Fincas y parcelas") presenta solo **Finca → Estación → Canal** al usuario.
2. Al dar de alta una Estación nueva, la aplicación crea **por debajo, de forma transparente**: una Zona oculta (una por finca, reutilizada para todas sus estaciones — o una por estación, ver nota de implementación) y un Device oculto asociado a esa Zona y a ese Gateway. El usuario nunca ve, nombra ni gestiona esa Zona/Device.
3. Un Sensor también se crea de forma transparente por Estación la primera vez que hace falta (o se reutiliza uno ya creado) — los Canales que reporta la estación cuelgan de ese Sensor oculto, pero en la UI aparecen como "Canales de la Estación" directamente, sin mostrar el Sensor intermedio.
4. `ADR-0004` sigue vigente sin cambios: si en el futuro aparece un concentrador LoRa real con varios dispositivos remotos, ese caso sí expondría Dispositivo como concepto propio en la UI (tal como ya preveía la sección de Consecuencias de aquel ADR) — este ADR solo resuelve el caso de hoy (100% conexión directa), no cierra la puerta al otro.

**Nota de implementación pendiente** (a decidir en Etapa 14 cuando se construya): si la Zona oculta es una por Finca o una por Estación. Una por Finca es más simple (menos filas); una por Estación deja la puerta abierta a que, si algún día se expone Zona en la UI, cada estación ya tenga su propia zona 1:1 sin tener que migrar datos. No bloquea el resto de esta decisión.

## Alternativas consideradas

- **Eliminar de verdad las tablas `zones`/`devices`/`sensors`, aplanando el esquema a `installations → gateways → channels`**: descartada. Simplifica el esquema hoy, pero si en el futuro se necesita un concentrador LoRa con varias sondas remotas (el caso que motivó `ADR-0004` en primer lugar), habría que reintroducir esas tres tablas desde cero, con la migración de datos que eso implica. El coste de mantener tres tablas de más hoy es bajo (no añaden complejidad de negocio, solo de esquema); el coste de tener que rehacerlas después es alto.
- **Mostrar Zona/Dispositivo/Sensor en la UI pero con nombres genéricos autogenerados** ("Zona 1", "Dispositivo 1"): descartada — no resuelve el problema real (el usuario seguiría viendo y teniendo que navegar tres pantallas/conceptos que no le aportan nada en el caso de conexión directa), solo lo disfraza.

## Consecuencias

- Las pantallas de Directorio IoT ya construidas en Flutter (`directory_screen.dart`, `installation_detail_screen.dart`, `gateway_detail_screen.dart`, `device_detail_screen.dart`, `sensor_detail_screen.dart`, y sus equivalentes de plataforma `platform_*`) se sustituyen por una única pantalla "Infraestructura" con el flujo Finca→Estación→Canal. Trabajo de implementación pendiente, no alcance de este ADR.
- El backend necesita un endpoint (o ampliar uno existente) de "aprovisionar estación" que reciba nombre+tipo de conectividad y devuelva la credencial MQTT, creando zona/device ocultos en la misma transacción — hoy son 2-3 llamadas separadas (`createZone`, `createGateway`, `createDevice`) que el frontend encadena a mano.
- El Admin de plataforma usa la **misma** pantalla "Infraestructura" que un técnico de organización, con un aviso de contexto ("Gestionando: Finca de \<Organización\>") en vez de pantallas paralelas — unifica dos implementaciones casi duplicadas que existían hasta ahora (`platform_installations_screen.dart` y equivalentes vs. las de organización).
- El glosario de `PRODUCT_REQUIREMENTS.md` §5 se amplía con la terminología de cara al usuario (Finca, Estación como término único independientemente de `connectivity_type`) sin sustituir los nombres técnicos internos (Instalación, Gateway) que siguen siendo los de la base de datos y el código.
