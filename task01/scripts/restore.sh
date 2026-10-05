#!/usr/bin/env bash
# Использование: ./scripts/restore.sh <имя проекта> <новый каталог> <архив.tar.gz.gpg> <input|files>
#   имя проекта   — имя нового Compose-проекта (например task01-restore); тома и контейнеры новые
#   новый каталог — куда собрать восстановленный проект (configs/, data/); исходный проект не трогается
#   архив         — файл backups/backup-<время>.tar.gz.gpg, созданный backup.sh
#   input|files   — способ передачи секретов:
#       input — пароль архива и значения .env вводятся с клавиатуры
#       files — пароль берётся из credentials.txt, готовый .env — из файла
#               (по умолчанию secrets/credentials.txt и configs/.env этого проекта; иначе CREDENTIALS_FILE=... ENV_FILE=...; ASSUME_YES=1 — без вопроса подтверждения)
# Исходный проект должен быть остановлен (порты 80/443 свободны): cd configs && docker compose stop
set -euo pipefail

PROJECT_NAME="${1:?Использование: restore.sh <имя проекта> <новый каталог> <архив.tar.gz.gpg> <input|files>}"
PROJECT_DIR="${2:?Укажите новый каталог проекта}"
INPUT_ARCHIVE="${3:?Укажите архив}"
SECRET_MODE="${4:?Укажите способ передачи секретов: input или files}"

if [ "$SECRET_MODE" != "input" ] && [ "$SECRET_MODE" != "files" ]; then
    echo "Недопустимое значение режима: '$SECRET_MODE' (ожидается 'input' или 'files')" >&2
    exit 1
fi
[ -f "$INPUT_ARCHIVE" ] || { echo "Архив не найден: $INPUT_ARCHIVE" >&2; exit 1; }
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../common/lib.sh"
need_cmd docker gpg tar

SOURCE_PROJECT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
mkdir -p "$PROJECT_DIR"
PROJECT_DIR="$(cd "$PROJECT_DIR" && pwd)"
INPUT_ARCHIVE="$(cd "$(dirname "$INPUT_ARCHIVE")" && pwd)/$(basename "$INPUT_ARCHIVE")"

echo "Подтверждение данных"
echo "  Проект Compose:    $PROJECT_NAME"
echo "  Новый каталог:     $PROJECT_DIR"
echo "  Входной архив:     $INPUT_ARCHIVE"
echo "  Передача секретов: $SECRET_MODE"
echo ""
if [ "${ASSUME_YES:-}" != "1" ]; then
    read -rp "Исходный проект остановлен (порты 80/443 свободны)? Данные верны? [y/N] " CONFIRM
    [ "$CONFIRM" = "y" ] || { echo "Отменено."; exit 1; }
fi

START=$SECONDS
TEMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TEMP_DIR"' EXIT
umask 077

echo "[1/7] Получаем пароль архива"
if [ "$SECRET_MODE" = "input" ]; then
    read -rsp "Пароль для расшифровки архива: " ARCHIVE_PASSPHRASE
    echo
else
    # по умолчанию — secrets/credentials.txt проекта, из которого запущен скрипт
    CREDENTIALS_FILE="${CREDENTIALS_FILE:-$SOURCE_PROJECT/secrets/credentials.txt}"
    [ -f "$CREDENTIALS_FILE" ] || read -rp "Путь к файлу с секретами (credentials.txt): " CREDENTIALS_FILE
    echo "  секреты: $CREDENTIALS_FILE"
    [ -f "$CREDENTIALS_FILE" ] || { echo "Файл $CREDENTIALS_FILE не найден" >&2; exit 1; }
    KEY="BACKUP_PASSPHRASE[$(basename "$INPUT_ARCHIVE")]"
    ARCHIVE_PASSPHRASE="$(env_get "$CREDENTIALS_FILE" "$KEY")"
    [ -n "$ARCHIVE_PASSPHRASE" ] || { echo "В $CREDENTIALS_FILE нет строки $KEY=..." >&2; exit 1; }
fi

echo "[2/7] Расшифровываем и распаковываем архив"
printf '%s\n' "$ARCHIVE_PASSPHRASE" \
    | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -d "$INPUT_ARCHIVE" > "$TEMP_DIR/backup.tar.gz"
unset ARCHIVE_PASSPHRASE
tar -xzf "$TEMP_DIR/backup.tar.gz" -C "$TEMP_DIR"
BACKUP_DATA="$TEMP_DIR/backup-tmp"

echo "[3/7] Собираем новый проект: configs/ и новые каталоги данных"
mkdir -p "$PROJECT_DIR/configs" "$PROJECT_DIR/data/gitea" "$PROJECT_DIR/data/postgres"
cp "$BACKUP_DATA/docker-compose.yml" "$BACKUP_DATA/Caddyfile" "$BACKUP_DATA/.env.example" "$PROJECT_DIR/configs/"
ENV_NEW="$PROJECT_DIR/configs/.env"

echo "[4/7] Настройки .env"
if [ "$SECRET_MODE" = "files" ]; then
    ENV_FILE="${ENV_FILE:-$SOURCE_PROJECT/configs/.env}"
    [ -f "$ENV_FILE" ] || read -rp "Путь к готовому .env: " ENV_FILE
    echo "  готовый .env: $ENV_FILE"
    [ -f "$ENV_FILE" ] || { echo "Файл $ENV_FILE не найден" >&2; exit 1; }
    cp "$ENV_FILE" "$ENV_NEW"
else
    : > "$ENV_NEW"
    echo "Введите значения (Enter — оставить значение из скобок):"
    while IFS='=' read -r KEY DEFAULT <&3 || [ -n "$KEY" ]; do
        case "$KEY" in ''|\#*) continue ;; esac
        case "$KEY" in
            COMPOSE_PROJECT_NAME) VALUE="$PROJECT_NAME" ;;
            *PASSWORD*) read -rsp "  $KEY: " VALUE; echo ;;
            *) if [[ "$DEFAULT" == *CHANGE_ME* ]]; then read -rp "  $KEY: " VALUE
               else read -rp "  $KEY [$DEFAULT]: " VALUE; VALUE="${VALUE:-$DEFAULT}"; fi ;;
        esac
        printf '%s=%s\n' "$KEY" "$VALUE" >> "$ENV_NEW"
    done 3< "$BACKUP_DATA/.env.example"
fi
# имя проекта фиксируется в .env: тома и контейнеры получают новые имена
env_set "$ENV_NEW" COMPOSE_PROJECT_NAME "$PROJECT_NAME"
chmod 600 "$ENV_NEW"
load_env "$PROJECT_DIR/configs" POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD DOMAIN

echo "[5/7] Поднимаем только PostgreSQL и восстанавливаем дамп"
cd "$PROJECT_DIR/configs"
docker compose up -d db
wait_until 120 docker compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    || die "PostgreSQL не поднялся (docker compose logs db)"
docker compose exec -T db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner < "$BACKUP_DATA/gitea_db.dump"

echo "[6/7] Распаковываем файлы Gitea в новый каталог данных"
tar -xzf "$BACKUP_DATA/gitea-data.tar.gz" -C "$PROJECT_DIR/data"

echo "[7/7] Запускаем Gitea и Caddy"
docker compose up -d server caddy
docker compose ps

echo ""
echo "Восстановление завершено: проект $PROJECT_NAME, каталог $PROJECT_DIR, время $(( SECONDS - START )) с"
echo "Проверка: ./scripts/check.sh $PROJECT_DIR files"
echo "Доступ: https://${DOMAIN} (или SSH-туннель на порт 3000 контейнера server)"
