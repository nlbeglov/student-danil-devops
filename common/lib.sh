#!/usr/bin/env bash
# Общие функции скриптов всех заданий. Подключается через source, сам не запускается:
#   source "$(dirname "${BASH_SOURCE[0]}")/../../common/lib.sh"

COMMON_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$COMMON_DIR/.." && pwd)"

stamp() { date +%Y-%m-%dT%H:%M:%S%z; }

die() { echo "ОШИБКА: $*" >&2; exit 1; }

# need_cmd <команда>...: останавливает скрипт, если нужной программы нет
need_cmd() {
    local c
    for c in "$@"; do
        command -v "$c" >/dev/null 2>&1 || die "не найдена команда '$c' (установка: sudo $REPO_ROOT/common/prepare-vps.sh)"
    done
}

# 32 hex-символа = 128 бит случайности; только [0-9a-f], безопасно для командной строки, curl и веб-форм
gen_secret() { openssl rand -hex 16; }

# env_get <файл> <ключ>: значение KEY=VALUE из файла (пусто, если файла или ключа нет).
# Ключ сравнивается как строка, а не как регулярное выражение (ключи вида BACKUP_PASSPHRASE[имя] допустимы)
env_get() {
    [ -f "$1" ] || return 0
    KEY="$2" awk -F= 'BEGIN { k = ENVIRON["KEY"] } $1 == k { sub(/^[^=]*=/, ""); print; exit }' "$1"
}

# env_set <файл> <ключ> <значение>: заменяет или добавляет строку KEY=VALUE.
# Пишет во временный файл и переименовывает: при сбое не останется полупустого файла
env_set() {
    local file="$1" key="$2" value="$3" tmp
    [ -f "$file" ] || ( umask 077; : > "$file" )
    tmp="$(mktemp "${file}.XXXXXX")"
    KEY="$key" VAL="$value" awk -F= '
        BEGIN { k = ENVIRON["KEY"]; v = ENVIRON["VAL"] }
        $1 == k && !seen { print k "=" v; seen = 1; next }
        { print }
        END { if (!seen) print k "=" v }' "$file" > "$tmp"
    chmod 600 "$tmp"
    mv "$tmp" "$file"
}

# secrets_init <каталог задания>: создаёт secrets/ (доступ только владельцу), печатает путь к credentials.txt
secrets_init() {
    local dir="$1/secrets"
    ( umask 077; mkdir -p "$dir" )
    chmod 700 "$dir"
    echo "$dir/credentials.txt"
}

# cred_ensure <каталог задания> <ключ>: значение из secrets/credentials.txt; если его нет, создаёт случайное
cred_ensure() {
    local file val
    file="$(secrets_init "$1")"
    val="$(env_get "$file" "$2")"
    if [ -z "$val" ]; then
        val="$(gen_secret)"
        env_set "$file" "$2" "$val"
    fi
    echo "$val"
}

# setup_db_password <каталог задания>: пароль PostgreSQL создаётся один раз и хранится в двух местах:
# secrets/credentials.txt (для скриптов и передачи проверяющему) и configs/.env (его читает Compose).
# Приоритет: сохранённый в credentials.txt, затем уже заполненный в .env, иначе новый. Повторный запуск пароль не меняет.
setup_db_password() {
    local task_dir="$1" env="$1/configs/.env" creds saved current
    [ -f "$env" ] || die "нет $env: cp configs/.env.example configs/.env и заполните DOMAIN"
    need_cmd openssl
    creds="$(secrets_init "$task_dir")"
    saved="$(env_get "$creds" POSTGRES_PASSWORD)"
    current="$(env_get "$env" POSTGRES_PASSWORD)"
    if [ -z "$saved" ]; then
        if [ -n "$current" ] && [[ "$current" != *CHANGE_ME* ]]; then saved="$current"; else saved="$(gen_secret)"; fi
        env_set "$creds" POSTGRES_PASSWORD "$saved"
    fi
    env_set "$env" POSTGRES_PASSWORD "$saved"
}

# load_env <каталог configs> [обязательные переменные...]: экспортирует переменные из configs/.env и проверяет их
load_env() {
    local env="$1/.env" v
    shift
    [ -f "$env" ] || die "нет $env (cp configs/.env.example configs/.env и заполните значения)"
    set -a
    # shellcheck disable=SC1090
    source "$env"
    set +a
    for v in "$@"; do
        [ -n "${!v:-}" ] && [[ "${!v}" != *CHANGE_ME* ]] || die "в $env не заполнена переменная $v"
    done
}

# wait_until <секунд> <команда...>: повторяет команду раз в 2 секунды, пока она не вернёт 0
wait_until() {
    local limit="$1" i
    shift
    for i in $(seq 1 $(( limit / 2 )) ); do
        "$@" >/dev/null 2>&1 && return 0
        sleep 2
    done
    return 1
}

# http_code <curl-аргументы...>: печатает только HTTP-код ответа (000 — ответа нет)
http_code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; }

# Для check.sh: счётчики OK/FAIL/WARN и итог с кодом возврата
CHECK_FAILED=0
ok()   { echo "  OK    $*"; }
warn() { echo "  WARN  $*"; }
fail() { echo "  FAIL  $*"; CHECK_FAILED=1; }
check_summary() {
    echo ""
    if [ "$CHECK_FAILED" -eq 0 ]; then echo "ИТОГ: все проверки пройдены"; return 0; fi
    echo "ИТОГ: есть провалы"
    return 1
}
