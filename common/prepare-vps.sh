#!/usr/bin/env bash
# Использование: sudo ./common/prepare-vps.sh   
# Готовит чистый Ubuntu/Debian VPS: Docker Engine + Compose plugin, утилиты для заданий,
# файрвол (снаружи только SSH, 80, 443). Идемпотентен: повторный запуск ничего не ломает.
set -euo pipefail

[ "$(id -u)" -eq 0 ] || { echo "Запустите от root: sudo $0" >&2; exit 1; }
command -v apt-get >/dev/null || { echo "Скрипт рассчитан на Ubuntu/Debian (apt-get)" >&2; exit 1; }

export DEBIAN_FRONTEND=noninteractive

echo "[1/4] Пакеты: git, curl, openssl, gpg, restic, python3-venv, ufw, netcat"
apt-get update -y
apt-get install -y ca-certificates curl git openssl gnupg restic python3-venv ufw netcat-openbsd

echo "[2/4] Docker Engine и Compose plugin"
if command -v docker >/dev/null && docker compose version >/dev/null 2>&1; then
    echo "  уже установлен: $(docker --version)"
else
    curl -fsSL https://get.docker.com | sh
fi
systemctl enable --now docker

echo "[3/4] Файрвол ufw: открыты только 22, 80, 443"
ufw allow 22/tcp
ufw allow 80/tcp
ufw allow 443/tcp
ufw --force enable
# Docker публикует порты в обход ufw: в заданиях наружу публикуются только 80/443 Caddy,
# БД и служебные порты контейнеров остаются во внутренней сети Compose

echo "[4/4] Проверка"
docker --version
docker compose version
systemctl is-enabled docker
ufw status | head -8
echo ""
echo "Готово. Дальше: README нужного задания."
