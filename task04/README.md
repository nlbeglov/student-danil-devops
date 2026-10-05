# 04. Мониторинг и уведомления

Uptime Kuma · ntfy · Nginx · Caddy. Наблюдение за HTTP-сервисом и доставка уведомлений; различие между ошибкой приложения (HTTP 503) и недоступностью всего сервера.

## Схема сервисов

1. AEZA (Хельсинки, Финляндия) 1 vCPU / 4GB RAM / disk: 10GB
Наименования: VPS-A, первый VPS, **target vps**

IP 130.17.27.121. Домен:
- danil2.fdghyt.com  (цель мониторинга)

Сервисы:
- caddy :80/:443 (свой, в `target-vps`)
- nginx :80 /health (200 | 503)

2. Senko Digital (Хельсинки, Финляндия) 2 vCPU / 4GB RAM / disk: 60GB
Наименования: VPS-B, второй VPS, **monitor vps**

Это основной VPS (144.31.119.139), на нём же работают задания 01, 02, 03 и 05. Домены:
- a5.fdghyt.com (Kuma)
- a6.fdghyt.com  (ntfy)

Сервисы:
- общий Caddy :80/:443 (`common/caddy`) проксирует домены на Kuma и ntfy через сеть `edge`
- uptime-kuma :3001 (внутр. сеть)
- ntfy :80
Kuma отправляет уведомления в ntfy по внутренней сети Compose

Структура каталога. Для каждого VPS своя папка с одинаковым устройством

```
task04/
	scripts/   check.sh (проверка стенда снаружи)
	target-vps/
		configs/   docker-compose.yml, Caddyfile, nginx/, .env.example
		scripts/   deploy-target.sh, set-health.sh
	monitor-vps/
		configs/   docker-compose.yml, .env.example
		scripts/   deploy-monitor.sh, setup-secrets.sh
	evidence/
```

## Порты

| Порт | VPS | Назначение | Доступность |
|---|---|---|---|
| 22 | оба | SSH | публично |
| 80 | оба | HTTP → редирект на HTTPS (Caddy: на VPS-A свой, на VPS-B общий) | публично |
| 443 | оба | HTTPS (Caddy: на VPS-A свой, на VPS-B общий) | публично |
| 80 (nginx) | target-vps | nginx `/health` | только внутренняя сеть Compose |
| 3001 | monitor-vps | Uptime Kuma | только внутренняя сеть Compose |
| 80 (ntfy) | monitor-vps | ntfy | только внутренняя сеть Compose |

## Команды запуска и проверки

Репозиторий склонирован на оба сервера в `/opt/devops` (корневой [README](../README.md)), на каждом установлен Docker (`sudo ../common/prepare-vps.sh`), A-записи доменов указывают на нужные VPS. На VPS-B до `deploy-monitor.sh` запущен общий Caddy (`common/caddy`, корневой README) и создана сеть `edge`.

### target-vps (VPS-A)
```bash
cd /opt/devops/task04/target-vps/configs
cp .env.example .env && nano .env        # TARGET_DOMAIN=danil2.fdghyt.com
../scripts/deploy-target.sh
curl -i https://danil2.fdghyt.com/health
../scripts/set-health.sh up|down         # переключение /health: 200 или 503
```

### monitor-vps (VPS-B)
```bash
cd /opt/devops/task04/monitor-vps/configs
cp .env.example .env && nano .env        # KUMA_DOMAIN=a5.fdghyt.com, NTFY_DOMAIN=a6.fdghyt.com
../scripts/deploy-monitor.sh
../scripts/setup-secrets.sh              # пароли, пользователи ntfy, monitor-vps/secrets/credentials.txt
```
Дальше вручную: администратор Kuma, уведомление и два монитора (раздел ниже).

