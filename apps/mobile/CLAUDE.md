# CLAUDE.md — apps/mobile

Sistema de diseño de la app Flutter (primer diseño real, 2026-08-04). Estas reglas anulan cualquier tentación de "solo por esta vez" al escribir una pantalla nueva.

## Regla principal

**Ningún color, fuente o radio de esquina se escribe a mano en una pantalla.** Todo pasa por:

- `lib/core/theme/app_colors.dart` — paleta completa (claro + oscuro). Nunca `Colors.red`, nunca un hexadecimal suelto (`Color(0xFF...)`) fuera de este archivo.
- `lib/core/theme/app_theme.dart` — `ThemeData` (Sora para títulos, Manrope para cuerpo). Los textos se piden con `Theme.of(context).textTheme.*`, nunca `TextStyle(fontSize: ...)` a mano.
- `lib/core/widgets/app_button.dart` — `AppButton` (variantes `primary`/`secondary`/`danger`). Nunca `ElevatedButton`/`TextButton`/`OutlinedButton` sueltos con estilo propio.
- `lib/core/widgets/app_card.dart` — `AppCard`. Nunca `Card` a pelo con `Container`/`BoxDecoration` reinventando el borde o la elevación.
- `lib/core/widgets/status_chip.dart` — `StatusChip` + `AppStatusTone` (`ok`/`warn`/`critical`/`neutral`). Para online/offline de gateway/dispositivo y para el ciclo de vida de una alerta (abierta/reconocida/resuelta). El estado siempre se codifica en color **y** en texto, nunca solo color.

Si una pantalla necesita algo que estos componentes no cubren, la respuesta es ampliar el componente (o crear uno nuevo en `core/widgets/`), no saltárselo con estilo local.

## Por qué

Un cambio de diseño futuro (otro verde, otra tipografía, otro radio de esquina) debe costar **una edición en un archivo**, no una búsqueda por toda la app. Eso solo funciona si de verdad nada se sale del sistema.

## Paleta (razonamiento, no solo valores)

- `brand` (verde pino, `#1F6F5C`) es el acento de marca — deliberadamente distinto de los tonos semánticos (`ok`/`warn`/`critical`), para que "todo bien" nunca se confunda visualmente con el color corporativo.
- `ok` es azul, no verde, precisamente para no competir con `brand`.
- Evitar los clichés de diseño genérico de IA: nada de "crema + serif + terracota", nada de gradiente morado-azul, nada de `rounded-lg` en todo.

## Antes de dar por cerrada una pantalla nueva

- [ ] ¿Usa `AppButton`/`AppCard`/`StatusChip` donde corresponda, en vez de widgets de Material a pelo?
- [ ] ¿Todo texto sale de `Theme.of(context).textTheme`?
- [ ] ¿Todo color sale de `AppColors` o de `Theme.of(context).colorScheme`?
- [ ] ¿Se probó en modo claro **y** oscuro (`AppTheme.light`/`AppTheme.dark`)?
