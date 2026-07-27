# MQTT_PROTOCOL.md

## 0. Estado de este documento
- Etapa del proceso: 6 — Contratos MQTT
- Estado: En análisis (contrato completo, pendiente de tu validación)
- Última actualización: 2026-07-27
- Depende de: Etapas 0, 1, 2, 3, 4, 5
- Bloquea: Etapa 7 (la API expone lo que aquí se define), Etapa 8 (seguridad: ACL exacta), Etapa 9 (configuración real de EMQX), Etapa 13 (implementación de `ingestion`)

## 1. Objetivo
Fijar, sin ambigüedad, qué publica un gateway (concentrador LoRa o estación NB-IoT/directa — [ADR-0004](ADR/0004-unidad-de-conexion-lora-y-nbiot.md)), en qué topic, con qué payload, qué QoS, y cómo se detecta que ha dejado de reportar. No se decide aquí la configuración final de EMQX en producción (Etapa 9) ni el detalle criptográfico de las credenciales (Etapa 8).

## 2. Decisiones tomadas en esta etapa

| Decisión | Elegido | Alternativa descartada |
|---|---|---|
| Identificadores en el payload | `external_identifier` de dispositivo y sensor (no UUID interno) | Exponer UUIDs internos al hardware de campo |
| Profundidad del topic | Un topic por gateway para datos (`.../data`), sensor/dispositivo van en el cuerpo JSON | Un topic por sensor (`.../sensor/{id}/data`) |
| QoS | 1 (al menos una vez) para datos y estado | QoS 0 (arriesga pérdida silenciosa en GPRS/NB-IoT inestable); QoS 2 (coste de handshake innecesario, ya deduplicamos en BD) |
| Detección de offline | Doble mecanismo: LWT (inmediato, a nivel de conexión) + umbral por timeout (a nivel de dato) | Solo timeout (más lento); solo LWT (no cubre dispositivos LoRa detrás de un concentrador) |
| Creación de canales | Automática en el primer mensaje válido que referencie un `channel_type` conocido para un sensor ya pre-registrado | Exigir pre-registro explícito de cada canal antes de aceptar datos |
| Credencial de `ingestion` | Credencial MQTT propia, de solo-suscripción, distinta de las de cada gateway | Que `ingestion` reutilice alguna credencial de gateway |

## 3. Identificadores: por qué van dos IDs externos en el payload
El payload identifica el dispositivo y el sensor por su `external_identifier` (el mismo que se registró en `devices`/`sensors`, Etapa 5), nunca por UUID interno — el hardware de campo no conoce ni debe conocer nuestros UUIDs.

Se necesitan **ambos** IDs (dispositivo y sensor), no solo el de sensor: `sensors.external_identifier` es único **dentro de su dispositivo** (`UNIQUE(device_id, external_identifier)`, Etapa 5), no globalmente — dos dispositivos del mismo gateway podrían llamar "1" a su primer sensor. Sin el `device_id`, el sistema no podría resolver de forma inequívoca a qué fila de `sensors` corresponde el dato.

## 4. Topics

Prefijo por gateway (igual para concentrador LoRa o estación directa, [ADR-0004](ADR/0004-unidad-de-conexion-lora-y-nbiot.md)): `org/{organizationId}/gw/{gatewayExternalId}/...`, donde `organizationId` es el UUID de la organización y `gatewayExternalId` es el `external_identifier` del gateway (Etapa 5) — el mismo valor que su usuario/client-id MQTT (sección 7).

| Topic | Dirección | Contenido |
|---|---|---|
| `org/{organizationId}/gw/{gatewayExternalId}/data` | Gateway → broker | Mensaje de telemetría (sección 5) |
| `org/{organizationId}/gw/{gatewayExternalId}/status` | Gateway → broker (vía LWT o publicación explícita) | `{"online": true\|false}`, **retained** |
| `org/{organizationId}/gw/{gatewayExternalId}/cmd` | Broker → gateway | **Reservado para V2** (comandos remotos), sin lógica ni suscripción activa en el gateway todavía |