### Проверка
```bash
cd /opt/devops/task04
./scripts/check.sh [target|monitor]
```
Скрипт работает с любого компьютера: редирект и HTTPS на VPS-A, `/health` (200 в режиме up, 503 в режиме down), порт 443, Kuma и ntfy по HTTPS, закрытый анонимный доступ к ntfy (чтение и публикация → 401/403), недоступность служебных портов снаружи. Роль дополнительно проверяет контейнеры на этом VPS. Адреса берутся из переменных `TARGET_DOMAIN`, `KUMA_DOMAIN`, `NTFY_DOMAIN`, из `configs/.env` либо по умолчанию из этого README. Состояние мониторов и приём уведомлений проверяются вручную (Kuma, клиент ntfy).

Подтверждения по требованиям (команды, вывод, скриншоты):

| Требование | Что показано | Файл |
|---|---|---|
| 1 | развёртывание двух VPS | [Требование 1](<evidence/Требование 1.md>) |
| 2 | переключение `/health` up/down | [Требование 2](<evidence/Требование 2.md>) |
| 3 | уведомление и два монитора | [Требование 3](<evidence/Требование 3.md>) |
| 4 | пользователи ntfy, анонимный доступ закрыт, клиент | [Требование 4](<evidence/Требование 4.md>) |
| 5 | опыты 1 и 2 | [Требование 5](<evidence/Требование 5.md>) |
| 6 | время доставки, перезагрузка VPS-B | [Требование 6](<evidence/Требование 6.md>) |

## Зависимости от common
`scripts/check.sh` подключает `../common/lib.sh`; подготовку VPS (Docker, ufw) выполняет `../common/prepare-vps.sh`. Задание использует два отдельных VPS, выделенных под него, поэтому с другими стендами порты не пересекаются.

## Ручные действия
- DNS: A-запись `danil2` на IP VPS-A (130.17.27.121) и две A-записи `a5`, `a6` на IP VPS-B (144.31.119.139).
- Файрвол: снаружи только 22 (SSH), 80, 443 (делает `sudo ../common/prepare-vps.sh`).
- Запуск `deploy-target.sh` на VPS-A, `deploy-monitor.sh` и `setup-secrets.sh` на VPS-B. Пароли генерируются и сохраняются в `monitor-vps/secrets/credentials.txt` (вне git), значения передаются проверяющему отдельно.
- Создание администратора Uptime Kuma в веб-интерфейсе (пароль `KUMA_ADMIN_PASSWORD` из `credentials.txt`).
- Настройка уведомления ntfy и двух мониторов в веб-интерфейсе Kuma (раздел ниже).
- Подписка клиента ntfy на топик `monitor-alerts` под пользователем `reader`.
- Выключение и включение VPS-A через панель провайдера (опыт 2).

## Создание мониторов и канала с нуля

1. Канал ntfy

После запуска  `setup-secrets.sh` создаются пользователи: admin, reader, kuma, анонимный доступ закрывается

2. Администратор Kuma

Создается вручную на сайте Uptime Kuma с помощью данных из `credentials.txt`

3. Уведомление
- Settings → Notifications → Setup Notification:
- Type: Ntfy, Friendly Name: `ntfy-own`;
- Server URL: адрес ntfy; Topic: `monitor-alerts`;
- Authentication: Username + Password, пользователь `kuma`, пароль `NTFY_KUMA_PASSWORD`;
- Default enabled и Apply on all existing monitors; проверить кнопкой Test.

4. Мониторы

| Поле | Монитор 1 | Монитор 2 |
|---|---|---|
| Monitor Type | HTTP(s) | TCP Port |
| Friendly Name | target-http-health | target-tcp-443 |
| URL | https://danil2.fdghyt.com/health | - |
| Hostname | - | danil2.fdghyt.com |
| Port | - | 443 |
| Heartbeat Interval | 30 | 30 |
| Retries | 0 | 0 |
| Accepted Status Codes | 200 | - |
| Notifications | ntfy-own on | ntfy-own on |

5. Клиент

Открываем сайт ntfy, заходим под пользователем reader и подписываемся на `monitor-alerts`
