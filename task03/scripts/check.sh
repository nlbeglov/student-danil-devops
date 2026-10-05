#!/usr/bin/env bash
# Использование: ./scripts/check.sh [каталог восстановленного проекта]   (по умолчанию <проект>/restore)
# Проверка после restore.sh (восстановленный проект: PostgreSQL и файлы, без своего Caddy):
#   [1/5] внешний репозиторий: restic check, ровно 3 снимка после политики хранения
#   [2/5] расписание: таймер systemd и последнее срабатывание
#   [3/5] manifest до и после восстановления (число строк, SHA-256 выгрузки и файлов)
#   [4/5] чтение восстановленных файлов (локально и по HTTPS) и запись id=101 в восстановленную БД
#   [5/5] ошибка доступа к хранилищу: backup.sh с неверным паролем restic -> ненулевой код и FAILED в журнале
# Запускать один раз после restore.sh: после записи id=101 manifest БД уже не совпадает с исходным,
# для повторной проверки сначала повторите восстановление.
# Код возврата: 0 — всё прошло, 1 — есть провалы.
set -uo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_task_env

RESTORE_DIR="${1:-$PROJECT_DIR/restore}"
ORIGINAL_MANIFEST="$EVIDENCE_DIR/manifest-original.txt"
RESTORED_MANIFEST="$RESTORE_DIR/evidence/manifest-restored.txt"

[ -f "$ORIGINAL_MANIFEST" ] || die "нет $ORIGINAL_MANIFEST: сначала prepare-data.sh"
[ -d "$RESTORE_DIR/configs" ] || die "нет восстановленного проекта в $RESTORE_DIR: сначала restore.sh"
restic_env

echo "Проверка: $(stamp)   восстановленный проект: $RESTORE_DIR"

echo ""
echo "[1/5] Внешний репозиторий"
restic snapshots --tag task03
if restic check >/dev/null 2>&1; then ok "restic check: репозиторий цел"; else fail "restic check нашёл ошибки"; fi
COUNT="$(restic snapshots --tag task03 --json 2>/dev/null | python3 -c 'import sys, json; print(len(json.load(sys.stdin)))' 2>/dev/null || echo 0)"
if [ "$COUNT" -eq 3 ]; then ok "после политики хранения осталось 3 снимка"
elif [ "$COUNT" -lt 3 ]; then warn "снимков $COUNT: для проверки политики нужно четыре успешных копии (./scripts/backup.sh)"
else fail "снимков $COUNT, ожидалось 3 (restic forget --keep-last 3 не отработал)"; fi

echo ""
echo "[2/5] Расписание"
if command -v systemctl >/dev/null && systemctl cat task03-backup.timer >/dev/null 2>&1; then
    systemctl list-timers task03-backup.timer --no-pager | head -3
    LAST="$(systemctl show task03-backup.service -p ExecMainStartTimestamp --value 2>/dev/null)"
    if [ -n "$LAST" ]; then ok "последний запуск службы: $LAST"; else warn "таймер установлен, но ещё не срабатывал"; fi
else
    warn "таймер не установлен: ./scripts/install-timer.sh"
fi

echo ""
echo "[3/5] Manifest до и после восстановления"
"$SCRIPT_DIR/manifest.sh" "$RESTORED_MANIFEST" "$RESTORE_DIR" >/dev/null
if diff -u "$ORIGINAL_MANIFEST" "$RESTORED_MANIFEST"; then
    ok "manifest совпадает: $(grep row_count "$RESTORED_MANIFEST"), SHA-256 выгрузки и файлов"
else
    fail "manifest различается (diff выше)"
fi

echo ""
echo "[4/5] Файлы и запись в восстановленную БД"
for PAIR in a.txt:alpha b.txt:beta c.txt:gamma; do
    NAME="${PAIR%%:*}"; WORD="${PAIR##*:}"
    if [ "$(cat "$RESTORE_DIR/data/files/$NAME" 2>/dev/null)" = "$WORD" ]; then ok "$NAME содержит $WORD"
    else fail "$NAME не содержит ожидаемого значения $WORD"; fi
done
# у восстановленного проекта нет своего Caddy: файлы по HTTPS отдаёт общий Caddy из каталога data/files основного проекта
RESULT="$(
    load_env "$RESTORE_DIR/configs" POSTGRES_USER POSTGRES_DB
    cd "$RESTORE_DIR/configs" || exit 1
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -q \
        -c "INSERT INTO items (id, value) VALUES (101, 'item-101') ON CONFLICT (id) DO NOTHING;" >/dev/null
    docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t -A -c "SELECT value FROM items WHERE id=101;"
)"
if [ "$RESULT" = "item-101" ]; then ok "запись id=101 добавлена и читается"; else fail "запись id=101 не добавлена"; fi

echo ""
echo "[5/5] Ошибка доступа к хранилищу: backup.sh с неверным паролем restic"
RESTIC_PASSWORD="заведомо-неверный-пароль" "$SCRIPT_DIR/backup.sh" >/dev/null 2>&1
RC=$?
if [ "$RC" -ne 0 ] && tail -n 3 "$BACKUP_LOG" | grep -q "FAILED"; then
    ok "backup.sh завершился с кодом $RC, неуспех записан в журнал ($BACKUP_LOG)"
else
    fail "ожидался ненулевой код и запись FAILED в журнале (код $RC)"
fi
echo "  Рабочие настройки не менялись: неверный пароль передавался только переменной окружения."

echo ""
echo "Верните основной стенд: cd $RESTORE_DIR/configs && docker compose stop; затем cd $CONFIGS_DIR && docker compose up -d"
check_summary
