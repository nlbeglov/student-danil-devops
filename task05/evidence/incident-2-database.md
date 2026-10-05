# Инцидент 2 — неверное имя хоста PostgreSQL (`database`)
- Внесён: 2026-10-04 09:37:56 · Причина установлена: ≈ 09:41 · Диагностика: ≈ 3 мин 52 с
- Полные выводы: [Требование 4](<Требование 4.md>), журналы [до](incident-2-before.txt) / [во время](incident-2-during.txt) / [после](incident-2-after.txt)

## Симптом
HTTPS, API, вход и clone дают 502. В `docker compose ps` у `server` статус `health: starting` и время «только что создан»; `db` и `caddy` в порядке.

## Гипотезы
1. Gitea не запускается из-за БД (имя хоста, порт, пароль). 2. Сломан DNS. 3. БД не запущена. 4. Повреждены данные.

## Проверки
**Логи Gitea:**
```
InitDBEngine() [E] ORM engine initialization attempt #1/10 failed. Error: dial tcp: lookup postgres-db on 127.0.0.11:53: no such host
InitDBEngine() [I] Backing off for 3 seconds
```
Gitea ищет хост `postgres-db` и не находит его; повторяет попытки.

**Жива ли БД** (`pg_isready`): `/var/run/postgresql:5432 - accepting connections`. Гипотеза 3 отвергнута.

**Имя хоста в настройках Gitea:** `GITEA__database__HOST=postgres-db:5432`.

**DNS в сети Compose:** `nslookup db` → `172.24.0.4`; `nslookup postgres-db` → `NXDOMAIN`. Гипотеза 2 отвергнута: DNS работает, но такого имени нет.

## Причина
В настройках Gitea неверное имя хоста БД (`postgres-db`), реальный сервис называется `db`.

## Связь ошибка → симптом
При старте Gitea обращается к БД по имени из настроек. DNS Docker не знает такого имени, подключение невозможно, Gitea не поднимает веб-сервер, и Caddy при запросах получает отказ и отвечает 502.

## Исправление
`./scripts/recover.sh`: `server` пересоздан со значением `db:5432`. Данные PostgreSQL не затрагивались.

## Контрольные проверки
[incident-2-after.txt](incident-2-after.txt): HTTPS 200, вход 200, clone, исходный коммит и сумма `check.txt` совпадают (данные целы), новый push `push-test-20261004-094155.txt`, анонимный доступ закрыт.
