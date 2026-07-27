# PRIVACY.md

## 0. Estado de este documento
- Etapa del proceso: transversal — no tiene número propio en `PROJECT_STATUS.md` (0-15); se apoya en Etapa 2 (`NON_FUNCTIONAL_REQUIREMENTS.md` §13), Etapa 5 (`DATA_MODEL.md`), Etapa 8 (`SECURITY.md`/`THREAT_MODEL.md`), Etapa 12 (`BACKUP_AND_RECOVERY.md` §7, borrado lógico) y Etapa 13 (implementación real de auth/auditoría/notificaciones).
- Estado: En análisis (primera versión completa, pendiente de tu validación — en particular la sección 2 sobre roles de responsable/encargado del tratamiento, que tiene implicaciones contractuales fuera del alcance de este repositorio)
- Última actualización: 2026-07-27
- Referenciado desde: `NON_FUNCTIONAL_REQUIREMENTS.md` §13, `INCIDENT_RESPONSE.md` §1/§14 (ambos apuntaban aquí como "a redactar")

## 1. Alcance y marco legal

Aplica el **RGPD** (Reglamento UE 2016/679) por el contexto España/UE del producto (`PRODUCT_REQUIREMENTS.md` §1: sector agro/ambiental, España) y por la elección de infraestructura en la UE (`DEPLOYMENT.md`: Hetzner Alemania/Finlandia, DigitalOcean Frankfurt) — decisión ya tomada en Etapa 9 en parte por esta razón.

Este documento cubre el tratamiento de **datos personales** dentro de la plataforma. No cubre obligaciones puramente contractuales/comerciales (facturación, condiciones de servicio) que están fuera del alcance de este repositorio técnico.

## 2. Responsable y encargado del tratamiento (roles RGPD)

Este es el punto de mayor ambigüedad legal del documento y **requiere tu validación** — la distinción no es solo técnica, tiene implicaciones contractuales:

| Dato | Quién decide su existencia/finalidad | Rol RGPD probable |
|---|---|---|
| Datos de la organización (cuentas de plataforma: qué organizaciones existen) | El operador de la plataforma (tú/tu empresa) | **Responsable del tratamiento** |
| Datos de miembros de una organización (nombre, email, rol de sus usuarios) | La organización cliente (decide a quién invita, con qué rol) | El operador de la plataforma actúa como **encargado del tratamiento** (Art. 28 RGPD); la organización cliente es la **responsable** |
| Metadatos técnicos de sesión (IP, user-agent) | Generados automáticamente por el sistema de autenticación | Responsable: el operador de la plataforma (es un dato de seguridad de la propia infraestructura, no decidido por la organización cliente) |
| Auditoría (`audit_log`) | Generado automáticamente | Mixto: el operador es responsable del mecanismo, pero el contenido (quién hizo qué) es dato de la organización cliente |

**Implicación práctica no resuelta en este repositorio**: si el operador de la plataforma actúa como encargado del tratamiento para los datos de miembros de cada organización, el RGPD (Art. 28) exige un **contrato de encargo de tratamiento** entre el operador y cada organización cliente. Esto es un documento legal/contractual, no código ni un documento técnico — se señala aquí como una tarea pendiente fuera del alcance de este repositorio, no como algo que este documento resuelve.

**Supuesto asumido** (a validar): dado que las organizaciones se dan de alta manualmente por el Admin de plataforma (Etapa 0), se asume que existe o existirá un acuerdo comercial marco con cada organización cliente que puede incorporar esta cláusula — no se modela aquí un flujo de "aceptar términos" en el producto para el MVP.

## 3. Inventario de datos personales

Basado en `DATA_MODEL.md` (Etapa 5) — no se repite el DDL completo, solo se marca qué columnas son datos personales y por qué.

| Tabla.columna | Dato personal? | Categoría | Base legal probable |
|---|---|---|---|
| `users.email`, `users.full_name` | Sí | Identificación | Ejecución de un contrato (Art. 6.1.b) — es la cuenta con la que el usuario opera la plataforma |
| `users.password_hash` | Indirectamente (dato de seguridad de la cuenta, no exportable/legible) | Autenticación | Interés legítimo (seguridad de la cuenta) |
| `organizations.contact_email` | Sí (email de una persona de contacto) | Identificación | Ejecución de un contrato |
| `sessions.ip_address`, `sessions.user_agent` | Sí (la IP es dato personal bajo RGPD) | Seguridad/técnico | Interés legítimo (detección de accesos indebidos, `SECURITY.md`) |
| `audit_log.actor_user_id`, `audit_log.metadata` | Sí (quién hizo qué; `metadata` puede contener valores libres) | Trazabilidad | Interés legítimo (cumplimiento, resolución de incidentes) + obligación legal en algunos casos |
| `notification_log.recipient_user_id` | Indirecto (referencia, no repite el email) | Trazabilidad de envíos | Interés legítimo |
| `installations.latitude/longitude` | **No**, con matiz | Ubicación de una instalación agrícola/ambiental, no de una persona (ya decidido en `NON_FUNCTIONAL_REQUIREMENTS.md` §13) | — |
| Telemetría (`telemetry`, `latest_readings`) | No | Magnitudes ambientales (temperatura, humedad, etc.) | — |
| `gateway_credentials` (hash) | No | Credencial de dispositivo, no de persona | — |