**ACL por gateway** (detalle criptográfico/config real en Etapa 8-9): al autenticar una credencial de gateway, el backend genera una regla de ACL con el `organizationId` y `gatewayExternalId` **concretos de ese gateway**, no con comodines — evita que una credencial válida publique en el topic de otra organización u otro gateway aunque conociera el patrón general del topic.

**`ingestion` tiene su propia credencial MQTT**, distinta de las de cualquier gateway: solo-suscripción (nunca publica), a `org/+/gw/+/data` y `org/+/gw/+/status` (comodín a través de todas las organizaciones — es un proceso interno de confianza, no expuesto a dispositivos de campo).

## 5. Payload de telemetría (`.../data`)

Un mensaje = un sensor, en un instante, con las lecturas de todos sus canales en ese ciclo (Etapa 1, sección 9):

```json
{
  "schema_version": 1,
  "device_id": "STA-042",
  "sensor_id": "S1",
  "ts": "2026-07-27T10:15:00Z",
  "message_id": "optional-dedup-hint",
  "readings": [
    { "channel": "temperature_air", "value": 23.4 },
    { "channel": "humidity_air", "value": 56.2 }
  ]
}
```

| Campo | Obligatorio | Notas |
|---|---|---|
| `schema_version` | Sí | Entero. `1` en el MVP (sección 12) |
| `device_id` | Sí | `external_identifier` del dispositivo, único dentro del gateway |
| `sensor_id` | Sí | `external_identifier` del sensor, único dentro del dispositivo |
| `ts` | Sí | ISO-8601 UTC, asignado por el dispositivo/estación (Etapa 1) |
| `message_id` | No | Señal auxiliar de deduplicación, mejor esfuerzo (Etapa 5, sección 5) |
| `readings[].channel` | Sí | Código de `channel_types` (Etapa 5) — no un UUID |
| `readings[].value` | Sí | Numérico |

## 6. Validaciones de `ingestion` (superficiales, en este orden)
1. Tamaño del mensaje ≤ **8 KB** — se rechaza sin parsear si lo excede (protección barata contra abuso, Etapa 1 "picos"/"valores inválidos").
2. `schema_version` soportado (sección 12).
3. `device_id` resuelve a un dispositivo pre-registrado **de ese gateway concreto** (Etapa 1, sección 7) — si no, se rechaza el mensaje completo y se registra como intento de dato no autorizado (Etapa 10).
4. `sensor_id` resuelve a un sensor pre-registrado de ese `device_id` — si no, se rechaza el mensaje completo.
5. `ts` dentro de un rango razonable: no más de 5 minutos en el futuro respecto a la recepción, ni más de 30 días en el pasado — fuera de rango, se rechaza el mensaje completo (reloj de dispositivo probablemente desincronizado; se registra como métrica de observabilidad, Etapa 10).
6. `readings`: máximo **8 elementos** por mensaje (margen sobre la media de 2 canales/sensor asumida en Etapa 2; más que eso es probablemente un mensaje malformado). Cada lectura se valida **de forma independiente**: si `channel` no es un tipo conocido o `value` está fuera del rango físico válido de ese tipo, **esa lectura concreta** se descarta (Etapa 1, sección 9) sin invalidar las demás lecturas válidas del mismo mensaje.
7. Lecturas que pasan validación → se resuelve/crea el `channel` (sección 9) y se encola el job idempotente (Arquitectura, sección 8).

## 7. QoS y sesión

- **QoS 1** en todas las publicaciones (`data`, `status`) — como ya deduplicamos por `(channel_id, ts_origin)` en base de datos (Etapa 5), no compensa pagar el coste de handshake de QoS 2 solo para evitar duplicados que ya toleramos.
- **Client ID = `external_identifier` del gateway**, estable entre reconexiones — necesario para que EMQX asocie correctamente la sesión, el LWT y la ACL de ese gateway.
- **Keep-alive MQTT** (PINGREQ/PINGRESP, mecanismo del propio protocolo): 60-120s, configurado en el gateway — es independiente del intervalo de reporte de datos (15-30 min, Etapa 2); un keep-alive corto permite que el broker detecte una conexión caída (y dispare el LWT) mucho antes de que se cumpla el plazo de "sin datos" de la sección 8.

