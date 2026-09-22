# ADR-0013: Campaña sencilla y cuaderno completo son el mismo modelo

- Estado: Aceptada
- Fecha: 2026-09-22

## Contexto

Dos públicos para el mismo módulo (BACKLOG.md #60). Uno quiere crear una campaña en menos de un minuto (finca, parcelas, cultivo, fecha) y apuntar riegos y cosechas. El otro necesita un cuaderno de explotación con aplicadores inscritos en el ROPO, números de registro, riquezas de abono y plan de abonado. Y el primero puede convertirse en el segundo a mitad de campaña.

## Decisión

**Un solo modelo con un modo** (`management_mode`: `simple` | `complete`). El modo decide la experiencia, las validaciones y qué es obligatorio; **nunca la estructura**.

- Pasar de sencilla a completa es cambiar el modo y responder un asistente corto: no se copia la campaña, no se borra nada y las actividades ya registradas sirven de base.
- Ver una campaña completa en modo sencillo no pierde datos: solo no se enseñan.
- En sencillo, lo que no es imprescindible va detrás de "Más detalles": quien quiera puede enriquecer el registro poco a poco.
- En completo, lo obligatorio según la configuración aplicable se enseña claramente, y cerrar la campaña avisa de lo que falta.

**Perfil del cuaderno** (`campaigns.notebook_profile`): solo las preguntas que el sistema no puede deducir (¿fitosanitarios profesionales? ¿fertilizantes? ¿fertirrigación? ¿ecológico o integrado? ¿residuos valorizables? ¿postcosecha?). Con las respuestas se muestran solo las secciones que aplican. Lo que ya se sabe (finca, titular, superficie de la parcela, cultivo de la campaña) no se vuelve a preguntar.

**Qué es obligatorio lo decide un conjunto de reglas versionado en el backend**, nunca Flutter: código con país, región, versión y vigencia (`effectiveFrom`/`effectiveTo`), la fuente legal de cada regla y sus pruebas. La primera versión es la nacional (`ES`), sin extensiones autonómicas (ADR-0014).

**Lenguaje prudente**: "según los datos registrados, este apartado podría ser obligatorio", "información pendiente", "preparado para revisión". **Nunca "cumple"**: la obligación depende de la ubicación, el tamaño, las ayudas, la producción certificada y circunstancias que la aplicación no conoce, y un cuaderno completo no es una garantía legal.

## Alternativas descartadas

- **Dos entidades** (campaña sencilla y cuaderno): obligaría a copiar datos al pasar de una a otra, y a mantener dos formularios de riego.
- **Umbrales en la app**: la normativa cambia (el RD 1051/2022 se ha modificado dos veces desde 2024) y cada cambio costaría una publicación en las tiendas.

## Consecuencias

- Las tablas de detalle tienen casi todo opcional en la base: la obligatoriedad vive en la validación por modo y en el conjunto de reglas.
- El indicador de completitud (solo en modo completo) lista información pendiente, no puntúa.
