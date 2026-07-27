# ADR-0001: Monolito modular con procesos separados (api/ingestion/worker)

- Estado: Aceptada
- Fecha: 2026-07-27

## Contexto
20 módulos de dominio, equipo de 3-6 personas, plazo de unos meses para el MVP, presupuesto de infraestructura de 100-500€/mes, escala objetivo de 500 estaciones (~3 msg/s sostenidos, Etapa 2). El usuario fijó como principio de partida: empezar con monolito modular y workers independientes, sin microservicios hasta que exista una necesidad medible, y separar la API de usuarios del canal de comunicación de dispositivos.

## Decisión
Un único código base (monorepo) con tres puntos de entrada desplegables: `api` (REST + WebSocket para usuarios), `ingestion` (único proceso que habla MQTT con EMQX) y `worker` (consumidor de BullMQ). Comparten módulos de dominio y capa de acceso a datos, pero se despliegan, escalan y reinician de forma independiente.

## Alternativas consideradas
- **Microservicio por módulo de dominio** (usuarios, telemetría, alertas... como servicios separados): descartada. El coste operativo (orquestación, redes internas, observabilidad distribuida, versionado de contratos entre servicios) no está justificado por la carga real (Etapa 2) ni por el tamaño de equipo; habría ralentizado el MVP sin beneficio medible.
- **Proceso único** (api, ingestion y worker en el mismo proceso): descartada. Mezclaría el ciclo de vida de peticiones HTTP de usuario con la ingesta de dispositivos, violando el principio de separar ambos canales, y arriesgando que un pico de telemetría (hasta 150 msg/s, Etapa 2) degrade la latencia de la API de usuarios.

## Consecuencias
- Necesita un mecanismo de coordinación entre procesos (Redis pub/sub para eventos de tiempo real, BullMQ para trabajo).
- Los límites de módulo ya existen en el código, por lo que extraer un módulo concreto a un servicio independiente en el futuro (si la carga lo justifica) es un cambio incremental, no una reescritura.
- Un solo repositorio y pipeline de CI/CD que construye una imagen y despliega tres variantes de contenedor (mismo build, distinto `CMD`).
