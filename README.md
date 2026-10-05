# Практические задания по Linux и Docker Compose

Комплект из пяти заданий: Git-сервис с восстановлением, доставка и откат приложения, резервное копирование, мониторинг с уведомлениями и диагностика сбоев. Каждое задание — самостоятельный проект Docker Compose в своей папке; общие функции и подготовка сервера лежат в `common/`.

## Скачать на сервер
Установить гит, если еще нет
```
apt update && apt install -y git
```
Одной командой на любом VPS:
```bash
git clone https://github.com/nlbeglov/student-danil-devops.git /opt/devops
```

Чистому VPS (Ubuntu/Debian) нужны Docker Engine с Compose plugin, restic (для задания 03) и файрвол с открытыми только 22, 80, 443. Если Docker ещё не установлен:
```bash
sudo /opt/devops/common/prepare-vps.sh
```
Перед запуском заданий в DNS нужны A-записи доменов на IP соответствующего VPS (иначе Caddy не получит сертификат).

## Общий Caddy (один раз на основном VPS)

Все сайты основного VPS (144.31.119.139) обслуживает один Caddy из `common/caddy`: он единственный занимает порты 80/443, сам получает сертификаты и проксирует каждый домен в нужное задание через общую сеть Docker `edge`. Поэтому задания работают одновременно, а их собственные compose-проекты порты 80/443 не публикуют.

```bash
docker network create edge
cd /opt/devops/common/caddy
cp .env.example .env && nano .env     # домены (по умолчанию уже a1…a6, danil1 — см. таблицу ниже)
docker compose up -d
```
После изменения `Caddyfile`: `docker compose exec caddy caddy reload --config /etc/caddy/Caddyfile`. Если задание ещё не запущено, его домен отвечает 502, остальные работают. Старые Caddy заданий и контейнеры, занимающие 80/443, перед запуском общего нужно остановить.

| Домен | Куда ведёт | Задание |
|---|---|---|
| a1.fdghyt.com | `task01-gitea:3000` | 01, Gitea |
| danil1.fdghyt.com | `task01-restore-gitea:3000` | 01, восстановленная копия |
| a2.fdghyt.com | `task02-app:8000` | 02, Python-сервис |
| a3.fdghyt.com | файлы `task03/data/files` | 03 |
| a4.fdghyt.com | `task05-caddy:80` | 05, Gitea |
| a5.fdghyt.com | `task04-kuma:3001` | 04, Uptime Kuma |
| a6.fdghyt.com | `task04-ntfy:80` | 04, ntfy |
| danil2.fdghyt.com | VPS 130.17.27.121 | 04, цель мониторинга (свой Caddy в `task04/target-vps`) |

A-записи: все домены кроме `danil2` указывают на 144.31.119.139, `danil2` — на 130.17.27.121.

## Запуск и проверка заданий

Каждое задание запускается и проверяется несколькими командами из своего README: в каталоге `taskNN/configs` создаётся `.env`, затем запускаются скрипты задания и `docker compose up -d`. Пароли генерируются скриптами `setup-secrets.sh` и сохраняются в `secrets/credentials.txt`. Порядок на основном VPS: Docker → сеть `edge` и общий Caddy → задания в любом порядке.

| Задание | Что внутри | Команды и проверка |
|---|---|---|
| 01 | Gitea, PostgreSQL; копия и восстановление | [task01/README.md](task01/README.md) |
| 02 | Python-сервис, GitHub Actions → GHCR → VPS, откат | [task02/README.md](task02/README.md) |
| 03 | PostgreSQL, раздача файлов, restic во внешнее хранилище | [task03/README.md](task03/README.md) |
| 04 | Uptime Kuma, ntfy, Nginx, Caddy на двух VPS | [task04/README.md](task04/README.md) |
| 05 | Gitea, PostgreSQL, Caddy; три воспроизводимых сбоя | [task05/README.md](task05/README.md) |

## Схема стенда

| Задание | Что внутри | VPS | Домен | Каталог на сервере |
| --- | --- | --- | --- | --- |
| 01 | Gitea, PostgreSQL; резервная копия и восстановление | основной VPS 144.31.119.139 (Senko Digital, 2 vCPU / 4 GB / 60 GB) | `a1.fdghyt.com`, копия — `danil1.fdghyt.com` | `/opt/devops/task01` |
| 02 | Python-сервис, CI/CD GitHub Actions → GHCR → VPS, откат | основной VPS | `a2.fdghyt.com` | `/opt/devops/task02` (и `/opt/task02-deploy` для доставки из CI) |
| 03 | PostgreSQL, раздача файлов, restic во внешнее хранилище | основной VPS | `a3.fdghyt.com` | `/opt/devops/task03` |
| 04 | Nginx + Caddy (цель, VPS 130.17.27.121); Uptime Kuma + ntfy (мониторинг, основной VPS) | основной VPS и второй VPS 130.17.27.121 | `danil2`, `a5`, `a6` `.fdghyt.com` | `/opt/devops/task04` на каждом VPS |
| 05 | Gitea, PostgreSQL, Caddy задания; три воспроизводимых сбоя | основной VPS | `a4.fdghyt.com` | `/opt/devops/task05` |

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
