#!/usr/bin/env bash
# Использование: backup.sh
# Единый скрипт для ежедневного (systemd-таймер) и ручного запуска резервной копии:
# запись в БД блокируется → pg_dump → дамп, файлы и настройки в зашифрованный restic-репозиторий
# вне VPS → политика хранения (остаются 3 последних снимка).
# Защита от параллельного запуска: flock. Журнал: evidence/backup.log. Код возврата:
# 0 — успех, 1 — ошибка (в журнале строка FAILED), 2 — копирование уже выполняется.
set -uo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_task_env

mkdir -p "$PROJECT_DIR/data"
# Защита от параллельных копирований: вторая копия скрипта сразу завершается, не дожидаясь первой
exec 9> "$PROJECT_DIR/data/backup.lock"
if ! flock -n 9; then
    log "FAILED: резервное копирование уже выполняется другим процессом"
    exit 2
fi

restic_env
TMP_DIR="$PROJECT_DIR/data/backup-tmp"
DB_READONLY=0

# При любом завершении (успех, ошибка, Ctrl+C): снять запрет записи в БД, удалить временный дамп, записать итог в журнал
cleanup() {
    local rc=$?
    if [ "$DB_READONLY" -eq 1 ]; then
        (cd "$CONFIGS_DIR" && docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
            -c "ALTER DATABASE \"$POSTGRES_DB\" RESET default_transaction_read_only;" >/dev/null 2>&1) || true
    fi
    rm -rf "$TMP_DIR"
    if [ "$rc" -eq 0 ]; then
        log "OK: резервное копирование завершено успешно"
    else
        log "FAILED: резервное копирование завершилось с ошибкой (код $rc)"
    fi
}
trap cleanup EXIT
set -e

log "[1/6] Проверяем доступ к репозиторию restic"
# Проверка до любых действий с БД: при неверном пароле или недоступном хранилище скрипт сразу падает
if ! OUTPUT="$(restic snapshots --tag task03 2>&1)"; then
    log "Нет доступа к репозиторию restic: $(echo "$OUTPUT" | tail -n 2 | tr '\n' ' ')"
    exit 1
fi

log "[2/6] Блокируем запись в базу данных на время копирования"
# новые подключения к БД становятся read-only: тестовые записи остановлены, чтение и pg_dump работают
cd "$CONFIGS_DIR"
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "ALTER DATABASE \"$POSTGRES_DB\" SET default_transaction_read_only = on;" >/dev/null
DB_READONLY=1

log "[3/6] Снимаем дамп PostgreSQL (pg_dump, custom format)"
rm -rf "$TMP_DIR"
mkdir -p "$TMP_DIR"
docker compose exec -T db pg_dump -U "$POSTGRES_USER" -d "$POSTGRES_DB" -F c > "$TMP_DIR/db.dump"

log "[4/6] Отправляем дамп, файлы и настройки в restic"
# в копию попадают настройки без секретов: env.sanitized (из .env без пароля БД) вместо .env.
# Пароли хранятся только в secrets/ и передаются отдельно (RESTIC_PASSWORD — ключ репозитория)
sed -E 's/^(POSTGRES_PASSWORD)=.*/\1=CHANGE_ME/' "$CONFIGS_DIR/.env" > "$TMP_DIR/env.sanitized"
restic backup \
    "$TMP_DIR/db.dump" "$TMP_DIR/env.sanitized" \
    "$PROJECT_DIR/data/files" \
    "$CONFIGS_DIR/docker-compose.yml" "$CONFIGS_DIR/01-items.sql" \
    --tag task03 --host task03

log "[5/6] Возвращаем запись в базу данных"
docker compose exec -T db psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" \
    -c "ALTER DATABASE \"$POSTGRES_DB\" RESET default_transaction_read_only;" >/dev/null
DB_READONLY=0

log "[6/6] Политика хранения: оставляем 3 последних снимка"
restic forget --keep-last 3 --tag task03 --host task03 --prune

log "Снимки в репозитории:"
restic snapshots --tag task03 | tee -a "$BACKUP_LOG"
