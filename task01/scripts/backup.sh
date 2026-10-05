#!/usr/bin/env bash
# Использование: ./scripts/backup.sh [каталог проекта]        (по умолчанию — каталог этого задания)
# Согласованная копия Gitea: остановка записи → дамп PostgreSQL → файлы Gitea → конфигурация → шифрование gpg.
# Результат: backups/backup-<время>.tar.gz.gpg. Пароль архива генерируется и сохраняется в
# secrets/credentials.txt (ключ BACKUP_PASSPHRASE[<имя архива>]); передаётся отдельно от архива.
# Переменная BACKUP_REMOTE=пользователь@хост:/путь — дополнительно скопировать архив вне VPS (scp).
set -euo pipefail

PROJECT_DIR="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../common/lib.sh"
need_cmd docker gpg openssl tar

load_env "$CONFIGS_DIR" POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD DOMAIN
CRED_FILE="$(secrets_init "$PROJECT_DIR")"

TIME_STAMP="$(date +%F_%H%M)"
BACKUP_DIR="$PROJECT_DIR/backup-tmp"
ARCHIVE_PATH="$PROJECT_DIR/backups/backup-${TIME_STAMP}.tar.gz"
mkdir -p "$PROJECT_DIR/backups"
umask 077

# Если скрипт упадёт между остановкой и запуском Gitea, сервис не должен остаться остановленным:
# при любом выходе (успех, ошибка, Ctrl+C) Gitea запускается снова, а временные файлы удаляются
SERVER_STOPPED=0
cleanup() {
    if [ "$SERVER_STOPPED" -eq 1 ]; then
        echo "Скрипт прерван: возвращаем Gitea в работу..." >&2
        (cd "$CONFIGS_DIR" && docker compose start server >/dev/null 2>&1) || true
    fi
    rm -rf "$BACKUP_DIR" "$ARCHIVE_PATH"
}
trap cleanup EXIT

START=$SECONDS
cd "$CONFIGS_DIR"
rm -rf "$BACKUP_DIR"; mkdir -p "$BACKUP_DIR"

echo "[1/7] Останавливаем запись в Gitea (PostgreSQL продолжает работать)"
docker compose stop server
SERVER_STOPPED=1

echo "[2/7] Снимаем согласованный дамп PostgreSQL"
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c > "$BACKUP_DIR/gitea_db.dump"

echo "[3/7] Архивируем файлы Gitea (репозитории, настройки, ключи)"
tar -czf "$BACKUP_DIR/gitea-data.tar.gz" -C "$PROJECT_DIR/data" gitea

echo "[4/7] Копируем конфигурацию (пароли заменяются на CHANGE_ME)"
sed -E 's/^(POSTGRES_PASSWORD)=.*/\1=CHANGE_ME/' .env > "$BACKUP_DIR/.env.example"
cp docker-compose.yml "$BACKUP_DIR/"

echo "[5/7] Возобновляем запись в Gitea"
docker compose start server
SERVER_STOPPED=0

echo "[6/7] Упаковываем и шифруем (gpg, AES256)"
tar -czf "$ARCHIVE_PATH" -C "$PROJECT_DIR" backup-tmp
BACKUP_PASSPHRASE="$(openssl rand -base64 24)"
printf '%s\n' "$BACKUP_PASSPHRASE" \
    | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 --cipher-algo AES256 -c "$ARCHIVE_PATH"
env_set "$CRED_FILE" "BACKUP_PASSPHRASE[$(basename "$ARCHIVE_PATH").gpg]" "$BACKUP_PASSPHRASE"
unset BACKUP_PASSPHRASE

echo "[7/7] Удаляем временные файлы"
rm -rf "$BACKUP_DIR" "$ARCHIVE_PATH"

if [ -n "${BACKUP_REMOTE:-}" ]; then
    echo "Копируем архив вне VPS: $BACKUP_REMOTE"
    scp "${ARCHIVE_PATH}.gpg" "$BACKUP_REMOTE"
fi

echo ""
echo "Защищённый архив: ${ARCHIVE_PATH}.gpg ($(du -h "${ARCHIVE_PATH}.gpg" | cut -f1))"
echo "Пароль архива:    $CRED_FILE (ключ BACKUP_PASSPHRASE[$(basename "$ARCHIVE_PATH").gpg])"
echo "Время копирования: $(( SECONDS - START )) с (Gitea была остановлена до шага 5)"
echo "Скопируйте архив на другой компьютер, а пароль передайте отдельным каналом."
