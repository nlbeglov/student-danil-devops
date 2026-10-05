#!/usr/bin/env bash
# Использование: ./scripts/setup-secrets.sh
# Запускать после заполнения configs/.env и ДО первого запуска стека (пароль PostgreSQL применяется при инициализации базы).
# Создаёт пароль PostgreSQL, записывает его в configs/.env и secrets/credentials.txt. Повторный запуск пароль не меняет.
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck disable=SC1091
source "$PROJECT_DIR/../common/lib.sh"
setup_db_password "$PROJECT_DIR"
echo "Пароль PostgreSQL записан в configs/.env и $PROJECT_DIR/secrets/credentials.txt"
