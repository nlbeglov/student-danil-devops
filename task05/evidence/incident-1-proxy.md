# Инцидент 1 — неверный порт gitea в upstream caddy (`proxy`)
> Разбор по прогону 06.10.2026 (стенд `a4.fdghyt.com`), полные выводы: [Требование 4](<Требование 4.md>)

- Внесён: 01:16:10 · диагностика: 46 с · восстановление: 01:16:56–01:17:01

## Симптом
`https://a4.fdghyt.com/` отвечает 502, вход и clone не работают; контейнеры `Up`, редирект http→https работает (308).

## Гипотезы
1. Gitea не работает. 2. Caddy задания не может достучаться до Gitea (порт, имя, сеть). 3. Неверный домен или сертификат (общий Caddy). 4. Gitea не достучалась до БД.

## Проверки
```
date: 01:16:56
$ docker compose ps
SERVICE   STATUS
caddy     Up 45 seconds
db        Up 33 minutes (healthy)
server    Up 33 minutes (healthy)
$ docker compose logs --tail 3 caddy
caddy-1  | {"level":"error","ts":1791238616.2911444,"logger":"http.log.error","msg":"dial tcp 172.21.0.2:3001: connect: connection refused","request":{"remote_ip":"172.18.0.5","remote_port":"37088","client_ip":"172.18.0.5","proto":"HTTP/1.1","method":"GET","ho
caddy-1  | {"level":"error","ts":1791238616.3218882,"logger":"http.log.error","msg":"dial tcp 172.21.0.2:3001: connect: connection refused","request":{"remote_ip":"172.18.0.5","remote_port":"37088","client_ip":"172.18.0.5","proto":"HTTP/1.1","method":"GET","ho
caddy-1  | {"level":"error","ts":1791238616.3560076,"logger":"http.log.error","msg":"dial tcp 172.21.0.2:3001: connect: connection refused","request":{"remote_ip":"172.18.0.5","remote_port":"37088","client_ip":"172.18.0.5","proto":"HTTP/1.1","method":"GET","ho
$ docker compose exec server curl -fsS http://localhost:3000/api/healthz
{
  "status": "pass",
  "description": "Gitea: Git with a cup of tea",
  "checks": {
    "database:ping": [
      {
        "status": "pass",
        "time": "2026-10-05T22:16:56Z"
      }
    ],
    "cache:ping": [
      {
        "status": "pass",
        "time": "2026-10-05T22:16:56Z"
      }
    ]
  }
}$ docker compose exec caddy wget -qO- --timeout=5 http://task05-server:3000/api/healthz
{
  "status": "pass",
  "description": "Gitea: Git with a cup of tea",
  "checks": {
    "database:ping": [
      {
        "status": "pass",
        "time": "2026-10-05T22:16:56Z"
      }
    ],
    "cache:ping": [
      {
        "status": "pass",
        "time": "2026-10-05T22:16:56Z"
      }
    ]
  }
}$ docker compose exec caddy wget -qO- --timeout=5 http://task05-server:3001/api/healthz
wget: can't connect to remote host (172.21.0.2): Connection refused
$ docker compose exec caddy cat /etc/caddy/Caddyfile
{
	auto_https off
}

:80 {
	reverse_proxy task05-server:3001
}
```

## Причина и связь с симптомом
upstream Caddy задания указывает на порт `3001`, а Gitea слушает `3000`. Общий Caddy принимает HTTPS и проксирует на Caddy задания, тот отправляет запрос на закрытый порт 3001 (`connection refused`) и отвечает 502. Gitea при этом здорова (`healthz` проходит), поэтому гипотезы 1, 3, 4 отпадают.

## Исправление
`recover.sh` возвращает эталонный Caddyfile (`task05-server:3000`).

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
  OK    push выполнен: push-test-20261006-011712.txt
[7/9] Эталонная конфигурация не менялась
  OK    docker-compose.yml и Caddyfile совпадают с эталоном
[8/9] Регистрация закрыта
  OK    формы регистрации нет (HTTP 200)
[9/9] Вход администратора review-admin
  OK    review-admin вошёл и является администратором
ИТОГ: все проверки пройдены
```
