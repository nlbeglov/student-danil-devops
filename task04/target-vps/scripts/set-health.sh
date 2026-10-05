#!/usr/bin/env bash
# Использование: set-health.sh up|down
#   up   — /health отвечает HTTP 200
#   down — /health отвечает HTTP 503 (HTTPS-порт остаётся доступным)
set -euo pipefail

MODE="${1:-}"
case "$MODE" in
    up|down) ;;
    *) echo "Использование: $0 up|down" >&2; exit 2 ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
CONFIGS_DIR="$PROJECT_DIR/configs"
LOG_FILE="$PROJECT_DIR/../evidence/set-health.log"
STATE_FILE="$PROJECT_DIR/data/health/state.inc"
TEMPLATE="$CONFIGS_DIR/nginx/health-templates/$MODE.inc"

cd "$CONFIGS_DIR"
# shellcheck disable=SC1091
source .env
[ -f "$TEMPLATE" ] || { echo "Нет шаблона $TEMPLATE" >&2; exit 1; }
mkdir -p "$(dirname "$STATE_FILE")" "$(dirname "$LOG_FILE")"

stamp() { date +%Y-%m-%dT%H:%M:%S%z; }

# Резервная копия текущего состояния — откатимся, если nginx отвергнет новый конфиг
BACKUP="$(mktemp)"
trap 'rm -f "$BACKUP"' EXIT
cp "$STATE_FILE" "$BACKUP" 2>/dev/null || true

echo "[1/3] Записываем состояние '$MODE'"
cp "$TEMPLATE" "$STATE_FILE"

echo "[2/3] Проверяем конфигурацию nginx"
if ! docker compose exec -T nginx nginx -t; then
    echo "nginx -t не прошёл, откатываем состояние" >&2
    cp "$BACKUP" "$STATE_FILE"
    echo "$(stamp) health=$MODE FAILED (nginx -t)" >> "$LOG_FILE"
    exit 1
fi

echo "[3/3] Перезагружаем конфигурацию (reload, без остановки контейнера)"
docker compose exec -T nginx nginx -s reload
echo "$(stamp) health=$MODE" >> "$LOG_FILE"

# Контрольный запрос по HTTPS: код зависит от режима, порт 443 отвечает в обоих.
# reload асинхронный: новые процессы nginx стартуют не мгновенно, поэтому ждём нужного кода до 10 секунд, вместо того чтобы проверять один раз сразу.
EXPECTED=200; [ "$MODE" = "down" ] && EXPECTED=503
CODE=""
for _ in $(seq 1 10); do
    CODE="$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 "https://${TARGET_DOMAIN}/health" || true)"
    [ "$CODE" = "$EXPECTED" ] && break
    sleep 1
done
echo "https://${TARGET_DOMAIN}/health -> HTTP $CODE"
[ "$CODE" = "$EXPECTED" ] || { echo "ОЖИДАЛСЯ $EXPECTED, получен $CODE" >&2; exit 1; }