# NON_FUNCTIONAL_REQUIREMENTS.md

## 0. Estado de este documento
- Etapa del proceso: 2 — Requisitos no funcionales
- Estado: En análisis (cifras propuestas a partir de tus respuestas, pendientes de tu validación)
- Última actualización: 2026-07-27
- Depende de: Etapa 0, Etapa 1
- Bloquea: Etapa 3 (Arquitectura), Etapa 5 (Modelo de datos, particionamiento), Etapa 9 (Infraestructura)

Ninguna cifra de este documento es definitiva por capricho: cada una se justifica a partir de la escala, presupuesto, disponibilidad y retención que has confirmado. Si la realidad se aleja de estos supuestos (p. ej. la escala crece 10x), este documento debe revisarse antes de seguir adelante con Etapa 3.

---

## 1. Decisiones tomadas en esta etapa

| Decisión | Elegido |
|---|---|
| Escala objetivo (12-24 meses) | 50-500 dispositivos, hasta ~20 organizaciones |
| Presupuesto de infraestructura | 100-500 €/mes |
| Disponibilidad objetivo | Media: ~99.5% mensual (~3h40min/mes de inactividad admisible) |
| Retención de telemetría cruda | 2+ años / indefinida (con matiz de arquitectura, ver sección 6) |

## 2. Datos confirmados y suposiciones usadas para convertir la escala en cifras

- **Confirmado**: hasta **4 sensores por dispositivo/estación** ⇒ a escala completa: 500 estaciones × 4 = **2.000 sensores**.
- [SUPOSICIÓN] Media de **2 canales de medición por sensor** (algunos sensores miden una única magnitud; otros, multi-paramétricos, miden varias — p. ej. temperatura + humedad + conductividad) ⇒ a escala completa: 2.000 sensores × 2 ≈ **4.000 canales de medición**. Esta es la unidad que realmente cuenta como fila de telemetría e hilo de alerta (sección 8, `FUNCTIONAL_REQUIREMENTS.md`).
- **Confirmado**: frecuencia de medición de **15 a 30 minutos** por sensor. Para dimensionar con margen de seguridad, este documento usa el extremo más exigente (**15 minutos**) como base de cálculo de mensajes/s y volumen diario.
- **Confirmado**: los mensajes viajan en **JSON**, un mensaje por sensor y ciclo, agrupando las lecturas de todos sus canales (ver sección 9 de `FUNCTIONAL_REQUIREMENTS.md`). Esto significa que el **número de mensajes MQTT** se calcula por sensor (2.000), mientras que el **volumen de filas en base de datos** se calcula por canal (4.000).

La única suposición real que queda abierta es la media de canales/sensor — está marcada para ser fácil de corregir si no es cierta.

## 3. Mensajes por segundo (ingesta MQTT → cola)
- **Media sostenida a escala completa**: ≥ 3 msg/s (2.000 sensores × 96 lecturas/día ÷ 86.400 s ≈ 2,2 msg/s; se redondea al alza con margen).
- **Pico soportado**: ≥ 150 msg/s durante al menos 60 segundos consecutivos. Escenario de referencia: si el 20% de las estaciones (400) pierden conectividad un día completo y, al reconectar, reenvían su backlog acumulado (96 lecturas) en una ventana de recuperación de ~5 minutos, se generan ~130 msg/s — se fija el requisito con margen sobre ese escenario. El pico depende de cuántas estaciones se reconectan a la vez, no de la frecuencia normal, por lo que se mantiene un margen amplio aunque la carga sostenida sea baja.
- Sin pérdida de mensajes en el pico: deben absorberse en cola (Redis/BullMQ), no descartarse ni bloquear el broker.
- Prueba de aceptación: prueba de carga que inyecte 150 msg/s durante 60s y verifique que el 100% de los mensajes válidos aparece finalmente en `telemetria` (aunque con latencia mayor de lo normal durante el pico).

