#!/usr/bin/env bash
# Использование: deploy.sh
# Требует configs/.env и secrets/credentials.txt (setup-secrets.sh).
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env
cred POSTGRES_PASSWORD >/dev/null

echo "[1/3] Каталоги данных"
mkdir -p "$PROJECT_DIR/data/gitea" "$PROJECT_DIR/data/postgres" "$EVIDENCE_DIR"

echo "[2/3] Поднимаем стек"
cd "$CONFIGS_DIR"
docker compose up -d

echo "[3/3] Ждём, пока Gitea ответит на healthz (до 2 минут)"
if ! wait_gitea; then
    echo "Gitea не поднялась. Состояние и логи:" >&2
    docker compose ps
    docker compose logs --tail 30 server
    exit 1
fi
docker compose ps
echo ""
echo "Дальше: $SCRIPT_DIR/prepare-demo.sh   (пользователи, репозиторий demo, два коммита)"
echo "Проверка:  curl -I https://${DOMAIN}/"