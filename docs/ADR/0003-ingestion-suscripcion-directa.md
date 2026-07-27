# ADR-0003: Ingesta MQTT con suscripción directa (sin shared subscriptions) en el MVP

- Estado: Aceptada
- Fecha: 2026-07-27

## Contexto
Carga estimada en Etapa 2: ≥3 msg/s sostenidos, ≥150 msg/s en pico (60s) a escala completa (500 estaciones). MQTT 5 / EMQX soportan suscripciones compartidas (`$share/grupo/topic`) para repartir mensajes entre varias instancias de un mismo consumidor.

## Decisión
El proceso `ingestion` arranca como una única instancia con una suscripción MQTT normal (no compartida) a los topics de telemetría. No se escala horizontalmente el proceso de ingesta en el MVP.

## Alternativas consideradas
- **Suscripciones compartidas desde el día 1**, permitiendo varias instancias de `ingestion` en paralelo: descartada por ahora. La carga estimada (unos pocos mensajes por segundo sostenidos, picos de segundos) la absorbe cómodamente un único proceso Node.js; escalar preventivamente sin necesidad medida contradice el principio ya fijado de no sobre-diseñar.

## Consecuencias
- El camino de escalado queda documentado: cuando el volumen lo requiera (revisar Etapa 2 si la escala real supera lo estimado), se cambia el topic de suscripción a `$share/ingestion/...` y se despliegan más réplicas del proceso `ingestion` — cambio de configuración, no de esquema de topics de publicación de los gateways (compatible hacia atrás).
- Con una única instancia, `ingestion` es un punto único de fallo para la ingesta (no para la API de usuarios, que sigue funcionando). Debe documentarse en `INCIDENT_RESPONSE.md` (etapa posterior) cómo se detecta y se reinicia, y verificarse que EMQX retiene la sesión/mensajes según QoS mientras no hay consumidor (configuración a validar en Etapa 9).
