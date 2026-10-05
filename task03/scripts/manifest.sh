#!/usr/bin/env bash
# Использование: manifest.sh [файл для manifest] [каталог проекта]
#   без аргументов — manifest исходного проекта в evidence/manifest-<время>.txt
#   каталог проекта нужен, чтобы снять контрольный manifest у восстановленного проекта
# Формат одинаков при каждом запуске, поэтому «до» и «после» сравниваются обычным diff.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${2:-$(cd "$SCRIPT_DIR/.." && pwd)}"
CONFIGS_DIR="$PROJECT_DIR/configs"
OUTPUT_FILE="${1:-$PROJECT_DIR/evidence/manifest-$(date +%Y%m%d-%H%M%S).txt}"
FILES_DIR="$PROJECT_DIR/data/files"

[ -f "$CONFIGS_DIR/.env" ] || { echo "Нет $CONFIGS_DIR/.env" >&2; exit 1; }
# shellcheck disable=SC1091
source "$CONFIGS_DIR/.env"
: "${POSTGRES_USER:?}" "${POSTGRES_DB:?}"
mkdir -p "$(dirname "$OUTPUT_FILE")"

echo "[1/3] Выгружаем таблицу items в CSV с сортировкой по id"
# ORDER BY id обязателен: без сортировки порядок строк не гарантирован и SHA-256 мог бы отличаться
DUMP_CSV="$(cd "$CONFIGS_DIR" && docker compose exec -T db \
    psql -U "$POSTGRES_USER" -d "$POSTGRES_DB" -t --csv \
    -c "SELECT id, value FROM items ORDER BY id;")"

ROW_COUNT="$(echo "$DUMP_CSV" | grep -c . || true)"
DUMP_SHA256="$(echo -n "$DUMP_CSV" | sha256sum | awk '{print $1}')"

echo "[2/3] Считаем SHA-256 каждого файла"
FILE_HASHES=""
for FILE in a.txt b.txt c.txt; do
    FULL_PATH="$FILES_DIR/$FILE"
    [ -f "$FULL_PATH" ] || { echo "ОШИБКА: файл $FULL_PATH не найден" >&2; exit 1; }
    HASH="$(sha256sum "$FULL_PATH" | awk '{print $1}')"
    FILE_HASHES="${FILE_HASHES}${FILE}=${HASH}"$'\n'
done

echo "[3/3] Записываем manifest в $OUTPUT_FILE"
{
    echo "row_count=${ROW_COUNT}"
    echo "dump_sha256=${DUMP_SHA256}"
    printf '%s' "$FILE_HASHES"
} > "$OUTPUT_FILE"

echo "Manifest сохранён: $OUTPUT_FILE"
cat "$OUTPUT_FILE"
