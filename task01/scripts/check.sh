#!/usr/bin/env bash
# Использование: ./scripts/check.sh [каталог проекта] [input|files]
#   каталог проекта — по умолчанию каталог этого задания; для восстановленной копии укажите её каталог
#   input — пароль review-user вводится с клавиатуры; files (по умолчанию) — берётся из secrets/credentials.txt проекта
# Переменные: CHECK_USER (по умолчанию review-user), EXPECTED_HASH (иначе берётся из evidence/baseline.txt),
#             CREDENTIALS_FILE (иначе <проект>/secrets/credentials.txt).
# Код возврата: 0 — всё прошло, 1 — есть провалы.
set -uo pipefail

PROJECT_DIR="$(cd "${1:-$(dirname "${BASH_SOURCE[0]}")/..}" && pwd)"
SECRET_MODE="${2:-files}"
CONFIGS_DIR="$PROJECT_DIR/configs"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../common/lib.sh"
# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/../../common/gitea.sh"

case "$SECRET_MODE" in input|files) ;; *) die "режим '$SECRET_MODE' недопустим (ожидается input или files)" ;; esac
load_env "$CONFIGS_DIR" DOMAIN
USERNAME="${CHECK_USER:-review-user}"
CREDENTIALS_FILE="${CREDENTIALS_FILE:-$PROJECT_DIR/secrets/credentials.txt}"

echo "Проверка: $(stamp)   проект: ${COMPOSE_PROJECT_NAME:-?}   домен: $DOMAIN"

echo ""
echo "[1/6] Контейнеры"
(cd "$CONFIGS_DIR" && docker compose ps)
RUNNING="$(cd "$CONFIGS_DIR" && docker compose ps --status running -q | wc -l | tr -d ' ')"
if [ "$RUNNING" -eq 2 ]; then ok "запущено 2 из 2 (server, db); HTTPS обслуживает общий Caddy"; else fail "запущено $RUNNING из 2"; fi

echo ""
echo "[2/6] Автозапуск после загрузки VPS"
BOOT_EPOCH="$(date -d "$(uptime -s)" +%s 2>/dev/null || echo 0)"
echo "  Система загрузилась: $(uptime -s 2>/dev/null || echo неизвестно)"
for CONTAINER in $(cd "$CONFIGS_DIR" && docker compose ps -q); do
    NAME="$(docker inspect --format='{{.Name}}' "$CONTAINER" | sed 's|^/||')"
    STARTED="$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER")"
    STARTED_EPOCH="$(date -d "$STARTED" +%s 2>/dev/null || echo 0)"
    echo "  $NAME запущен: $STARTED"
    if [ "$BOOT_EPOCH" -gt 0 ] && [ "$STARTED_EPOCH" -gt 0 ]; then
        DELTA=$(( STARTED_EPOCH - BOOT_EPOCH ))
        # контейнер, запущенный вручную позже, не доказывает автозапуск: показываем разницу и не считаем это провалом
        if [ "$DELTA" -ge 0 ] && [ "$DELTA" -le 300 ]; then ok "$NAME стартовал через ${DELTA} с после загрузки"
        else warn "$NAME стартовал через ${DELTA} с после загрузки (не после перезагрузки, либо запуск вручную)"; fi
    fi
done

echo ""
echo "[3/6] Данные физически на месте"
for D in gitea postgres; do
    if [ -n "$(ls -A "$PROJECT_DIR/data/$D" 2>/dev/null)" ]; then ok "data/$D: $(du -sh "$PROJECT_DIR/data/$D" | cut -f1)"; else fail "data/$D пуст или не найден"; fi
done

echo ""
echo "[4/6] HTTPS и редирект (общий Caddy), закрытые порты, регистрация"
CODE="$(http_code "https://${DOMAIN}/")"
[ "$CODE" = "200" ] && ok "https://${DOMAIN} -> 200" || fail "https://${DOMAIN} -> $CODE (ожидалось 200)"
CODE="$(http_code "http://${DOMAIN}/")"
case "$CODE" in 301|302|307|308) ok "http -> редирект $CODE" ;; *) fail "http -> $CODE (ожидался редирект на HTTPS)" ;; esac
for PORT in 3000 5432; do
    if [ -z "$(cd "$CONFIGS_DIR" && docker compose ps --format '{{.Ports}}' | grep -E "0\.0\.0\.0:${PORT}->|:::${PORT}->")" ]; then
        ok "порт $PORT не опубликован наружу"
    else fail "порт $PORT опубликован наружу"; fi
done
SIGNUP_BODY="$(curl -s --max-time 10 "https://${DOMAIN}/user/sign_up" || true)"
if echo "$SIGNUP_BODY" | grep -q 'name="retype"'; then fail "форма регистрации доступна"; else ok "открытой регистрации нет"; fi

echo ""
echo "[5/6] Приватный репозиторий недоступен анонимно (ожидается 404)"
CODE="$(http_code "https://${DOMAIN}/review-user/demo")"
[ "$CODE" = "404" ] && ok "анонимный запрос к review-user/demo -> 404" || fail "анонимный запрос -> $CODE (ожидалось 404)"

echo ""
echo "[6/6] Вход ${USERNAME}, clone и hash последнего коммита"
if [ "$SECRET_MODE" = "input" ]; then
    read -rsp "Пароль для $USERNAME: " PASSWORD; echo
else
    KEY="$(printf '%s' "$USERNAME" | tr 'a-z.-' 'A-Z__')_PASSWORD"
    PASSWORD="$(env_get "$CREDENTIALS_FILE" "$KEY")"
    [ -n "$PASSWORD" ] || die "в $CREDENTIALS_FILE нет $KEY (или используйте режим input)"
fi
git_auth_setup "$USERNAME" "$PASSWORD"
unset PASSWORD
RESP="$(gitea_api GET /user)"
if [ "${RESP##*$'\n'}" = "200" ]; then ok "вход выполнен: $USERNAME"; else fail "вход не удался (HTTP ${RESP##*$'\n'})"; fi

EXPECTED="${EXPECTED_HASH:-$(env_get "$PROJECT_DIR/evidence/baseline.txt" COMMIT_HASH)}"
mk_tmp_dir
if git clone -q "https://${DOMAIN}/review-user/demo.git" "$TMP_RESULT/demo" 2>/dev/null; then
    ok "clone выполнен"
    COMMITS="$(git -C "$TMP_RESULT/demo" rev-list --count HEAD)"
    ACTUAL="$(git -C "$TMP_RESULT/demo" rev-parse HEAD)"
    echo "  Коммитов: $COMMITS, hash последнего: $ACTUAL"
    [ "$COMMITS" -ge 2 ] && ok "в истории не меньше двух коммитов" || fail "в истории меньше двух коммитов"
    if [ -z "$EXPECTED" ]; then warn "исходный hash неизвестен: задайте EXPECTED_HASH или создайте evidence/baseline.txt"
    elif git -C "$TMP_RESULT/demo" cat-file -e "${EXPECTED}^{commit}" 2>/dev/null; then ok "исходный коммит $EXPECTED есть в истории"
    else fail "исходного коммита $EXPECTED в истории нет"; fi
    [ "$(git -C "$TMP_RESULT/demo" show HEAD:check.txt 2>/dev/null)" = "gitea-test-v1" ] \
        && ok "check.txt содержит gitea-test-v1" || warn "check.txt в последнем коммите изменён (после новых коммитов это нормально)"
else
    fail "clone не удался"
fi

check_summary
