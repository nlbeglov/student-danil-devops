# 05. Диагностика эксплуатационных сбоев

Gitea · PostgreSQL · Caddy · Docker Compose. Рабочий стенд с данными и три воспроизводимых сбоя, для каждого из которых показаны диагностика, исправление и проверка сохранности данных.

## Схема сервисов

Один VPS: Senko Digital (Хельсинки, Финляндия), 2 vCPU / 4 GB RAM / disk: 60 GB. Compose-проект `task05`, домен `a4.fdghyt.com`; HTTPS обслуживает общий Caddy (`common/caddy`).

```
Интернет ─► общий Caddy :80/:443 ──(сеть edge)──► caddy задания :80 ──► server (Gitea) :3000 ──► db (PostgreSQL) :5432
```

| Сервис | Образ | Назначение |
|---|---|---|
| caddy | `caddy:2.11.4` | собственный Caddy задания: по HTTP внутри сети, проксирует на `task05-server:3000` (его upstream ломает сбой `proxy`); порты наружу не публикует |
| общий Caddy | `caddy:2.11.4` | `common/caddy`: HTTPS и редирект для `a4.fdghyt.com`, проксирует на `task05-caddy:80` |
| server | `docker.gitea.com/gitea:1.27.3` | Gitea; регистрация закрыта (`DISABLE_REGISTRATION=true`) |
| db | `postgres:14` | база Gitea, только во внутренней сети Compose |

Данные хранятся в bind-mount `data/gitea` и `data/postgres` и сохраняются между перезапусками и перезагрузками VPS.

Структура каталога:
```
task05/
	configs/   docker-compose.yml, .env.example, Caddyfile, faults/ (override-файлы трёх сбоев)
	scripts/   setup-secrets.sh, deploy.sh, prepare-demo.sh, fault.sh, recover.sh, check.sh, lib.sh
	evidence/  подтверждения по требованиям, журналы опытов, разборы инцидентов
```

## Порты

| Порт | Назначение | Доступность |
|---|---|---|
| 22 | SSH к VPS | публично |
| 80 | HTTP → редирект на HTTPS (Caddy) | публично |
| 443 | HTTPS (Caddy → Gitea) | публично |
| 3000 | Gitea (внутри контейнера) | только внутренняя сеть Compose |
| 5432 | PostgreSQL | только внутренняя сеть Compose |

Порты 3000 и 5432 наружу не публикуются. Проверка с внешней сети: `curl -v --max-time 5 http://a4.fdghyt.com:3000/` завершается таймаутом без ответа (одного `nc -zv` недостаточно: сеть может принять рукопожатие на любой порт).

## Команды запуска и проверки

Репозиторий склонирован на сервер в `/opt/devops` (корневой [README](../README.md)), Docker установлен (`sudo ../common/prepare-vps.sh`), Docker установлен. Общий Caddy (`../common/caddy`) уже запущен (корневой [README](../README.md)), сеть `edge` создана, A-запись `a4.fdghyt.com` указывает на VPS.

Первый запуск:
```bash
cd /opt/devops/task05/configs
cp .env.example .env && nano .env        # DOMAIN=a4.fdghyt.com
../scripts/setup-secrets.sh              # пароли → secrets/credentials.txt, POSTGRES_PASSWORD → .env (до первого запуска стека)
../scripts/deploy.sh                     # поднять стек
../scripts/prepare-demo.sh               # review-admin, review-user, закрытый репозиторий demo, 2 коммита, эталон
```

Контрольные проверки:
```bash
../scripts/check.sh                      # проверки на чтение
../scripts/check.sh push                 # то же и новый push с отдельным файлом
```

Проверка по требованиям (команды, вывод, скриншоты):

| Требование | Что показано | Файл |
|---|---|---|
| 1 | развёртывание стенда, пользователи, закрытый репозиторий, clone/push, анонимный отказ | [Требование 1](<evidence/Требование 1.md>) |
| 2 | эталон (hash коммита, SHA-256 `check.txt`), перезагрузка VPS | [Требование 2](<evidence/Требование 2.md>) |
| 3 | три сбоя как override-файлы | [Требование 3](<evidence/Требование 3.md>) |
| 4 | диагностика трёх сбоев | [Требование 4](<evidence/Требование 4.md>) |
| 5 | проверки после каждого исправления | [Требование 5](<evidence/Требование 5.md>) |
| 6 | скрипты, журнал опытов, время диагностики | [Требование 6](<evidence/Требование 6.md>) |

## Сбои и их восстановление

Сбои вносятся командой `./scripts/fault.sh <сбой>` (только один за раз), исправляются `./scripts/recover.sh` (данные сохраняются).

| Сбой | Команда | Что ломается | Симптом | Разбор |
|---|---|---|---|---|
| Неверный порт Gitea в upstream Caddy | `fault.sh proxy` | связь Caddy → Gitea | 502, контейнеры `Up`, в логах Caddy `connection refused` на `task05-server:3001` | [incident-1-proxy.md](evidence/incident-1-proxy.md) |
| Неверное имя хоста PostgreSQL в настройках Gitea | `fault.sh database` | связь Gitea → БД | 502, `server` в `health: starting`, в логах `no such host` | [incident-2-database.md](evidence/incident-2-database.md) |
| Том данных Gitea только для чтения | `fault.sh readonly` | запись Gitea на диск | 502, в логах `Read-only file system` | [incident-3-readonly.md](evidence/incident-3-readonly.md) |

## Зависимости от common
Скрипты самостоятельны (общие функции в `scripts/lib.sh`); подготовку VPS выполняет `../common/prepare-vps.sh`. Порты 80/443 занимает только общий Caddy, поэтому задания работают одновременно (у задания 01 домен `a1.fdghyt.com`, у задания 05 — `a4.fdghyt.com`).

## Ручные действия
- DNS: A-запись домена на IP VPS.
- Файрвол (ufw): снаружи только 22 (SSH), 80, 443.
- Создание `configs/.env` из `.env.example` на сервере.
- Запуск `setup-secrets.sh`, `deploy.sh`, `prepare-demo.sh`. Пароли генерируются и сохраняются в `secrets/credentials.txt` (права 600, вне git), значения передаются проверяющему отдельно.
- Опыты: `fault.sh`, диагностика по логам и состоянию, `recover.sh`, `check.sh push`.
- Перезагрузка VPS для проверки сохранности данных (требование 2).
