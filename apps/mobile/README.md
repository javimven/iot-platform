# App Flutter — Plataforma IoT (Etapa 14)

Contrato: [`API_DESIGN.md`](../../docs/API_DESIGN.md) / [`OPENAPI.yaml`](../../docs/OPENAPI.yaml).
Arquitectura de procesos y auth: [`ARCHITECTURE.md`](../../docs/ARCHITECTURE.md) sección 6.

## Estado
Login (con selección de organización si aplica) → lista de instalaciones →
última lectura de cada canal → gráfica histórica (24h/7d/30d) → alertas
(filtro por estado, reconocer/resolver) → **Directorio IoT completo**:
instalación → zonas (alta/edición/baja) + gateways (alta/edición/
deshabilitar) → dispositivos (alta/edición/deshabilitar) → sensores (alta/
baja) → canales (edición de umbral). Gateway muestra su credencial una
única vez al crearlo o rotarlo (no se puede recuperar después).

Botones de alta/edición solo se muestran si el rol lo permitiría
(`org_admin`/`technician`) — es una pista de UI, el control de acceso real
lo sigue haciendo el backend (`RequirePermission`), nunca el cliente.

**Validado** (2026-07-28, Flutter 3.44.8 estable): `flutter analyze` sin
incidencias, `flutter test` (12/12 en verde), `flutter build web` y
**`flutter build apk --debug`** compilan. iOS solo se puede **compilar**
de verdad en macOS (Xcode) — aquí solo se ha generado el proyecto `ios/`,
no compilado ni ejecutado.

**Bug real encontrado al validar Android** (no hipotético — sin esto
`flutter build apk` fallaba siempre): `jni` 1.0.1 (dependencia transitiva
de `flutter_secure_storage` → `path_provider_android`) fue **retirado por
sus propios autores en pub.dev** — su `build.gradle` solo aplicaba el
plugin de Kotlin si `AGP < 9`, y este proyecto usa AGP 9.0.1 (generado por
`flutter create` en 2026), así que fallaba con "Could not find method
kotlin()". Corregido con `dependency_overrides: jni: ^1.0.2` en
`pubspec.yaml` — esa versión elimina el bloque de Kotlin que ya no
necesitaba. Quitar el override en cuanto `path_provider_android` publique
una versión que ya no dependa de la 1.0.1.

Al conectar el módulo de Alertas contra el backend real se encontraron y
corrigieron dos divergencias de contrato reales (no hipotéticas — habrían
fallado en producción):
- `GET /installations` devuelve un array plano, no el sobre `{data, meta}`
  que `installations_api.dart` esperaba — habría lanzado un `TypeError` en
  tiempo de ejecución la primera vez que alguien abriera la lista de
  instalaciones. `API_DESIGN.md` §5/`OPENAPI.yaml` ya corregidos para
  documentar el array plano real (`BACKLOG.md` #13).
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

# 4. Compilación Android (opcional, para verificar el target además de web)
flutter build apk --debug
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
    directory/       Directorio IoT completo: zonas/gateways/dispositivos/
                     sensores (alta) + canales (edición de umbral)
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
- **Directorio IoT completo**, incluida la reasignación de zona de un
  dispositivo: `DeviceDetailScreen` resuelve la instalación del
  dispositivo vía `GET /zones/:id` (la zona actual ya trae
  `installationId`) antes de pedir la lista de zonas de esa instalación
  para el desplegable — dos llamadas extra al abrir el diálogo, aceptable
  para una acción de edición poco frecuente. Sensor no tiene edición en el
  backend (solo alta/baja), por eso tampoco la tiene aquí.
- **`GET /gateways` no filtra por instalación** (backend, `BACKLOG.md` #13,
  resuelto documentando la realidad en vez de paginar): `DirectoryApi.
  gatewaysForInstallation` pide todos los gateways de la organización y
  filtra en cliente por `installationId`. Aceptable a la escala del MVP
  (`NON_FUNCTIONAL_REQUIREMENTS.md` §2, ≤500 dispositivos).
- **Credencial de gateway mostrada una vez** (`showGatewayCredentialDialog`,
  compartido entre alta y rotación): `SelectableText` + botón de copiar al
  portapapeles, diálogo no descartable por accidente (`barrierDismissible:
  false`) — coherente con que el backend nunca la vuelve a exponer
  (SECURITY.md §6).
