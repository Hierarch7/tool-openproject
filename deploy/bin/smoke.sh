#!/usr/bin/env bash
# Ждём, пока приложение ответит на /health_check.
# Миграции идут в entrypoint контейнера web, поэтому окно ожидания широкое.
#   smoke.sh <окружение>
#
# При OPENPROJECT_HTTPS=true приложение редиректит http→https (301), поэтому
# для таких окружений обязателен заголовок X-Forwarded-Proto.
set -euo pipefail

TARGET="${1:?usage: smoke.sh <окружение>}"
CONF=/etc/bo-deploy.conf

[ -f "$CONF" ] || { echo "нет $CONF" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONF"

KEY="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
DIR_VAR="${KEY}_DIR"; PORT_VAR="${KEY}_PORT"; HOST_VAR="${KEY}_HOST"; TLS_VAR="${KEY}_HTTPS"
DIR="${!DIR_VAR:-}"; PORT="${!PORT_VAR:-}"; HOST="${!HOST_VAR:-}"; TLS="${!TLS_VAR:-false}"

[ -n "$DIR" ] && [ -n "$PORT" ] && [ -n "$HOST" ] \
  || { echo "окружение '$TARGET' не описано в $CONF" >&2; exit 2; }

URL="http://127.0.0.1:$PORT/health_check"
HDR=(-H "Host: $HOST")
[ "$TLS" = "true" ] && HDR+=(-H "X-Forwarded-Proto: https")

for i in $(seq 1 120); do
  code="$(curl -s -o /dev/null -w '%{http_code}' --max-time 10 "${HDR[@]}" "$URL" || true)"
  if [ "$code" = "200" ]; then
    echo "OK: $URL ответил 200 (попытка $i)"
    exit 0
  fi
  echo "ждём приложение... попытка $i/120, код '$code'"
  sleep 10
done

echo "ОШИБКА: $URL не ответил 200 за 20 минут" >&2
docker compose -f "$DIR/docker-compose.yml" logs --tail 200 web >&2 || true
exit 1
