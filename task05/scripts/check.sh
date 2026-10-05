#!/usr/bin/env bash
# Использование: check.sh [push]
#   без аргумента — проверки только на чтение
#   push          — дополнительно коммит нового файла и push в demo
# Код возврата: 0 — всё прошло, 1 — есть провалы. Перед проверкой нужен prepare-demo.sh (эталон).
set -uo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

MODE="${1:-}"
if [ -n "$MODE" ] && [ "$MODE" != "push" ]; then
    echo "Использование: $0 [push]" >&2
    exit 2
fi
[ -f "$BASELINE_FILE" ] || { echo "Нет $BASELINE_FILE: сначала prepare-demo.sh" >&2; exit 1; }
# shellcheck disable=SC1090
source "$BASELINE_FILE"

USER_NAME="$(cred REVIEW_USER_USER)" || exit 1
USER_PASS="$(cred REVIEW_USER_PASSWORD)" || exit 1
git_auth_setup "$USER_NAME" "$USER_PASS"

FAILED=0
ok()   { echo "  OK    $*"; }
fail() { echo "  FAIL  $*"; FAILED=1; }
code() { curl -s -o /dev/null -w '%{http_code}' --max-time 10 "$@" || true; }

CURRENT_FAULT="нет"
[ -f "$FAULT_STATE" ] && CURRENT_FAULT="$(cat "$FAULT_STATE")"
echo "Проверка: $(stamp)    внесённый сбой: ${CURRENT_FAULT}"
echo ""

echo "[1/9] Контейнеры"
(cd "$CONFIGS_DIR" && docker compose ps)
RUNNING="$(cd "$CONFIGS_DIR" && docker compose ps --status running -q | wc -l)"
if [ "$RUNNING" -eq 3 ]; then ok "запущено 3 из 3"; else fail "запущено $RUNNING из 3"; fi

echo ""
echo "[2/9] HTTPS и редирект"
HTTPS_CODE="$(code "https://${DOMAIN}/")"
HTTPS_OK=0
if [ "$HTTPS_CODE" = "200" ]; then ok "https://${DOMAIN}/ -> 200"; HTTPS_OK=1; else fail "https://${DOMAIN}/ -> ${HTTPS_CODE} (ожидалось 200)"; fi
REDIR_CODE="$(code "http://${DOMAIN}/")"
case "$REDIR_CODE" in 301|302|307|308) ok "http -> редирект ${REDIR_CODE}" ;; *) fail "http -> ${REDIR_CODE} (ожидался редирект)" ;; esac

echo ""
echo "[3/9] Закрытый репозиторий недоступен без авторизации"
ANON_CODE="$(code "https://${DOMAIN}/api/v1/repos/${USER_NAME}/demo")"
case "$ANON_CODE" in 404|401|403) ok "анонимный API -> ${ANON_CODE}" ;; *) fail "анонимный API -> ${ANON_CODE} (ожидалось 404/401/403)" ;; esac
if [ "$HTTPS_OK" -eq 1 ]; then
    if env -u GIT_ASKPASS git ls-remote "https://${DOMAIN}/${USER_NAME}/demo.git" >/dev/null 2>&1; then
        fail "анонимный clone/ls-remote удался (должен быть отказ)"
    else
        ok "анонимный clone отклонён"
    fi
else
    echo "  --    анонимный clone не проверяется: HTTPS недоступен"
fi

echo ""
echo "[4/9] Вход пользователя ${USER_NAME}"
RESP="$(api GET /user)"
LOGIN_CODE="${RESP##*$'\n'}"
if [ "$LOGIN_CODE" = "200" ] && echo "${RESP%$'\n'*}" | grep -q "\"login\":\"${USER_NAME}\""; then
    ok "вход выполнен (API /user -> 200)"
else
    fail "вход не удался (HTTP ${LOGIN_CODE})"
fi

