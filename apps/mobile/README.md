# App Flutter — Plataforma IoT (Etapa 14)

Contrato: [`API_DESIGN.md`](../../docs/API_DESIGN.md) / [`OPENAPI.yaml`](../../docs/OPENAPI.yaml).
Arquitectura de procesos y auth: [`ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) sección 6.

## Estado
Vertical delgada end-to-end: login (con selección de organización si aplica) →
lista de instalaciones → última lectura de cada canal de una instalación.
Directorio IoT completo (zonas, gateways, dispositivos, sensores, canales,
gráficas, alertas) queda para el siguiente paso.

**Validado** (2026-07-27, Flutter 3.44.8 estable): el código original se
escribió sin SDK disponible y solo se había revisado línea a línea a mano.
Ya se instaló el SDK, se generó el andamiaje nativo (`android/`, `ios/`,
`web/`, org `com.iotplatform`) y se ejecutó `flutter analyze` (sin
incidencias), `flutter test` (4/4 tests en verde) y `flutter build web`
(compila y genera `build/web`). iOS solo se puede **compilar** de verdad
en macOS (Xcode) — aquí solo se ha podido generar el proyecto `ios/`, no
compilarlo ni ejecutarlo.

## Puesta en marcha

El andamiaje nativo (`android/`, `ios/`, `web/`) ya está generado y
versionado — no hace falta volver a ejecutar `flutter create`.

```bash
cd apps/mobile

# 1. Dependencias
flutter pub get

# 2. Validación (TESTING_STRATEGY.md §3-6)
flutter analyze
flutter test

# 3. Arrancar contra el backend local (docker-compose.yml en la raíz del repo)
flutter run -d chrome --dart-define=API_BASE_URL=http://localhost:3000/v1
```

## Estructura

```
lib/
  core/
    api/        Cliente HTTP (Dio), manejo de 401/refresh, errores RFC 7807
    storage/    Persistencia segura del refresh token
    router/     GoRouter con redirect según estado de sesión
  features/
    auth/           Login, selección de organización, refresh (API_DESIGN.md §3)
    installations/   Listado y detalle de instalación (últimas lecturas)
    readings/        Etiquetas de presentación del catálogo de canales
```

## Decisiones de esta etapa
- **Riverpod clásico** (`StateNotifierProvider`/`FutureProvider`), sin
  `@riverpod` con generación de código — evita depender de `build_runner`
  sin poder verificar aquí que el código generado sea correcto.
- **Access token solo en memoria**; el refresh token (sessionId+secret) es lo
  único persistido, en `flutter_secure_storage` (SECURITY.md §6).
- **`GET /me` tras cada login/refresh** para obtener `organizationId`/
  `roleCode`/`isPlatformAdmin` — más simple que decodificar el JWT en el
  cliente y reutiliza un endpoint ya construido.