## 8. Detección de offline: dos mecanismos complementarios

1. **LWT (Last Will and Testament)**, a nivel de conexión: al conectar, el gateway registra en EMQX un mensaje `{"online": false}` (retained) sobre `.../status`, que el broker publica automáticamente si la conexión cae sin un `DISCONNECT` limpio (corte de red, apagón). Al conectar con éxito, se publica (retained) `{"online": true}`. `ingestion` está suscrito a `.../status` y reacciona **inmediatamente**, sin esperar al siguiente ciclo del job de timeout.
   - Solo aplica al **gateway** (es una propiedad de su conexión MQTT). Un dispositivo LoRa detrás de un concentrador no tiene conexión propia, por tanto no tiene LWT propio — para él solo aplica el mecanismo 2. Una estación NB-IoT/directa, al ser un gateway de un solo dispositivo (ADR-0004), **sí** se beneficia de LWT también a nivel de "dispositivo" (son la misma entidad física).
2. **Umbral por timeout**, a nivel de dato (cubre dispositivos sin conexión propia, y también gateways cuya conexión sigue técnicamente viva pero han dejado de enviar datos): se marca offline si no se recibe una lectura válida en **2,5 × el intervalo de heartbeat esperado** (Etapa 5, `heartbeat_interval_seconds`) — con un intervalo de 15 min, offline a los ~37,5 min; con 30 min, a los ~75 min. El multiplicador de 2,5 tolera **un** ciclo de reporte perdido por una pérdida temporal de conectividad (Etapa 1) sin disparar una falsa alerta, pero no dos.

## 9. Creación automática de canales

Un `channel` (Etapa 5) se crea automáticamente la primera vez que llega una lectura válida de un `channel_type` conocido para un sensor ya pre-registrado, heredando el umbral por defecto de su tipo a nivel de organización (sin override). **Alternativa considerada**: exigir que el técnico declare explícitamente cada canal de cada sensor antes de aceptar datos — descartada porque añade un paso de provisioning por cada magnitud sin beneficio de seguridad real (la barrera de seguridad ya está en el pre-registro de dispositivo/sensor, sección 6, punto 3-4; un canal es solo "qué magnitud resulta que reporta este sensor ya autorizado").

## 10. Comandos remotos (reservado, V2)
Topic `.../cmd` reservado en el namespace (sección 4) y en la ACL, sin lógica de aplicación ni suscripción activa del gateway en el MVP — evita un cambio incompatible de topics cuando se implemente (Arquitectura, sección 10).

## 11. Versionado y compatibilidad
- `schema_version` empieza en `1`. Cuando exista una v2, `ingestion` debe seguir aceptando v1 (principio ya fijado: compatibilidad hacia atrás en mensajes de dispositivos) hasta que se retire explícitamente con política de deprecación (Etapa 15) — nunca un cambio silencioso que rompa gateways ya desplegados en campo.
- El orden de entrega de QoS 1 no está garantizado entre reconexiones — ya cubierto por la tolerancia al desorden de `latest_readings` (Etapa 5); no se necesita mecanismo adicional aquí.

## 12. Riesgos
- Si el reloj de un gateway se desincroniza de forma sostenida (no solo puntual), sus mensajes se rechazarían sistemáticamente por la regla de la sección 6.5 — se marca como métrica a vigilar en Etapa 10 (no un caso aislado a ignorar).
- La creación automática de canales (sección 9) podría, en teoría, crear canales "basura" si un sensor defectuoso reporta un `channel` inesperado pero con `value` dentro de rango físico válido de ese tipo — riesgo aceptado (bajo impacto: un canal de más, sin datos incorrectos), no se añade validación extra para un caso tan marginal.
- El umbral 2,5× de la sección 8 es un valor de partida razonado, no medido con hardware real — a ajustar con datos reales de campo una vez haya estaciones desplegadas (no bloquea el lanzamiento).

