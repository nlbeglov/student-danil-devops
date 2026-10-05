#!/usr/bin/env bash
# Использование: setup-secrets.sh
# Запускать ДО первого запуска стека (пароль PostgreSQL применяется при инициализации базы).
# Создаёт пароли, показывает и сохраняет в secrets/credentials.txt, пароль БД пишет в configs/.env.
# Идемпотентен: существующие пароли не меняются.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

ENV_FILE="$CONFIGS_DIR/.env"
[ -f "$ENV_FILE" ] || { echo "Нет $ENV_FILE: скопируй из .env.example и заполни" >&2; exit 1; }
# shellcheck disable=SC1091
source "$ENV_FILE"
: "${DOMAIN:?}"
[ "$DOMAIN" != "CHANGE_ME" ] || { echo "DOMAIN в .env всё ещё CHANGE_ME" >&2; exit 1; }
command -v openssl >/dev/null || { echo "Нужен openssl (apt-get install -y openssl)" >&2; exit 1; }

# Всё, что создаём, доступно только владельцу
umask 077
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# 32 hex-символа = 128 бит случайности; только [0-9a-f], безопасно для командной строки и curl
gen() { openssl rand -hex 16; }
saved() { [ -f "$CRED_FILE" ] && grep -m1 "^$1=" "$CRED_FILE" | cut -d= -f2- || true; }
keep_or_gen() { local v; v="$(saved "$1")"; [ -n "$v" ] && echo "$v" || gen; }

# PostgreSQL: приоритет — сохранённый пароль, затем значение из .env, затем новое
PG_PASSWORD="$(saved POSTGRES_PASSWORD)"
if [ -z "$PG_PASSWORD" ] && [ -n "${POSTGRES_PASSWORD:-}" ] && [ "$POSTGRES_PASSWORD" != "CHANGE_ME" ]; then
    PG_PASSWORD="$POSTGRES_PASSWORD"
fi
[ -n "$PG_PASSWORD" ] || PG_PASSWORD="$(gen)"
REVIEW_ADMIN_PASSWORD="$(keep_or_gen REVIEW_ADMIN_PASSWORD)"
REVIEW_USER_PASSWORD="$(keep_or_gen REVIEW_USER_PASSWORD)"

echo "[1/2] Записываем POSTGRES_PASSWORD в $ENV_FILE"
if grep -q '^POSTGRES_PASSWORD=' "$ENV_FILE"; then
    sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${PG_PASSWORD}|" "$ENV_FILE"
else
    echo "POSTGRES_PASSWORD=${PG_PASSWORD}" >> "$ENV_FILE"
fi

echo "[2/2] Сохраняем пароли в $CRED_FILE"
# Пишем во временный файл и переименовываем: при сбое не останется полупустого файла
TMP="$(mktemp "$SECRETS_DIR/.credentials.XXXXXX")"
cat > "$TMP" <<EOF
# Учётные данные task05. Создано/обновлено: $(stamp)
# Файл секретный: не коммитить, не класть в архив, передавать отдельно.

GITEA_URL=https://${DOMAIN}
POSTGRES_PASSWORD=${PG_PASSWORD}

REVIEW_ADMIN_USER=review-admin
REVIEW_ADMIN_PASSWORD=${REVIEW_ADMIN_PASSWORD}
REVIEW_USER_USER=review-user
REVIEW_USER_PASSWORD=${REVIEW_USER_PASSWORD}
EOF
chmod 600 "$TMP"
mv "$TMP" "$CRED_FILE"

echo ""
echo "===================== ПАРОЛИ (сохранены в $CRED_FILE) ====================="
grep -v '^#' "$CRED_FILE"
echo "==========================================================================="