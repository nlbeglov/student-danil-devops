#!/usr/bin/env bash
# Использование: deploy-monitor.sh
# Запускать на VPS-B. Требует configs/.env (cp configs/.env.example configs/.env)
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
cd "$CONFIGS_DIR"

[ -f .env ] || { echo "Нет $CONFIGS_DIR/.env: скопируй из .env.example и заполни" >&2; exit 1; }
# shellcheck disable=SC1091
source .env
for V in KUMA_DOMAIN NTFY_DOMAIN; do
    [ -n "${!V:-}" ] && [ "${!V}" != "CHANGE_ME" ] || { echo "$V не задан" >&2; exit 1; }
done

echo "[1/2] Поднимаем стек"
mkdir -p "$PROJECT_DIR/data/kuma" "$PROJECT_DIR/data/ntfy"
docker compose up -d

echo "[2/2] Статус"
docker compose ps
cat <<EOF

РУЧНЫЕ ДЕЙСТВИЯ ДАЛЬШЕ:
  1) $SCRIPT_DIR/setup-secrets.sh     — создать пароли и пользователей ntfy
  2) https://$KUMA_DOMAIN             — СРАЗУ создать администратора Kuma
     (первый, кто откроет страницу до создания админа, станет админом!)
  3) настроить уведомление и мониторы (см. Шаг 5 гайда / README)
EOF