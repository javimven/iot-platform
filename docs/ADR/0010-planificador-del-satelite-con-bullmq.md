# ADR-0010: El repaso diario del satélite usa el planificador de BullMQ, no `setInterval`

- Estado: Aceptada
- Fecha: 2026-09-22

## Contexto

El módulo de satélite (BACKLOG.md #36) necesita un trabajo periódico: cada día, buscar si Sentinel-2 ha pasado por encima de cada parcela y encolar lo que haya nuevo.

Todos los trabajos periódicos que ya existen en el proyecto usan `setInterval` dentro de un servicio de Nest: `OfflineDetectionService` (60 s), `NoSensorDataService` (5 min), `NotificationDispatchService` (30 s) y `TelemetryPartitionsService` (12 h). Funcionan bien, y su propio código deja escrita la condición que lo hace posible: *"se revisita si hace falta coordinar el escaneo entre varias réplicas de `worker` en el futuro"*. Hoy hay **una sola** réplica de `worker`.

## Decisión

El repaso del satélite **no hereda ese patrón**. Se registra como *job scheduler* de BullMQ (`Queue.upsertJobScheduler`, patrón cron `30 4 * * *` UTC) sobre la cola `satellite-processing`.

Y esa cola es **propia, separada de `telemetry-processing`**: procesar una imagen tarda segundos y depende de una API de terceros, y eso no puede ponerse nunca por delante del mensaje de una estación. Las consume el mismo proceso `worker`; no hace falta un contenedor nuevo mientras el volumen sea este.

## Por qué aquí sí y en los demás no

La diferencia no es el gusto, es el coste de equivocarse:

- Con `setInterval`, **dos réplicas de `worker` harían dos repasos simultáneos**. En `OfflineDetectionService` eso significa mirar dos veces las mismas filas: trabajo de más, resultado idéntico. Aquí significa **gastar el doble de cuota de Copernicus**, que está limitada y es la única parte del sistema que se paga por uso.
- La planificación de BullMQ vive en Redis, así que el repaso se ejecuta una vez aunque haya varios consumidores. Es el mismo Redis que ya está en producción: **cero tecnología nueva**.
- De propina, lo que `setInterval` no da: reintentos con espera, historial de fallos y un trabajo que no se pierde si el proceso se reinicia a mitad.

`upsertJobScheduler` es idempotente: arrancar el worker diez veces no crea diez planificaciones, y cambiar la hora actualiza la que hay en vez de añadir otra.

## Consecuencias

- El proyecto pasa a tener **dos formas** de programar trabajo periódico. Es deuda consciente: lo coherente a futuro sería mover los cuatro `setInterval` a este mismo mecanismo, y queda anotado en el BACKLOG. Mientras tanto, el fichero del worker de satélite explica por qué no sigue al vecino, para que no parezca un despiste.
- El repaso corre a las **4:30 UTC**: de madrugada, y a una hora rara a propósito para no caer en el minuto en punto en el que medio mundo lanza sus cron contra las mismas APIs.
- Una parcela recién creada no espera al repaso: su histórico se encola en el momento del alta (`SatelliteQueueProducer`, desde el proceso `api`). Si ese encolado falla, **no** se rompe la creación de la parcela: el repaso del día siguiente la recogerá igual.

## Alternativa descartada

`SatelliteSchedulerService` con `setInterval`, como los demás. Encaja mejor con lo que ya hay y no necesita explicación, pero traslada al futuro un problema conocido —y en el único sitio del sistema donde ejecutar dos veces cuesta dinero de verdad.
