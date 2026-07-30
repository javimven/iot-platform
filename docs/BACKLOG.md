# BACKLOG.md

Captura continua de ideas/funcionalidades que surgen durante el diseño, fuera del orden de las etapas formales. Cada entrada se clasifica en cuanto se captura:

- **MVP**: entra en el alcance ya cerrado en `PRODUCT_REQUIREMENTS.md` sección 9.1.
- **V2**: fase de producto posterior al MVP (sección 9.2).
- **Futuro**: backlog sin fecha (sección 9.3).
- **Sin decidir**: capturada pero pendiente de que tú y yo decidamos dónde encaja.

Última actualización: 2026-07-27 (volcado inicial).

## Cómo se usa este documento
- Cuando se te ocurra algo, dímelo en cualquier momento — no hace falta esperar a un punto concreto del proceso.
- Lo añado aquí con una frase, la clasifico con mi recomendación, y si afecta a una etapa ya cerrada (p. ej. cambia el modelo de datos), lo señalo explícitamente en el documento de esa etapa en vez de tocarlo en silencio.
- Las entradas "Sin decidir" se revisan contigo antes de que la etapa a la que afectan se dé por cerrada.

---

## Volcado inicial (2026-07-27)

### 1. Dashboard de estación con última lectura + gráfica al pulsar
**MVP.** Ya estaba en `FUNCTIONAL_REQUIREMENTS.md` secciones 10-12. Ajustado con tu detalle: rangos de gráfica 24h/48h/7d/30d (añadí 48h), y el método de agregación (media o acumulado) se elige automáticamente según el tipo de canal — ver más abajo, punto de "agregación por tipo".

### 2. Configurar/añadir/quitar sensores de una estación
**MVP.** Ya cubierto por los permisos de Técnico/Admin de organización (`sensors.create/update/delete`, `PERMISSIONS.md`). Sin cambios.

### 3. Agregación de gráficas: media vs. acumulado según el tipo de dato (ej. lluvia)
**MVP — aplicado ya**, porque afecta a la corrección de la función de gráficas que ya está en el MVP (una gráfica de lluvia promediada es simplemente errónea, no es una mejora futura). Añadí `channel_types.default_aggregation` (`average` / `sum` / `count_true`) en `DATA_MODEL.md` y `precipitación acumulada` como tipo de canal de ejemplo.
- [SUPOSICIÓN a verificar en Etapa 6]: se asume que el sensor de lluvia reporta el incremento desde la última lectura (no un contador que solo crece). Si el hardware real funciona distinto, la agregación cambia de "sumar valores" a "diferencia entre el primer y último valor del periodo".
- El **selector manual** para forzar otra representación (ver la lluvia como instantánea, o la temperatura como acumulada) queda en **V2** — el MVP solo aplica el método correcto por defecto, sin control de usuario.

### 4. Coordenadas GPS en instalaciones
**MVP — aplicado ya** (campo barato de añadir ahora, caro de migrar después). Añadí `latitude`/`longitude` a `installations` en `DATA_MODEL.md`. Resuelve la pregunta abierta que quedaba de la Etapa 0.

### 5. Pestaña de tiempo/clima (API de terceros tipo AEMET/OpenWeatherMap, hoy y semana)
**V2.** Nueva integración externa: requiere gestión de API key del proveedor, caché (no llamar a la API externa en cada vista de usuario) y pasa a formar parte de "estado de proveedores externos" en observabilidad (ya anticipado en `OBSERVABILITY.md`, pendiente de escribir en Etapa 10). Depende del punto 4 (ya resuelto).

### 6. Informes en PDF (intervalo personalizable, selección de sensores, máx/mín/medias por día, identificación clara de estación)
**V2.** Nuevo módulo "Informes", más elaborado que la simple "exportación de datos" ya prevista en V2 (Etapa 0) — de hecho la sustituye/amplía. Requiere: generación de PDF (librería HTML→PDF o similar), consultas de agregación por día (min/max/avg — ya soportadas por el esquema de `telemetry` sin cambios, es una consulta SQL, no una tabla nueva), y una UI de selección de sensores/rango. Se combina de forma natural con el punto 10 (Campañas): el intervalo de un informe podría fijarse automáticamente al rango de una campaña.
- **Sugerencia mía**: además del PDF, ofrecer export CSV/Excel de los mismos datos con el mismo selector de sensores/rango — mismo componente de UI, dos formatos de salida, sin duplicar trabajo.
- **Sugerencia mía**: un "resumen periódico" por email (diario/semanal, min/max/avg + alertas del periodo) es mucho más barato de construir que el motor de informes completo y da valor antes — candidato a V2 temprano, antes del informe PDF completo.

