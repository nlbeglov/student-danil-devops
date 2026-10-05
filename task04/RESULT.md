## 1. Общая информация
- Номер задания: 04
- Дата: 02.10.2026
- Затраченные часы: 8

## 2. Ссылки
| Адрес | Назначение |
|---|---|
| https://test3.politblocks.com/health | цель мониторинга (VPS-A): nginx `/health`, 200 или 503 |
| https://test0.politblocks.com | Uptime Kuma (VPS-B), вход по логину |
| https://test1.politblocks.com | ntfy (VPS-B), доступ только по авторизации |

- Репозиторий: [вставить ссылку]
- Финальный коммит: [вставить]

## 3. Сервисы и характеристики
| Сервис | Образ | Версия/тег |
|---|---|---|
| nginx (VPS-A) | nginx | 1.27.5-alpine |
| caddy (VPS-A, VPS-B) | caddy | 2.11.4 |
| Uptime Kuma (VPS-B) | louislam/uptime-kuma | 1.23.16 |
| ntfy (VPS-B) | binwiederhier/ntfy | v2.11.0 |

- VPS-A (цель): Aeza, Хельсинки, 1 vCPU / 4 GB RAM / диск 10 GB
- VPS-B (мониторинг): Senko Digital, Хельсинки, 2 vCPU / 4 GB RAM / диск 60 GB

## 4. Статус требований
| № | Требование | Статус | Подтверждение |
|---|---|---|---|
| 1 | Два VPS, отдельный Compose на каждый | выполнено | [Требование 1](<evidence/Требование 1.md>) |
| 2 | `set-health.sh up\|down`, reload nginx | выполнено | [Требование 2](<evidence/Требование 2.md>) |
| 3 | HTTP- и TCP-проверки, интервал 30 с, уведомления DOWN/UP | выполнено | [Требование 3](<evidence/Требование 3.md>) |
| 4 | Свой ntfy с авторизацией, защита входом Kuma | выполнено | [Требование 4](<evidence/Требование 4.md>) |
| 5 | Два опыта: HTTP 503; выключение VPS-A | выполнено | [Требование 5](<evidence/Требование 5.md>) |
| 6 | Сообщения DOWN/UP ≤ 180 с, сохранность после перезагрузки VPS-B | выполнено | [Требование 6](<evidence/Требование 6.md>) |

## 5. Проверка за 5 минут
Действия (внешняя автоматическая проверка с любого компьютера: `./scripts/check.sh`):
1. Открыть `https://test0.politblocks.com`, войти. Оба монитора (`target-http-health`, `target-tcp-443`) в состоянии UP.
2. Открыть `https://test1.politblocks.com`, войти как `reader`, подписаться на `monitor-alerts`.
3. На VPS-A: `/opt/devops/task04/target-vps/scripts/set-health.sh down`, подождать до 40 с.
4. Вернуть `/opt/devops/task04/target-vps/scripts/set-health.sh up`.
5. Проверить анонимный доступ: `curl -s -o /dev/null -w '%{http_code}\n' "https://test1.politblocks.com/monitor-alerts/json?poll=1"`.

Ожидаемый результат:
- после шага 3 DOWN только у `target-http-health`, `target-tcp-443` остаётся UP; в ntfy приходит сообщение DOWN;
- после шага 4 оба в UP, в ntfy приходит сообщение UP;
- шаг 5 возвращает 403 (анонимное чтение закрыто).

### Измеренная задержка доставки

| Опыт | Воздействие | Сообщение | Задержка |
|---|---|---|---|
| 1 | `set-health down`, 01:15 | 01:15:47 DOWN `target-http-health` | ≤ 47 с |
| 1 | `set-health up`, 01:18 | 01:18:28 UP `target-http-health` | ≤ 28 с |
| 2 | выключение VPS-A, 01:29 | 01:29:24 DOWN `target-http-health`, 01:29:28 DOWN `target-tcp-443` | ≤ 28 с |
| 2 | включение VPS-A, 01:35 | 01:35:08 UP `target-http-health`, 01:35:13 UP `target-tcp-443` | ≤ 7 с |

## Проблемы и ограничения
- Опечатка в домене (`poltblocks` вместо `politblocks`): Caddy не мог выпустить сертификат (NXDOMAIN). Исправлено в `.env`.
- Ошибка 403 при первой отправке из Kuma в ntfy: в форме уведомления не была выбрана авторизация. Исправлено выбором Username + Password для пользователя kuma.
- `nginx -s reload` асинхронный: контрольный запрос сразу после reload мог попасть в старые процессы. В `set-health.sh` добавлено ожидание нужного кода до 10 с.
- Часовой пояс времени воздействий и уведомлений: UTC+3 (MSK).
- Время воздействий в опытах записано с точностью до минуты, поэтому задержка указана как верхняя граница.
- Браузерные уведомления приходят при открытой вкладке ntfy (Web Push не настроен).
- Пароли хранятся в `secrets/credentials.txt` на VPS-B, вне git, и передаются отдельно.