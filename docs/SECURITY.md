# SECURITY.md

## 0. Estado de este documento
- Etapa del proceso: 8 — Seguridad y modelo de amenazas
- Estado: En análisis (consolidado + nuevas decisiones, pendiente de tu validación)
- Última actualización: 2026-07-27
- Depende de: Etapas 0-7
- Bloquea: Etapa 9 (infraestructura aplica estos controles), Etapa 13 (implementación)

Este documento tiene dos partes: (1) consolida controles de seguridad **ya decididos** en etapas anteriores, con referencia a dónde se definieron, para no duplicar contenido; (2) fija los controles que **aún no se habían concretado**. El modelo de amenazas completo vive en [`THREAT_MODEL.md`](THREAT_MODEL.md).

## 1. Decisiones tomadas en esta etapa (lo nuevo)

| Decisión | Elegido |
|---|---|
| Corrección de RLS | `set_config(..., $n, true)` parametrizado, nunca `SET`/`SET LOCAL` interpolado (ya aplicado en `DATA_MODEL.md`/`ARCHITECTURE.md`) |
| Firma de JWT | Asimétrica (RS256 o EdDSA), no HS256 — permite rotar la clave de firma sin compartir secreto con quien solo verifica |
| MFA | TOTP (app autenticadora), no SMS — sin coste de operador, diseño fijado ahora aunque la construcción sea V2 (ya decidido en Etapa 0) |
| Rate limiting | Valores concretos por categoría de endpoint (sección 5) |
| CORS | Lista blanca de orígenes conocidos, sin comodín, con credenciales |
| Gestión de secretos | Variables de entorno inyectadas por la plataforma de despliegue, nunca en código/git; herramienta concreta en Etapa 9 |
| Cifrado de datos sensibles en reposo | Cifrado a nivel de almacenamiento (volumen/backup gestionado), sin cifrado de columna para email/nombre — evita romper índices/búsquedas sin beneficio real dado el tipo de dato |
| CSRF en un frontend Flutter Web con Bearer tokens | Amenaza de baja aplicabilidad por diseño (sección 6) — el foco real es XSS, no CSRF |
| Escaneo de dependencias | `npm audit`/Dependabot (backend), `osv-scanner`/`dart pub outdated` (Flutter), escaneo de imagen Docker (Trivy) en CI/CD |

## 2. Controles ya decididos en etapas anteriores (consolidado, sin repetir detalle)

| Control | Dónde se decidió |
|---|---|
| Argon2id para contraseñas | Fijado desde el inicio del proyecto (stack base) |
| Access tokens de corta duración + refresh rotativos | `ARCHITECTURE.md` sección 6, `API_DESIGN.md` sección 3 |
| Revocación de sesiones | `DATA_MODEL.md` (`sessions`), `PERMISSIONS.md` (`sessions.revoke_own/others`) |
| RBAC y permisos granulares | `PERMISSIONS.md` completo |
| Aislamiento multitenant (app + RLS + ACL de broker) | `ARCHITECTURE.md` secciones 6-7, `DATA_MODEL.md` sección 7 |
| Seguridad por fila (RLS) | `DATA_MODEL.md` sección 7 (corregida en esta etapa, sección 1) |
| Consultas parametrizadas / anti SQL injection | Uso de Prisma/Drizzle (nunca SQL con interpolación de texto) + corrección de la sección 1 |
| Auditoría | `DATA_MODEL.md` (`audit_log`), `PERMISSIONS.md` sección 3 |
| Principio de mínimo privilegio (rol de BD) | `DATA_MODEL.md` sección 7 (sin `BYPASSRLS`, sin `UPDATE`/`DELETE` en `audit_log`) |
| Credenciales de dispositivo sin compartir, ACL por gateway | [ADR-0002](ADR/0002-autenticacion-dispositivos-sin-mtls.md), [ADR-0004](ADR/0004-unidad-de-conexion-lora-y-nbiot.md) |
| Excepción auditada de aislamiento (Admin de plataforma / Directorio IoT) | [ADR-0005](ADR/0005-admin-plataforma-gestion-global-iot.md) |
| Cifrado en tránsito (TLS) | `ARCHITECTURE.md` (MQTT), obligatorio también para la API (HTTPS, Etapa 9) |
| Rechazo de valores/mensajes fuera de rango o malformados | `MQTT_PROTOCOL.md` secciones 5-6 |

