#!/usr/bin/env bash
# Использование: recover.sh
# Возвращает рабочую конфигурацию (только docker-compose.yml, без override-файлов).
# Данные сохраняются: тома и bind-mount не удаляются и не пересоздаются.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_env

# Эталонные файлы не должны были меняться: предупреждаем, если это не так
if [ -f "$EVIDENCE_DIR/baseline-config.sha256" ]; then
    (cd "$PROJECT_DIR" && sha256sum -c evidence/baseline-config.sha256 --quiet 2>/dev/null) \
        || echo "ВНИМАНИЕ: docker-compose.yml или Caddyfile отличаются от эталона (evidence/baseline-config.sha256)" >&2
fi

PREVIOUS="нет"
[ -f "$FAULT_STATE" ] && PREVIOUS="$(cat "$FAULT_STATE")"
log_event "recover: начато (сбой был: ${PREVIOUS})"

cd "$CONFIGS_DIR"
docker compose -f docker-compose.yml up -d --no-deps --force-recreate server caddy

echo "Ждём, пока Gitea станет доступна..."
if ! wait_gitea; then
    echo "Gitea не поднялась после восстановления. Состояние и логи:" >&2
    docker compose ps
    docker compose logs --tail 30 server
    exit 1
fi

rm -f "$FAULT_STATE"
log_event "recover: завершено, рабочая конфигурация возвращена"
docker compose ps
echo ""
echo "Теперь проверь результат: $SCRIPT_DIR/check.sh push"