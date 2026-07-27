# FUNCTIONAL_REQUIREMENTS.md

## 0. Estado de este documento
- Etapa del proceso: 1 — Requisitos funcionales
- Estado: En análisis (decisiones clave cerradas, contenido en borrador pendiente de tu revisión)
- Última actualización: 2026-07-27
- Depende de: Etapa 0 ([`PRODUCT_REQUIREMENTS.md`](PRODUCT_REQUIREMENTS.md))
- Bloquea: Etapa 4 (modelo de permisos detallado), Etapa 5 (modelo de datos), Etapa 6 (MQTT), Etapa 7 (API)

Este documento define **comportamiento**, no estructura de tablas ni de API — eso corresponde a etapas posteriores. Se centra en el alcance del **MVP**; lo diferido a V2/Futuro se indica explícitamente y no se detalla todavía.

---

## 1. Decisiones tomadas en esta etapa

| Decisión | Elegido |
|---|---|
| Pertenencia usuario↔organización | Muchos-a-muchos vía módulo Miembros; un usuario puede pertenecer a varias organizaciones, con un rol distinto (único) por organización |
| Aprovisionamiento de gateways/dispositivos | Pre-registro obligatorio en la plataforma antes de que puedan enviar telemetría aceptada |
| Configuración de umbrales de alerta | Por canal de medición, con valor por defecto heredado del tipo de canal (magnitud) a nivel de organización (override opcional) |
| Destinatarios de notificaciones (MVP) | Todos los miembros con rol Admin de organización, Técnico u Operador de la organización afectada (Solo lectura no recibe notificaciones automáticas) |

## 2. Organizaciones
- Alta: exclusivamente por el administrador de plataforma (decidido en Etapa 0). Campos MVP: nombre, identificador único (slug), email de contacto principal, estado.
- Al crear la organización, el admin de plataforma invita también a su primer Administrador de organización (mismo flujo de invitación que el resto de miembros, sección 3).
- Estados: `activa` → `suspendida` (bloquea login de todos sus miembros y rechaza autenticación de sus gateways/dispositivos) → baja lógica (soft delete, sin borrado físico en MVP).
- Sin datos de facturación/plan en MVP (Futuro).

## 3. Usuarios y Miembros
- **Usuario**: identidad global (email único + contraseña). Independiente de cualquier organización.
- **Miembro**: tupla (usuario, organización, rol). Un usuario puede tener varios Miembros (una organización por rol), nunca dos roles distintos dentro de la misma organización en MVP.
- **Invitación**: un Admin de organización invita por email con un rol asignado. Se crea el Miembro en estado `invitado`. Se envía un enlace de un solo uso con caducidad (valor exacto en Etapa 2 — NFR). Si el email ya tiene Usuario, se asocia el Miembro tras aceptar; si no, el enlace permite crear la contraseña.
- Estados de Miembro: `invitado` → `activo` → `suspendido` (revocable por Admin de organización sin borrar su histórico de auditoría) → baja lógica.
- Ningún usuario puede autoinvitarse ni crear organizaciones (alta 100% controlada, Etapa 0).
- **Selector de organización activa**: si un usuario tiene ≥2 Miembros activos, elige organización activa al entrar; el contexto de sesión queda ligado a esa organización (cambiar de organización re-emite el contexto de autorización, nunca es solo un cambio de vista en el frontend — relevante para el aislamiento multitenant de la Etapa 8).

## 4. Roles y permisos (alto nivel — matriz fina en Etapa 4)

| Capacidad | Admin plataforma | Admin organización | Técnico | Operador | Solo lectura |
|---|---|---|---|---|---|
| Gestionar organizaciones | Sí (todas) | No | No | No | No |
| Gestionar miembros/roles de su organización | No | Sí | No | No | No |
| Alta/baja instalaciones, zonas, gateways, dispositivos, sensores | No | Sí | Sí | No | No |
| Configurar umbrales de alerta | No | Sí | Sí | No | No |
| Ver telemetría, últimas lecturas, gráficas | No¹ | Sí | Sí | Sí | Sí |
| Reconocer / resolver alertas | No¹ | Sí | Sí | Sí | No |
| Ver auditoría de la organización | No¹ | Sí | Parcial (técnica) | No | No |

¹ El Admin de plataforma no accede por defecto a datos operativos de ninguna organización (telemetría, alertas, auditoría de negocio). Un futuro "modo soporte" auditado y explícito queda fuera del MVP (backlog Futuro).

> Matriz fina (acción por acción, con el mecanismo de alcance por instalación) en [`PERMISSIONS.md`](PERMISSIONS.md) — Etapa 4.

