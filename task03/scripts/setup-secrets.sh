#!/usr/bin/env bash
# Использование: ./scripts/setup-secrets.sh
# Запускать после заполнения configs/.env и ДО первого запуска стека.
# Создаёт пароль PostgreSQL (configs/.env и secrets/credentials.txt) и ключ шифрования restic (RESTIC_PASSWORD
# в secrets/credentials.txt). Повторный запуск пароли не меняет.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
setup_db_password "$PROJECT_DIR"
cred_ensure "$PROJECT_DIR" RESTIC_PASSWORD >/dev/null
echo "Пароли сохранены в $CRED_FILE (POSTGRES_PASSWORD, RESTIC_PASSWORD)"
echo "ВАЖНО: сохраните RESTIC_PASSWORD отдельно от VPS: при потере сервера без него копии не прочитать."