## 4. Frecuencia de medición y volumen diario de datos
- Frecuencia base de cálculo: 1 lectura / 15 min / sensor, es decir 96 lecturas/día por sensor y por canal (sección 2).
- Volumen a escala completa: 4.000 canales × 96 lecturas/día ≈ **384.000 filas/día** de telemetría cruda (~55-60 MB/día con índices, estimación orientativa).
- Proyección: ~20-22 GB/año de dato crudo a escala completa. A este volumen, PostgreSQL particionado por rango de fechas es suficiente; no se justifica una extensión especializada (p. ej. TimescaleDB) solo por volumen — se revisará como ADR en Etapa 3 si aparece otra razón (no solo volumen).

## 5. Latencia máxima (todas en p95 bajo carga normal, no en el pico de la sección 3)
| Operación | Límite |
|---|---|
| Dispositivo → dato visible en "últimas lecturas" | ≤ 5 s |
| API: lectura de listados / últimas lecturas | ≤ 300 ms |
| API: consulta histórica (rango ≤ 30 días, agregación horaria) | ≤ 2 s |
| Detección de alerta → notificación enviada | ≤ 60 s |

## 6. Retención de telemetría
- Agregados (medias horarias/diarias): retención **indefinida** — volumen mucho menor que el dato crudo, coste marginal.
- Dato crudo: **13 meses** con SLA de consulta rápida (sección 5) en PostgreSQL particionado "caliente".
- Dato crudo de más de 13 meses: se conserva (retención de negocio "2+ años/indefinida" confirmada) pero sin garantía de la latencia de la sección 5 — son particiones "frías" que simplemente no se borran.
- **Actualizado en Etapa 5** (`DATA_MODEL.md`): con las cifras reales (~20-22 GB/año a escala completa, sección 4), incluso a 2+ años el volumen total (~40-50 GB) es trivial para una instancia PostgreSQL gestionada dentro del presupuesto de 100-500€/mes. Se descarta el export a almacenamiento S3-compatible planteado inicialmente — añadiría un job de export/restore sin necesidad real. Todo el dato crudo permanece en PostgreSQL particionado.
- **Riesgo marcado**: esta simplificación se acepta bajo el supuesto de la sección 2 (≤500 dispositivos). Si la escala crece un orden de magnitud, se revisa (archivado a S3, compresión, o límite de retención de dato crudo) antes de que el coste de almacenamiento o el tamaño de la instancia se disparen.

## 7. Disponibilidad
- **99.5% mensual** para API y aplicación Flutter (~3h40min/mes de inactividad admisible), excluyendo ventanas de mantenimiento programado y comunicadas con antelación (política de comunicación en Etapa 15).
- **Ingesta MQTT**: debe tolerar una caída del backend de hasta 15 minutos sin pérdida de datos — los gateways siguen intentando publicar y el broker/cola persiste los mensajes hasta que el backend vuelve.
- Sin failover automático ni multi-AZ en el MVP (coherente con presupuesto de 100-500€/mes); recuperación asistida manualmente dentro del RTO de la sección 9.

## 8. RPO (Recovery Point Objective)
- Datos de negocio (usuarios, organizaciones, configuración, alertas): **≤ 15 minutos** de pérdida máxima, vía backups continuos/WAL de PostgreSQL.
- Telemetría: **≤ 5 minutos**, gracias a la persistencia de la cola antes de confirmar el mensaje como procesado.

## 9. RTO (Recovery Time Objective)
- **≤ 4 horas** para restaurar el servicio completo tras un fallo grave (coherente con la disponibilidad "Media" elegida; sin necesidad de failover automático inmediato en el MVP).

## 10. Escalabilidad
- El monolito modular + workers debe escalar horizontalmente (más instancias de API/workers) sin cambios de código hasta **~10x la escala objetivo** (~5.000 dispositivos) antes de necesitar reconsiderar particionamiento de base de datos o la estrategia de mensajería.
- Más allá de ese umbral: revisar este documento, no rediseñar preventivamente ahora (principio ya fijado: no crear microservicios/Kubernetes sin necesidad medible).