## 5. Instalaciones y Zonas
- Instalación: pertenece a una organización. Campos MVP: nombre, ubicación en texto libre, **coordenadas GPS (latitud/longitud)**, estado activa/inactiva. Se capturan desde el MVP aunque la función que las usa (pestaña de tiempo, V2) no se construya todavía — resuelve la pregunta abierta heredada de Etapa 0. Sin mapa visual en el MVP (solo el dato, no la interfaz de mapa).
- Zona: pertenece a una instalación, jerarquía plana en MVP (sin sub-zonas anidadas). Campos: nombre, tipo libre (texto).

## 6. Gateways (unidad de conexión — [ADR-0004](ADR/0004-unidad-de-conexion-lora-y-nbiot.md))
- "Gateway" cubre dos topologías de conectividad:
  - **Concentrador LoRa**: agrupa varios dispositivos que llegan por LoRa y transmite por GPRS/Ethernet/otros.
  - **Estación de conexión directa** (NB-IoT u otra tecnología con IP propia): la propia estación de campo abre la conexión MQTT sin concentrador intermedio. Se registra igual que un gateway, pero con un único dispositivo asociado (el mismo equipo físico).
- Registro: pre-registro obligatorio por Técnico o Admin de organización, antes del despliegue físico, indicando el tipo de conectividad (`connectivity_type`: concentrador LoRa / NB-IoT directo / otro directo). Genera identificador único y credenciales MQTT propias (mecanismo criptográfico exacto en Etapa 8).
- Un gateway se asocia a **una única instalación** (simplificación de MVP — ver `PERMISSIONS.md`).
- Estados: `no_aprovisionado` → `online` (heartbeat/datos recientes) → `offline` (sin señal dentro del intervalo esperado) → `deshabilitado` (revocación manual).
- Intervalo de heartbeat esperado: configurable por gateway, con valor por defecto a nivel de organización [SUPOSICIÓN: el valor numérico se fija en Etapa 2 — NFR].

## 7. Dispositivos
- Pre-registro obligatorio. Un dispositivo detrás de un **concentrador LoRa** no tiene credencial de red propia (llega por LoRa al gateway); su "pre-registro" significa que el sistema rechaza a nivel de aplicación cualquier dato que referencie un `device_id` no registrado para ese gateway (ver `ARCHITECTURE.md`, sección 6). Una **estación de conexión directa** es, a la vez, su propio gateway y su único dispositivo (ADR-0004) — el pre-registro es, de facto, un único paso desde la perspectiva del usuario, aunque cree dos registros internamente.
- Un dispositivo (también llamado **estación** en el dominio agro/ambiental) se asocia a un gateway (canal de transmisión, que en el caso directo es la propia estación) y a una zona (ubicación lógica). **Regla de integridad**: la zona de un dispositivo debe pertenecer a la misma instalación que su gateway (detalle de constraint en Etapa 5).
- Un dispositivo tiene **hasta 4 sensores** conectados (confirmado).
- Su estado online/offline se calcula de forma independiente al del gateway: un gateway puede estar online mientras un dispositivo concreto conectado a él ha dejado de reportar (p. ej. batería agotada). En una estación de conexión directa, ambos estados coincidirán casi siempre (es el mismo equipo físico) — redundancia menor aceptada, no se modela de forma especial.

## 8. Sensores y canales de medición
- **Sensor**: sonda/transductor físico conectado a un dispositivo. Un mismo sensor puede medir **más de una magnitud a la vez** (p. ej. una sonda que reporta temperatura, humedad y conductividad en el mismo ciclo) — por tanto, un sensor expone **1 o varios canales de medición**.
- **Canal de medición**: unidad real de una magnitud. Cada canal tiene: tipo (temperatura, humedad, conductividad, nivel, batería...), unidad, tipo de dato (numérico continuo / booleano / contador), rango físicamente válido, y opcionalmente un umbral de alerta propio que sobrescribe el umbral por defecto de su tipo a nivel de organización (sección 1). **La telemetría, las últimas lecturas y las alertas de umbral se referencian siempre a un canal, no a un sensor completo.**
- Catálogo de tipos de canal gestionado a nivel de plataforma (no por organización).
- Tipos iniciales [SUPOSICIÓN, ampliable sin cambios estructurales]: temperatura ambiente (°C), humedad relativa (%), humedad de suelo (%), conductividad (µS/cm), nivel de depósito (%), batería (V o %), intensidad de señal (dBm), **precipitación acumulada (mm, tipo `counter`)**.
- Cada tipo de canal tiene un **método de agregación por defecto** (`average` para magnitudes instantáneas, `sum` para acumulativas como la precipitación, `count_true` para booleanas) — necesario para que las gráficas e informes agregados (sección 12) resuman cada magnitud con sentido (Etapa 5, `DATA_MODEL.md`).
- [SUPOSICIÓN] Media de 2 canales por sensor (algunos miden una única magnitud; otros, como el multi-paramétrico del ejemplo, miden 3). Es la base de cálculo de volumen de datos en `NON_FUNCTIONAL_REQUIREMENTS.md`.

