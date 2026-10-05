# Инцидент 3 — том данных gitea подключён только для чтения (`readonly`)
> Разбор по прогону 06.10.2026 (стенд `a4.fdghyt.com`), полные выводы: [Требование 4](<Требование 4.md>)

- Внесён: 01:18:18 · диагностика: 46 с · восстановление: 01:19:04–01:19:16

## Симптом
`https://a4.fdghyt.com/` отвечает 502; у `server` статус `health: starting`.

## Гипотезы
1. Caddy не достучался до Gitea. 2. Gitea не стартует из-за БД. 3. Gitea не может писать на диск (права, том только для чтения, нет места).

## Проверки
```
date: 01:19:04
$ docker compose ps
SERVICE   STATUS
caddy     Up About a minute
db        Up 35 minutes (healthy)
server    Up 2 seconds (health: starting)
$ docker compose logs --tail 4 server
server-1  | 2026/10/05 22:19:01 modules/storage/storage.go:270:initActions() [I] Initialising Actions storage with type: local
server-1  | 2026/10/05 22:19:01 modules/storage/local.go:48:NewLocalStorage() [I] Creating new Local Storage at /data/gitea/actions_log
server-1  | 2026/10/05 22:19:01 modules/storage/storage.go:274:initActions() [I] Initialising ActionsArtifacts storage with type: local
server-1  | 2026/10/05 22:19:01 modules/storage/local.go:48:NewLocalStorage() [I] Creating new Local Storage at /data/gitea/actions_artifacts
$ docker inspect: монтирование /data
source=/opt/devops/task05/data/gitea rw=false mode=ro
$ docker compose exec server touch /data/write-test
touch: /data/write-test: Read-only file system
```

## Причина и связь с симптомом
том `/data` смонтирован только для чтения (`:ro`). Gitea при старте создаёт каталоги и пишет ключи, конфигурацию и журналы в `/data`; запись невозможна (`Read-only file system`), Gitea не становится здоровой, Caddy получает отказ и отвечает 502.

## Исправление
`recover.sh` пересоздаёт `server` с эталонным томом (`rw`).

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
  OK    push выполнен: push-test-20261006-011927.txt
[7/9] Эталонная конфигурация не менялась
  OK    docker-compose.yml и Caddyfile совпадают с эталоном
[8/9] Регистрация закрыта
  OK    формы регистрации нет (HTTP 200)
[9/9] Вход администратора review-admin
  OK    review-admin вошёл и является администратором
ИТОГ: все проверки пройдены
```
