# ADR-0012: Campaña, unidad de cultivo y actividad con detalle tipado

- Estado: Aceptada
- Fecha: 2026-09-22

## Contexto

El módulo de Campañas (BACKLOG.md #60) tiene que servir a la vez a quien solo quiere saber qué ha plantado y qué le ha echado, y a quien lleva un cuaderno de explotación completo que un día se enviará al CUE. La idea anterior (BACKLOG.md #34) era una campaña por estación con cultivo en texto y dos fechas; se pensó cuando no existían parcelas.

Hoy ya hay parcelas dibujadas en el mapa (migración 0008), y el cuaderno oficial —Anexo V del SIEX 3.11, Reglamento (UE) 2023/564, RD 1051/2022— registra cada actuación **sobre una superficie concreta**, con su cultivo y con fechas de inicio y fin.

## Decisión

**Finca → Campaña → Unidad de cultivo → Parcelas**, y el cuaderno se construye con **actividades**.

- **`campaigns`**: periodo productivo de una finca. Fechas `DATE`, estado (`draft`, `active`, `closed`, `archived`) y modo (ADR-0013).
- **`crop_units`**: mismo cultivo y manejo sobre una o varias parcelas. Se aproxima a la Unidad Homogénea de Cultivo sin obligar a nadie a conocer el término. Una campaña sencilla tiene una sola, creada en el alta. El cultivo se elige de un **catálogo global** (`crops`) y se guarda también su nombre, para que un cuaderno cerrado no cambie si se renombra el catálogo.
- **`crop_unit_parcels`**: qué parcela ocupa cada unidad y cuánta superficie. **No se asume** que la superficie cultivada sea la de la parcela.
- **`campaign_activities`**: lo que se ha hecho. Es común a todos los tipos, con **fecha de inicio y de fin siempre**, como en todos los bloques del CUE. Así un registro agrupado (la fertirrigación de una quincena, que admite el RD 1051/2022) es un registro normal y no un caso especial.
- **`activity_targets`**: sobre qué parcelas de qué unidad, con su superficie. Una actividad sobre tres parcelas es un registro con tres destinos, no tres registros.
- **Un detalle tipado por tipo regulado**: `irrigation_details`, `fertilization_details`, `phytosanitary_details` (con `phytosanitary_products`, porque un tratamiento puede ser una mezcla), `harvest_details` y `field_work_details`. La observación y "otra" no necesitan detalle.
- **Catálogos reutilizables** de personas (aplicadores, empresas, asesores) y equipos: se dan de alta una vez y se eligen.
- **`documents` + `document_links`**: un fichero se guarda una vez (índice único sobre su SHA-256 por organización) y se vincula a campaña, actividad, equipo o persona, con una clave foránea por destino y un CHECK de que es exactamente uno. Se reutilizan el mismo bucket y el mismo `StorageService` que el satélite.

### Por qué detalle tipado y no un JSON

Los datos del cuaderno son los que se exportarán al CUE y los que se piden en una inspección: dosis, número de registro, superficie tratada. Tienen que validarse y consultarse (el resumen suma m³ y kg de N por hectárea), y un JSON por actividad no permite ninguna de las dos cosas. Tampoco una tabla por apartado del cuaderno oficial, que serían una treintena para empezar. Cinco detalles cubren los tipos regulados del MVP. Los que lleguen después (semilla tratada, postcosecha, almacenes) serán una tabla más cada uno.

### Historia que no cambia

- **Campaña cerrada = cuaderno congelado.** Un trigger rechaza cualquier alta, cambio o borrado en sus actividades y detalles hasta reabrirla (la reapertura queda en la auditoría con su motivo). La aplicación ya lo impide; el trigger es la red de seguridad.
- **Copia en el momento de registrar** los datos de catálogo que se referencian (aplicador, asesor, equipo): si mañana cambia la ficha del equipo, el tratamiento de hoy sigue diciendo con qué equipo se hizo.
- **Instantánea al cerrar** (`campaign_snapshots`): titular, finca, parcelas y superficies tal como eran. El cuaderno de una campaña cerrada se genera a partir de ella. Es inmutable por trigger, y hay una por cada cierre si se reabre y se vuelve a cerrar.

Se eligió **copia al registrar + instantánea al cerrar** frente a versionar cada catálogo (tablas de historial de personas, equipos, fincas y parcelas). Da la misma garantía para lo que importa, un cuaderno cerrado que no cambia, con dos columnas JSON y una tabla, en vez de un historial por cada entidad.

## Consecuencias

- Doce tablas nuevas en tres migraciones (0010-0012), todas con RLS y `organization_id` propio, y triggers de coherencia (la parcela, de la finca de la campaña; el destino de una actividad, de su campaña; el documento, de su organización). Las claves foráneas no pasan por RLS, así que sin estos triggers un id de otra organización colado en una petición pasaría.
- Las parcelas pasan a ser de Satélite **y** de Campañas: la API exige cualquiera de las dos funciones, y el histórico de Copernicus solo se encola si la organización tiene el satélite contratado.
- Los campos que acabarán siendo códigos de un catálogo oficial (sistema de riego, tipo de material, método de aplicación…) son `TEXT` validado en la aplicación. Cuando entren los catálogos del SIEX se mapean sin migración (ADR-0014).
- Purgar una organización con campañas cerradas exige al dueño de la base desactivar el trigger de las instantáneas. Es a propósito.
