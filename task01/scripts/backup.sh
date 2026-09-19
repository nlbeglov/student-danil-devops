#!/usr/bin/env bash

# -e останавливает весь скрипт сразу если любая команда завершится с ошибкой
# -u остановит скрипт при отсутствии переменной 
# -o pipefail если при цепочке команд упала любая - упал весь конвеер
set -euo pipefail

PROJECT_DIR="${1:?Использование: backup.sh <project dir>}"

# заданем переменные
BACKUP_DIR="$PROJECT_DIR/backup-tmp"
SECRETS_DIR="$PROJECT_DIR/secrets"
SECRETS_FILE="$SECRETS_DIR/credentials.txt"
TIME_STAMP=$(date +%F_%H%M)
ARCHIVE_PATH="$PROJECT_DIR/backups/backup-${TIME_STAMP}.tar.gz"

# создаём все нужные папки заранее, до первого использования
mkdir -p "$BACKUP_DIR" "$SECRETS_DIR" "$(dirname "$ARCHIVE_PATH")"
# доступ только с рута
chmod 700 "$SECRETS_DIR"

cd "$PROJECT_DIR"
# подгружаем данные из .env для доступа к бд
source .env

# останавливаем только gitea для того чтобы дамп бд не менялся
echo "[1/7] Останавливаем запись в Gitea..."
docker compose stop server

echo "[2/7] Снимаем согласованный дамп PostgreSQL..."
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c > "$BACKUP_DIR/gitea_db.dump"

echo "[3/7] Архивируем файлы Gitea..."
tar -czf "$BACKUP_DIR/gitea-data.tar.gz" -C "$PROJECT_DIR" gitea

echo "[4/7] Копируем конфигурацию..."
sed -E 's/=.*/=CHANGE_ME/' .env > "$BACKUP_DIR/.env.example"
cp docker-compose.yml Caddyfile "$BACKUP_DIR/"

echo "[5/7] Возобновляем запись в Gitea..."
docker compose start server

echo "[6/7] Упаковываем финальный архив..."
tar -czf "$ARCHIVE_PATH" -C "$PROJECT_DIR" backup-tmp
# генерируем пароль 
BACKUP_PASSPHRASE=$(openssl rand -base64 24)
# паролим архив
echo "$BACKUP_PASSPHRASE" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 -c "$ARCHIVE_PATH"
# записываем пароль от бэкапа в credentials.txt
echo "Backup passphrase (${ARCHIVE_PATH}.gpg): $BACKUP_PASSPHRASE" >> "$SECRETS_FILE"
chmod 600 "$SECRETS_FILE"

echo "[7/7] Удаляем мусор..."
rm -f "$ARCHIVE_PATH"
rm -rf "$BACKUP_DIR"

echo ""
echo "Защищенный архив готов: ${ARCHIVE_PATH}.gpg"
echo "Пароль записан в: $SECRETS_FILE"