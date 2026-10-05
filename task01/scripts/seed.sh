#!/usr/bin/env bash
# Использование: ./scripts/seed.sh
# Создаёт review-admin, review-user и закрытый репозиторий demo с двумя коммитами (check.txt = gitea-test-v1 + LF).
# Hash последнего коммита сохраняется в evidence/baseline.txt: с ним сравнивает check.sh.
# Идемпотентен: если эталон уже создан, ничего не делает. Запускать после docker compose up -d.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
BASELINE_FILE="$PROJECT_DIR/evidence/baseline.txt"
# shellcheck disable=SC1091
source "$PROJECT_DIR/../common/lib.sh"
# shellcheck disable=SC1091
source "$PROJECT_DIR/../common/gitea.sh"
need_cmd docker curl git openssl

load_env "$CONFIGS_DIR" DOMAIN POSTGRES_PASSWORD

if [ -f "$BASELINE_FILE" ]; then
    echo "Эталон уже создан ($BASELINE_FILE), повторный запуск не нужен."
    exit 0
fi

ADMIN_USER="review-admin"
USER_NAME="review-user"
ADMIN_PASS="$(cred_ensure "$PROJECT_DIR" REVIEW_ADMIN_PASSWORD)"
USER_PASS="$(cred_ensure "$PROJECT_DIR" REVIEW_USER_PASSWORD)"

echo "[1/4] Ждём Gitea"
wait_gitea || die "Gitea не отвечает (docker compose logs server)"

echo "[2/4] Пользователи"
ensure_gitea_user "$ADMIN_USER" "$ADMIN_PASS" --admin
ensure_gitea_user "$USER_NAME" "$USER_PASS"

echo "[3/4] Закрытый репозиторий demo (создаёт $USER_NAME); ждём HTTPS"
wait_until 120 curl -fsS --max-time 5 -o /dev/null "https://${DOMAIN}/" \
    || die "https://${DOMAIN} не отвечает: проверьте A-запись домена и порты 80/443"
git_auth_setup "$USER_NAME" "$USER_PASS"
RESP="$(gitea_api GET "/repos/${USER_NAME}/demo")"
if [ "${RESP##*$'\n'}" != "200" ]; then
    RESP="$(gitea_api POST /user/repos '{"name":"demo","private":true,"default_branch":"main"}')"
    [ "${RESP##*$'\n'}" = "201" ] || die "не удалось создать репозиторий (HTTP ${RESP##*$'\n'}): ${RESP%$'\n'*}"
fi

echo "[4/4] Два коммита через HTTPS"
mk_tmp_dir
WORK="$TMP_RESULT/demo"
git clone -q "https://${DOMAIN}/${USER_NAME}/demo.git" "$WORK" 2>/dev/null || true
if git -C "$WORK" rev-parse HEAD >/dev/null 2>&1; then
    die "в demo уже есть коммиты: удалите репозиторий в Gitea и повторите, либо создайте evidence/baseline.txt вручную (COMMIT_HASH=...)"
fi
cd "$WORK"
git checkout -q -B main
GIT=(git -c user.name="$USER_NAME" -c user.email="${USER_NAME}@example.com")
printf '# demo\n' > README.md
git add README.md
"${GIT[@]}" commit -q -m "Add README"
# строка из задания и перевод строки LF (printf, а не echo)
printf 'gitea-test-v1\n' > check.txt
git add check.txt
"${GIT[@]}" commit -q -m "Add check.txt"
git push -q origin main

COMMIT_HASH="$(git rev-parse HEAD)"
mkdir -p "$PROJECT_DIR/evidence"
cat > "$BASELINE_FILE" <<EOT
COMMIT_HASH=${COMMIT_HASH}
CHECK_SHA256=$(sha256sum check.txt | cut -d' ' -f1)
CREATED=$(stamp)
EOT

echo ""
echo "Полный hash последнего коммита: ${COMMIT_HASH}"
echo "Эталон: $BASELINE_FILE"
