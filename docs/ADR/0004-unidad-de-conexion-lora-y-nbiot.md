# ADR-0004: "Gateway" como unidad de conexión, no solo concentrador LoRa

- Estado: Aceptada
- Fecha: 2026-07-27

## Contexto
Hasta ahora el modelo asumía una única topología: sensores → LoRa → Gateway (con GPRS/Ethernet) → MQTT. El usuario ha indicado que también habrá estaciones con **NB-IoT u otras tecnologías** que no dependen de un gateway y se conectan **directamente** al broker MQTT. El modelo de autenticación (ADR-0002), el esquema de credenciales (`gateway_credentials`) y las ACL de EMQX (`org/{orgId}/gw/{gatewayId}/...`) ya estaban construidos en torno al concepto de "Gateway" como la única entidad que abre conexión de red.

## Decisión
Se reinterpreta "Gateway" como **la unidad que abre la conexión MQTT** (no necesariamente un concentrador físico de varios sensores LoRa). Cubre dos casos:
1. **Concentrador LoRa**: un gateway físico con varios `devices` (estaciones) asociados, tal como ya estaba modelado.
2. **Estación de conexión directa** (NB-IoT u otra): se modela como un gateway con **exactamente un** `device` asociado. La estación en sí lleva la credencial MQTT (heredada de `gateways`/`gateway_credentials`) y aparece en el sistema como un gateway de un solo dispositivo.

Se añade un campo descriptivo `connectivity_type` en `gateways` (`lora_concentrator` | `direct_nbiot` | `direct_other`) — no cambia la lógica de autenticación, ACL, credenciales, heartbeat/offline ni particionamiento; es solo informativo (para filtrar/mostrar en el frontend "mis gateways LoRa" vs. "mis estaciones directas").

## Alternativas consideradas
- **Tabla `device_credentials` paralela** para estaciones de conexión directa, dejando `devices.gateway_id` nullable: descartada. Habría duplicado credenciales, ACL, rotación, detección de offline y particionamiento en dos rutas de código paralelas para un problema que la reinterpretación de "Gateway" resuelve sin tocar el esquema de `devices` ni la lógica de seguridad ya construida (Etapa 3, `PERMISSIONS.md`, `DATA_MODEL.md`).
- **Renombrar la entidad `gateways`** a un nombre más neutro (p. ej. `connection_units`): descartado por ahora — el coste de renombrar una entidad ya referenciada en `ARCHITECTURE.md`, `PERMISSIONS.md` y `DATA_MODEL.md` no aporta nada funcional; el nombre de tabla es un detalle interno, la UI/lenguaje de dominio de cara al usuario (Etapa 1, Etapa 14) puede mostrar "estación" o "gateway" según `connectivity_type` sin que el esquema tenga que reflejarlo.

## Consecuencias
- El flujo de aprovisionamiento (Etapa 7, API) para una estación NB-IoT probablemente se ofrezca como **un único endpoint/pantalla** ("aprovisionar estación") que crea internamente el par gateway+device de forma transparente, en vez de exponer al usuario los dos pasos separados que sí tienen sentido para un concentrador LoRa (alta del gateway, luego alta de cada dispositivo). Detalle de UX a resolver en Etapa 7/14, no bloquea el modelo de datos.
- El diseño de topics MQTT (Etapa 6) no necesita un caso especial: toda unidad de conexión, sea concentrador o estación directa, publica bajo `org/{orgId}/gw/{gatewayId}/...`.
- Redundancia menor aceptada: para una estación directa, el estado online/offline de su `gateway` y el de su único `device` se moverán casi siempre en paralelo. No se considera un problema suficiente para modelarlo de otra forma.
