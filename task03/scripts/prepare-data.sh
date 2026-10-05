#!/usr/bin/env bash
# Использование: prepare-data.sh
# Создаёт тестовые файлы a.txt, b.txt, c.txt (строки alpha, beta, gamma, окончание LF) и снимает
# исходный manifest в evidence/manifest-original.txt. Запускается один раз до первой резервной копии,
# после запуска стека (нужна работающая БД).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
FILES_DIR="$PROJECT_DIR/data/files"
ORIGINAL_MANIFEST="$PROJECT_DIR/evidence/manifest-original.txt"

mkdir -p "$FILES_DIR" "$PROJECT_DIR/evidence"

echo "[1/2] Создаём тестовые файлы с окончанием LF"
# printf гарантирует ровно один перевод строки в конце файла (echo ведёт себя по-разному в разных оболочках)
printf 'alpha\n' > "$FILES_DIR/a.txt"
printf 'beta\n'  > "$FILES_DIR/b.txt"
printf 'gamma\n' > "$FILES_DIR/c.txt"

echo "[2/2] Снимаем исходный manifest (эталон для сравнения после восстановления)"
"$SCRIPT_DIR/manifest.sh" "$ORIGINAL_MANIFEST"

echo ""
echo "Готово. Исходный manifest: $ORIGINAL_MANIFEST"