## 3. Recuperación segura de contraseña
Ya especificado en `API_DESIGN.md` sección 3 (`/auth/forgot-password`, `/auth/reset-password`). Refuerzos de esta etapa:
- El token de restablecimiento es de un solo uso, con expiración corta (ej. 30 min) y se invalida si se solicita uno nuevo antes de usarlo.
- Al completar un restablecimiento de contraseña, se **revocan todas las sesiones activas** del usuario (fuerza a reautenticar en todos los dispositivos) — igual que un cambio de contraseña desde el perfil.
- La respuesta de `/auth/forgot-password` es idéntica exista o no la cuenta (202 siempre) — ya fijado en Etapa 7, se repite aquí porque es, ante todo, un control de seguridad (no filtrar qué emails están registrados).

## 4. MFA (diseño para V2, ya decidido como TOTP)
- Aplica a Admin de plataforma y Admin de organización (roles con más capacidad de daño si se comprometen) — Técnico/Operador/Solo lectura quedan fuera del alcance inicial de MFA.
- TOTP (RFC 6238, apps tipo Google Authenticator/Authy) en vez de SMS: sin coste de operador de telefonía, sin el riesgo conocido de SIM-swapping del SMS.
- Códigos de recuperación (10 códigos de un solo uso) generados al activar MFA, para el caso de pérdida del dispositivo con la app autenticadora.
- No se implementa en el MVP (ya decidido en Etapa 0); este diseño evita tener que rediscutir el mecanismo cuando llegue V2.

## 5. Rate limiting (valores concretos)

| Categoría | Límite |
|---|---|
| Login (`/auth/login`) | 5 intentos / 15 min, por combinación IP + email |
| Recuperación de contraseña (`/auth/forgot-password`) | 3 / hora, por email |
| Refresh de token | 30 / hora, por sesión |
| API general (autenticado) | 300 peticiones / minuto, por usuario |
| Ingesta MQTT | No se limita por mensaje individual (ya cubierto por el diseño de picos de `NON_FUNCTIONAL_REQUIREMENTS.md`/`MQTT_PROTOCOL.md`); se limita por **tamaño** de mensaje (8 KB, Etapa 6), no por frecuencia, para no descartar datos legítimos en una ráfaga de reconexión |

Respuesta al superar el límite: `429 Too Many Requests` con cabecera `Retry-After`, mismo formato de error RFC 7807 que el resto de la API.

## 6. CSRF y XSS en un frontend Flutter Web con Bearer tokens

**CSRF es una amenaza de baja aplicabilidad aquí, no por descuido sino por diseño**: CSRF explota que el navegador adjunta automáticamente cookies/credenciales a peticiones cross-site. Esta API se autentica con un **Bearer token en la cabecera `Authorization`**, no con cookies — un sitio malicioso no puede hacer que el navegador de la víctima adjunte un header que ese sitio no conoce. Por tanto, **no se implementa un token CSRF tradicional** (sería protección redundante para una amenaza que ya no aplica con este esquema de autenticación).

El riesgo real se traslada a **XSS**: si un atacante consigue ejecutar JavaScript en la página Flutter Web, podría leer el token desde donde esté almacenado en el navegador. Mitigaciones:
- Cabecera `Content-Security-Policy` estricta (restringe orígenes de scripts; sin `unsafe-inline` salvo lo imprescindible por el propio motor de Flutter Web).
- El framework (Flutter Web) renderiza mediante Canvas/DOM controlado, no HTML interpolado a mano — reduce la superficie de XSS reflejado típica de apps que concatenan HTML manualmente; aun así, cualquier contenido de usuario mostrado en la UI (nombres, comentarios futuros) debe tratarse como no confiable.
- Vida corta del access token (ya decidido) limita el daño de un token robado; el refresh token rotativo revoca la cadena completa si se detecta un uso indebido (reutilización de un refresh token ya rotado = señal de robo, Etapa 13 debe tratarlo como incidente y revocar toda la sesión).
- **Aplazado a V2/Futuro** (no bloquea el MVP): explorar un backend-for-frontend que entregue el refresh token en una cookie `httpOnly`+`Secure`+`SameSite=Strict` en vez de almacenamiento accesible por JS, si el análisis de riesgo posterior lo considera necesario.