**Matiz sobre `installations.latitude/longitude`**: se mantiene la decisión de Etapa 2 de que no es dato personal en el caso de uso definido (fincas/invernaderos, no domicilios). Si en el futuro se onboarding a organizaciones donde una instalación coincide con una vivienda particular (p. ej. un huerto doméstico), esta clasificación debería revisarse caso a caso — se señala como riesgo, no se bloquea el diseño por un caso límite no confirmado.

## 4. Minimización y finalidad

- No se recoge ningún dato personal más allá del necesario para operar la cuenta (nombre, email) y para la seguridad de la sesión (IP, user-agent) — no hay perfilado, scoring ni analítica de comportamiento de usuario en el MVP.
- La telemetría de sensores (temperatura, humedad, conductividad, etc.) es, por diseño de producto, sobre el **entorno**, no sobre personas — coherente con `NON_FUNCTIONAL_REQUIREMENTS.md` §13.
- El campo `audit_log.metadata` (jsonb, `Record<string, unknown>`) es de propósito general y podría, en teoría, terminar conteniendo datos personales adicionales si un desarrollador futuro añade un campo con datos de un tercero (p. ej. el email de un invitado en el evento `member.invite`). **Regla a aplicar**: `metadata` debe limitarse a identificadores (IDs) y valores de configuración, nunca a datos de contacto de una persona distinta del actor — a revisar en cada PR que añada un nuevo `AuditLogService.record()`.

## 5. Base legal por finalidad

| Finalidad | Base legal (Art. 6 RGPD) |
|---|---|
| Crear y gestionar la cuenta de usuario, autenticación | 6.1.b — ejecución de un contrato |
| Registro de sesiones (IP, user-agent), rate limiting | 6.1.f — interés legítimo (seguridad) |
| Auditoría de acciones administrativas | 6.1.f — interés legítimo; en algunos sectores puede ser 6.1.c (obligación legal) |
| Envío de emails transaccionales (invitación, reset de contraseña, alertas) | 6.1.b (invitación/reset, parte del servicio) y 6.1.f (alertas, interés legítimo de notificar una anomalía que el usuario ha configurado) |

No se usa el consentimiento (6.1.a) como base legal para ninguna finalidad del MVP — no hay marketing, cookies de terceros ni tratamiento opcional en este alcance.

## 6. Derechos de los interesados (Art. 15-22 RGPD)

| Derecho | Mecanismo actual | Estado |
|---|---|---|
| Acceso | Ninguno automatizado en la API (el usuario ve sus propios datos vía `/me`, pero no un export formal) | **Gap MVP** — ver §9 |
| Rectificación | Parcial: un Admin de organización puede editar nombre/rol de un miembro (`MembersService`); el propio usuario no tiene un endpoint de autoedición de su `full_name` todavía | **Gap MVP** |
| Supresión ("derecho al olvido") | Baja lógica de organización (`FUNCTIONAL_REQUIREMENTS.md` §2: `activa → suspendida → baja lógica`); no hay borrado físico de `users`/`members` en el MVP | Parcial — ver §7 |
| Portabilidad | Ninguno | **Gap MVP**, Futuro |
| Oposición/limitación | No aplica en el MVP (no hay tratamiento basado en consentimiento ni marketing) | N/A |

Estos gaps son coherentes con el alcance MVP ya fijado (`PRODUCT_REQUIREMENTS.md` §9: prioriza el flujo operativo end-to-end) — se documentan aquí como deuda conocida, no se resuelven en este documento.

## 7. Supresión y retención

