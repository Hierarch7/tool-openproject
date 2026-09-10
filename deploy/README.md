# deploy/ — обвязка выката OpenProject

Здесь лежит то, что раньше существовало только на дисках серверов: скрипты выката,
конфиги runner'ов и эталоны compose. Файлы сняты с рабочих хостов как есть —
`deploy.sh` и `smoke.sh` побайтово совпадают с тем, что крутится в проде.

## Где что работает

| Инстанс | Хост | Каталог | Порт | Окружение | Стенд |
|---|---|---|---|---|---|
| bo.hesoyam.biz | hy (185.189.44.137) | `/opt/openproject` | 8095 | `production` | `/opt/openproject-staging`, 8096 |
| bo.processing.systems | gambit (84.32.186.99) | `/opt/openproject-processing` | 8097 | `processing` | нет |

Оба — OpenProject из этого репозитория, образ `bo-openproject:<sha>`, PostgreSQL 17.
Домен `bo.processing.systems` проксируется через Cloudflare.

`bo.gambit-core.com` (gambit, `/opt/openproject`, 8095) закрыт: DNS-запись снята, из пайплайна
убран, его проект `tech` переехал на `bo.processing.systems` вместе с историей и вложениями.
Контейнеры `op-*` на хосте пока стоят — поэтому `compose/gambit-production.yml` ещё лежит здесь,
а compose-проект нового инстанса называется `op-processing`, а не `op`.

## Как выкатывается

Пайплайн [`.forgejo/workflows/deploy-bo.yml`](../.forgejo/workflows/deploy-bo.yml) на своём Forgejo
(`git.processing.systems/devteam/canban`):

```
push в main       → прод на обоих инстансах
push в bo-staging → стенд на hy
workflow_dispatch → с выбором окружения
```

`main` — одновременно мейнлайн и деплойная ветка: промежуточной ступени между мержем и продом нет.

Джобы идут на self-hosted runner'ах в host-режиме (метки `hy-op`, `gambit-op`), образ собирается
на том же хосте, куда катится — реестр не нужен. Внутри джоба зовёт
`sudo /opt/bo-deploy/deploy.sh <окружение> <sha>` и следом `smoke.sh`.

`deploy.sh` перед выкатом снимает дамп БД в `/var/backups/openproject`, пинит образ в `OP_IMAGE=`
внутри `.env` рядом с compose и оставляет 5 последних sha-тегов. Миграции гонит сам образ на
старте контейнера `web`.

## Содержимое

```
bin/deploy.sh, bin/smoke.sh      → /opt/bo-deploy/            (root:root 755)
etc/bo-deploy.conf.<роль>        → /etc/bo-deploy.conf        описание окружений хоста
etc/sudoers.d/forgejo-runner-op  → /etc/sudoers.d/            грант runner'у ровно на два скрипта
etc/forgejo-runner/op-config.yaml→ /etc/forgejo-runner/
etc/systemd/*.service            → /etc/systemd/system/
nginx/hocuspocus-location.conf   → вставляется в bo.conf ВРУЧНУЮ
nginx/action-cable-location.conf → вставляется в bo.conf ВРУЧНУЮ
nginx/bo-processing.vhost.conf   → /etc/nginx/sites-available/bo-processing.conf ВРУЧНУЮ
compose/*.yml                    → эталон для сверки, НЕ для копирования
```

Раскладка: `sudo deploy/install.sh hy` (или `gambit`). Скрипт идемпотентен и намеренно не трогает
живой конфиг: не перезапускает runner (это оборвало бы текущий выкат), не правит nginx и не
перезаписывает `docker-compose.yml`.

`deploy/` внесён в `.dockerignore` — правки здесь не инвалидируют кэш сборки образа и не вызывают
лишнюю пересборку прода.

## Грабли, за которые заплачено

**Апгрейд только по одной мажорной версии.** `MigrationSquasher` отказывается идти 15 → 17
напрямую. Путь: свой образ → откат на стоковый `openproject:16` → миграции → снова свой.

**OpenProject 17 требует PostgreSQL ≥ 15** — миграция `ModifyFriendlyIdSlugsConstraints` создаёт
индекс с `NULLS NOT DISTINCT`. На PG 13 падает синтаксисом. Апгрейд СУБД — дампом и ресторой.

**`db:seed` гоняется при каждом старте контейнера**, а демо-сидеры гейтятся по «пусто ли ещё»
(`DemoData::GroupSeeder#applicable?` это `Group.count.zero?`). На живом инстансе без групп апгрейд
создаёт 7 демо-групп и 14 юзеров вида `marko.marketing`. Закрыто флагом
`OPENPROJECT_SKIP_DEMO_SEED=true` в compose (реализация — `config/initializers/zz_skip_demo_seed.rb`).

**Проверять WebSocket только с `curl --http1.1`.** Listener отдаёт HTTP/2, где механизма `Upgrade`
нет вовсе, и приходит обманчивый `200` вместо `101`.

**`smoke.sh` на проде обязан слать `Host` и `X-Forwarded-Proto: https`** — при
`OPENPROJECT_HTTPS=true` приложение иначе отвечает `301`, и проверка не дождётся `200` никогда.

**uid переиспользуются.** После удаления пользователя его uid занимает следующий созданный, и
каталоги молча меняют владельца. Здесь это подарило runner'у владение `/opt/bo-deploy`, то есть
возможность подменить скрипты, на которые ему же выдан sudo. После `userdel` —
`find /opt /var/backups -uid <старый uid>`.
