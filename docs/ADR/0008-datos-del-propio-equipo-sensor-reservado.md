# ADR-0008: Datos del propio equipo con un `sensor_id` reservado

- Estado: Aceptada
- Fecha: 2026-09-17
- Relacionado: [ADR-0004](0004-unidad-de-conexion-lora-y-nbiot.md), [ADR-0006](0006-infraestructura-ui-oculta-zona-dispositivo-sensor.md)

## Contexto
Para distinguir «la estación no envía» de «envía, pero sin datos de sus sensores» (lo que pasa en la WSC2-N tras un reinicio o quedarse sin batería, que borra la declaración de sus sensores), el puente de `rs485-tool` empezó a mandar en cada envío la batería (`battery_voltage`) y la cobertura (`signal_strength`) de la estación (`BACKLOG.md` #49 F). El contrato MQTT solo acepta lecturas de un sensor pre-registrado, así que se mandaron como un quinto «sensor», `estacion`, que había que dar de alta a mano.

No se pudo: la estación ya tenía sus 4 sensores, y un dispositivo tiene «hasta 4 sensores conectados» (`FUNCTIONAL_REQUIREMENTS.md` §7, confirmado por el usuario el 2026-07-27). El usuario, preguntado: «no son sensores, pero son datos que se deben ver de alguna manera».

## Decisión
Los datos del propio equipo llegan con un `sensor_id` **reservado, `_device`**, y no son un sensor a efectos de negocio:

- **No hay que darlos de alta.** `ingestion` crea ese sensor la primera vez que llega un mensaje suyo, siempre que el gateway y el dispositivo estén pre-registrados, igual que ya crea los canales en el primer mensaje válido (`MQTT_PROTOCOL.md` §9). La barrera de seguridad sigue en el pre-registro del dispositivo.
- **No cuentan para el máximo de 4** ni salen en el Directorio IoT: la API no los lista, no se pueden consultar ni borrar por la ruta de sensores, y no se puede registrar a mano un sensor con ese identificador.
- **Se ven en la app** como un grupo más de las lecturas de la estación, con el nombre «Estación» y al final: no cuentan como sensor de campo en el resumen ni para el aviso de «envía sin datos de sensores».

En el esquema sigue siendo una fila de `sensors`, con sus canales y su telemetría como cualquier otra: umbrales, históricos, gráficas y alertas funcionan sin cambios.

## Alternativas consideradas
- **Subir el límite a 5**: descartada. Dejaría registrar 5 sondas físicas, en contra de la regla confirmada, y seguiría exigiendo un alta a mano por estación que es fácil olvidar.
- **Excluir del límite un sensor dado de alta a mano con un identificador reservado**: descartada frente a crearlo solo. Mismo cambio en el límite, pero con un paso manual por estación que no aporta seguridad (el dispositivo ya está pre-registrado).
- **Canales colgando del dispositivo, sin sensor intermedio**: es el modelo más fiel, pero pide migración (`channels.sensor_id` opcional y `device_id`), políticas RLS, cambios en ingesta, API y app, para el mismo resultado visible. Si algún día hay muchos datos de equipo (temperatura interna, errores, versión de firmware) con tratamiento propio, es el camino.
- **Mezclarlos en un sensor real** (p. ej. el ambiente): descartada. Tras un reinicio no llega ningún sensor, y la batería aparecería como magnitud de una sonda.

## Consecuencias
- `MQTT_PROTOCOL.md`: `_device` queda reservado en `sensor_id` (§5), con la excepción en la validación del punto 4 (§6). Cualquier equipo puede usarlo, no solo la WSC2-N: un nodo LoRa detrás de un concentrador mandaría así su batería.
- `FUNCTIONAL_REQUIREMENTS.md` §7: el máximo de 4 son sondas conectadas; los datos del equipo no cuentan.
- `OPENAPI.yaml`: `POST .../sensors` devuelve 400 con `_device`, y los listados no lo incluyen.
- Las lecturas de una estación (`latest-readings`) sí lo incluyen, con `sensorExternalIdentifier: "_device"`: la app lo reconoce por ese identificador, no por el tipo de canal.
- El puente de `rs485-tool` manda `_device` en vez de `estacion`.
