#!/usr/bin/env bash
# Использование: sudo ./scripts/install-timer.sh [daily|test|remove]   (по умолчанию daily)
#   daily  — ежедневный запуск backup.sh в 03:15
#   test   — каждую минуту, ТОЛЬКО для проверки расписания; после проверки вернуть: install-timer.sh daily
#   remove — удалить таймер
# Устанавливает systemd-юниты из systemd/ с подстановкой пути к проекту. Журнал: evidence/backup.log и journalctl.
set -euo pipefail

MODE="${1:-daily}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
UNIT_DIR="/etc/systemd/system"

[ "$(id -u)" -eq 0 ] || { echo "Нужен root: sudo $0 $MODE" >&2; exit 1; }
command -v systemctl >/dev/null || { echo "systemd не найден" >&2; exit 1; }

case "$MODE" in
    daily)  ONCALENDAR='*-*-* 03:15:00' ;;
    test)   ONCALENDAR='*-*-* *:*:00' ;;
    remove)
        systemctl disable --now task03-backup.timer 2>/dev/null || true
        rm -f "$UNIT_DIR/task03-backup.service" "$UNIT_DIR/task03-backup.timer"
        systemctl daemon-reload
        echo "Таймер удалён."
        exit 0 ;;
    *) echo "Использование: $0 [daily|test|remove]" >&2; exit 2 ;;
esac

sed "s|@PROJECT_DIR@|$PROJECT_DIR|g" "$PROJECT_DIR/systemd/task03-backup.service" > "$UNIT_DIR/task03-backup.service"
sed "s|@ONCALENDAR@|$ONCALENDAR|g" "$PROJECT_DIR/systemd/task03-backup.timer" > "$UNIT_DIR/task03-backup.timer"
systemctl daemon-reload
systemctl enable --now task03-backup.timer
systemctl restart task03-backup.timer

echo "Режим: $MODE (OnCalendar=$ONCALENDAR)"
systemctl list-timers task03-backup.timer --no-pager
echo "Последние запуски: journalctl -u task03-backup.service -n 20 --no-pager"
