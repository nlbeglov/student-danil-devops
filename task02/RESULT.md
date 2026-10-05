## 1. Общая информация
- Номер задания: 02
- Дата: 22.09.2026 – 06.10.2026
- Затраченные часы: 16

## 2. Ссылки
| Адрес | Назначение |
|---|---|
| https://a2.fdghyt.com | HTTPS-адрес развёрнутого сервиса (общий Caddy → app): `/health`, `/version`, `/add` |
| [github.com/nlbeglov/nerp-test-task02](https://github.com/nlbeglov/nerp-test-task02) | репозиторий |
| [Actions](https://github.com/nlbeglov/nerp-test-task02/actions) | журналы CI/CD |
| [Packages](https://github.com/nlbeglov/nerp-test-task02/pkgs/container/nerp-test-task02) | образы в GHCR |

- Репозиторий: [github.com/nlbeglov/nerp-test-task02](https://github.com/nlbeglov/nerp-test-task02)
- Финальный (задеплоенный) коммит: `9bbf43403d7ad70e096258e989cb951f75511d98` («Revert "Broken release: off-by-one bug in addition"»), digest `sha256:20c1dc13c5ed5ff22809b2aed480dbb927109d53d7cfe84965071d36aa3061c2`
- Ошибочная ревизия: `023ae38d846099ff458b9145003f715b77e331a4` («Broken release: off-by-one bug in addition»), прогон [CI/CD #7](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37384982475)

## 3. Сервисы и характеристики
| Сервис | Образ | Версия/тег |
|---|---|---|
| app | ghcr.io/nlbeglov/nerp-test-task02 | по digest (таблица ниже) |
| Caddy (общий, `common/caddy`) | caddy | 2.11.4 |

- VPS: Senko Digital (Хельсинки, Финляндия), общий с заданием 01: 2 vCPU / 4GB RAM / disk: 60GB, 144.31.119.139

## 4. Статус требований
| № | Требование | Статус | Подтверждение |
|---|---|---|---|
| 1 | Репозиторий и сервис: `/health` → 200, `/version` → JSON, `/add` → JSON или 400 | выполнено | [Требование 1](<evidence/Требование 1.md>) |
| 2 | Автотесты, Dockerfile, Compose, HTTPS через Caddy, без БД | выполнено | [Требование 2](<evidence/Требование 2.md>) |
| 3 | GitHub Actions: тесты → сборка → GHCR → доставка по digest, привязка к commit | выполнено | [Требование 3](<evidence/Требование 3.md>) |
| 4 | Проверка `/health` и `/version`, digest предыдущего выпуска, `concurrency`, секреты в CI/CD | выполнено | [Требование 4](<evidence/Требование 4.md>) |
| 5 | Версии A и B, затем ошибка в сложении: тест падает, на VPS остаётся рабочая версия | выполнено | [Требование 5](<evidence/Требование 5.md>) |
| 6 | Ручной откат на готовый digest без пересборки, проверка `/version`, `/health`, сложения | выполнено | [Требование 6](<evidence/Требование 6.md>) |

## 5. Проверка за 5 минут
Действия:
1. `curl -s https://a2.fdghyt.com/health`
2. `curl -s https://a2.fdghyt.com/version`
3. `curl -s "https://a2.fdghyt.com/add?a=2&b=3"`
4. Открыть [Actions](https://github.com/nlbeglov/nerp-test-task02/actions): прогон [#7](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37384982475) красный на шаге `Run tests`, jobs `build` и `deploy` пропущены.
5. Автоматически на сервере: `cd /opt/devops/task02/configs && ../scripts/check.sh` (тесты, образ по digest, `/health`, `/version`, сложение, ответы 400, редирект).
6. `cat /opt/devops/task02/configs/releases.log` — журнал выпусков: A, B, откат на A, revert; в нём нет доставки ошибочной ревизии.

Ожидаемый результат:
- `/health` → `{"status":"ok"}`, `/version` → `{"version":"9bbf43403d7ad70e096258e989cb951f75511d98"}`, сложение → `{"result":5}`;
- прогон с ошибкой в сложении завершается `Failure` на тестах, шаги `build` и `deploy` не выполняются, на VPS остаётся версия B;
- откат запускается в Actions без сборки образа, `/version` после него равен коммиту A, digest совпадает с выпуском A.

### Версия — commit — digest
| Версия (`/version`) | Коммит | Digest образа | Итог прогона CI/CD |
|---|---|---|---|
| `b9250cdadd9605b8d2eaadb86d815a8f119ce1ca` (A) | [b9250cd](https://github.com/nlbeglov/nerp-test-task02/commit/b9250cdadd9605b8d2eaadb86d815a8f119ce1ca) «Release A» | `sha256:73bf45da1f0f1b91f8de5e35fd52faa0b12ad32e991f62f9d9cee1df8ec48639` | тесты, сборка, доставка ✅ ([#5](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37384308403)) |
| `2edfb80179fe8f1a2fe0ac6fa3a158551025f9b2` (B) | [2edfb80](https://github.com/nlbeglov/nerp-test-task02/commit/2edfb80179fe8f1a2fe0ac6fa3a158551025f9b2) «Release B» | `sha256:32aa863fc9a0de0416896a3eb864d540809f6aab66e0e08428a38287b98e848a` | тесты, сборка, доставка ✅ ([#6](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37384842975)) |
| ошибочная ревизия | [023ae38](https://github.com/nlbeglov/nerp-test-task02/commit/023ae38d846099ff458b9145003f715b77e331a4) «Broken release» | образ не собирался | `test` упал, `build` и `deploy` пропущены ([#7](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37384982475)); на VPS осталась версия B |
| `b9250cdadd9605b8d2eaadb86d815a8f119ce1ca` (откат на A) | тот же образ A | `sha256:73bf45da1f0f1b91f8de5e35fd52faa0b12ad32e991f62f9d9cee1df8ec48639` | Rollback ✅ ([Rollback #3](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37385256876)), без сборки; `/version` = A |
| `9bbf43403d7ad70e096258e989cb951f75511d98` (revert) | [9bbf434](https://github.com/nlbeglov/nerp-test-task02/commit/9bbf43403d7ad70e096258e989cb951f75511d98) «Revert Broken release» | `sha256:20c1dc13c5ed5ff22809b2aed480dbb927109d53d7cfe84965071d36aa3061c2` | следующий обычный выпуск ✅ ([#8](https://github.com/nlbeglov/nerp-test-task02/actions/runs/37385324487)) |

Порядок следующего обычного выпуска после отката описан в [Требование 6](<evidence/Требование 6.md>).

## Проблемы и ограничения
- Первый запуск deploy в прогоне #5 упал: на пересозданном сервере не было ключа CI (`Permission denied (publickey,password)`). Создан новый ключ для CI, публичная часть добавлена в `authorized_keys` на VPS, приватная записана в секрет `VPS_SSH_KEY`; после «Re-run failed jobs» deploy прошёл.
- Введённые в форму Rollback значения `image_digest` и `app_version` не видны без авторизации; соответствие подтверждается журналом выпусков на VPS (`releases.log`: образ и версия A) и digest из прогона #5.
- Стенд работает за общим Caddy: `compose`, `Dockerfile`, `requirements.txt` и `.env.example` лежат в `configs/`, домен `a2.fdghyt.com`, CI доставляет в `/opt/devops/task02/configs`; содержимое `task02/` является корнем репозитория GitHub.
- В `evidence/` нет скриншотов: подтверждения даны выводом команд и ссылками на публичные страницы GitHub Actions и GHCR.
