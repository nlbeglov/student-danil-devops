#!/usr/bin/env bash
# Общие функции скриптов task05. Подключается через source, сам не запускается.

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
SECRETS_DIR="$PROJECT_DIR/secrets"
CRED_FILE="$SECRETS_DIR/credentials.txt"
EVIDENCE_DIR="$PROJECT_DIR/evidence"
BASELINE_FILE="$EVIDENCE_DIR/baseline.txt"
FAULT_STATE="$PROJECT_DIR/data/fault.current"
EVENT_LOG="$EVIDENCE_DIR/faults.log"

stamp() { date +%Y-%m-%dT%H:%M:%S%z; }

# Событие пишется в журнал с временем и часовым поясом (нужно для «времени диагностики»)
log_event() {
    mkdir -p "$EVIDENCE_DIR"
    echo "$(stamp) $*" | tee -a "$EVENT_LOG"
}

# Читает configs/.env и проверяет, что обязательные переменные заполнены
load_env() {
    [ -f "$CONFIGS_DIR/.env" ] || { echo "Нет $CONFIGS_DIR/.env: скопируй из .env.example и заполни" >&2; exit 1; }
    # shellcheck disable=SC1091
    source "$CONFIGS_DIR/.env"
    local v
    for v in COMPOSE_PROJECT_NAME POSTGRES_USER POSTGRES_DB POSTGRES_PASSWORD DOMAIN; do
        [ -n "${!v:-}" ] && [ "${!v}" != "CHANGE_ME" ] \
            || { echo "В $CONFIGS_DIR/.env не заполнена переменная $v" >&2; exit 1; }
    done
}

# Значение из secrets/credentials.txt: cred REVIEW_USER_PASSWORD
cred() {
    [ -f "$CRED_FILE" ] || { echo "Нет $CRED_FILE: сначала setup-secrets.sh" >&2; return 1; }
    local v
    v="$(grep -m1 "^$1=" "$CRED_FILE" | cut -d= -f2-)"
    [ -n "$v" ] || { echo "В $CRED_FILE нет $1" >&2; return 1; }
    echo "$v"
}

# Временные файлы и каталоги удаляются при выходе из скрипта.
# Результат функции кладётся в TMP_RESULT, а не в stdout: в $(...) массив не обновился бы.
TMP_PATHS=()
trap 'rm -rf ${TMP_PATHS[@]+"${TMP_PATHS[@]}"}' EXIT
mk_tmp_dir()  { TMP_RESULT="$(mktemp -d)"; TMP_PATHS+=("$TMP_RESULT"); }
mk_tmp_file() { TMP_RESULT="$(mktemp)";    TMP_PATHS+=("$TMP_RESULT"); }

# Учётные данные для git и API: git_auth_setup <пользователь> <пароль>
# Пароль не попадает ни в URL, ни в аргументы процессов: git берёт его через GIT_ASKPASS из окружения
git_auth_setup() {
    GIT_USER="$1"; GIT_PASS="$2"
    mk_tmp_file
    cat > "$TMP_RESULT" <<'EOF'
#!/bin/sh
case "$1" in
    Username*) printf '%s\n' "$GIT_USER" ;;
    *)         printf '%s\n' "$GIT_PASS" ;;
esac
EOF
    chmod 700 "$TMP_RESULT"
    export GIT_ASKPASS="$TMP_RESULT" GIT_USER GIT_PASS GIT_TERMINAL_PROMPT=0
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=

}

# Запрос к API Gitea: api <метод> <путь> [json]
# Печатает тело ответа, а в последней строке HTTP-код. Пароль передаётся curl через stdin (-K -), не через аргументы
api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-sS --max-time 20 -K - -X "$method" -H 'Content-Type: application/json' -w $'\n%{http_code}')
    [ -n "$data" ] && args+=(-d "$data")
    printf 'user = "%s:%s"\n' "$GIT_USER" "$GIT_PASS" \
        | curl "${args[@]}" "https://${DOMAIN}/api/v1${path}"
}

# Ждёт, пока Gitea внутри контейнера ответит на healthz (до 2 минут); от Caddy и DNS не зависит
wait_gitea() {
    local i
    for i in $(seq 1 60); do
        if (cd "$CONFIGS_DIR" && docker compose exec -T server curl -fsS http://localhost:3000/api/healthz >/dev/null 2>&1); then
            return 0
        fi
        sleep 2
    done
    return 1
}