## 11. Compatibilidad móvil y web
- Android: últimas 2 versiones mayores soportadas por el canal estable de Flutter (orientativo: Android 8.0 / API 26 en adelante; se fija la versión mínima exacta al elegir la versión de Flutter en Etapa 3).
- iOS: últimas 2 versiones mayores (orientativo: iOS 15 en adelante).
- Web: últimas versiones estables de Chrome, Edge, Firefox y Safari. Sin soporte a navegadores sin WebSocket ni a Internet Explorer.

## 12. Seguridad
- Cumplimiento mínimo: **OWASP ASVS nivel 2**. Nivel 1 es insuficiente para una plataforma multiempresa con datos de varios clientes; nivel 3 es desproporcionado para un MVP con presupuesto de 100-500€/mes. Detalle completo en Etapa 8 (`SECURITY.md`, `THREAT_MODEL.md`).

## 13. Privacidad
- Aplica RGPD (contexto España/UE). Datos personales limitados a los de usuarios (nombre, email, rol); la telemetría ambiental de sensores no constituye dato personal en el caso de uso agro/ambiental definido (no hay geolocalización de personas). Detalle completo en [`PRIVACY.md`](PRIVACY.md): inventario de datos personales, roles de responsable/encargado del tratamiento, derechos de los interesados y procedimiento de notificación de brechas.

## 14. Accesibilidad
- [SUPOSICIÓN — a confirmar si es requisito duro o aspiracional] Objetivo **WCAG 2.1 nivel AA** en el frontend web; nivel A como mínimo bloqueante para el lanzamiento del MVP.

## 15. Coste mensual de infraestructura
- **100-500 €/mes** (confirmado). Esta cifra ya condiciona las decisiones de las secciones 7 y 9 (sin alta disponibilidad ni multi-AZ en el MVP).

## 16. Tiempo máximo de despliegue
- [SUPOSICIÓN] Un despliegue completo a producción (desde merge a `main` hasta verificación post-despliegue) no debe superar **20 minutos**, para poder iterar sin fricción.

## 17. Tiempo máximo de recuperación ante despliegue fallido (rollback)
- **≤ 10 minutos** desde que se detecta el fallo hasta que el rollback se completa (coherente con la estrategia de despliegue sin interrupciones de Etapa 9).

## 18. Rendimiento de consultas históricas
- p95 ≤ 2 s para rango ≤ 30 días con agregación horaria.
- p95 ≤ 5 s para rango de hasta 1 año con agregación diaria.
- Consultas de **dato crudo sin agregar** limitadas a un rango máximo de **7 días por petición** — más allá de eso, la API obliga a usar agregación. Evita que una consulta descontrolada degrade la base de datos para el resto de organizaciones (relevante en un entorno multitenant compartido).

## 19. Resumen de valores medibles (tabla única de referencia)

| Métrica | Valor objetivo |
|---|---|
| Dispositivos (objetivo 12-24 meses) | 500 estaciones (2.000 sensores / ~4.000 canales) |
| Mensajes/s sostenidos | ≥ 3 |
| Mensajes/s en pico (60s) | ≥ 150, sin pérdida |
| Volumen diario | ~384.000 filas / ~55-60 MB |
| Retención dato crudo "caliente" | 13 meses |
| Retención dato crudo archivado | 2+ años / indefinida |
| Latencia ingesta → última lectura | ≤ 5 s (p95) |
| Latencia API listados | ≤ 300 ms (p95) |
| Latencia histórico ≤30d agregado | ≤ 2 s (p95) |
| Latencia alerta → notificación | ≤ 60 s (p95) |
| Disponibilidad | 99.5% mensual |
| RPO negocio / telemetría | ≤ 15 min / ≤ 5 min |
| RTO | ≤ 4 horas |
| Escalabilidad sin rediseño | hasta ~5.000 dispositivos |
| Coste infraestructura | 100-500 €/mes |
| Tiempo de despliegue | ≤ 20 min |
| Tiempo de rollback | ≤ 10 min |
| Rango máx. consulta de dato crudo | 7 días |