## 9. Telemetría — formato de medición
- Formato de mensaje: **JSON** (confirmado). Un mensaje corresponde a **un sensor** en un instante dado y agrupa las lecturas de **todos sus canales** en ese ciclo (p. ej. un único mensaje con temperatura + humedad + conductividad) — reduce el número de publicaciones MQTT sin perder granularidad (cada canal se sigue almacenando como fila independiente).
- Cada mensaje incluye como mínimo: identificador de sensor, marca de tiempo de origen (asignada por el dispositivo/estación), versión de esquema (`schema_version`), y una lista de lecturas `{canal, valor}`.
- El servidor añade una marca de tiempo de recepción; se conservan ambas (origen y recepción) para diagnosticar reenvíos o desfases.
- Deduplicación: mismo dato si coincide (canal, timestamp de origen) o (sensor, id de mensaje si existe); mecanismo exacto (constraint de BD) en Etapa 5.
- Valores fuera del rango físico válido de su canal se descartan sin generar alerta de umbral, pero se registran como "lectura inválida" (Etapa 10) para detectar sensores defectuosos.
- El campo `schema_version` permite evolucionar el formato sin romper estaciones/gateways antiguos (esquema completo en Etapa 6 — `MQTT_PROTOCOL.md`).

## 10. Últimas lecturas
- Tabla derivada: por canal de medición, último valor válido conocido + su timestamp de origen. Se actualiza solo si el timestamp entrante es más reciente que el ya registrado (tolera desorden). Evita consultar el histórico completo para pintar el estado actual.

## 11. Consulta de datos históricos
- API de consulta por sensor (o conjunto de sensores de una zona/instalación) y rango de fechas, paginada.
- Rango máximo por petición y política de agregación (crudo vs. promedios) se fijan como valores numéricos en Etapa 2 (NFR) — no se aceptan como "rápido" sin cifra.

## 12. Gráficas (MVP)
- Gráfica de línea temporal por canal, accesible al pulsar sobre su última lectura en el dashboard. Rangos predefinidos: **24h, 48h, 7 días, 30 días**, y rango personalizado.
- El método de agregación (sección 8: `average` con min/max, o `sum`) se elige automáticamente según el tipo de canal — sin selector manual en el MVP (el selector manual para forzar otra representación queda en V2, `BACKLOG.md`).
- Sin comparativa multi-sensor superpuesta ni dashboards personalizables (diferido a V2).

## 13. Detección de dispositivo/gateway offline
- Basada en heartbeat/última comunicación: si no reporta dentro de su intervalo esperado (configurable, con valor por defecto de organización), pasa a `offline` y dispara automáticamente una alerta de tipo "offline".
- La reconexión (`offline` → `online`) resuelve automáticamente esa alerta concreta, quedando registrada en el histórico.

## 14. Alertas
- Tipos MVP: (a) umbral de un canal de medición superado (por encima/por debajo de un límite), (b) dispositivo/gateway offline.
- Ciclo de vida: `abierta` → `reconocida` (acción manual de Operador, Técnico o Admin de organización) → `resuelta`.
- Resolución: la de tipo offline se auto-resuelve al reconectar. La de umbral [SUPOSICIÓN] se auto-resuelve cuando el valor vuelve a rango normal de forma sostenida; permanece siempre visible en el histórico independientemente de cómo se resuelva.
- Mientras una alerta de un canal/tipo está abierta, no se generan alertas duplicadas por la misma causa (una única alerta abierta por canal+tipo hasta resolverse).
- Solo lectura no puede reconocer ni resolver alertas (tabla de la sección 4).

## 15. Notificaciones
- Canal MVP: email.
- Destinatarios: Admin de organización, Técnico y Operador de la organización afectada (sección 1). Sin suscripción granular por usuario/zona en MVP (diferido a V2).
- Sin resúmenes/digest ni preferencias horarias en MVP; el throttling técnico para no reenviar email repetidamente por una misma alerta abierta se resuelve como detalle de diseño en etapas posteriores, no como requisito funcional visible al usuario.

## 16. Comandos remotos — diferido a V2
- Fuera de alcance del MVP: ningún mecanismo de control hacia dispositivos. Se detallará al abordar la fase de producto V2.

## 17. Firmware — diferido a V2
- Fuera de alcance del MVP. Se detallará al abordar V2.

