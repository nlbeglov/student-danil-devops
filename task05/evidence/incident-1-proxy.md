# Инцидент 1 — неверный порт Gitea в upstream Caddy (`proxy`)
- Внесён: 2026-10-04 07:51:29 · Причина установлена: ≈ 07:55 · Диагностика: ≈ 3 мин 50 с
- Полные выводы: [Требование 4](<Требование 4.md>), журналы [до](incident-1-before.txt) / [во время](incident-1-during.txt) / [после](incident-1-after.txt)

## Симптом
`https://git.politblocks.com/` отвечает 502, вход и clone не работают. Все три контейнера `Up`, редирект http→https работает (308).

## Гипотезы
1. Gitea не работает. 2. Caddy не может достучаться до Gitea (порт, имя, сеть). 3. Неверный домен или сертификат. 4. Gitea не достучалась до БД.

## Проверки
**Логи Caddy:**
```
dial tcp 172.24.0.2:3001: connect: connection refused
```
Caddy пытается подключиться к порту 3001.

**Жива ли Gitea** (`docker compose exec server curl -fsS http://localhost:3000/api/healthz`): `"status": "pass"`, `database:ping` = `pass`. Гипотезы 1 и 4 отвергнуты.

**Доступность из контейнера Caddy:** `wget http://server:3000/api/healthz` отвечает `pass`; `wget http://server:3001/...` → `Connection refused`. Имя `server` разрешается (172.24.0.2), порт 3001 закрыт; гипотеза 3 отвергнута, так как HTTPS принят и 502 отдаёт сам Caddy.

**Конфигурация, которую читает Caddy** (`cat /etc/caddy/Caddyfile`): `reverse_proxy server:3001`.

## Причина
В Caddyfile upstream указан на порт 3001, а Gitea слушает 3000.

## Связь ошибка → симптом
Caddy принимает HTTPS-запрос, пытается проксировать его на порт 3001, где никто не слушает, соединение отклоняется, и клиент получает 502.

## Исправление
`./scripts/recover.sh`: Caddy пересоздан с эталонным Caddyfile (`server:3000`), данные не затрагивались.

## Контрольные проверки
[incident-1-after.txt](incident-1-after.txt): HTTPS 200, вход 200, clone, исходный коммит и сумма `check.txt` совпадают, новый push `push-test-20261004-075533.txt`, анонимный доступ закрыт.
