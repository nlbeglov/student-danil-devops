# Отчет
- Имя: **Раянов Данил**
- Дата начала: **16.09.2026**
- Дата окончания: **05.10.2026**
- Общее затраченное время: **66 часов**

## Сводная таблица

| Номер задания | Статус    | Затраченные часы | Основной адрес                                                                                                   | Ссылка на подробный отчет            |
| ------------- | --------- | ---------------- | ---------------------------------------------------------------------------------------------------------------- | ------------------------------------ |
| 1             | выполнено | 22               | https://a1.fdghyt.com (копия: https://danil1.fdghyt.com)                                                         | [task01/RESULT.md](task01/RESULT.md) |
| 2             | выполнено | 16               | https://a2.fdghyt.com                                                                                            | [task02/RESULT.md](task02/RESULT.md) |
| 3             | выполнено | 11               | https://a3.fdghyt.com/a.txt                                                                                      | [task03/RESULT.md](task03/RESULT.md) |
| 4             | выполнено | 9                | https://a5.fdghyt.com (Kuma), https://a6.fdghyt.com (ntfy), https://danil2.fdghyt.com:8443/health (цель)        | [task04/RESULT.md](task04/RESULT.md) |
| 5             | выполнено | 8                | https://a4.fdghyt.com                                                                                            | [task05/RESULT.md](task05/RESULT.md) |

Основной VPS: 144.31.119.139 (Senko Digital, 2 vCPU / 4 GB / 60 GB), цель мониторинга задания 04 и внешнее хранилище restic задания 03: 130.17.27.121.

## Общий маршрут проверки (10–15 минут)

Все стенды основного VPS работают одновременно за общим Caddy (`common/caddy`), переключать ничего не нужно.

1. **Задание 1 (≈ 3 мин).** `cd /opt/devops/task01/configs && ../scripts/check.sh`: HTTPS, анонимный 404 к `review-user/demo`, вход `review-user`, clone, hash коммита (исходный — `3c7bc3b218b336b11f43ac898848f1726656ee64`). Восстановленная копия: см. `task01/RESULT.md`.
2. **Задание 2 (≈ 3 мин).** `cd /opt/devops/task02/configs && ../scripts/check.sh`: `/health`, `/version`, `/add?a=2&b=3` → `{"result":5}`, ошибки 400. В GitHub Actions прогон `f34b487` красный на тестах, образ из него не опубликован; запуск Rollback.
3. **Задание 3 (≈ 3 мин).** `restic snapshots` (три снимка), `systemctl list-timers task03-backup.timer`, затем `cd /opt/devops/task03/configs && docker compose stop && ../scripts/restore.sh && ../scripts/check.sh` (manifest, `id=101`, ненулевой код при ошибке доступа).
4. **Задание 4 (≈ 3 мин).** `/opt/devops/task04/scripts/check.sh`; Kuma: оба монитора UP; `task04/target-vps/scripts/set-health.sh down` → DOWN только у HTTP-проверки, `up` → UP; сообщения приходят в клиент ntfy; анонимный доступ к ntfy → 403.
5. **Задание 5 (≈ 3 мин).** `cd /opt/devops/task05/configs && ../scripts/check.sh push`; `../scripts/fault.sh proxy` → 502, диагностика по логам Caddy, `../scripts/recover.sh`, повторный `check.sh push`.

Подробные проверки «за пять минут» — в RESULT каждого задания.
