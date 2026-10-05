#!/usr/bin/env bash
# Использование: setup-secrets.sh [топик]      (по умолчанию monitor-alerts)
# Запускать на VPS-B после deploy-monitor.sh (ntfy должен быть запущен).
# Создаёт пароли, применяет их пользователям ntfy, показывает и сохраняет в
# secrets/credentials.txt. Идемпотентен: существующие пароли не меняются.
set -euo pipefail

TOPIC="${1:-monitor-alerts}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
SECRETS_DIR="$PROJECT_DIR/secrets"
CRED_FILE="$SECRETS_DIR/credentials.txt"
cd "$CONFIGS_DIR"

[ -f .env ] || { echo "Нет $CONFIGS_DIR/.env" >&2; exit 1; }
# shellcheck disable=SC1091
source .env
: "${KUMA_DOMAIN:?}" "${NTFY_DOMAIN:?}"

command -v openssl >/dev/null || { echo "Нужен openssl (apt-get install -y openssl)" >&2; exit 1; }
docker compose exec -T ntfy true 2>/dev/null \
    || { echo "Контейнер ntfy не запущен: сначала deploy-monitor.sh" >&2; exit 1; }

# Всё, что создаём, доступно только владельцу
umask 077
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"

# 32 hex-символа = 128 бит случайности; только [0-9a-f], поэтому безопасно
# для командной строки, curl и копирования в веб-формы
gen() { openssl rand -hex 16; }

# Значение из существующего файла (пусто, если файла или ключа нет)
saved() { [ -f "$CRED_FILE" ] && grep -m1 "^$1=" "$CRED_FILE" | cut -d= -f2- || true; }

# Старое значение, а если его нет, новое
keep_or_gen() { local v; v="$(saved "$1")"; [ -n "$v" ] && echo "$v" || gen; }

KUMA_ADMIN_PASSWORD="$(keep_or_gen KUMA_ADMIN_PASSWORD)"
NTFY_ADMIN_PASSWORD="$(keep_or_gen NTFY_ADMIN_PASSWORD)"
NTFY_READER_PASSWORD="$(keep_or_gen NTFY_READER_PASSWORD)"
NTFY_KUMA_PASSWORD="$(keep_or_gen NTFY_KUMA_PASSWORD)"

echo "[1/3] Сохраняем пароли в $CRED_FILE"
# Пишем во временный файл и переименовываем: при сбое не останется полупустого файла
TMP="$(mktemp "$SECRETS_DIR/.credentials.XXXXXX")"
cat > "$TMP" <<EOF
# Учётные данные. Создано/обновлено: $(date +%Y-%m-%dT%H:%M:%S%z)

KUMA_URL=https://${KUMA_DOMAIN}
KUMA_ADMIN_USER=admin
KUMA_ADMIN_PASSWORD=${KUMA_ADMIN_PASSWORD}

NTFY_URL=https://${NTFY_DOMAIN}
NTFY_TOPIC=${TOPIC}
NTFY_ADMIN_USER=admin
NTFY_ADMIN_PASSWORD=${NTFY_ADMIN_PASSWORD}
NTFY_READER_USER=reader
NTFY_READER_PASSWORD=${NTFY_READER_PASSWORD}
NTFY_KUMA_USER=kuma
NTFY_KUMA_PASSWORD=${NTFY_KUMA_PASSWORD}
EOF
chmod 600 "$TMP"
mv "$TMP" "$CRED_FILE"

ntfy_cli() { docker compose exec -T ntfy ntfy "$@"; }
user_exists() { ntfy_cli user list 2>/dev/null | grep -q "user $1 "; }

# Пароль передаётся через переменную окружения NTFY_PASSWORD (`-e NTFY_PASSWORD`
# без значения берёт её из текущего окружения), поэтому в аргументы процесса он не попадает
apply_user() {
    local name="$1" role="$2" pw="$3"
    export NTFY_PASSWORD="$pw"
    if user_exists "$name"; then
        docker compose exec -T -e NTFY_PASSWORD ntfy ntfy user change-pass "$name"
    else
        docker compose exec -T -e NTFY_PASSWORD ntfy ntfy user add --role="$role" "$name"
    fi
    unset NTFY_PASSWORD
}

echo "[2/3] Применяем пароли к пользователям ntfy"
apply_user admin  admin "$NTFY_ADMIN_PASSWORD"
apply_user reader user  "$NTFY_READER_PASSWORD"
apply_user kuma   user  "$NTFY_KUMA_PASSWORD"

echo "[3/3] Права на топик '$TOPIC'"
ntfy_cli access reader "$TOPIC" read-only
ntfy_cli access kuma   "$TOPIC" write-only
ntfy_cli access

echo ""
echo "===================== ПАРОЛИ (сохранены в $CRED_FILE) ====================="
grep -v '^#' "$CRED_FILE"
echo "==========================================================================="
echo "Пароль Kuma применяется вручную: создай администратора в $KUMA_DOMAIN с этими данными."