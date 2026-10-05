#!/usr/bin/env bash
# Использование: restic-init.sh
# Инициализирует зашифрованный restic-репозиторий во внешнем хранилище (SFTP). Идемпотентен:
# если репозиторий уже есть, ничего не делает.
# Доступ к хранилищу по SSH-ключу настраивается один раз в ~/.ssh/config (IdentityFile для хоста хранилища),
# поэтому restic ничего не знает про ключ.
set -euo pipefail

# shellcheck disable=SC1091
source "$(dirname "${BASH_SOURCE[0]}")/lib.sh"
load_task_env
restic_env
command -v restic >/dev/null || { echo "Нужен restic (apt-get install -y restic)" >&2; exit 1; }

echo "Репозиторий: $RESTIC_REPOSITORY"
if restic cat config >/dev/null 2>&1; then
    echo "Репозиторий уже инициализирован."
else
    restic init
fi
echo ""
restic snapshots
