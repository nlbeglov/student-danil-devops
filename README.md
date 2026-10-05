# Практические задания по Linux и Docker Compose

Комплект из пяти заданий: Git-сервис с восстановлением, доставка и откат приложения, резервное копирование, мониторинг с уведомлениями и диагностика сбоев. Каждое задание — самостоятельный проект Docker Compose в своей папке; общие функции и подготовка сервера лежат в `common/`.

## Скачать на сервер

Одной командой на любом VPS (нужен git):
```bash
git clone https://github.com/<OWNER>/<REPO>.git /opt/devops
```
Для закрытого репозитория вместо URL используйте адрес с токеном (`https://<токен>@github.com/<OWNER>/<REPO>.git`) или deploy key.

Чистому VPS (Ubuntu/Debian) нужны Docker Engine с Compose plugin, restic (для задания 03) и файрвол с открытыми только 22, 80, 443. Если Docker ещё не установлен:
```bash
sudo /opt/devops/common/prepare-vps.sh
```
Перед запуском заданий в DNS нужны A-записи доменов на IP соответствующего VPS (иначе Caddy не получит сертификат).

## Запуск и проверка заданий

Каждое задание запускается и проверяется несколькими командами из своего README: в каталоге `taskNN/configs` создаётся `.env`, затем запускаются скрипты задания и `docker compose up -d`. Пароли генерируются скриптами `setup-secrets.sh` и сохраняются в `secrets/credentials.txt`.

| Задание | Что внутри | Команды и проверка |
|---|---|---|
| 01 | Gitea, PostgreSQL, Caddy; копия и восстановление | [task01/README.md](task01/README.md) |
| 02 | Python-сервис, GitHub Actions → GHCR → VPS, откат | [task02/README.md](task02/README.md) |
| 03 | PostgreSQL, Caddy, restic во внешнее хранилище | [task03/README.md](task03/README.md) |
| 04 | Uptime Kuma, ntfy, Nginx, Caddy на двух VPS | [task04/README.md](task04/README.md) |
| 05 | Gitea, PostgreSQL, Caddy; три воспроизводимых сбоя | [task05/README.md](task05/README.md) |

Задания 01, 02, 03 и 05 используют порты 80/443 одного VPS, поэтому включаются по очереди: перед запуском очередного остановите Caddy предыдущего (`cd /opt/devops/taskNN/configs && docker compose stop`; данные и тома сохраняются). Задание 04 живёт на двух отдельных VPS.

## Схема стенда

| Задание | Что внутри | VPS | Домен | Каталог на сервере |
| --- | --- | --- | --- | --- |
| 01 | Gitea, PostgreSQL, Caddy; резервная копия и восстановление | Senko Digital (2 vCPU / 4 GB / 60 GB) | `git.politblocks.com` | `/opt/devops/task01` |
| 02 | Python-сервис, CI/CD GitHub Actions → GHCR → VPS, откат | Senko Digital | `test0.politblocks.com` | `/opt/devops/task02` (и `/opt/task02-deploy` для доставки из CI) |
| 03 | PostgreSQL, Caddy, restic во внешнее хранилище | Senko Digital | [домен] | `/opt/devops/task03` |
| 04 | Nginx + Caddy (цель); Uptime Kuma + ntfy + Caddy (мониторинг) | Aeza (1 vCPU / 4 GB / 10 GB) и Senko Digital | `test3`, `test0`, `test1` `.politblocks.com` | `/opt/devops/task04` на каждом VPS |
| 05 | Gitea, PostgreSQL, Caddy; три воспроизводимых сбоя | Senko Digital | `git.politblocks.com` | `/opt/devops/task05` |

Структура репозитория (в каждом задании одинаково):
```
README.md  RESULT.md
common/    lib.sh, gitea.sh (небольшие общие функции), prepare-vps.sh (установка Docker и файрвол)
taskNN/
	configs/   docker-compose.yml, Caddyfile, .env.example   (рабочий .env создаётся вручную из .env.example)
	scripts/   скрипты задания (секреты, backup/restore, check.sh и т.д.)
	evidence/  команды, выводы, скриншоты
	data/ secrets/   создаются при запуске, в git не попадают
```
Задание 04 делится на каталоги по серверам (`target-vps/`, `monitor-vps/`), общая внешняя проверка — `task04/scripts/check.sh`.

## Секреты

Пароли и токены в репозиторий не попадают: `configs/.env` и `secrets/credentials.txt` создаются скриптами на сервере (права 600), в Compose используются ссылки на переменные, в `.env.example` — `CHANGE_ME`. Значения передаются проверяющему отдельно.
