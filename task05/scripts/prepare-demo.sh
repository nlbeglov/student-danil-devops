#!/usr/bin/env bash
# Использование: prepare-demo.sh
# Запускать после deploy.sh. Создаёт пользователей, закрытый репозиторий demo с двумя коммитами
# и фиксирует эталон (hash коммита, SHA-256 check.txt, хэши конфигурации) в evidence/.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

ADMIN_USER="$(cred REVIEW_ADMIN_USER)"
ADMIN_PASS="$(cred REVIEW_ADMIN_PASSWORD)"
USER_NAME="$(cred REVIEW_USER_USER)"
USER_PASS="$(cred REVIEW_USER_PASSWORD)"

echo "[1/5] Ждём Gitea"
wait_gitea || { echo "Gitea не отвечает" >&2; exit 1; }

gitea_cli() { (cd "$CONFIGS_DIR" && docker compose exec -T -u git server gitea "$@"); }

# ensure_user <имя> <пароль> [доп. флаги]: создаёт пользователя, если его ещё нет
ensure_user() {
    local name="$1" pass="$2"
    shift 2
    if gitea_cli admin user list | grep -qw "$name"; then
        echo "  пользователь $name уже есть"
    else
        gitea_cli admin user create --username "$name" --password "$pass" \
            --email "${name}@example.com" --must-change-password=false "$@"
    fi
}

echo "[2/5] Пользователи"
ensure_user "$ADMIN_USER" "$ADMIN_PASS" --admin
ensure_user "$USER_NAME" "$USER_PASS"

echo "[3/5] Закрытый репозиторий demo (создаёт $USER_NAME)"
git_auth_setup "$USER_NAME" "$USER_PASS"
RESP="$(api GET "/repos/${USER_NAME}/demo")"
if [ "${RESP##*$'\n'}" = "200" ]; then
    echo "  репозиторий уже есть"
else
    RESP="$(api POST /user/repos '{"name":"demo","private":true,"default_branch":"main"}')"
    if [ "${RESP##*$'\n'}" != "201" ]; then
        echo "Не удалось создать репозиторий (HTTP ${RESP##*$'\n'}):" >&2
        echo "${RESP%$'\n'*}" >&2
        exit 1
    fi
fi

echo "[4/5] Два коммита через HTTPS"
mk_tmp_dir
WORK="$TMP_RESULT/demo"
git clone -q "https://${DOMAIN}/${USER_NAME}/demo.git" "$WORK" 2>/dev/null || true
if git -C "$WORK" rev-parse HEAD >/dev/null 2>&1; then
    # эталон из evidence/ относится к этому стенду, только если его коммит есть в репозитории
    if [ -f "$BASELINE_FILE" ] \
        && git -C "$WORK" cat-file -e "$(grep -m1 '^COMMIT_HASH=' "$BASELINE_FILE" | cut -d= -f2-)^{commit}" 2>/dev/null; then
        echo "Эталон уже создан и соответствует репозиторию ($BASELINE_FILE), повторный запуск не нужен."
        exit 0
    fi
    echo "В репозитории demo уже есть коммиты, автоматическое создание остановлено." >&2
    echo "Удали репозиторий в Gitea и запусти скрипт снова, либо создай эталон вручную." >&2
    exit 1
fi
cd "$WORK"
git checkout -q -B main
GIT=(git -c user.name="$USER_NAME" -c user.email="${USER_NAME}@example.com")

printf '# demo\n' > README.md
git add README.md
"${GIT[@]}" commit -q -m "Add README"

# Эталон из задания: строка diagnostics-test-v1 и перевод строки LF (printf, а не echo)
printf 'diagnostics-test-v1\n' > check.txt
git add check.txt
"${GIT[@]}" commit -q -m "Add check.txt"
git push -q origin main

COMMIT_HASH="$(git rev-parse HEAD)"
CHECK_SHA256="$(sha256sum check.txt | cut -d' ' -f1)"

echo "[5/5] Фиксируем эталон"
mkdir -p "$EVIDENCE_DIR"
# эталон другого стенда (например, из репозитория) не затирается, а сохраняется рядом
if [ -f "$BASELINE_FILE" ]; then
    mv "$BASELINE_FILE" "$EVIDENCE_DIR/baseline-previous-$(date +%Y%m%d-%H%M%S).txt"
    [ -f "$EVIDENCE_DIR/baseline-config.sha256" ] && mv "$EVIDENCE_DIR/baseline-config.sha256" "$EVIDENCE_DIR/baseline-config-previous-$(date +%Y%m%d-%H%M%S).sha256"
fi
cat > "$BASELINE_FILE" <<EOF
COMMIT_HASH=${COMMIT_HASH}
CHECK_SHA256=${CHECK_SHA256}
CREATED=$(stamp)
EOF
# Хэши эталонной конфигурации: по ним check.sh и recover.sh убедятся, что файлы не менялись
(cd "$PROJECT_DIR" && sha256sum configs/docker-compose.yml configs/Caddyfile > evidence/baseline-config.sha256)

echo ""
echo "Полный hash последнего коммита: ${COMMIT_HASH}"
echo "SHA-256 check.txt:              ${CHECK_SHA256}"
echo "Эталон сохранён: $BASELINE_FILE"
echo "Конфигурация:    $EVIDENCE_DIR/baseline-config.sha256"