## 7. Gestión centralizada de secretos
- Ningún secreto (credenciales de BD, claves de firma JWT, credenciales SMTP, credenciales admin de EMQX) vive en código ni en el repositorio — se inyectan como variables de entorno por la plataforma de despliegue.
- Herramienta concreta (gestor de secretos del proveedor cloud, Docker secrets, o similar) se decide en Etapa 9 según el proveedor elegido; aquí se fija el principio y la prohibición de alternativas (nunca en `.env` versionado, nunca hardcodeado "temporalmente").
- Los secretos de **dispositivos** (credenciales de gateway) siguen su propio ciclo de vida ya definido (Etapa 5-7: hash en BD, texto claro solo en la respuesta de creación/rotación) — no se gestionan con esta misma herramienta, son secretos de negocio, no de infraestructura.
- **Escaneo automático (`gitleaks`) en cada push** (`ci-cd.yml`, job `dependency-scan`) — primera vez que se ejecutó realmente (2026-07-28/29, antes siempre se saltaba porque el paso previo de `npm audit` fallaba primero). Encontró un falso positivo real: `apps/backend/.env.example` documenta el placeholder de la clave RSA como `"-----BEGIN PRIVATE KEY-----\n...\n-----END PRIVATE KEY-----"` (con puntos suspensivos literales, nunca contenido base64 real) — la regla `private-key` de gitleaks solo mira las cabeceras `-----BEGIN/END ... KEY-----`, así que dispara igual. Añadido `.gitleaks.toml` (raíz del repo, `gitleaks-action` lo detecta solo) con una excepción por **regex** (no por ruta) que solo cubre el patrón exacto del placeholder con `...` literal — verificado localmente con el binario de `gitleaks` que una clave real pegada por error en ese mismo fichero seguiría detectándose (la excepción no es un "no escanees este fichero").

