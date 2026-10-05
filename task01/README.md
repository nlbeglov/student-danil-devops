# 01. Git-сервис и восстановление

Gitea, PostgreSQL и Caddy в Docker Compose; согласованная зашифрованная копия и восстановление в отдельном проекте с новыми томами.

## Схема сервисов

Docker Compose проект из трёх сервисов на одном VPS:

- **caddy** (`caddy:2.11.4`) reverse proxy, терминирует HTTPS, редирект с HTTP;
- **server** (`docker.gitea.com/gitea:1.27.3`) Gitea, Git-сервис, регистрация закрыта;
- **db** (`postgres:14`) база данных Gitea.

Данные хранятся в `data/gitea` и `data/postgres` (рядом с `configs/`, в git не попадают).

Структура каталога:
```
task01/
	configs/   docker-compose.yml, Caddyfile, .env.example
	scripts/   setup-secrets.sh, seed.sh, user-create.sh, backup.sh, restore.sh, check.sh
	evidence/  подтверждения по требованиям
	data/      (создаётся при запуске) данные Gitea и PostgreSQL
	secrets/   (создаётся при запуске) credentials.txt: пароли, пароли архивов
	backups/   (создаётся backup.sh) зашифрованные копии
```

## Порты

| Порт | Назначение | Доступность |
| ---- | ---------- | ------------------------------ |
| 22   | SSH        | публично |
| 80   | HTTP → редирект на HTTPS (Caddy) | публично |
| 443  | HTTPS (Caddy → Gitea) | публично |
| 3000 | Gitea      | только внутренняя сеть Compose |
| 5432 | PostgreSQL | только внутренняя сеть Compose |

## Команды запуска и проверки

Репозиторий склонирован на сервер в `/opt/devops` (корневой [README](../README.md)), Docker установлен, A-запись домена указывает на VPS. Если на 80/443 работает стенд другого задания, сначала остановите его (`cd ../taskNN/configs && docker compose stop`).

Первый запуск:
```bash
cd /opt/devops/task01/configs
cp .env.example .env && nano .env        # DOMAIN
../scripts/setup-secrets.sh              # пароль PostgreSQL → .env и secrets/credentials.txt (до первого запуска)
docker compose up -d
docker compose ps
../scripts/seed.sh                       # review-admin, review-user, закрытый репозиторий demo с двумя коммитами
```
Дополнительный пользователь (интерактивно): `../scripts/user-create.sh`.

Проверка (контейнеры, автозапуск, данные, HTTPS, анонимный 404, вход, clone, hash коммита):
```bash
../scripts/check.sh                      # для восстановленной копии: ../scripts/check.sh /opt/task01-restore files
```

Резервная копия и восстановление:
```bash
# остановка записи → дамп → файлы → конфигурация → шифрование gpg; копия лежит в backups/
../scripts/backup.sh
# (необязательно) сразу скопировать вне VPS: BACKUP_REMOTE=user@host:/path ../scripts/backup.sh

# восстановление в отдельный проект с новыми томами; исходный проект остановлен
docker compose stop
../scripts/restore.sh task01-restore /opt/task01-restore ../backups/backup-<время>.tar.gz.gpg files
../scripts/check.sh /opt/task01-restore files
docker compose up -d                     # основной стенд снова запущен (восстановленный: cd /opt/task01-restore/configs && docker compose stop)
```
Режим секретов `input` — пароль архива и значения `.env` вводятся с клавиатуры, `files` — пароль берётся из `credentials.txt`, значения `.env` из готового файла (по умолчанию `secrets/credentials.txt` и `configs/.env` этого проекта; другие пути — переменными `CREDENTIALS_FILE`, `ENV_FILE`; `ASSUME_YES=1` убирает вопрос подтверждения). Если исходного VPS уже нет, возьмите с собой архив, `credentials.txt` (или пароль архива) и `.env`.

Подтверждения по требованиям (команды, вывод, скриншоты):

| Требование | Что показано | Файл |
|---|---|---|
| 1 | развёртывание Gitea, PostgreSQL, Caddy | [Требование 1](<evidence/Требование 1.md>) |
| 2 | пользователи, репозиторий `demo`, hash | [Требование 2](<evidence/Требование 2.md>) |
| 3 | clone/push, анонимный отказ, порты | [Требование 3](<evidence/Требование 3.md>) |
| 4 | резервная копия | [Требование 4](<evidence/Требование 4.md>) |
| 5 | восстановление в отдельном проекте | [Требование 5](<evidence/Требование 5.md>) |
| 6 | скрипты, проверка после перезагрузки | [Требование 6](<evidence/Требование 6.md>) |

## Зависимости от common
Скрипты подключают `../common/lib.sh` и `../common/gitea.sh` (общие функции: `.env`, пароли, запросы к API Gitea). Подготовка чистого VPS (Docker, ufw) — `sudo ../common/prepare-vps.sh`. Caddy задания обслуживает только домен Gitea; порты 80/443 делят все задания одного VPS, поэтому стенды включаются по очереди.

## Ручные действия
- DNS: A-запись домена на IP VPS (до запуска, иначе Caddy не получит сертификат).
- Заполнить `DOMAIN` в `configs/.env`.
- Скопировать архив из `backups/` на другой компьютер, пароль архива из `secrets/credentials.txt` передать отдельным каналом.
- Перезагрузка VPS для проверки сохранности данных (требование 6).