### 7. Acceso a servicios de terceros vía API (ej. imágenes satelitales para humedad de parcela)
**Futuro.** Exploratorio por tu propia descripción ("si fuera necesario"). Nota de modelado: si esto avanza, probablemente haga falta un polígono de parcela (no solo el punto GPS del punto 4) — no se modela todavía.

### 8. Alertas de riesgo de enfermedades (modelos agronómicos sobre los datos)
**Futuro.** Va más allá de un umbral simple (Etapa 1): los modelos de riesgo de enfermedad reales (mildiu, botritis, etc.) combinan temperatura + humedad + duración en ventanas de tiempo, por cultivo. Depende del punto 10 (Campañas) para saber qué cultivo hay en cada parcela y en qué fase.

### 9. Pestaña de recomendaciones (ej. sobre riego)
**Futuro.** Junto con el punto 8, es candidato natural para el agente de IA (punto 11) en vez de reglas hechas a mano.

### 10. Agente de IA sobre los datos + feedback del usuario
**Futuro** (implementación), pero **nota arquitectónica añadida ya** en `ARCHITECTURE.md` sección 10: el diseño actual (telemetría en PostgreSQL, monolito modular + workers) no bloquea añadir un futuro proceso de lectura/IA más adelante. Sin cambios de esquema ahora.
- **Sugerencia mía**: cuando se construyan las recomendaciones (punto 9), capturar el feedback del usuario (útil / no útil, o similar) desde el primer momento, no añadirlo después — es el dato de entrenamiento para el agente futuro.

### 11. Multi-idioma + control centralizado de qué ve cada organización
**Resuelto (2026-07-27):**
- **Idioma: autoservicio, no admin-controlado.** Cada usuario elige su idioma (español, inglés, francés) desde una pestaña de configuración. **V2** — no se toca el modelo de datos ahora (se añadirá `users.locale` cuando se diseñe V2 de frontend, Etapa 14).
- **Control centralizado = feature flags por organización, no idioma.** Lo que el Admin de plataforma controla es qué pestañas/módulos ve cada organización (informes, campañas, clima, satélite...). Si una función no está contratada, la pestaña aparece **bloqueada** (visible, no oculta) en vez de desaparecer — mecanismo de upsell. **Mecanismo construido ya** (infraestructura, aunque casi todas las funciones concretas que gatea son V2/Futuro): tablas `features`/`organization_features` en `DATA_MODEL.md`, permisos `org_features.read/update` en `PERMISSIONS.md`.
- **Además surgió**: querías que el Admin de plataforma pueda añadir/quitar estaciones y sensores de **cualquier** organización sin ser miembro de ella (tu empresa hace la instalación física). Esto es una excepción real y explícita al aislamiento multitenant que hasta ahora era estricto — la diseñé como [ADR-0005](ADR/0005-admin-plataforma-gestion-global-iot.md): acotada a Directorio IoT (instalaciones→canales), nunca a telemetría/alertas/miembros, y con auditoría obligatoria visible para el cliente. Ya aplicado en `PERMISSIONS.md` y `DATA_MODEL.md`.

### 12. Campañas (qué se planta, cuándo, comparar evolución durante la campaña)
**V2.** Nuevo módulo. Se combina con el punto 6 (informes: intervalo = duración de la campaña) y es prerrequisito conceptual de los puntos 8 y 9 (el cultivo/fase de la campaña determina qué modelo de enfermedad o recomendación aplica).
- **Sugerencia mía**: diseñarlo pensando ya en comparar campañas entre sí (misma parcela, distintos años; o distintas parcelas, misma campaña) — refuerza por qué se decidió retención de telemetría de 2+ años en la Etapa 2 (comparar la misma época del año anterior).
- **Sugerencia mía**: los umbrales de alerta podrían depender de la fase de la campaña (p. ej. humedad de suelo objetivo distinta en germinación vs. floración) — no lo has pedido, pero encaja de forma natural una vez existan campañas. Lo dejo anotado para cuando se diseñe V2 de alertas, no lo doy por incluido.

---

## Deuda técnica descubierta durante la implementación

Distinto de las ideas de producto de arriba: esto no son funciones nuevas, son divergencias entre lo documentado y lo realmente construido, encontradas al verificar código ya dado por "terminado" contra la realidad (backend real + Flutter SDK real, Etapa 14).

### 13. Paginación offset documentada pero no implementada
**Resuelto (2026-07-27).** `API_DESIGN.md` §5 documentaba paginación offset (`?page&pageSize` → `{data, meta}`) para instalaciones, zonas, gateways, dispositivos, sensores, miembros y alertas — ninguno de esos endpoints la implementaba de verdad en `apps/backend`. Se eligió la opción conservadora entre las dos planteadas (implementar de verdad vs. simplificar la documentación): **se simplificó `API_DESIGN.md`/`OPENAPI.yaml`** para reflejar el array plano real, en vez de retrofitar paginación en ~7 endpoints sin nadie disponible para revisar un cambio de ese tamaño. Se eliminaron los esquemas `MemberPage`/`InstallationPage`/`GatewayPage`/`AlertPage`/`PageMeta` y los parámetros `Page`/`PageSize` de `OPENAPI.yaml` (quedaban huérfanos). Si el volumen real lo justifica en el futuro, se revisa como tarea propia — criterio de cuándo en `MAINTENANCE.md` §3.