echo ""
echo "[5/9] Clone, исходный коммит и контрольная сумма check.txt"
mk_tmp_dir
WORK="$TMP_RESULT"
if git clone -q "https://${DOMAIN}/${USER_NAME}/demo.git" "$WORK/demo" 2>"$WORK/clone.err"; then
    ok "clone выполнен"
    if git -C "$WORK/demo" cat-file -e "${COMMIT_HASH}^{commit}" 2>/dev/null; then
        ok "исходный коммит в истории: ${COMMIT_HASH}"
    else
        fail "исходного коммита ${COMMIT_HASH} в истории нет"
    fi
    ACTUAL_SHA="$(git -C "$WORK/demo" show "${COMMIT_HASH}:check.txt" 2>/dev/null | sha256sum | cut -d' ' -f1)"
    if [ "$ACTUAL_SHA" = "$CHECK_SHA256" ]; then
        ok "SHA-256 check.txt совпадает: ${ACTUAL_SHA}"
    else
        fail "SHA-256 check.txt отличается: ${ACTUAL_SHA} (эталон ${CHECK_SHA256})"
    fi
else
    fail "clone не удался"
    head -3 "$WORK/clone.err" | sed 's/^/        /'
fi

echo ""
echo "[6/9] Новый push с отдельным файлом"
if [ "$MODE" = "push" ] && [ -d "$WORK/demo/.git" ]; then
    NEW_FILE="push-test-$(date +%Y%m%d-%H%M%S).txt"
    printf 'push check %s\n' "$(stamp)" > "$WORK/demo/$NEW_FILE"
    git -C "$WORK/demo" add "$NEW_FILE"
    git -C "$WORK/demo" -c user.name="$USER_NAME" -c user.email="${USER_NAME}@example.com" commit -q -m "Add $NEW_FILE"
    if git -C "$WORK/demo" push -q origin HEAD 2>"$WORK/push.err"; then
        ok "push выполнен: $NEW_FILE"
    else
        fail "push не удался"
        head -3 "$WORK/push.err" | sed 's/^/        /'
    fi
else
    echo "  --    пропущено (запуск без аргумента push или clone не удался)"
fi

echo ""
echo "[7/9] Эталонная конфигурация не менялась"
if (cd "$PROJECT_DIR" && sha256sum -c evidence/baseline-config.sha256 --quiet 2>/dev/null); then
    ok "docker-compose.yml и Caddyfile совпадают с эталоном"
else
    fail "эталонная конфигурация изменена"
fi

echo ""
echo "[8/9] Регистрация закрыта"
SIGNUP_CODE="$(code "https://${DOMAIN}/user/sign_up")"
SIGNUP_BODY="$(curl -s --max-time 10 "https://${DOMAIN}/user/sign_up" || true)"
# Gitea при закрытой регистрации либо отвечает 404, либо показывает страницу без формы (поля name="retype" нет)
if [ "$SIGNUP_CODE" = "404" ] || { [ "$SIGNUP_CODE" = "200" ] && ! echo "$SIGNUP_BODY" | grep -q 'name="retype"'; }; then
    ok "формы регистрации нет (HTTP ${SIGNUP_CODE})"
else
    fail "форма регистрации доступна (HTTP ${SIGNUP_CODE})"
fi

echo ""
echo "[9/9] Вход администратора review-admin"
ADMIN_NAME="$(cred REVIEW_ADMIN_USER)" || exit 1
ADMIN_PASS="$(cred REVIEW_ADMIN_PASSWORD)" || exit 1
RESP="$(GIT_USER="$ADMIN_NAME" GIT_PASS="$ADMIN_PASS" api GET /user)"
if [ "${RESP##*$'\n'}" = "200" ] && echo "${RESP%$'\n'*}" | grep -q '"is_admin":true'; then
    ok "${ADMIN_NAME} вошёл и является администратором"
else
    fail "вход ${ADMIN_NAME} не удался или нет прав администратора (HTTP ${RESP##*$'\n'})"
fi

echo ""
if [ "$FAILED" -eq 0 ]; then echo "ИТОГ: все проверки пройдены"; else echo "ИТОГ: есть провалы"; exit 1; fi