- **Organización**: `activa → suspendida → baja lógica` (soft delete, `FUNCTIONAL_REQUIREMENTS.md` §2). No hay borrado físico automático en el MVP.
- **Usuario individual que deja una organización**: su fila en `members` pasa a `status: inactive` (RLS y permisos ya dejan de concederle acceso); su fila en `users` (email, nombre) permanece si tiene membresías en otras organizaciones o membresías históricas — no se borra físicamente por diseño, ya que `audit_log.actor_user_id` y `notification_log.recipient_user_id` referencian `users.id` (borrar físicamente rompería la integridad del historial de auditoría, que a su vez es requisito de seguridad de `SECURITY.md`).
- **Tensión no resuelta**: esto entra en conflicto potencial con una solicitud de supresión total de un usuario bajo RGPD. La mitigación estándar (y la que se recomienda adoptar, sin implementar todavía) es **anonimización** en vez de borrado físico: sustituir `email`/`full_name` por un valor no identificable mientras se preserva la fila y su `id` (para no romper referencias de auditoría), y revocar todas sus sesiones. No implementado en el MVP — **gap a resolver antes de aceptar clientes con usuarios finales que puedan invocar este derecho activamente** (más probable en V2/Futuro si el producto crece más allá de un círculo cerrado de organizaciones conocidas).
- **Telemetría**: retención de 13 meses "caliente" + indefinida "fría" (`NON_FUNCTIONAL_REQUIREMENTS.md` §6) — no aplica un derecho de supresión individual porque no es dato personal (§3).
- **Backups**: un backup restaurado (`BACKUP_AND_RECOVERY.md`) puede reintroducir temporalmente datos que se habían anonimizado/suprimido tras la fecha del backup — riesgo aceptado y ya documentado allí como limitación general de cualquier sistema de backup, se hereda aquí sin necesidad de repetirlo.

## 8. Cifrado y seguridad de los datos personales

Ya decidido en `SECURITY.md` (Etapa 8), se resume aquí por relevancia RGPD (Art. 32, seguridad del tratamiento):
- Contraseñas: Argon2id, nunca reversible ni en texto plano.
- Secretos de refresh token: hash SHA-256 (alta entropía, no requiere Argon2).
- Transporte: TLS obligatorio (API vía HTTPS, dispositivos vía MQTT+TLS).
- Backups externos (`pg_dump` a Hetzner Object Storage): cifrado con `age`, clave fuera de la VPS (`BACKUP_AND_RECOVERY.md` §1).
- Aislamiento multi-tenant: RLS en PostgreSQL + contexto de aplicación (`ARCHITECTURE.md`) — evita que una organización acceda a los datos personales de miembros de otra.

## 9. Notificación de brechas de seguridad (Art. 33-34 RGPD)

Vincula con `INCIDENT_RESPONSE.md` §1, que ya señalaba "si hay datos personales afectados, el procedimiento de notificación de `PRIVACY.md`" — se define aquí:

1. **Detección**: cualquier Sev1/Sev2 (`INCIDENT_RESPONSE.md` §2) que implique acceso, exfiltración o pérdida de datos de las tablas listadas en §3 de este documento se trata como potencial brecha de datos personales.
2. **Plazo**: el RGPD exige notificar a la autoridad de control (AEPD, en España) en un plazo de **72 horas** desde que se tiene constancia de la brecha, si existe riesgo para los derechos de los afectados.
3. **Evaluación de riesgo** (a decidir por ti/el responsable legal, no automatizable): ¿hay riesgo real para los afectados? (p. ej. una exposición de `password_hash` con Argon2id tiene riesgo bajo por ser no reversible; una exposición de `users.email`+`full_name` sin cifrar tiene más riesgo).
4. **Notificación a los interesados** (Art. 34): solo si el riesgo es alto (p. ej. credenciales en texto plano expuestas, lo cual no debería ser posible dado el diseño de §8).
5. **Registro interno**: toda brecha, se notifique o no externamente, se registra internamente (reutilizar el mecanismo de post-mortem de `INCIDENT_RESPONSE.md` §6) — es una obligación del Art. 33.5 RGPD independientemente de si se notifica a la autoridad.

**Limitación actual**: no existe un proceso formal de "evaluación de riesgo para notificación" fuera de este documento — en el estado actual del equipo (3-6 personas), la decisión de notificar recaería en quien asuma el rol de responsable legal/DPO de facto. No se modela un Delegado de Protección de Datos (DPO) formal en el MVP; probablemente no sea obligatorio a esta escala (Art. 37 RGPD: obligatorio solo bajo ciertos criterios de volumen/tipo de dato que este producto no alcanza en el MVP) — a revisar si la escala crece significativamente.

## 10. Terceros y subencargados (Art. 28 RGPD)

Proveedores de infraestructura que procesan datos personales por cuenta del operador de la plataforma (`DEPLOYMENT.md`):