## 8. Rotación de credenciales
- Credenciales de gateway: ya soportado (`POST /gateways/{id}/rotate-credential`, Etapa 7).
- Clave de firma JWT: asimétrica con `kid` (key id) en la cabecera del token — permite tener una clave nueva activa para firmar y la anterior aún válida solo para verificar durante un periodo de solape, sin invalidar de golpe todas las sesiones activas.
- Credenciales de infraestructura (BD, SMTP, EMQX admin): rotación manual programada cada 90 días como parte del mantenimiento operativo — ver [`MAINTENANCE.md` §2](MAINTENANCE.md#2-calendario-de-mantenimiento-recurrente) — sin automatización obligatoria en el MVP.

## 9. Cifrado de datos sensibles en reposo
- Cifrado a nivel de almacenamiento: volumen de la base de datos y backups cifrados (lo ofrece cualquier proveedor de BD gestionada, Etapa 9) — suficiente para el nivel de sensibilidad real de los datos de este MVP (email, nombre; sin datos de salud, biométricos ni financieros).
- **No** se cifra a nivel de columna el email/nombre de usuario: romper el índice único de `email` (necesario en cada login) o de búsqueda por nombre no se justifica por el tipo de dato — sería coste de complejidad sin reducción de riesgo real frente al cifrado de almacenamiento ya presente.
- Contraseñas y secretos de dispositivo: **hash, no cifrado reversible** (ya fijado desde el inicio del proyecto) — nunca se necesita recuperarlos, solo verificarlos.

## 10. Escaneo de dependencias
- Backend (NestJS/TypeScript): `npm audit` + Dependabot (o equivalente) en el repositorio, ejecutado en cada PR y semanalmente aunque no haya cambios.
- Frontend (Flutter/Dart): `dart pub outdated` + un escáner de vulnerabilidades conocidas (p. ej. OSV-Scanner) en el pipeline.
- Imagen Docker: escaneo de vulnerabilidades del sistema base (p. ej. Trivy) antes de publicar cualquier imagen (Etapa 9, paso del pipeline ya previsto en el listado original de CI/CD).
- Política: una vulnerabilidad **crítica o alta** sin parche disponible bloquea el despliegue a producción; con parche disponible, se actualiza antes de continuar. Vulnerabilidades medias/bajas se registran pero no bloquean (evita parálisis por dependencias transitivas de bajo riesgo real).
- **`npm audit` se ejecuta con `--omit=dev`** (descubierto en la primera ejecución real del pipeline, 2026-07-28): la mayoría de los hallazgos "high" del árbol completo (`tmp`, `webpack`, `picomatch`, `inquirer`) llegan transitivamente vía `@nestjs/cli`, que solo se ejecuta en local durante `nest build`/generación de código — nunca en el proceso desplegado. Auditar el árbol completo habría bloqueado el despliegue por vulnerabilidades sin exposición real, sin ganar nada en seguridad efectiva. `--omit=dev` limita la puerta a lo que realmente corre en producción.
- **`lodash`/`multer`/`qs` fijados a versión parcheada vía `overrides`** (`package.json`, 2026-07-28): tras `--omit=dev` quedaban 3 hallazgos "high" reales (`lodash` vía `@nestjs/config`, `multer` vía `@nestjs/platform-express` — este último **no alcanzable hoy**, no hay ninguna ruta con `FileInterceptor`/`MulterModule` implementada — y `qs`/`body-parser`, sí alcanzable en cada petición). Los tres tenían una versión parcheada publicada (`lodash@4.18.1`, `multer@2.2.0`, `qs@6.15.3`) que `@nestjs/cli`/`@nestjs/config`/`@nestjs/platform-express` simplemente no habían adoptado todavía en sus propios rangos declarados — resuelto forzando esas versiones vía el campo `overrides` de npm, sin tocar la versión de NestJS ni esperar a una subida mayor. Verificado: `tsc`/`eslint`/`nest build`/46 tests unitarios/4 de integración (Postgres real) en verde, y arranque real de la API con peticiones HTTP reales (JSON body y query strings con sintaxis de array/objeto, el patrón exacto de los CVEs de `qs`) confirmando que la ruta de parseo sigue funcionando tras el cambio.
- Tras los overrides, `npm audit --omit=dev --audit-level=high` da **0 vulnerabilidades altas/críticas** (6 restantes, todas moderadas/bajas: `ajv`, `file-type`, `body-parser` vía rutas internas de `@nestjs/core`/`@nestjs/common` sin fix no-breaking disponible aún) — registradas, no bloqueantes, sin exposición directa a input de atacante.
- `nodemailer` (CVEs de inyección SMTP/CRLF/SSRF) — subido de `6.10.1` a `9.0.3` (única versión sin estos CVEs), verificado con un envío real a través de Mailpit, sin cambios de código necesarios (superficie de API usada — `createTransport`/`sendMail` con host/port/auth — se mantuvo estable).

## 11. CORS
- Lista blanca explícita de orígenes permitidos (dominio de producción y de staging de la app Flutter Web) — nunca `*` combinado con `credentials: true`.
- Métodos permitidos: los usados por la API (`GET, POST, PATCH, DELETE`). Cabeceras permitidas: `Authorization, Content-Type, Idempotency-Key`.
- Apps móviles (Android/iOS) no están sujetas a CORS (no son un contexto de navegador) — esta sección aplica solo a la variante web.

## 12. Mapeo con OWASP ASVS (nivel 2, ya fijado en Etapa 2)
Vista de alto nivel, no checklist exhaustivo (la revisión detallada y periódica es una actividad continua de Etapa 15, no un entregable único de esta etapa):

| Capítulo ASVS | Cómo se cubre |
|---|---|
| V2 Autenticación | Argon2id, MFA TOTP (V2), rate limiting de login (sección 5) |
| V3 Gestión de sesión | Refresh rotativo, revocación, vida corta del access token |
| V4 Control de acceso | RBAC (`PERMISSIONS.md`), RLS, ACL de broker (defensa en profundidad) |
| V5 Validación de entrada | Validación de DTOs en la API (Etapa 7), validación de payload MQTT (Etapa 6) |
| V7 Manejo de errores/logging | Formato RFC 7807 sin fugas de detalle interno (sección 13), logs estructurados (Etapa 10) |
| V8 Protección de datos | Cifrado en tránsito y en reposo (secciones 9), hash de secretos |
| V10 Código malicioso/dependencias | Escaneo de dependencias (sección 10) |
| V13 API y servicios web | Contrato OpenAPI, rate limiting, CORS (esta etapa) |

## 13. Manejo de errores sin fuga de información
- Las respuestas de error (RFC 7807, Etapa 7) nunca incluyen stack traces, nombres de tabla/columna, ni detalles de la excepción original en producción — solo un `detail` genérico y un `instance`.
- El detalle completo (excepción, stack trace) va a los logs estructurados del servidor con un identificador de correlación (Etapa 10), nunca a la respuesta HTTP.
- 403 sin distinguir "no tienes permiso" de "no existe" cuando la existencia del recurso es información sensible (ya fijado en `PERMISSIONS.md` sección 9 para el alcance por instalación) — se generaliza aquí como regla para toda la API.

## 14. Riesgos
- MFA no estar en el MVP deja las cuentas de Admin de organización/plataforma dependiendo solo de la contraseña hasta V2 — riesgo aceptado conscientemente, mitigado parcialmente por rate limiting y Argon2id.
- La ausencia de mTLS en dispositivos (ADR-0002) sigue siendo el mayor riesgo residual del lado de campo — ver `THREAT_MODEL.md`, amenaza de suplantación de dispositivos.
- El almacenamiento del token en el navegador (sección 6) es, hoy, la superficie de ataque más realista contra una cuenta de usuario si existiera una vulnerabilidad XSS — ninguna mitigación aquí es absoluta, de ahí el énfasis en CSP y en la vida corta del token.

## 15. Entregables de esta etapa
- Este documento (`SECURITY.md`).
- [`THREAT_MODEL.md`](THREAT_MODEL.md).
- Corrección aplicada a `DATA_MODEL.md`/`ARCHITECTURE.md` (RLS con `set_config` parametrizado).

## 16. Criterios de aceptación de esta etapa
- Cada uno de los controles de seguridad listados en el encargo original del usuario aparece en este documento, ya sea como "ya decidido" (con referencia) o como decisión nueva.
- El modelo de amenazas cubre las 12 categorías solicitadas, cada una con mitigación existente y riesgo residual explícito.

## 17. Pruebas necesarias derivadas
- Intentar 6 logins fallidos seguidos con el mismo email+IP y confirmar `429` en el sexto.
- Cambiar la contraseña de un usuario con 2 sesiones activas y confirmar que ambas quedan revocadas.
- Confirmar que una respuesta de error en producción no contiene el nombre de ninguna tabla/columna real ni un stack trace.
- Confirmar que las cabeceras CORS rechazan un origen fuera de la lista blanca aunque la petición incluya un token válido.
- Escanear la imagen Docker de referencia y confirmar que el pipeline bloquea ante una vulnerabilidad crítica simulada.

## 18. Lista de tareas de esta etapa
- [x] Consolidar controles ya decididos con referencias cruzadas.
- [x] Especificar MFA, rate limiting, CORS, secretos, cifrado, CSRF/XSS, escaneo de dependencias.
- [x] Corregir el mecanismo de RLS (`set_config` parametrizado).
- [ ] Revisión y validación por tu parte.
- [ ] Cerrar etapa y pasar a Etapa 9 (infraestructura y DevOps).

## 19. Dependencias
- Depende de Etapas 0-7.
- Bloquea Etapa 9 (aplicar estos controles en la infraestructura real: TLS, gestor de secretos, CORS, escaneo en CI/CD).

## 20. Aspectos que se aplazan explícitamente
- Implementación de MFA (V2, diseño ya fijado aquí).
- Backend-for-frontend con cookie `httpOnly` para refresh token (V2/Futuro, solo si el riesgo lo justifica).
- Automatización de rotación de credenciales de infraestructura (manual programada en el MVP).
- Checklist ASVS línea a línea — actividad periódica de Etapa 15, no de esta etapa.

## 21. Errores frecuentes a evitar
- No implementar un token CSRF "porque toca" sin analizar si el esquema de autenticación (Bearer token, no cookie) lo hace irrelevante — perder tiempo en la mitigación equivocada deja menos tiempo para la que sí importa (XSS).
- No interpolar valores de petición directamente en sentencias `SET`/`SET LOCAL` de PostgreSQL — usar siempre `set_config` parametrizado (sección 1).
- No cifrar columnas "por si acaso" cuando el cifrado de almacenamiento ya cubre el riesgo real — rompe índices y búsquedas sin beneficio de seguridad adicional para este tipo de dato.
- No dejar que un mensaje de error de producción revele estructura interna (nombres de tabla, stack trace) aunque sea "solo para depurar más rápido".

## 22. Historial de decisiones de esta etapa

| Fecha | Decisión | Alternativas consideradas |
|---|---|---|
| 2026-07-27 | JWT firmado con algoritmo asimétrico (RS256/EdDSA) con `kid` | HS256 (simétrico, sin rotación cómoda) |
| 2026-07-27 | MFA por TOTP, diseño fijado para V2 | SMS (descartado: coste, riesgo de SIM-swapping) |
| 2026-07-27 | CSRF tradicional no se implementa (Bearer token, no cookie) | Añadir token CSRF "por estándar" sin análisis de aplicabilidad |
| 2026-07-27 | Cifrado en reposo a nivel de almacenamiento, no de columna, para email/nombre | Cifrado de columna para todo dato considerado "personal" |
| 2026-07-27 | Rate limiting con valores concretos por categoría de endpoint | Un único límite global para toda la API |
