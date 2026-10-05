#!/usr/bin/env bash
# Использование: fault.sh proxy|database|readonly
#   proxy    — неверный порт Gitea в upstream Caddy
#   database — неверное имя хоста PostgreSQL в настройках Gitea
#   readonly — том данных Gitea подключён только для чтения
# Эталонный docker-compose.yml не меняется, сбой накладывается файлом configs/faults/<сбой>.yml
set -euo pipefail

FAULT="${1:-}"
case "$FAULT" in
    proxy)             SERVICE="caddy" ;;
    database|readonly) SERVICE="server" ;;
    *) echo "Использование: $0 proxy|database|readonly" >&2; exit 2 ;;
esac

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

[ -f "$CONFIGS_DIR/faults/$FAULT.yml" ] || { echo "Нет файла faults/$FAULT.yml" >&2; exit 1; }
if [ -f "$FAULT_STATE" ]; then
    echo "Уже внесён сбой '$(cat "$FAULT_STATE")': сначала выполни recover.sh" >&2
    exit 1
fi

cd "$CONFIGS_DIR"
# --no-deps: пересоздаём только затронутый сервис, а не всю цепочку зависимостей
docker compose -f docker-compose.yml -f "faults/$FAULT.yml" up -d --no-deps --force-recreate "$SERVICE"

echo "$FAULT" > "$FAULT_STATE"
log_event "fault=$FAULT внесён (пересоздан сервис: $SERVICE)"
echo ""
echo "Сбой внесён. Диагностику начинай с наблюдения симптома (check.sh, логи, статус), а не с чтения override-файла."