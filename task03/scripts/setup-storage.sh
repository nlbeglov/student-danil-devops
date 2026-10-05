#!/usr/bin/env bash
# Использование: ./scripts/setup-storage.sh <пользователь@хост-хранилища>
# Один раз настраивает доступ VPS к внешнему SFTP-хранилищу без пароля: создаёт отдельный SSH-ключ
# ~/.ssh/task03_restic_key, прописывает его в ~/.ssh/config для этого хоста и копирует публичную часть
# на хранилище (понадобится пароль хранилища один раз). Выполнять от того пользователя, под которым
# будет работать backup.sh и таймер (root). Приватный ключ остаётся только на VPS.
set -euo pipefail

TARGET="${1:?Использование: $0 пользователь@хост-хранилища}"
HOST="${TARGET#*@}"
KEY="$HOME/.ssh/task03_restic_key"

mkdir -p "$HOME/.ssh"; chmod 700 "$HOME/.ssh"
if [ ! -f "$KEY" ]; then
    ssh-keygen -t ed25519 -C "task03-restic" -f "$KEY" -N ""
fi
if ! grep -q "IdentityFile $KEY" "$HOME/.ssh/config" 2>/dev/null; then
    {
        echo ""
        echo "Host $HOST"
        echo "    IdentityFile $KEY"
        echo "    IdentitiesOnly yes"
        echo "    StrictHostKeyChecking accept-new"
    } >> "$HOME/.ssh/config"
    chmod 600 "$HOME/.ssh/config"
fi
ssh-copy-id -i "$KEY.pub" "$TARGET"
ssh -o BatchMode=yes "$TARGET" echo "Доступ без пароля работает"
echo "Дальше: RESTIC_REPOSITORY=sftp:$TARGET:/путь/к/репозиторию  (значение для configs/.env)"
