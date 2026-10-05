# Инцидент 2 — неверное имя хоста postgresql в настройках gitea (`database`)
> Разбор по прогону 06.10.2026 (стенд `a4.fdghyt.com`), полные выводы: [Требование 4](<Требование 4.md>)

- Внесён: 01:17:14 · диагностика: 46 с · восстановление: 01:18:00–01:18:06

## Симптом
`https://a4.fdghyt.com/` отвечает 502; у `server` статус `health: starting`, контейнеры `Up`.

## Гипотезы
1. Caddy не достучался до Gitea. 2. Gitea не стартует: не может подключиться к БД (имя, пароль, сеть). 3. Проблема в данных Gitea (права, том). 4. Не работает сам PostgreSQL.

## Проверки
```
date: 01:17:59
$ docker compose ps
SERVICE   STATUS
caddy     Up About a minute
db        Up 34 minutes (healthy)
server    Up 17 seconds (health: starting)
$ docker compose logs --tail 4 server
server-1  | 2026/10/05 22:17:58 routers/common/db.go:29:InitDBEngine() [I] ORM engine initialization attempt #6/10...
server-1  | 2026/10/05 22:17:58 cmd/web.go:205:serveInstalled() [I] PING DATABASE postgres
server-1  | 2026/10/05 22:17:58 routers/common/db.go:35:InitDBEngine() [E] ORM engine initialization attempt #6/10 failed. Error: dial tcp: lookup postgres-db on 127.0.0.11:53: no such host
server-1  | 2026/10/05 22:17:58 routers/common/db.go:36:InitDBEngine() [I] Backing off for 3 seconds
$ docker compose exec server getent hosts postgres-db
rc=2
$ docker compose exec server getent hosts db
172.21.0.3        db  db
$ docker compose exec db pg_isready -h 127.0.0.1
127.0.0.1:5432 - accepting connections
$ docker compose exec server env | grep GITEA__database__HOST
GITEA__database__HOST=postgres-db:5432
```

## Причина и связь с симптомом
у Gitea неверное имя хоста БД `postgres-db` (в сети Compose БД называется `db`). Gitea не может разрешить имя БД через DNS Docker (`lookup postgres-db ... no such host`), не завершает инициализацию и не поднимает веб-сервер, поэтому Caddy получает отказ и отвечает 502. PostgreSQL при этом принимает соединения (`pg_isready`), значит проблема в настройке Gitea.

## Исправление
`recover.sh` пересоздаёт `server` из эталонного `docker-compose.yml` (`GITEA__database__HOST=db:5432`).

## Проверка после исправления
```
[1/9] Контейнеры
  OK    запущено 3 из 3
[2/9] HTTPS и редирект
  OK    https://a4.fdghyt.com/ -> 200
  OK    http -> редирект 308
[3/9] Закрытый репозиторий недоступен без авторизации
  OK    анонимный API -> 404
  OK    анонимный clone отклонён
[4/9] Вход пользователя review-user
  OK    вход выполнен (API /user -> 200)
[5/9] Clone, исходный коммит и контрольная сумма check.txt
  OK    clone выполнен
  OK    исходный коммит в истории: b5d32d9e96d30988d5a3322a6fd0e0ceebcdbea3
  OK    SHA-256 check.txt совпадает: 7e7733ff0982d931645c43e95712b0ae5e0eae27993a1815913d23fa42fbef29
[6/9] Новый push с отдельным файлом
  OK    push выполнен: push-test-20261006-011817.txt
[7/9] Эталонная конфигурация не менялась
  OK    docker-compose.yml и Caddyfile совпадают с эталоном
[8/9] Регистрация закрыта
  OK    формы регистрации нет (HTTP 200)
[9/9] Вход администратора review-admin
  OK    review-admin вошёл и является администратором
ИТОГ: все проверки пройдены
```
