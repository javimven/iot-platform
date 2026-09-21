#!/usr/bin/env bash
# Aviso por correo cuando el disco de la VPS se llena (BACKLOG.md #54).
#
# El 2026-09-18 el disco llegó al 100 %: EMQX dejó de arrancar, el puente se
# quedó sin broker y la plataforma pasó tres días sin recibir datos sin que
# saltara ninguna alarma. Esto avisa antes de llegar ahí.
#
# Se instala en la VPS (ver infra/systemd/aviso-disco.timer) y usa el SMTP de
# la propia plataforma, el de /opt/iot-platform/.env: ni cuenta nueva ni
# servicio externo. El destinatario sale de AVISO_DISCO_EMAIL o, si no está,
# del correo del admin de plataforma de ese mismo archivo — nunca va escrito
# aquí, que esto sí está en git.
#
# Prueba manual (fuerza el envío):  UMBRAL=1 /usr/local/bin/aviso-disco.sh
set -uo pipefail

UMBRAL=${UMBRAL:-80}
PUNTO=${PUNTO:-/}
ENTORNO=${ENTORNO:-/opt/iot-platform/.env}
REPETIR=${REPETIR:-86400} # no repetir el mismo aviso antes de 24 h

# La marca y el mensaje van en RAM (/dev/shm): con el disco lleno, escribir en
# el disco es justo lo que no se puede hacer.
MARCA=/dev/shm/aviso-disco.ultimo
MENSAJE=/dev/shm/aviso-disco.txt

uso=$(df --output=pcent "$PUNTO" | tr -dc '0-9')
[ -n "$uso" ] || exit 0

# Segundo canal, independiente del correo y del propio servidor (BACKLOG.md
# #55: cuando el correo de Brevo dejó de entregar, el aviso se quedó mudo).
# Healthchecks.io avisa si NO recibe el latido —servidor caído, sin red, disco
# lleno— y también si le mandamos un fallo a propósito. La URL va en el .env
# (HEALTHCHECKS_DISCO_URL); sin ella, esta parte no hace nada.
latido() {
  local destino="$1"
  [ -n "${HEALTHCHECKS_DISCO_URL:-}" ] || return 0
  curl -fsS -m 10 --retry 3 -o /dev/null "${HEALTHCHECKS_DISCO_URL}${destino}" ||
    logger -t aviso-disco "no se pudo mandar el latido a Healthchecks"
}
set -a
# shellcheck disable=SC1090
. "$ENTORNO" 2>/dev/null
set +a

if [ "$uso" -lt "$UMBRAL" ]; then
  # Ya holgado: se olvida el aviso anterior para poder volver a avisar.
  [ "$uso" -lt $((UMBRAL - 5)) ] && rm -f "$MARCA"
  latido ""
  exit 0
fi
latido "/fail"

ahora=$(date +%s)
anterior=$(cat "$MARCA" 2>/dev/null || echo 0)
[ $((ahora - anterior)) -lt "$REPETIR" ] && exit 0

destino=${AVISO_DISCO_EMAIL:-${PLATFORM_ADMIN_BOOTSTRAP_EMAIL:-}}
if [ -z "${SMTP_HOST:-}" ] || [ -z "${EMAIL_FROM:-}" ] || [ -z "$destino" ]; then
  logger -t aviso-disco "disco al ${uso}% y no hay a quién avisar (falta SMTP_HOST/EMAIL_FROM/destino en $ENTORNO)"
  exit 1
fi

{
  echo "From: ${EMAIL_FROM}"
  echo "To: ${destino}"
  echo "Subject: [iot-platform] Disco al ${uso}% en $(hostname)"
  echo "Content-Type: text/plain; charset=utf-8"
  echo
  echo "El disco de $(hostname) está al ${uso}% (aviso a partir del ${UMBRAL}%)."
  echo
  echo "Si llega al 100%: EMQX no arranca, el puente se queda sin broker y la"
  echo "plataforma deja de recibir datos de las estaciones (BACKLOG.md #54)."
  echo
  df -h "$PUNTO"
  echo
  docker system df 2>/dev/null
  echo
  echo "Para liberar espacio:  docker image prune -af --filter 'until=72h'"
} >"$MENSAJE"

if curl --silent --show-error --ssl-reqd \
  --url "smtp://${SMTP_HOST}:${SMTP_PORT:-587}" \
  --user "${SMTP_USER}:${SMTP_PASSWORD}" \
  --mail-from "${EMAIL_FROM}" --mail-rcpt "$destino" \
  --upload-file "$MENSAJE"; then
  echo "$ahora" >"$MARCA"
  logger -t aviso-disco "aviso enviado: disco al ${uso}%"
else
  logger -t aviso-disco "no se pudo enviar el aviso (disco al ${uso}%)"
fi
rm -f "$MENSAJE"
