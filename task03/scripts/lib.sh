#!/usr/bin/env bash
# Общие функции скриптов task03. Подключается через source, сам не запускается.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
SECRETS_DIR="$PROJECT_DIR/secrets"
CRED_FILE="$SECRETS_DIR/credentials.txt"
EVIDENCE_DIR="$PROJECT_DIR/evidence"
FILES_DIR="$PROJECT_DIR/data/files"
BACKUP_LOG="$EVIDENCE_DIR/backup.log"
# shellcheck disable=SC1091
source "$PROJECT_DIR/../common/lib.sh"

# Строка пишется на экран и в журнал резервного копирования (с временем и часовым поясом)
log() {
    mkdir -p "$EVIDENCE_DIR"
    echo "$(stamp) $*" | tee -a "$BACKUP_LOG"
}

# Читает configs/.env и проверяет, что обязательные переменные заполнены
load_task_env() {
    load_env "${1:-$CONFIGS_DIR}" COMPOSE_PROJECT_NAME POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD DOMAIN RESTIC_REPOSITORY
}

# Значение из secrets/credentials.txt: cred RESTIC_PASSWORD
cred() {
    local v
    v="$(env_get "$CRED_FILE" "$1")"
    [ -n "$v" ] || { echo "В $CRED_FILE нет $1 (создаётся командой setup-secrets.sh)" >&2; return 1; }
    echo "$v"
}

# Переменные для restic. Если RESTIC_PASSWORD уже задан в окружении (например, неверный для проверки
# ошибки доступа), он не перезаписывается
restic_env() {
    need_cmd restic
    export RESTIC_REPOSITORY
    if [ -z "${RESTIC_PASSWORD:-}" ]; then
        RESTIC_PASSWORD="$(cred RESTIC_PASSWORD)" || exit 1
    fi
    export RESTIC_PASSWORD
}

# Ждёт готовности PostgreSQL в проекте, из каталога configs которого вызвана
wait_db() {
    wait_until 120 docker compose exec -T db pg_isready -U "$POSTGRES_USER" -d "$POSTGRES_DB"
}
