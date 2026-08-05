#!/usr/bin/env bash
# Раскладка обвязки деплоя OpenProject на хост. Идемпотентно, запускать от root:
#
#   sudo deploy/install.sh hy
#   sudo deploy/install.sh gambit
#
# Ставит только то, что безопасно перезаписать. Живой конфиг (docker-compose.yml,
# .env, vhost nginx) не трогает — см. вывод в конце и deploy/README.md.
set -euo pipefail

ROLE="${1:-}"
SRC="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

case "$ROLE" in
  hy|gambit) ;;
  *) echo "usage: install.sh <hy|gambit>" >&2; exit 2 ;;
esac
[ "$(id -u)" = 0 ] || { echo "нужен root" >&2; exit 1; }

CONF_SRC="$SRC/etc/bo-deploy.conf.$ROLE"
[ -f "$CONF_SRC" ] || { echo "нет $CONF_SRC" >&2; exit 2; }

# Каталог со скриптами обязан быть root:root — runner'у выдан sudo на его содержимое,
# и владение каталогом позволило бы подменить скрипты.
install -d -o root -g root -m 755 /opt/bo-deploy
install -o root -g root -m 755 "$SRC/bin/deploy.sh" /opt/bo-deploy/deploy.sh
install -o root -g root -m 755 "$SRC/bin/smoke.sh"  /opt/bo-deploy/smoke.sh
install -o root -g root -m 644 "$CONF_SRC"          /etc/bo-deploy.conf

# sudoers проверяем во временном файле: битый файл в /etc/sudoers.d ломает sudo целиком.
TMP_SUDO="$(mktemp)"
trap 'rm -f "$TMP_SUDO"' EXIT
cp "$SRC/etc/sudoers.d/forgejo-runner-op" "$TMP_SUDO"
visudo -c -f "$TMP_SUDO" >/dev/null
install -o root -g root -m 440 "$TMP_SUDO" /etc/sudoers.d/forgejo-runner-op

install -d -o root -g root -m 755 /etc/forgejo-runner
install -o root -g root -m 644 "$SRC/etc/forgejo-runner/op-config.yaml"    /etc/forgejo-runner/op-config.yaml
install -o root -g root -m 644 "$SRC/etc/systemd/forgejo-runner-op.service" /etc/systemd/system/forgejo-runner-op.service
systemctl daemon-reload

install -d -o root -g root -m 700 /var/backups/openproject

echo
echo "Разложено: /opt/bo-deploy/{deploy,smoke}.sh, /etc/bo-deploy.conf, sudoers,"
echo "           конфиг и unit runner'а (systemd перечитан)."
echo
echo "Намеренно НЕ сделано:"
echo "  * runner не перезапущен  — 'systemctl restart forgejo-runner-op', но НЕ во время выката"
echo "  * nginx не тронут        — блок из deploy/nginx/hocuspocus-location.conf вставляется в bo.conf вручную"
echo "  * compose не перезаписан — deploy/compose/*.yml это эталон для сверки, а не для копирования"