| Proveedor | Rol | Datos que toca | Ubicación |
|---|---|---|---|
| Hetzner Cloud | Subencargado (cómputo) | Todos (BD, app corren aquí) | Alemania/Finlandia (UE) |
| DigitalOcean (Managed PostgreSQL) | Subencargado (almacenamiento) | Todos los datos personales de §3 | Frankfurt (UE) |
| Hetzner Object Storage | Subencargado (backups) | Backup cifrado de todo lo anterior | UE |
| Proveedor SMTP (a elegir, Etapa 9 — Mailpit solo en desarrollo) | Subencargado (envío de email) | Email + nombre del destinatario, contenido del mensaje | **A confirmar** — debe elegirse un proveedor con sede o garantías adecuadas en la UE (cláusulas contractuales tipo si es fuera de la UE) |
| Grafana Cloud, UptimeRobot, Healthchecks.io, Firebase Crashlytics (`OBSERVABILITY.md`) | Subencargados (observabilidad) | Metadatos técnicos, no debería incluir PII de negocio si `OBSERVABILITY.md` §títulos de logging se respeta (no loguear email/nombre en texto libre de logs de aplicación) | Variable — Crashlytics (Google) fuera de la UE, requiere cláusulas contractuales tipo |

**Acción pendiente, fuera de este repositorio**: formalizar acuerdos de encargo de tratamiento (o confirmar que ya están cubiertos por los términos estándar de cada proveedor, como es habitual en Hetzner/DO) con cada uno de los proveedores de la tabla anterior antes de operar en producción con datos reales de organizaciones.

## 11. Riesgos

- El rol de responsable/encargado (§2) no está resuelto contractualmente — riesgo legal, no técnico, pero bloquea operar con clientes reales hasta clarificarse.
- No hay mecanismo de anonimización de usuario (§7) — si una organización cliente recibe una solicitud de un empleado suyo para ser "olvidado", hoy no hay una función de producto que lo resuelva limpiamente sin romper `audit_log`.
- `audit_log.metadata` es de tipo libre (`jsonb`) — riesgo de fuga de datos personales no controlada si un desarrollador futuro no sigue la regla de la sección 4.
- Firebase Crashlytics (si se usa en producción) exporta datos fuera de la UE — requiere cláusulas contractuales tipo, no evaluado en detalle aquí.

## 12. Entregables de esta etapa
- Este documento (`PRIVACY.md`).
- Actualización de referencias cruzadas en `NON_FUNCTIONAL_REQUIREMENTS.md` §13 e `INCIDENT_RESPONSE.md` (apuntaban aquí como "a redactar").

## 13. Criterios de aceptación de esta etapa
- [ ] Confirmas el análisis de roles responsable/encargado de la sección 2 (o indicas que ya existe un acuerdo marco con las organizaciones cliente que lo cubre).
- [ ] Confirmas que el gap de anonimización (§7) se acepta como deuda conocida para el MVP.
- [ ] Confirmas el proveedor SMTP de producción antes de operar con datos reales (§10).

## 14. Aspectos que se aplazan explícitamente
- Endpoint de autoservicio de acceso/portabilidad de datos (§6) — Futuro, salvo que un cliente lo exija antes.
- Anonimización automática de usuario al ejercer el derecho de supresión (§7) — V2/Futuro.
- DPO formal — solo si la escala lo exige (Art. 37 RGPD).
- Flujo de "aceptar términos/DPA" dentro del producto — se asume acuerdo comercial fuera de banda por ahora.

## 15. Errores frecuentes a evitar
- No tratar la telemetría ambiental como si tuviera las mismas obligaciones RGPD que los datos de usuario — son categorías distintas (§3), no diluir la distinción "por si acaso".
- No añadir campos de datos personales de terceros a `audit_log.metadata` sin pasar antes por la regla de la sección 4.
- No asumir que "borrado lógico" ya satisface un derecho de supresión RGPD — son conceptos distintos (uno es recuperabilidad operativa, el otro es un derecho legal) y ahora mismo hay una tensión real sin resolver entre ambos (§7).
- No operar en producción con un proveedor SMTP o de observabilidad sin haber confirmado su ubicación/garantías (§10) — es fácil arrancar con lo que sea más rápido de configurar y olvidar esta verificación.

## 16. Historial de decisiones de esta etapa
- 2026-07-27: primera versión, creada tras cerrar Etapa 13 (backend) — se detectó que `NON_FUNCTIONAL_REQUIREMENTS.md` §13 e `INCIDENT_RESPONSE.md` llevaban desde su creación apuntando a un `PRIVACY.md` que nunca se había redactado.
