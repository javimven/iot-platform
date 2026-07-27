# App Flutter — Plataforma IoT (Etapa 14)

Contrato: [`API_DESIGN.md`](../../docs/API_DESIGN.md) / [`OPENAPI.yaml`](../../docs/OPENAPI.yaml).
Arquitectura de procesos y auth: [`ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) sección 6.

## Estado
Login (con selección de organización si aplica) → lista de instalaciones →
última lectura de cada canal de una instalación → gráfica histórica de un
canal (24h/7d/30d) → lista de alertas (filtro por estado, reconocer/
resolver). Directorio IoT completo (zonas, gateways, dispositivos,
sensores, canales) queda para el siguiente paso.

**Validado** (2026-07-27, Flutter 3.44.8 estable): el SDK está instalado en
este entorno; `flutter analyze` sin incidencias, `flutter test` (8/8 en
verde) y `flutter build web` compilan. iOS solo se puede **compilar** de
verdad en macOS (Xcode) — aquí solo se ha generado el proyecto `ios/`, no
compilado ni ejecutado.

Al conectar el módulo de Alertas contra el backend real se encontraron y
corrigieron dos divergencias de contrato reales (no hipotéticas — habrían
fallado en producción):
- `GET /installations` devuelve un array plano, no el sobre `{data, meta}`
  que `installations_api.dart` esperaba — habría lanzado un `TypeError` en
  tiempo de ejecución la primera vez que alguien abriera la lista de
  instalaciones. Ver `API_DESIGN.md` §5 para el detalle (paginación
  documentada pero no implementada en ningún listado salvo auditoría).
- `GET /installations/:id/latest-readings` no devolvía `channelTypeCode`
  pese a que `OPENAPI.yaml` lo documenta y el cliente ya lo esperaba —
  cada lectura se habría mostrado sin etiqueta. Corregido en
  `ReadingsService` (backend).

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
    alerts/          Lista de alertas, filtro por estado, reconocer/resolver
    readings/        Gráfica histórica de un canal + etiquetas del catálogo
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
- **`fl_chart`** para la gráfica histórica: única dependencia de gráficas
  del proyecto (no estaba en el stack inicial, no es una desviación que
  necesite ADR — es una librería de UI, no de arquitectura); puro Dart,
  sin dependencias nativas, mantenida activamente, funciona igual en
  web/Android/iOS.