## 18. Exportación de datos — diferido a V2
- El MVP no incluye exportación; solo consulta vía UI/API (sección 11).

## 19. Auditoría (acciones registradas en MVP)
- Alta, suspensión y baja de organización.
- Invitación, activación, cambio de rol, suspensión y baja de un miembro.
- Alta, deshabilitación y baja de gateway o dispositivo.
- Cambios en la configuración de umbrales de alerta.
- Reconocimiento y resolución manual de alertas.
- Revocación de sesión.

No se audita: lecturas de telemetría normales ni navegación de solo consulta (volumen sin valor).

## 20. MVP vs. V2 vs. Futuro
Ver [`PRODUCT_REQUIREMENTS.md`, sección 9](PRODUCT_REQUIREMENTS.md#9-propuesta-de-alcance-por-fases-borrador) para la división completa por módulo. Este documento no la repite, solo añade el comportamiento de lo que sí entra en MVP.

## 21. Preguntas abiertas (heredadas de Etapa 0, aún sin bloquear esta etapa)
- ~~¿Geolocalización/mapa de instalaciones desde el MVP?~~ Resuelto: se captura GPS (lat/lng) desde el MVP, sin mapa visual todavía.
- ¿Hay clientes piloto ya identificados o se valida internamente primero?
- ¿Basta con email para notificaciones en MVP o se necesita push móvil desde el día 1?

## 22. Criterios de aceptación de esta etapa
- Cada módulo del MVP tiene comportamiento descrito sin ambigüedad suficiente para pasar a modelo de datos (Etapa 5) y contrato de API (Etapa 7).
- Las 4 decisiones de la sección 1 no contradicen los principios ya fijados (aislamiento multitenant, sin credenciales compartidas entre dispositivos, no confiar en permisos de frontend).

## 23. Pruebas necesarias derivadas (para etapas posteriores)
- Un mismo email invitado a dos organizaciones distintas termina en un único Usuario con dos Miembros independientes.
- Un dispositivo no pre-registrado no puede publicar telemetría aceptada por el sistema.
- Un canal de medición sin umbral propio hereda el de su tipo a nivel de organización; al definir uno propio, lo sobrescribe.
- La alerta de offline se auto-resuelve al reconectar; la de umbral requiere que el valor vuelva a rango antes de auto-resolverse.
- El Admin de plataforma no puede leer telemetría/alertas/auditoría de negocio de ninguna organización.
- Cambiar de organización activa revoca el contexto de autorización de la organización anterior (no es solo un cambio de UI).

## 24. Aspectos que se aplazan explícitamente
- Matriz de permisos fina, por acción y módulo (Etapa 4).
- Valores numéricos de NFR: intervalos de heartbeat, retención, latencia, tamaño máximo de rango consultable (Etapa 2).
- Mecanismo criptográfico exacto de credenciales de dispositivo (Etapa 8).
- Formato exacto de payload MQTT y versionado (Etapa 6).
- Todo lo relativo a comandos remotos, firmware y exportación (fase de producto V2).

## 25. Errores frecuentes a evitar
- Definir "offline" sin intervalo numérico configurable — nunca debe quedar como concepto vago.
- Dar al rol Técnico permisos de gestión de usuarios/roles (no le corresponden).
- Confundir "resolver una alerta" con "que el valor vuelva a rango": son conceptos relacionados pero no idénticos.
- Dar al Admin de plataforma acceso implícito a datos de organizaciones: debe ser excepción explícita y auditada (Futuro), nunca el comportamiento por defecto.
- Diseñar el modelo de Miembro como si un usuario perteneciera a una sola organización — ya se decidió que es muchos-a-muchos.

## 26. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | Pertenencia usuario↔organización muchos-a-muchos vía Miembros | Pertenencia exclusiva a una única organización |
| 2026-07-27 | Pre-registro obligatorio de gateways/dispositivos | Auto-descubrimiento con reclamación posterior |
| 2026-07-27 | Umbral por sensor con default heredado del tipo a nivel de organización | Solo por sensor; solo por tipo a nivel de organización |
| 2026-07-27 | Notificaciones a Admin de organización + Técnico + Operador | Solo Admin de organización; suscripción granular desde MVP |
| 2026-07-27 | Modelo sensor→canal de medición (un sensor puede tener varios canales); hasta 4 sensores/estación; frecuencia 15-30 min; formato de mensaje JSON | Modelo "1 sensor = 1 magnitud" (descartado tras aclaración del usuario) |
| 2026-07-27 | Soporte de estaciones NB-IoT/directas modeladas como gateway de un solo dispositivo (ADR-0004) | Tabla de credenciales de dispositivo paralela (descartada, duplicaba lógica ya construida) |