## 13. Entregables de esta etapa
- Este documento (`MQTT_PROTOCOL.md`) con el contrato completo de topics, payload, QoS y detección de offline.

## 14. Criterios de aceptación de esta etapa
- Un gateway y un desarrollador de `ingestion` pueden implementar contra este documento sin necesitar preguntas adicionales sobre formato de mensaje, topic o QoS.
- Cada regla de validación de la sección 6 tiene un motivo de rechazo distinguible (para poder registrar y depurar, Etapa 10).

## 15. Pruebas necesarias derivadas
- Publicar un mensaje válido con 2 lecturas (una válida, una fuera de rango) y confirmar que se almacena la válida y se descarta solo la otra, sin rechazar el mensaje completo.
- Publicar con un `device_id` no pre-registrado para ese gateway y confirmar rechazo completo del mensaje.
- Desconectar bruscamente un gateway (matar el proceso TCP sin `DISCONNECT`) y confirmar que EMQX publica el LWT y que `gateways.status` pasa a `offline` sin esperar al job de timeout.
- Dejar de enviar datos de un dispositivo (sin desconectar el gateway) más de 2,5× su intervalo y confirmar que se marca offline solo ese dispositivo, no el gateway.
- Intentar publicar con una credencial de gateway hacia el topic de otro gateway/organización y confirmar que la ACL lo rechaza (ya cubierto en Etapa 3, se repite aquí con el topic real).
- Publicar un mensaje de más de 8 KB y confirmar que se rechaza sin intentar parsear el JSON.

## 16. Lista de tareas de esta etapa
- [x] Definir topics, payload, QoS y mecanismo de offline.
- [x] Resolver por qué se necesitan dos IDs externos en el payload.
- [x] Decidir creación automática de canales.
- [ ] Revisión y validación por tu parte.
- [ ] Cerrar etapa y pasar a Etapa 7 (contrato de API).

## 17. Dependencias
- Depende de Etapas 0-5 (cerradas/en análisis).
- Bloquea Etapa 7 (la API de consulta refleja estos mismos identificadores externos donde aplique), Etapa 8 (ACL y credenciales concretas), Etapa 9 (configuración real de EMQX), Etapa 13 (`ingestion`).

## 18. Aspectos que se aplazan explícitamente
- Configuración literal de EMQX (auth hook HTTP vs. Postgres, formato exacto de reglas ACL) — Etapa 9.
- Ajuste del multiplicador 2,5× con datos de campo reales.
- `schema_version 2` y su contenido — cuando haga falta, no antes.

## 19. Errores frecuentes a evitar
- No exponer UUIDs internos al hardware de campo — siempre `external_identifier`.
- No usar QoS 2 "por si acaso" — ya deduplicamos en BD, es coste sin beneficio.
- No confundir el keep-alive de MQTT (conexión, segundos) con el intervalo de heartbeat de negocio (dato, minutos) — son mecanismos y escalas de tiempo distintos.
- No rechazar un mensaje completo por una sola lectura inválida dentro de él — se descarta esa lectura, no las demás.
- No usar comodines de organización en la ACL de un gateway concreto — cada credencial debe llevar su `organizationId` y `gatewayExternalId` fijos, nunca un patrón abierto.

## 20. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | Topic por gateway para datos, IDs de sensor/dispositivo en el cuerpo JSON | Topic por sensor individual |
| 2026-07-27 | QoS 1 para datos y estado | QoS 0; QoS 2 |
| 2026-07-27 | Detección de offline: LWT (conexión) + timeout 2,5× (dato) | Solo timeout; solo LWT |
| 2026-07-27 | Creación automática de canales en el primer mensaje válido | Pre-registro explícito de cada canal |
| 2026-07-27 | Credencial MQTT propia y de solo-suscripción para `ingestion` | Reutilizar una credencial de gateway para el proceso de ingesta |
