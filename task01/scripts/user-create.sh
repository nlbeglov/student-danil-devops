#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# compose-файл лежит либо прямо в каталоге проекта (как на сервере), либо в configs/ (как в репозитории)

COMPOSE_DIR="$PROJECT_DIR/configs"
ENV_FILE="$COMPOSE_DIR/.env"
SECRETS_DIR="$PROJECT_DIR/secrets"
CRED_FILE="$SECRETS_DIR/credentials.txt"

[ -f "$ENV_FILE" ] || { echo "Не найден $ENV_FILE" >&2; exit 1; }
# shellcheck disable=SC1090
source "$ENV_FILE"
: "${DOMAIN:?В .env нет переменной DOMAIN}"
command -v openssl >/dev/null || { echo "Нужен openssl (apt-get install -y openssl)" >&2; exit 1; }

gitea_cli() { (cd "$COMPOSE_DIR" && docker compose exec -T -u git server gitea "$@"); }

[ -n "$(cd "$COMPOSE_DIR" && docker compose ps -q --status running server)" ] \
    || { echo "Контейнер server не запущен: сначала docker compose up -d" >&2; exit 1; }

echo "=== Создание пользователя Gitea (${DOMAIN}) ==="

read -rp "Имя пользователя: " USERNAME
[[ "$USERNAME" =~ ^[A-Za-z0-9][A-Za-z0-9_.-]*$ ]] \
    || { echo "Недопустимое имя: допустимы буквы, цифры, '-', '_', '.', первый символ — буква или цифра" >&2; exit 1; }

# проверяем, что такого пользователя ещё нет (вторая колонка списка — Username)
if gitea_cli admin user list | awk 'NR>1 {print $2}' | grep -qx "$USERNAME"; then
    echo "Пользователь '$USERNAME' уже существует" >&2
    exit 1
fi

read -rp "Сделать администратором? [y/N]: " IS_ADMIN
read -rsp "Пароль (Enter — сгенерировать случайный): " PASSWORD
echo
if [ -z "$PASSWORD" ]; then
    PASSWORD="$(openssl rand -hex 16)"
    PASSWORD_MODE="сгенерирован"
else
    read -rsp "Повторите пароль: " PASSWORD_CONFIRM
    echo
    [ "$PASSWORD" = "$PASSWORD_CONFIRM" ] || { echo "Пароли не совпадают" >&2; exit 1; }
    PASSWORD_MODE="введён вручную"
fi

# Gitea требует email при создании пользователя: собираем его из имени и домена
EMAIL="${USERNAME}@${DOMAIN}"
ROLE="обычный пользователь"
[[ "$IS_ADMIN" =~ ^[Yy] ]] && ROLE="администратор"

echo ""
echo "Будет создан пользователь:"
echo "  Имя:    $USERNAME"
echo "  Роль:   $ROLE"
echo "  Email:  $EMAIL (собран автоматически)"
echo "  Пароль: $PASSWORD_MODE"
read -rp "Создать? [Y/n]: " CONFIRM
[[ ! "$CONFIRM" =~ ^[Nn] ]] || { echo "Отменено."; exit 1; }

ARGS=(--username "$USERNAME" --email "$EMAIL" --password "$PASSWORD" --must-change-password=false)
[ "$ROLE" = "администратор" ] && ARGS+=(--admin)
gitea_cli admin user create "${ARGS[@]}"

# Сохраняем пароль: строка ИМЯ_PASSWORD=значение (review-user -> REVIEW_USER_PASSWORD).
# Старая запись этого пользователя заменяется, остальные строки файла не трогаются
KEY="$(printf '%s' "$USERNAME" | tr 'a-z.-' 'A-Z__')_PASSWORD"
umask 077
mkdir -p "$SECRETS_DIR"
chmod 700 "$SECRETS_DIR"
touch "$CRED_FILE"
TMP="$(mktemp "$SECRETS_DIR/.credentials.XXXXXX")"
awk -F= -v k="$KEY" '$1 != k' "$CRED_FILE" > "$TMP"
echo "${KEY}=${PASSWORD}" >> "$TMP"
chmod 600 "$TMP"
mv "$TMP" "$CRED_FILE"

echo ""
echo "Пользователь $USERNAME создан."
echo "Пароль: $PASSWORD"
echo "Сохранён в: $CRED_FILE (ключ $KEY)"