### 14. `sessions.read_others`/`revoke_others` definidos en la matriz de permisos pero nunca implementados
**Sin decidir (encontrado 2026-07-30).** `PERMISSIONS.md` §1 documenta que el Admin de organización tiene `sessions.read_others`/`revoke_others` (ver también a qué miembro de qué sesión), y `permissions.spec.ts` incluso comprueba que `roleHasPermission('org_admin', 'sessions.revoke_others')` es `true` — pero no existe ningún endpoint que use esos permisos: `AuthController`/`SessionsService` solo soportan `listOwn`/`revoke` sobre la propia sesión del que llama, ninguno acepta un `userId`/`memberId` ajeno. Encontrado al construir `SessionsListScreen` en Flutter (self-service, "mis sesiones") y comprobar contra el código real qué hacía falta para la versión de admin — no hacía falta nada porque no existe. No es un fallo de seguridad (nadie ve/revoca sesiones ajenas sin querer, al revés: un admin no puede hacerlo aunque el permiso diga que sí) — es una función documentada y con permiso ya reservado que nunca se construyó. Pendiente de decidir si se implementa (endpoint `GET/DELETE /members/:id/sessions` o similar, más la pantalla de admin correspondiente) o se retira de `PERMISSIONS.md`/`permissions.ts` si no hace falta.

### 15. Paginación por cursor documentada (telemetría/auditoría) pero tampoco implementada
**Resuelto (2026-07-30).** Mismo problema que #13, en la otra mitad de la tabla de `API_DESIGN.md` §5 — la que decía "esta sí es real". `GET /channels/:channelId/readings`, `GET /audit-log` y `GET /platform/audit-log` documentaban `?cursor&limit` → `{data, meta: {nextCursor}}`, pero ninguno de los tres controladores acepta esos parámetros: devuelven un array plano (`$queryRaw` para telemetría; `findMany(...).take(200)` para auditoría, sin filtro `from`/`to` tampoco pese a estar documentado en `/audit-log`). Encontrado al construir el visor de auditoría de organización en Flutter (Etapa 14). Misma solución que #13: se simplificaron `API_DESIGN.md`/`OPENAPI.yaml` para reflejar el array plano real (auditoría limitada a las 200 entradas más recientes, sin filtro de fecha) en vez de construir cursor de verdad en los tres endpoints. Se eliminaron los esquemas `AuditLogPage`/`ReadingPage`/`CursorMeta` y los parámetros `Cursor`/`Limit` de `OPENAPI.yaml` (quedaban huérfanos). El cliente Flutter de lecturas (`readings_api.dart`) ya estaba bien — nunca llegó a usar cursor/limit; el que estaba mal era solo el documento.

### 16. Umbral por defecto de canal a nivel de organización: solo escritura, sin lectura
**Resuelto (2026-07-30).** `OrgChannelThresholdsController` solo exponía `PUT /organization/channel-thresholds/{channelTypeCode}` (crea/actualiza el valor) — no existía ningún `GET` para leer los valores actuales de `org_channel_thresholds`. Un cliente podía escribir un nuevo valor por defecto a ciegas, pero no mostrar "esto es lo que hay configurado ahora" antes de editarlo. Corregido añadiendo `GET /organization/channel-thresholds` (lista completa de la organización, `channels.read` — mismo permiso que ya tenía cualquier rol para leer canales). Construida la sección correspondiente en `OrganizationSettingsScreen`: cruza el catálogo completo de `GET /channel-types` con lo ya configurado (igual patrón que el editor de funciones del panel de plataforma), edición solo para `org_admin`/`technician` (`channels.update_threshold`). Verificado en vivo: catálogo de 8 tipos de canal, umbral sin definir se muestra como tal, `PUT` seguido de `GET` confirma el valor guardado.

