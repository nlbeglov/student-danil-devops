#!/usr/bin/env bash
# Использование: ./scripts/restore.sh [каталог восстановленного проекта]   (по умолчанию <проект>/restore)
# Восстанавливает БД и файлы из ВНЕШНЕГО restic-репозитория в ОТДЕЛЬНЫЙ проект Compose с новыми томами
# (<каталог>/data/postgres, <каталог>/data/files); исходные тома не трогаются.
# Откуда берётся доступ к репозиторию:
#   - переменные RESTIC_REPOSITORY и RESTIC_PASSWORD из окружения (когда исходного проекта на VPS уже нет), либо
#   - configs/.env и secrets/credentials.txt исходного проекта.
# Исходный проект должен быть остановлен: cd configs && docker compose stop
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
need_cmd docker restic

if [ -z "${RESTIC_REPOSITORY:-}" ] || [ -z "${RESTIC_PASSWORD:-}" ]; then
    [ -f "$CONFIGS_DIR/.env" ] || die "нет $CONFIGS_DIR/.env: задайте RESTIC_REPOSITORY и RESTIC_PASSWORD переменными окружения"
    load_task_env
fi
restic_env

RESTORE_DIR="${1:-$PROJECT_DIR/restore}"
mkdir -p "$RESTORE_DIR"
RESTORE_DIR="$(cd "$RESTORE_DIR" && pwd)"
RESTORE_NAME="task03-restore"
TMP_RESTORE="$RESTORE_DIR/.restore-tmp"
START=$SECONDS

echo "[1/8] Проверяем, что исходный проект остановлен"
if [ -f "$CONFIGS_DIR/docker-compose.yml" ] && [ -n "$(cd "$CONFIGS_DIR" && docker compose ps -q --status running 2>/dev/null)" ]; then
    die "исходный проект запущен. Остановите его: cd configs && docker compose stop"
fi

echo "[2/8] Удаляем временный локальный дамп и каталог сборки копии"
rm -rf "$PROJECT_DIR/data/backup-tmp"
[ ! -e "$PROJECT_DIR/data/backup-tmp" ] && echo "  временных файлов копии на VPS нет"

echo "[3/8] Проверяем внешний репозиторий (restic check)"
restic snapshots --tag task03
restic check

echo "[4/8] Получаем последний снимок из внешнего хранилища"
rm -rf "$TMP_RESTORE"
mkdir -p "$TMP_RESTORE"
restic restore latest --tag task03 --host task03 --target "$TMP_RESTORE"
DUMP_FILE="$(find "$TMP_RESTORE" -name db.dump -type f | head -1)"
ENV_SRC="$(find "$TMP_RESTORE" -name env.sanitized -type f | head -1)"
FILES_SRC="$(find "$TMP_RESTORE" -type d -path '*/data/files' | head -1)"
[ -n "$DUMP_FILE" ] || die "дамп db.dump не найден в снимке"
[ -n "$ENV_SRC" ] || die "env.sanitized не найден в снимке"
[ -n "$FILES_SRC" ] || die "каталог data/files не найден в снимке"

echo "[5/8] Собираем новый проект $RESTORE_NAME в $RESTORE_DIR"
mkdir -p "$RESTORE_DIR"/{configs,data/postgres,data/files,secrets,evidence}
for F in docker-compose.yml Caddyfile 01-items.sql; do
    SRC="$(find "$TMP_RESTORE" -name "$F" -type f | head -1)"
    [ -n "$SRC" ] || die "в снимке нет $F"
    cp "$SRC" "$RESTORE_DIR/configs/$F"
done
cp -r "$FILES_SRC/." "$RESTORE_DIR/data/files/"
# .env из снимка (без пароля БД): имя проекта меняется, пароль БД создаётся новый
( umask 077; cp "$ENV_SRC" "$RESTORE_DIR/configs/.env" )
env_set "$RESTORE_DIR/configs/.env" COMPOSE_PROJECT_NAME "$RESTORE_NAME"
env_set "$RESTORE_DIR/configs/.env" POSTGRES_PASSWORD "$(cred_ensure "$RESTORE_DIR" POSTGRES_PASSWORD)"
load_env "$RESTORE_DIR/configs" POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD DOMAIN

echo "[6/8] Поднимаем PostgreSQL в новом проекте и восстанавливаем дамп"
cd "$RESTORE_DIR/configs"
docker compose up -d db
wait_db || die "PostgreSQL не поднялся (docker compose logs db)"
# --clean --if-exists: init-скрипт мог создать таблицу items на пустом томе, pg_restore пересоздаёт её из дампа
docker compose exec -T db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner < "$DUMP_FILE"

echo "[7/8] Запускаем Caddy: файлы снова отдаются по HTTPS"
docker compose up -d

echo "[8/8] Убираем временные файлы восстановления"
rm -rf "$TMP_RESTORE"

echo ""
echo "Восстановление завершено: проект $RESTORE_NAME, каталог $RESTORE_DIR, время $(( SECONDS - START )) с"
docker compose ps
echo "Проверка: $SCRIPT_DIR/check.sh $RESTORE_DIR"
