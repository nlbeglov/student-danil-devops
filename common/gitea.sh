#!/usr/bin/env bash
# Функции работы с Gitea для заданий 01 и 05. Подключается через source после common/lib.sh.
# Перед использованием должны быть заданы CONFIGS_DIR (каталог с docker-compose.yml) и DOMAIN.

# Временные файлы и каталоги удаляются при выходе из скрипта.
# Результат функции кладётся в TMP_RESULT, а не в stdout: в $(...) массив не обновился бы.
TMP_PATHS=()
trap 'rm -rf ${TMP_PATHS[@]+"${TMP_PATHS[@]}"}' EXIT
mk_tmp_dir()  { TMP_RESULT="$(mktemp -d)"; TMP_PATHS+=("$TMP_RESULT"); }
mk_tmp_file() { TMP_RESULT="$(mktemp)";    TMP_PATHS+=("$TMP_RESULT"); }

# gitea_cli <аргументы gitea>: команда gitea внутри контейнера server от пользователя git
gitea_cli() { (cd "$CONFIGS_DIR" && docker compose exec -T -u git server gitea "$@"); }

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

# Учётные данные для git и API: git_auth_setup <пользователь> <пароль>
# Пароль не попадает ни в URL, ни в аргументы процессов: git берёт его через GIT_ASKPASS из окружения
git_auth_setup() {
    GIT_USER="$1"; GIT_PASS="$2"
    mk_tmp_file
    cat > "$TMP_RESULT" <<'ASKPASS'
#!/bin/sh
case "$1" in
    Username*) printf '%s\n' "$GIT_USER" ;;
    *)         printf '%s\n' "$GIT_PASS" ;;
esac
ASKPASS
    chmod 700 "$TMP_RESULT"
    export GIT_ASKPASS="$TMP_RESULT" GIT_USER GIT_PASS GIT_TERMINAL_PROMPT=0
    # системные credential helper'ы отключены: иначе сохранённые данные искажают проверку анонимного доступа
    export GIT_CONFIG_COUNT=1 GIT_CONFIG_KEY_0=credential.helper GIT_CONFIG_VALUE_0=
}

# Запрос к API Gitea: gitea_api <метод> <путь> [json]
# Печатает тело ответа, а в последней строке HTTP-код. Пароль передаётся curl через stdin (-K -), не через аргументы
gitea_api() {
    local method="$1" path="$2" data="${3:-}"
    local args=(-sS --max-time 20 -K - -X "$method" -H 'Content-Type: application/json' -w $'\n%{http_code}')
    [ -n "$data" ] && args+=(-d "$data")
    printf 'user = "%s:%s"\n' "$GIT_USER" "$GIT_PASS" \
        | curl "${args[@]}" "https://${DOMAIN}/api/v1${path}"
}

# ensure_gitea_user <имя> <пароль> [доп. флаги gitea]: создаёт пользователя, если его ещё нет
ensure_gitea_user() {
    local name="$1" pass="$2"
    shift 2
    if gitea_cli admin user list | awk 'NR>1 {print $2}' | grep -qx "$name"; then
        echo "  пользователь $name уже есть"
    else
        gitea_cli admin user create --username "$name" --password "$pass" \
            --email "${name}@example.com" --must-change-password=false "$@"
    fi
}