## 20. Criterios de aceptación de esta etapa
- Todas las cifras anteriores son verificables mediante una prueba concreta (carga, latencia, o auditoría de configuración) — ninguna queda como adjetivo sin número.
- Las suposiciones marcadas (secciones 2, 14, 16) están explícitas y son fácilmente corregibles sin invalidar el resto del documento.

## 21. Pruebas necesarias derivadas
- Prueba de carga: 3 msg/s sostenidos durante 1 hora sin degradación de latencia (sección 3 y 5).
- Prueba de pico: ráfaga de 150 msg/s durante 60s tras simular reconexión de varias estaciones, verificando cero pérdida de mensajes.
- Prueba de consulta: rango de 30 días agregado por hora responde en ≤2s con la tabla de telemetría poblada a volumen de 1 año completo (no con una tabla vacía, para que la prueba sea representativa).
- Prueba de límite: una petición de dato crudo sin agregar con rango >7 días debe ser rechazada por la API con un error claro, no truncada silenciosamente.
- Prueba de recuperación: restaurar un backup y medir que el tiempo total está dentro del RTO de 4 horas.
- Prueba de despliegue: medir el tiempo real del pipeline CI/CD end-to-end contra el límite de 20 minutos, y el tiempo de rollback contra el límite de 10 minutos.

## 22. Lista de tareas de esta etapa
- [x] Confirmar escala, presupuesto, disponibilidad y retención.
- [x] Convertir cada NFR ambiguo en una cifra verificable.
- [ ] Revisión del usuario / ajustes.
- [ ] Cerrar etapa y pasar a Etapa 3 (Arquitectura).

## 23. Dependencias
- Depende de Etapas 0 y 1 (ya cerradas).
- Bloquea: Etapa 3 (arquitectura: dimensionado de colas, réplicas, particionamiento), Etapa 5 (estrategia de particionamiento/archivado de telemetría), Etapa 9 (infraestructura: elección de proveedor y tier acorde al presupuesto).

## 24. Aspectos que se aplazan explícitamente
- Elección concreta de proveedor cloud/VPS y su tier exacto (Etapa 9), aunque ya queda acotado por el presupuesto de 100-500€/mes.
- Estrategia exacta de archivado (Postgres cold partitions vs. export a S3) — se decide en Etapa 5 con más detalle de modelo de datos.
- Nivel de accesibilidad definitivo (AA vs. aspiracional) — confirmar antes de cerrar Etapa 14 (frontend), no bloquea el resto ahora.

## 25. Errores frecuentes a evitar
- No aceptar "rápido", "seguro" o "escalable" sin cifra — ya se ha hecho el ejercicio aquí, no relajarlo en etapas posteriores.
- No dimensionar la arquitectura (Etapa 3) para una escala mayor a la aquí acordada "por si acaso" — el principio ya fijado es no sobre-diseñar sin necesidad medible.
- No tratar la retención "indefinida" como excusa para no particionar/archivar: sin la estrategia de la sección 6, el coste crecería sin control aunque el volumen por sí solo sea manejable.
- No confundir RPO (cuánto dato se puede perder) con RTO (cuánto se tarda en recuperar el servicio): son cifras independientes y ambas están fijadas arriba.

## 26. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | Escala objetivo: 50-500 dispositivos, ~20 organizaciones | Piloto <50; 500-5.000; >5.000 |
| 2026-07-27 | Presupuesto: 100-500 €/mes | <100€ self-hosted único VPS; 500-2.000€; >2.000€ |
| 2026-07-27 | Disponibilidad: Media, 99.5% mensual | Básica 99%; Alta 99.9%; Crítica 99.95%+ |
| 2026-07-27 | Retención cruda: 2+ años/indefinida, con archivado a partir de 13 meses | 3-6 meses; 1 año |
| 2026-07-27 | Recalculado con datos reales del usuario: 4 sensores/estación, 2 canales/sensor (supuesto), frecuencia 15-30 min (se usa 15 min como peor caso) | Cifras previas basadas en 3 sensores/dispositivo y frecuencia de 5 min (descartadas) |
