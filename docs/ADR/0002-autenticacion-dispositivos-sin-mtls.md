# ADR-0002: Autenticación de gateways con credenciales propias + ACL, sin mTLS/PKI en el MVP

- Estado: Aceptada
- Fecha: 2026-07-27 (revisada 2026-07-27 tras aclarar que solo el gateway tiene conectividad de red — los dispositivos llegan por LoRa)

## Contexto
Principio ya fijado: no credenciales compartidas entre dispositivos, auth de dispositivo separada de auth de usuario. Equipo de 3-6 personas con plazo de unos meses para el MVP (Etapa 0). EMQX soporta autenticación conectable (HTTP, PostgreSQL) y ACL por cliente, además de TLS. Los sensores llegan al gateway por LoRa; solo el **gateway** tiene GPRS/Ethernet y por tanto solo el gateway abre una sesión MQTT — los dispositivos/estaciones no tienen ni pueden tener una credencial de red propia.

## Decisión
Cada **gateway** recibe, al pre-registrarse (Etapa 1), una credencial MQTT única (usuario/contraseña o token) — no compartida con ningún otro gateway. EMQX valida esa credencial contra el backend y aplica una ACL que restringe a esa credencial a publicar únicamente bajo su propio prefijo de topic (`org/{orgId}/gw/{gatewayId}/...`). Los **dispositivos** se autorizan a nivel de aplicación (el proceso `ingestion` rechaza `device_id` no pre-registrados para ese gateway), no mediante una credencial de red propia. TLS es obligatorio para el cifrado en tránsito (no negociable), pero la autenticación mutua vía certificados de cliente (mTLS) queda fuera del MVP.

## Alternativas consideradas
- **mTLS con PKI propia por gateway** (certificado de cliente individual): más robusto frente a robo de credenciales, pero exige montar y operar una autoridad certificadora, un flujo de emisión/distribución de certificados al aprovisionar cada gateway, y un mecanismo de rotación/revocación (CRL u OCSP, o certificados de corta duración). Ese coste de ingeniería no encaja en el plazo de "unos meses" ya decidido para el MVP.
- **Credencial por dispositivo además de por gateway**: descartada por no tener sentido físico — el dispositivo nunca abre una conexión de red propia (llega por LoRa al gateway), así que no hay nada que autenticar a ese nivel; su control de acceso es una autorización de aplicación (lista de `device_id` pre-registrados), no una autenticación de transporte.

## Consecuencias
- El nivel de seguridad resultante (TLS de transporte + credencial única por gateway + ACL) debe revisarse explícitamente en la Etapa 8 (modelo de amenazas) frente a escenarios de robo/filtración de credenciales de un gateway — un gateway comprometido puede inyectar datos falsos para cualquiera de sus dispositivos pre-registrados, aunque no para los de otro gateway/organización.
- mTLS queda documentado como mejora candidata para V2/Futuro si el análisis de amenazas de la Etapa 8 concluye que es necesario, o si aparecen clientes con requisitos de seguridad más estrictos.
- La rotación de una credencial de gateway comprometida debe ser una operación soportada desde el MVP (revocar y emitir una nueva), aunque no haya PKI.