### 17. Catálogo de `features` nunca expuesto por ningún endpoint
**Resuelto (2026-07-30).** `GET /organization/features` y `GET /platform/organizations/{id}/features` solo devuelven filas `organization_features` ya existentes — para una organización que nunca ha tenido ninguna función activada (la inmensa mayoría, dado que casi todo lo que gatea este mecanismo es V2/Futuro, `BACKLOG.md` #11) esa lista está vacía. No hay manera de saber, activando por primera vez, qué funciones existen (`features.code`/`label`, sí seedeadas: `reports_pdf`, `campaigns`, `weather_widget`, `satellite_imagery`, `recommendations`) — ningún endpoint expone el catálogo completo, solo el estado por organización. Encontrado al construir el editor de funciones del panel de plataforma en Flutter. Corregido añadiendo `GET /platform/features` (`PlatformFeaturesCatalogController`, solo lectura, `org_features.read`, mismo patrón simple que `ChannelTypesController`) — con esto el editor puede cruzar el catálogo completo contra lo que ya está activado por organización y mostrar todas las funciones (activadas o no), no solo las que alguna vez se tocaron.

### 18. ADR-0005 (Directorio IoT global del Admin de plataforma) solo se mecanizó para gateways
**Sin decidir (encontrado 2026-07-30).** `PlatformGatewaysController` lleva en su propio comentario "representativo del resto de recursos de Directorio IoT (instalaciones→canales), que se mecanizan igual" — y `API_DESIGN.md` §2 documenta explícitamente que `/platform/organizations/{id}/...` debe cubrir "mismos recursos que en `/v1/...` (instalaciones→canales)". En la práctica **solo gateways tiene la variante de plataforma**; instalaciones, zonas, dispositivos, sensores y canales no tienen ningún endpoint bajo `/platform/organizations/{id}/...` — un Admin de plataforma no puede, hoy, crear la instalación inicial de un cliente nuevo (el primer paso de todo el Directorio IoT), solo gestionar gateways de instalaciones que ya existieran por otra vía (creadas por el propio Admin de la organización cliente tras aceptar su invitación). `API_DESIGN.md` §7 ya había anticipado justo este riesgo ("cualquier nuevo endpoint de organización debe recordar exponer... su variante de plataforma — no se puede confiar solo en la revisión de código") con un checklist previsto para Etapa 13 que evidentemente no se siguió para 5 de los 6 recursos. Encontrado al plantear el panel de plataforma en Flutter (Etapa 14). Pendiente de decidir: mecanizar de verdad los 5 controladores/rutas que faltan (siguiendo el patrón ya existente de `PlatformGatewaysController`) + la pantalla de Flutter correspondiente, o aceptar que en la práctica el flujo real es "el Admin de plataforma da de alta la organización e invita al primer Admin, que construye su propio Directorio IoT" y ajustar `API_DESIGN.md`/ADR-0005 para reflejarlo en vez de dejarlo como intención sin cumplir.

### 19. `audit_log` no dejaba escribir acciones de plataforma sin prefijo `platform.`
**Resuelto (2026-07-30).** Al construir el editor de funciones del panel de plataforma en Flutter, `PUT /platform/organizations/{id}/features` rompía con 500 ("new row violates row-level security policy for table audit_log") en cualquier alta/baja de función. Causa raíz: la política de RLS de `audit_log` no tenía un `WITH CHECK` propio, así que Postgres reutilizaba la misma expresión de `USING` (pensada para restringir qué puede *leer* un Admin de plataforma de la auditoría de otra organización) también para las *escrituras* — y la única acción de plataforma sin prefijo `platform.` (`org_features.update`) no la cumplía. Corregido con la migración `0004_audit_log_platform_write_check` (`WITH CHECK` separado y más permisivo para escrituras) más un cambio en `AuditLogService#record` (INSERT vía `$executeRaw` sin `RETURNING`, ya que Prisma `.create()` exige que la fila devuelta *también* pase la política de lectura, y ahí seguía rompiendo incluso con el `WITH CHECK` ya corregido). Detalle completo en `DATA_MODEL.md` §7. Verificado en vivo: la escritura ya no falla y la organización afectada sigue viendo la entrada en su propia auditoría, tal y como exige el ADR-0005.

---

## Pregunta pendiente: alcance de "control de qué ve cada usuario"

Tu frase: *"la configuración de que ve cada usuario y capacidad de modificarlo siempre la voy a tener yo como administrador y que los usuarios no puedan cambiar lo que ven"*. Esto admite dos lecturas muy distintas y quiero confirmar cuál antes de detallarlo:

1. **Solo idioma**: cada usuario tiene un idioma asignado, pero lo asigna el Admin (¿de plataforma? ¿de organización?) en vez de elegirlo el propio usuario libremente.
2. **Visibilidad de funciones/módulos** (más amplio): qué pestañas/funciones ve cada organización o usuario (p. ej. "informes" o "recomendaciones" solo para ciertos clientes/planes) se controla centralmente — esto sería un sistema de *feature flags* por organización, no solo idioma, y encajaría con vender la plataforma en distintos niveles/planes.

Si es la lectura 2, es una pieza de arquitectura real (probablemente ligada a `organizations` — un plan/tier por organización) que conviene fijar antes de la Etapa 7 (API), no dejarla para V2 sin más.
