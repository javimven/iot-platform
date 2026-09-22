# ADR-0014: Modelo propio, traducido al SIEX/CUE en una capa aparte

- Estado: Aceptada
- Fecha: 2026-09-22

## Contexto

El cuaderno digital de explotación (CUE) y el SIEX están regulados por el RD 1054/2022. El RD 34/2025 los hizo **voluntarios** durante esta PAC, salvo que una norma sectorial exija el formato electrónico, y **obligatorios desde el 1/1/2028** para explotaciones por encima de ciertos umbrales. El registro de tratamientos fitosanitarios, en cambio, será electrónico y legible por máquina **desde el 1/1/2027**: Reglamento de Ejecución (UE) 2023/564, aplazado por el 2025/2203, y en España el RD 1039/2025, que permite papel hasta el 31/12/2026.

El FEGA publica la documentación técnica del SIEX, hoy en la **versión 3.11** (Anexo V "Definición de variables", Anexo VI "Interfaz Único Común" 3.11.4, Anexo VII "Catálogos"; página actualizada el 9/9/2026), y la cambia con frecuencia.

## Decisión

1. **Modelo interno con nombres propios**, pensado para el software y no para el formulario. Los campos se alinearon con el Anexo V 3.11 (bloques 5, 8, 9, 10 y 11 del CUE) para que todo lo obligatorio tenga dónde guardarse, pero sin copiar su estructura ni su nomenclatura.
2. **Traducción en una capa aparte** (`CueMapper`, fase 4): modelo interno ↔ esquema SIEX. Cada exportación lleva su `schemaVersion` (hoy `3.11`), y el modelo interno no depende de ninguna versión.
3. **Códigos oficiales como datos, no como modelo.** El agricultor elige "Aguacate", y el código EPPO o el del catálogo SIEX es una columna del catálogo interno (`crops.eppo_code`, `siex_code`, `siex_catalog_version`) que se rellena **al importar el catálogo oficial**, nunca a ojo. Los campos que serán códigos de un catálogo (sistema de riego, material fertilizante, método de aplicación, tipo de labor) se guardan como texto validado en la aplicación y se mapean sin migración.
4. **La DGC del SIEX corresponde a Unidad de cultivo × Parcela** (`crop_unit_parcels`), que es donde se imputan las actuaciones.
5. **Comunidad autónoma** en la finca (`installations.region_code`, ISO 3166-2): de ella dependen las zonas vulnerables (que designa cada comunidad), los modelos de cuaderno autonómicos y los conectores. La base es nacional. Las extensiones autonómicas serán reglas o configuración añadidas al conjunto de reglas (ADR-0013); en el MVP no hay ninguna.
6. **Sin conexión administrativa hasta fase 4.** Antes de enviar nada hay que resolver la autorización del titular (Anexos VIII-X), la habilitación de la aplicación como CUE comercial, los certificados y el servicio web del REA/CUE (Anexo VI).

## Consecuencias

- Mientras no haya conexión, la exportación estructurada (JSON/CSV, junto al PDF) es lo que convierte el cuaderno en un registro "legible por máquina" para 2027.
- Importar catálogos (Anexo VII, EPPO, Registro de Productos Fitosanitarios del MAPA) es trabajo de fase 3. El registro del MAPA se consulta en la web (`servicio.mapa.gob.es/regfiweb`), pero **no se ha confirmado** que publique una exportación oficial: queda por investigar antes de decidir cómo integrarlo. Nada de leer su HTML.
- Una actualización del SIEX debería tocar el mapeador y el conjunto de reglas, no las tablas.
