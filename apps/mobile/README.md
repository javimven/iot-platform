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

**Panel de plataforma** (2026-07-30, Admin de plataforma "puro", sin
organización propia): `PlatformOrganizationsScreen` (listar/crear/suspender/
reactivar organizaciones), `PlatformOrganizationFeaturesScreen` (editor de
funciones contratadas) y `PlatformAuditLogScreen`. El router ahora distingue
este rol al decidir a dónde redirigir tras el login (antes siempre mandaba a
`/installations`, que le habría devuelto 403 sin organización activa). Al
construirlo se encontraron y corrigieron dos huecos reales más: no existía
ningún endpoint con el catálogo completo de funciones contratables
(`GET /platform/features`, nuevo), y `PUT /platform/organizations/{id}/features`
rompía siempre con 500 por un bug real de RLS en `audit_log` (la política no
distinguía leer de escribir) — corregido con una migración nueva y
reescribiendo cómo se registra la auditoría.

**Directorio IoT del panel de plataforma** (2026-07-30, ADR-0005/`BACKLOG.md`
#18 cerrado): desde "Directorio IoT" en el menú de cada organización,
`PlatformInstallationsScreen` → `PlatformInstallationDetailScreen` (zonas +
gateways) → `PlatformGatewayDetailScreen` (dispositivos) →
`PlatformDeviceDetailScreen` (sensores) — solo crear y listar, sin editar/
deshabilitar/rotar credencial (`BACKLOG.md` #20: el backend rechazaría esas
operaciones por ID para un Admin de plataforma puro). Al verificar la cadena
completa en vivo se encontró un **bug real de aislamiento multi-tenant**:
`GET /platform/organizations/{id}/installations` y `.../gateways` devolvían
filas de todas las organizaciones, no solo la de la URL — ninguno de los dos
`findAll` filtraba por `organizationId` en el `where` de Prisma, y para el
Admin de plataforma ni RLS ni el alcance por instalación lo hacían por él
(`BACKLOG.md` #21, corregido). Verificado en vivo contra el backend real.

**Ajustes de organización y auditoría** (2026-07-30): `OrganizationSettingsScreen`
(perfil editable solo por `org_admin`; funciones contratadas, solo visibles
para `org_admin`; umbrales por defecto de canal, visibles para cualquier rol
y editables por `org_admin`/`technician` — `BACKLOG.md` #16, cerrado
añadiendo el `GET` que faltaba) y `AuditLogScreen` (`org_admin`/`technician`) — agrupadas
en un nuevo menú "Más" en la barra de Instalaciones. Al construirlas se
encontró y corrigió un **bug crítico real**: `GET /audit-log` y
`GET /platform/audit-log` llevaban rotos desde siempre (500 en cuanto había
al menos una fila) porque `AuditLogEntry.id` es `BigInt` y `JSON.stringify`
no lo serializa de forma nativa — nunca se había detectado porque nadie
había llamado a ese endpoint de verdad hasta ahora. Corregido con un parche
global en `main.ts`; `id` ahora viaja como string. Verificado en vivo contra
el backend real.

**Sesiones activas propias** (2026-07-30, cualquier rol): `SessionsListScreen`
(ruta `/sessions`, icono en la barra de Instalaciones) — listar y cerrar
sesión en otro dispositivo (`GET`/`DELETE /auth/sessions`). Cerrar la sesión
de *este* dispositivo se deshabilita aquí a propósito (ya existe el botón
"Cerrar sesión"). Verificado en vivo contra el backend real. Al construirla
se encontró que `sessions.read_others`/`revoke_others` (permiso de
`org_admin` para gestionar sesiones de otros miembros) está definido en la
matriz de permisos pero nunca implementado en ningún endpoint —
`BACKLOG.md` #14, decisión pendiente.

**Gestión de miembros** (2026-07-29, `org_admin` únicamente): `MembersListScreen`
(ruta `/members`, entrada en la barra de Instalaciones) — listar, invitar,
cambiar rol, suspender/reactivar, asignar alcance por instalación y eliminar
miembros. Verificado el contrato HTTP exacto contra el backend real; en el
proceso se encontraron y corrigieron dos bugs reales en el backend (no en
Flutter): `GET /members` filtraba el hash Argon2 de cada miembro
(`SECURITY.md` §7), y ni invitar ni cambiar rol/estado devolvían
`email`/`fullName` pese a estar documentado.

**Activar cuenta invitada / recuperar contraseña** (2026-07-29): el backend
siempre tuvo `/auth/accept-invitation`, `/auth/forgot-password` y
`/auth/reset-password` (Etapa 13i), pero hasta ahora no había ninguna
pantalla para ellos — el único mecanismo real de alta de usuarios
(invitación por email) no era usable desde la app. `AcceptInvitationScreen`/
`ForgotPasswordScreen`/`ResetPasswordScreen` (rutas `/accept-invitation`,
`/forgot-password`, `/reset-password`, con el `token` leído de la query de
la URL del email) cierran ese hueco; enlace "¿Olvidaste tu contraseña?" en
el login. Verificado el contrato HTTP exacto contra el backend real (token
de invitación/restablecimiento leído de Mailpit, no simulado) — sin
herramienta de automatización de navegador en este entorno no se pudo
interactuar visualmente con la UI resultante.

Botones de alta/edición solo se muestran si el rol lo permitiría
(`org_admin`/`technician`) — es una pista de UI, el control de acceso real
lo sigue haciendo el backend (`RequirePermission`), nunca el cliente.

**Validado** (2026-07-28, Flutter 3.44.8 estable): `flutter analyze` sin
incidencias, `flutter test` (12/12 en verde), `flutter build web` y
`flutter build apk --debug` compilan localmente. **iOS validado vía
GitHub Actions** (`.github/workflows/mobile-ios-build.yml`, runner
`macos-14` — no hay Mac en este entorno de desarrollo): compila sin firma
de código (`flutter build ios --release --no-codesign`, no hay cuenta de
Apple Developer configurada, así que no genera un `.ipa` instalable en un
dispositivo real, solo confirma que el código compila para iOS). Se
dispara automáticamente al tocar `apps/mobile/**` en `master`, o a mano
desde la pestaña Actions de GitHub (`workflow_dispatch`).

**Primera ejecución confirmada** (2026-07-28): éxito en ~3 minutos,
artefacto `ios-build-unsigned` de 7,2 MB
([run](https://github.com/javimven/iot-platform/actions/runs/30352818973)).
Con esto, los tres targets (web, Android, iOS) están validados — compilan
de verdad, no solo "debería funcionar".

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
