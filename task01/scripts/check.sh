#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="${1:?Использование: check.sh <project dir> <input|files>}"
SECRET_MODE="${2:?Использование: <input|files>}"

echo "[0/6] Проверка корректности данных"
# проверка на корректность введения данных
if [ "$SECRET_MODE" != "input" ] && [ "$SECRET_MODE" != "files" ]; then
    echo "Недопустимое значение режима: '$SECRET_MODE' (ожидается 'input' или 'files')" >&2
    exit 1
fi

# Проверяем существует ли env
[ -f "$PROJECT_DIR/.env" ] || { echo "Не найден $PROJECT_DIR/.env" >&2; exit 1; }

# загружаем данные из env
source "$PROJECT_DIR/.env"

# проверяем есть ли строка DOMAIN
[ -n "${DOMAIN:-}" ] || { echo "В .env нет переменной DOMAIN" >&2; exit 1; }

# проверяем есть ли строка PROJECT_NAME
[ -n "${PROJECT_NAME:-}" ] || { echo "В .env нет переменной PROJECT_NAME" >&2; exit 1; }

cd "$PROJECT_DIR"

echo "Проект: $PROJECT_NAME"
echo ""

echo "[1/6] Статус контейнеров"
docker compose -p "$PROJECT_NAME" ps

echo ""
echo "[2/6] Контейнеры стартовали автоматически при загрузке VPS?"

BOOT_TIME=$(uptime -s)
echo "Система загрузилась: $BOOT_TIME"

# перебераем все контейнеры проекта
for CONTAINER in $(docker compose -p "$PROJECT_NAME" ps -q); do
                NAME=$(docker inspect --format='{{.Name}}' "$CONTAINER" | sed 's|^/||')
        STARTED=$(docker inspect --format='{{.State.StartedAt}}' "$CONTAINER")
        echo "  $NAME запущен: $STARTED"
done

echo "Ручная проверка - необходимо определить что время запуска не сильно отличается"

echo ""
echo "[3/6] Данные физически на месте (bind-mount не пустой)"
du -sh ./gitea ./postgres 2>/dev/null || echo "ВНИМАНИЕ: одна из папок не найдена"

echo ""
echo "[4/6] Сервис отвечает по HTTPS"

curl -sI --max-time 5 "https://${DOMAIN}" | head -3

echo ""
echo "[5/6] Приватный репозиторий недоступен анонимно (ожидается 404)"

curl -sI --max-time 5 "https://${DOMAIN}/review-user/demo" | head -1

echo ""
echo "[6/6] Вход пользователя и проверка commit hash"

echo "Получаем список пользователей из Gitea..."

# сохраняем весь вывод команды в переменную один раз
USER_LIST_RAW=$(docker compose -p "$PROJECT_NAME" exec -T -u git server gitea admin user list)

# head -1 — берём только первую строку вывода (заголовок)
HEADER=$(echo "$USER_LIST_RAW" | head -1)

# tr -s ' ' '\n' — заменить повторяющиеся пробелы на переводы строк,
# то есть "разложить" строку заголовка по словам, каждое на своей строке
# grep -n -i '^Username$' — найти строку, точно равную "Username"
# (без учёта регистра), -n покажет её номер
# cut -d: -f1 — оставить только сам номер (до двоеточия) —
# это и есть номер нужной колонки
USERNAME_COL=$(echo "$HEADER" | tr -s ' ' '\n' | grep -n -i '^Username$' | cut -d: -f1)

if [ -z "$USERNAME_COL" ]; then
    echo "Не удалось определить колонку Username в выводе Gitea CLI" >&2
    exit 1
fi

# из всех строк, кроме заголовка (NR>1), берём значение из найденной колонки
USER_LIST=$(echo "$USER_LIST_RAW" | awk -v col="$USERNAME_COL" 'NR>1 {print $col}')

if [ -z "$USER_LIST" ]; then
    echo "Не удалось получить список пользователей" >&2
    exit 1
fi

echo "Выбери пользователя для проверки:"
select USERNAME in $USER_LIST; do
    if [ -n "$USERNAME" ]; then
        break
    else
        echo "Некорректный выбор, попробуй снова"
    fi
done

echo "Выбран пользователь: $USERNAME"

if [ "$SECRET_MODE" = "input" ]; then
    read -rsp "Пароль для $USERNAME: " PASSWORD
    echo
else
    read -rp "Путь к файлу с секретами (credentials.txt): " CREDENTIALS_FILE
    [ -f "$CREDENTIALS_FILE" ] || { echo "Файл $CREDENTIALS_FILE не найден" >&2; exit 1; }
    PASSWORD=$(grep -F "${USERNAME} password:" "$CREDENTIALS_FILE" | sed -E 's/^.*: //')
    if [ -z "$PASSWORD" ]; then
        echo "В $CREDENTIALS_FILE не найдена строка '${USERNAME} password: ...'" >&2
        exit 1
    fi
    echo "Пароль найден в $CREDENTIALS_FILE"
fi

USER_CHECK=$(curl -s -o /dev/null -w "%{http_code}" -u "${USERNAME}:${PASSWORD}" "https://${DOMAIN}/api/v1/user")
if [ "$USER_CHECK" = "200" ]; then
    echo "Вход выполнен успешно: $USERNAME"
else
    echo "ОШИБКА: вход не удался (HTTP $USER_CHECK)" >&2
    unset PASSWORD
    exit 1
fi

COMMIT_RESPONSE=$(curl -s -u "${USERNAME}:${PASSWORD}" "https://${DOMAIN}/api/v1/repos/review-user/demo/commits?limit=1")
unset PASSWORD

ACTUAL_HASH=$(echo "$COMMIT_RESPONSE" | grep -oP '"sha"\s*:\s*"\K[a-f0-9]+' | head -1)

if [ -z "$ACTUAL_HASH" ]; then
    echo "ОШИБКА: не удалось получить commit hash (нет доступа или репозиторий не найден)" >&2
    exit 1
fi

echo "Текущий hash последнего коммита: $ACTUAL_HASH"