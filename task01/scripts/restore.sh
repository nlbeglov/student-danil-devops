#!/usr/bin/env bash
set -euo pipefail

# ${1:?сообщение} — взять первый аргумент запуска скрипта, если его не передали скрипт остановится
PROJECT_NAME="${1:?Использование: restore.sh <project name> <project dir> <backup.tar.gz.gpg> <input|files>}"
PROJECT_DIR="${2:?Укажи директорию нового проекта}"
INPUT_ARCHIVE="${3:?Укажи местоположение архива}"
SECRET_MODE="${4:?Использование: <input|files>}"

# сразу проверяем, что режим это одно из двух ожидаемых значений
if [ "$SECRET_MODE" != "input" ] && [ "$SECRET_MODE" != "files" ]; then
  echo "Недопустимое значение режима: '$SECRET_MODE' (ожидается 'input' или 'files')" >&2
  exit 1
fi

echo "Подтвреждение данных"
echo "Название проекта:         $PROJECT_NAME"
echo "Новая директория:         $PROJECT_DIR"
echo "Входной архив:            $INPUT_ARCHIVE"
echo "Способ передачи сикретов: $SECRET_MODE"
echo ""

read -rp "Исходный проект остановлен (порты 80/443 свободны)? Введенные данные корректны? [y/N] " CONFIRM
[ "$CONFIRM" = "y" ] || { echo "Отменено."; exit 1; }

echo "Создаём новую, гарантированно уникальную временную папку"
TEMP_DIR="$(mktemp -d)"

echo "Получаем Passphrase"
if [ "$SECRET_MODE" = "input" ]; then
    read -rsp "Passphrase для расшифровки архива: " ARCHIVE_PASSPHRASE
    echo
else
    read -rp "Путь к файлу с секретами (credentials.txt): " CREDENTIALS_FILE
    [ -f "$CREDENTIALS_FILE" ] || { echo "Файл $CREDENTIALS_FILE не найден" >&2; exit 1; }
    ARCHIVE_PASSPHRASE=$(grep -F "$INPUT_ARCHIVE" "$CREDENTIALS_FILE" | sed -E 's/^.*: //')
    if [ -z "$ARCHIVE_PASSPHRASE" ]; then
        echo "В $CREDENTIALS_FILE не найдена строка с паролем для $INPUT_ARCHIVE" >&2
        exit 1
    fi
    echo "Passphrase найден в $CREDENTIALS_FILE"
fi

echo "Расшифровываем архив"
echo "$ARCHIVE_PASSPHRASE" | gpg --batch --yes --pinentry-mode loopback --passphrase-fd 0 \
  -d "$INPUT_ARCHIVE" > "$TEMP_DIR/backup.tar.gz"

echo "Стираем переменную с паролем из памяти текущего скрипта"
unset ARCHIVE_PASSPHRASE

echo "Распаковываем уже расшифрованный архив"
tar -xzf "$TEMP_DIR/backup.tar.gz" -C "$TEMP_DIR"

echo "Записываем путь до распакованных данных"
BACKUP_DATA="$TEMP_DIR/backup-tmp"

echo "Создаем папки"
mkdir -p "$PROJECT_DIR"/{gitea,postgres}

echo "Копируем существующие файлы конфигураций"
cp "$BACKUP_DATA/docker-compose.yml" "$PROJECT_DIR/"
cp "$BACKUP_DATA/Caddyfile" "$PROJECT_DIR/"

echo "Получаем env"
if [ "$SECRET_MODE" = "files" ]; then
    read -rp "Путь к готовому .env файлу: " ENV_FILE
    [ -f "$ENV_FILE" ] || { echo "Файл $ENV_FILE не найден" >&2; exit 1; }
    cp "$ENV_FILE" "$PROJECT_DIR/.env"
else
    echo ""
    echo "Введите значения для .env:"
        # читаем .env.example построчно; IFS='=' разбивает строку по знаку "="
    # на KEY и остаток строки (VALUE_DEFAULT нам не нужен, но переменная
    # обязана быть, иначе read возьмёт остаток строки в KEY)
    while IFS='=' read -r KEY VALUE_DEFAULT <&3 || [ -n "$KEY" ]; do
        [ -z "$KEY" ] && continue
        case "$KEY" in
            \#*) continue ;;   # пропускаем строки-комментарии, если такие есть
        esac
        # для полей с паролем — скрытый ввод, как для passphrase выше
        case "$KEY" in
            *PASSWORD*|*PASSWD*)
                read -rsp "  $KEY: " VALUE
                echo
                ;;
            *)
                read -rp "  $KEY: " VALUE
                ;;
        esac
        echo "${KEY}=${VALUE}" >> "$PROJECT_DIR/.env"
    done 3< "$BACKUP_DATA/.env.example"
fi
# фиксируем введеное имя проекта
echo "PROJECT_NAME=${PROJECT_NAME}" >> "$PROJECT_DIR/.env"

chmod 600 "$PROJECT_DIR/.env"

cd "$PROJECT_DIR"
source .env

echo "Поднимаем только PostgreSQL"
docker compose -p "$PROJECT_NAME" up -d db
sleep 5

echo "Восстанавливаем дамп"
docker compose -p "$PROJECT_NAME" exec -T db pg_restore -U "$POSTGRES_USER" -d "$POSTGRES_DB" --clean --if-exists --no-owner < "$BACKUP_DATA/gitea_db.dump"

echo "Распаковываем файлы Gitea в новый том"
tar -xzf "$BACKUP_DATA/gitea-data.tar.gz" -C "$PROJECT_DIR"

echo "Запускаем Gitea и Caddy"
docker compose -p "$PROJECT_NAME" up -d server caddy

rm -rf "$TEMP_DIR"

echo ""
echo "Восстановление завершено"
docker compose -p "$PROJECT_NAME" ps