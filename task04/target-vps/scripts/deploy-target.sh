#!/usr/bin/env bash
# Использование: deploy-target.sh
# Запускать на VPS-A. Требует target-vps/.env (cp .env.example .env && nano .env).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
cd "$CONFIGS_DIR"

[ -f .env ] || { echo "Нет $CONFIGS_DIR/.env — скопируй из .env.example и заполни" >&2; exit 1; }
# shellcheck disable=SC1091
source .env
: "${TARGET_DOMAIN:?TARGET_DOMAIN не задан}"
[ "$TARGET_DOMAIN" != "CHANGE_ME" ] || { echo "TARGET_DOMAIN всё ещё CHANGE_ME" >&2; exit 1; }

echo "[1/3] Начальное состояние /health = up"
mkdir -p "$PROJECT_DIR/data/health"
cp "$CONFIGS_DIR/nginx/health-templates/up.inc" "$PROJECT_DIR/data/health/state.inc"

echo "[2/3] Поднимаем стек"
docker compose up -d

echo "[3/3] Проверяем"
docker compose ps
echo ""
echo "Дальше:  curl -i https://$TARGET_DOMAIN/health   (ожидается HTTP 200)"
echo "Переключение: $SCRIPT_DIR/set-health.sh up|down"