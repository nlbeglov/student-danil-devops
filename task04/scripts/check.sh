#!/usr/bin/env bash
# Использование: ./scripts/check.sh [target|monitor]
# Внешняя проверка стенда по HTTPS: можно запускать с любого компьютера (с VPS или со своего).
# Роль target или monitor дополнительно проверяет контейнеры Compose на этом VPS.
# Адреса: переменные TARGET_DOMAIN, TARGET_PORT (HTTPS-порт цели), KUMA_DOMAIN, NTFY_DOMAIN; иначе из configs/.env своей роли
# (если он есть на этой машине); иначе адреса из README.
# Код возврата: 0 — автоматические проверки пройдены, 1 — есть провалы.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck disable=SC1091
source "$SCRIPT_DIR/../../common/lib.sh"
ROLE="${1:-}"
TARGET_DOMAIN="${TARGET_DOMAIN:-$(env_get "$SCRIPT_DIR/../target-vps/configs/.env" TARGET_DOMAIN)}"
KUMA_DOMAIN="${KUMA_DOMAIN:-$(env_get "$SCRIPT_DIR/../monitor-vps/configs/.env" KUMA_DOMAIN)}"
NTFY_DOMAIN="${NTFY_DOMAIN:-$(env_get "$SCRIPT_DIR/../monitor-vps/configs/.env" NTFY_DOMAIN)}"
TARGET_DOMAIN="${TARGET_DOMAIN:-danil2.fdghyt.com}"
# HTTPS-порт цели: на VPS 130.17.27.121 порт 443 занят чужим сервисом, поэтому 8443
TARGET_PORT="${TARGET_PORT:-$(env_get "$SCRIPT_DIR/../target-vps/configs/.env" HTTPS_PORT)}"
TARGET_PORT="${TARGET_PORT:-8443}"
KUMA_DOMAIN="${KUMA_DOMAIN:-a5.fdghyt.com}"
NTFY_DOMAIN="${NTFY_DOMAIN:-a6.fdghyt.com}"
TOPIC="${NTFY_TOPIC:-monitor-alerts}"

code() { curl -s -o /dev/null -w '%{http_code}' --max-time 8 "$@" || true; }

if [ -n "$ROLE" ]; then
    case "$ROLE" in target|monitor) ;; *) die "роль '$ROLE' недопустима (target или monitor)" ;; esac
    echo "[0/4] Контейнеры Compose на этом VPS (роль $ROLE)"
    (cd "$SCRIPT_DIR/../${ROLE}-vps/configs" && docker compose ps)
    if [ -z "$(cd "$SCRIPT_DIR/../${ROLE}-vps/configs" && docker compose ps -q --status running)" ]; then fail "контейнеры не запущены"; else ok "контейнеры запущены"; fi
    echo ""
fi

# expect_code <описание> <допустимые коды через |> <фактический код>
expect_code() {
    if [[ "$3" =~ ^($2)$ ]]; then ok "$1 -> $3"; else fail "$1 -> $3 (ожидалось $2)"; fi
}

echo "Проверка: $(date +%Y-%m-%dT%H:%M:%S%z)"
echo ""
echo "[1/4] VPS-A (цель): HTTPS и /health"
expect_code "http://$TARGET_DOMAIN (редирект)" "301|302|307|308" "$(code "http://$TARGET_DOMAIN/")"
HEALTH="$(code "https://$TARGET_DOMAIN:$TARGET_PORT/health")"
echo "  /health сейчас -> $HEALTH (200 в режиме up, 503 в режиме down)"
expect_code "/health" "200|503" "$HEALTH"
if nc -z -w 5 "$TARGET_DOMAIN" "$TARGET_PORT" 2>/dev/null; then ok "TCP $TARGET_PORT открыт"; else fail "TCP $TARGET_PORT закрыт"; fi

echo ""
echo "[2/4] VPS-B (мониторинг): Kuma и ntfy по HTTPS"
expect_code "https://$KUMA_DOMAIN" "200|301|302" "$(code "https://$KUMA_DOMAIN/")"
expect_code "https://$NTFY_DOMAIN" "200" "$(code "https://$NTFY_DOMAIN/")"

echo ""
echo "[3/4] ntfy: анонимный доступ закрыт"
expect_code "анонимное чтение"     "401|403" "$(code "https://$NTFY_DOMAIN/$TOPIC/json?poll=1")"
expect_code "анонимная публикация" "401|403" "$(code -d anon-test "https://$NTFY_DOMAIN/$TOPIC")"

echo ""
echo "[4/4] Служебные порты снаружи недоступны (запрос не получает ответа)"
# Проверяется реальным запросом: nc -zv может показать «succeeded» из-за посредника в сети,
# а HTTP-код 000 означает, что сервис не ответил
for TARGET in "$TARGET_DOMAIN:8080" "$KUMA_DOMAIN:3001" "$KUMA_DOMAIN:2586"; do
    RESULT="$(code "http://$TARGET/")"
    if [ "$RESULT" = "000" ]; then ok "$TARGET: нет ответа"; else fail "$TARGET: ответ HTTP $RESULT"; fi
done

echo ""
echo "Вручную: оба монитора в Kuma UP, интервал 30 с, HTTP принимает только 200; уведомления приходят в клиент ntfy."
check_summary
