# 03. Резервное копирование БД и файлов

PostgreSQL · Caddy (общий) · pg_dump · restic. Учебная БД и каталог файлов, регулярное копирование во внешнее SFTP-хранилище, восстановление в отдельный проект при остановленном исходном.

## Схема сервисов

Один VPS, Compose-проект `task03`; внешнее хранилище restic — отдельный сервер по SFTP.

```
Интернет ─► общий Caddy :80/:443 ──► data/files (a.txt, b.txt, c.txt)   db (PostgreSQL) :5432 — только сеть Compose
backup.sh ─► pg_dump + файлы + настройки ─► restic ─► SFTP-хранилище вне VPS
```

| Сервис | Образ | Назначение |
|---|---|---|
| db | `postgres:14` | БД `lab`, таблица `items` (100 строк), данные в `data/postgres` |
| общий Caddy | `caddy:2.11.4` | HTTPS для `a3.fdghyt.com`, выдача файлов из `task03/data/files` (`common/caddy`) |
| restic | пакет ОС | копии во внешнее хранилище (зашифрованный репозиторий) |

Структура каталога:
```
task03/
	configs/   docker-compose.yml (только PostgreSQL), 01-items.sql, .env.example
	scripts/   setup-storage.sh, setup-secrets.sh, restic-init.sh, prepare-data.sh, manifest.sh, backup.sh,
	           restore.sh, check.sh, install-timer.sh, lib.sh
	systemd/   task03-backup.service, task03-backup.timer (шаблоны)
	evidence/  подтверждения по требованиям, backup.log, manifest-original.txt
	data/      (создаётся при запуске) postgres/, files/
	secrets/   (создаётся при запуске) credentials.txt: пароль PostgreSQL, ключ restic
```

## Порты

| Порт | Назначение | Доступность |
|---|---|---|
| 22 | SSH | публично |
| 80 | HTTP → редирект на HTTPS (общий Caddy) | публично |
| 443 | HTTPS (общий Caddy, файлы) | публично |
| 5432 | PostgreSQL | только внутренняя сеть Compose |

## Команды запуска и проверки

Репозиторий склонирован на сервер в `/opt/devops` (корневой [README](../README.md)), Docker и restic установлены (`sudo ../common/prepare-vps.sh`), есть SFTP-хранилище с SSH-доступом. Общий Caddy (`../common/caddy`) уже запущен (см. корневой [README](../README.md)), сеть `edge` создана, A-запись `a3.fdghyt.com` указывает на VPS.

Первый запуск:
```bash
cd /opt/devops/task03/configs
cp .env.example .env && nano .env        # DOMAIN=a3.fdghyt.com, RESTIC_REPOSITORY=sftp:user@host:/path
../scripts/setup-storage.sh user@host    # один раз: SSH-ключ и доступ к хранилищу без пароля
../scripts/setup-secrets.sh              # пароль PostgreSQL → .env, ключ restic → secrets/credentials.txt
docker compose up -d
../scripts/prepare-data.sh               # a.txt, b.txt, c.txt и исходный manifest
../scripts/restic-init.sh                # инициализация зашифрованного репозитория
curl -s https://<DOMAIN>/a.txt           # alpha
```

Копии и расписание:
```bash
../scripts/backup.sh                     # ручной запуск; тот же скрипт запускает таймер
sudo ../scripts/install-timer.sh daily   # ежедневно в 03:15 (test — каждую минуту, только для проверки расписания)
tail -n 20 ../evidence/backup.log        # журнал; код завершения: 0 успех, 1 ошибка, 2 уже выполняется
```
Четыре успешных копии подряд (`for i in 1 2 3 4; do ../scripts/backup.sh; done`) оставляют в репозитории три последних снимка.

Восстановление и проверка (исходный проект остановлен):
```bash
docker compose stop
../scripts/restore.sh                    # проект task03-restore в ../restore, новые тома, данные из restic
../scripts/check.sh                      # manifest, файлы, запись id=101, ошибка доступа к хранилищу
(cd ../restore/configs && docker compose stop)   # остановить копию
docker compose up -d                     # основной стенд снова запущен
```
Если исходного проекта на VPS уже нет: `RESTIC_REPOSITORY=... RESTIC_PASSWORD=... ../scripts/restore.sh <каталог>`.

Подтверждения по требованиям (команды, вывод):

| Требование | Что показано | Файл |
|---|---|---|
| 1 | PostgreSQL, Caddy, таблица `items` | [Требование 1](<evidence/Требование 1.md>) |
| 2 | файлы и исходный manifest | [Требование 2](<evidence/Требование 2.md>) |
| 3 | pg_dump + restic во внешнее хранилище | [Требование 3](<evidence/Требование 3.md>) |
| 4 | расписание, блокировка, журнал, 3 снимка | [Требование 4](<evidence/Требование 4.md>) |
| 5 | восстановление из внешнего хранилища | [Требование 5](<evidence/Требование 5.md>) |
| 6 | сравнение manifest, `id=101`, ошибка доступа | [Требование 6](<evidence/Требование 6.md>) |

## Зависимости от common
Скрипты подключают `../common/lib.sh` (работа с `.env`, пароли, проверки); пакеты `restic`, `python3` и ufw ставит `../common/prepare-vps.sh`. HTTPS и выдачу файлов обслуживает общий Caddy из `../common/caddy` (он монтирует `task03/data/files`); проект Compose порты 80/443 не занимает, восстановленный проект тоже работает без Caddy.

## Ручные действия
- DNS: A-запись домена на IP VPS.
- Заполнить `DOMAIN` и `RESTIC_REPOSITORY` в `configs/.env`.
- Внешнее SFTP-хранилище (отдельный сервер) и `./scripts/setup-storage.sh user@host` (понадобится пароль хранилища один раз).
- Сохранить `RESTIC_PASSWORD` из `secrets/credentials.txt` отдельно от VPS и передать проверяющему закрытым способом.
- Временное сокращение интервала для проверки расписания (`sudo ./scripts/install-timer.sh test`) и возврат к ежедневному (`daily`).
- Проверка ошибки доступа к хранилищу выполняется внутри `check.sh` (неверный пароль передаётся одним запуском).
