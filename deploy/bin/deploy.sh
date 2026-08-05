#!/usr/bin/env bash
# Выкат OpenProject (сборка из hierarch/canban) на текущем хосте.
#   deploy.sh <окружение> <sha>
#
# Окружения описаны в /etc/bo-deploy.conf — на каждом хосте свои.
# Образ уже собран локально (docker build в джобе), реестр не используется.
set -euo pipefail

TARGET="${1:?usage: deploy.sh <окружение> <sha>}"
SHA="${2:?usage: deploy.sh <окружение> <sha>}"
IMAGE="bo-openproject"
CONF=/etc/bo-deploy.conf
BACKUP_DIR="/var/backups/openproject"

[ -f "$CONF" ] || { echo "нет $CONF" >&2; exit 2; }
# shellcheck disable=SC1090
. "$CONF"

KEY="$(echo "$TARGET" | tr '[:lower:]' '[:upper:]')"
DIR_VAR="${KEY}_DIR"
DIR="${!DIR_VAR:-}"
[ -n "$DIR" ] || { echo "окружение '$TARGET' не описано в $CONF" >&2; exit 2; }
[ -d "$DIR" ] || { echo "нет каталога $DIR" >&2; exit 2; }

docker image inspect "$IMAGE:$SHA" >/dev/null

cd "$DIR"

# Дамп перед выкатом: образ гонит db:migrate сам на старте web, а миграции
# OpenProject необратимы — откат только восстановлением.
if [ -n "$(docker compose ps -q postgres 2>/dev/null)" ]; then
  mkdir -p "$BACKUP_DIR"; chmod 700 "$BACKUP_DIR"
  STAMP="$(date +%Y%m%d-%H%M%S)"
  DUMP="$BACKUP_DIR/$TARGET-$STAMP.sql.gz"
  echo "-----> Дамп БД: $DUMP"
  docker compose exec -T postgres pg_dump -U openproject openproject | gzip > "$DUMP"
  ls -1t "$BACKUP_DIR/$TARGET-"*.sql.gz 2>/dev/null | tail -n +11 | xargs -r rm -f
else
  echo "-----> postgres не запущен, дамп пропущен (первый выкат?)"
fi

# Пин образа: docker compose подхватывает OP_IMAGE из .env рядом с compose-файлом
if grep -q '^OP_IMAGE=' .env 2>/dev/null; then
  sed -i "s|^OP_IMAGE=.*|OP_IMAGE=$IMAGE:$SHA|" .env
else
  echo "OP_IMAGE=$IMAGE:$SHA" >> .env
fi

echo "-----> Поднимаю $TARGET ($DIR) на $IMAGE:$SHA"
docker compose up -d --remove-orphans

# Чистка: оставляем 5 последних sha-тегов, именованные теги не трогаем
docker images "$IMAGE" --format '{{.Tag}}|{{.CreatedAt}}' \
  | grep -Ev '^(staging|production)\|' \
  | sort -t'|' -k2 -r \
  | tail -n +6 \
  | cut -d'|' -f1 \
  | while read -r tag; do docker rmi "$IMAGE:$tag" >/dev/null 2>&1 || true; done

echo "-----> Готово"
