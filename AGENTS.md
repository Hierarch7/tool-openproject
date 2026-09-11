# OpenProject AI Coding Agent Instructions

<!-- pipelines:claude-core start -->
## Language
- Respond in Russian.

## Scope and context
- Work ONLY with files explicitly provided, opened in the editor, or pasted.
- Do NOT assume routes, database schema, policies, guards, middleware, or tenant logic unless shown.
- If context is missing:
  - ask up to 3 specific questions, OR
  - proceed with explicit assumptions and list them.

## Default response format
1. Short plan (3-6 bullet points)
2. Unified diff (minimal changes only)
3. Short notes ONLY for changed lines (reason / risk)

Forbidden:
- rewriting full files
- repeating unchanged code
- verbose explanations
- generic advice

## Commit rules

Когда пользователь говорит «коммит» — выполнить процедуру подготовки коммитов:

1. **Анализ изменений**: `git diff --cached --name-status` (staged) + `git diff --name-status` (unstaged). Сгруппировать файлы по функциональным модулям (неважно какого типа — главное что относятся к одному модулю).
2. **Предложить структуру**: описать каждый коммит — короткое имя + список файлов. Conventional commits: `feat/fix/refactor/test/docs/i18n/seed/chore`. Комментарии на русском.
3. **Формат сообщения коммита**:
   ```
   scope: краткое описание

   Что сделано:
   - пункт 1
   - пункт 2

   Детали изменений (при необходимости)
   Технические детали (при необходимости)
   ```
4. **Без списка файлов** в сообщении коммита.
5. **БЕЗ подписи Claude/Anthropic** (`Co-Authored-By` и т.п.).
6. **После одобрения** — выполнить все коммиты одной командой в консоли.

## Diff review rules

Когда пользователь говорит «проверь диф» — выполнить ревью:

1. Запустить `git diff` (или `git diff --cached` если есть staged).
2. Проверить: ломает ли логику, есть ли edge cases, соответствует ли принятым в проекте практикам.
3. **Только список замечаний, без кода.** Разбить по приоритетам:
   - **HIGH** — блокеры мержа
   - **MED** — починить сейчас если быстро
   - **LOW** — мелочи / косметика
4. Для каждого пункта указать:
   - Краткая причина
   - Стратегия фикса (1-2 предложения)
   - Нужен ли тест и какой сценарий
5. Не overengineering — не предлагать рефакторинг ради рефакторинга.

## Fix all rules

Когда пользователь говорит «исправь всё» — режим глубокого исправления:

1. Проанализировать все изменения / указанный код **по порядку**.
2. Не быстрые заплатки — **корректные, продуманные, надёжные решения** (best practices).
3. Без лишних деталей и объяснений — сразу к делу.
4. **Использовать существующие паттерны проекта**, а не изобретать свои. Смотреть sibling-файлы.
5. Если в коде есть несовершенства — применять более продвинутые подходы.
6. При необходимости — провести веб-поиск или задать вопрос пользователю (до 3 вопросов).

## Editing rules
- Prefer minimal diffs.
- Keep public APIs stable unless explicitly asked.
- If multiple solutions exist:
  - list 2-3 briefly
  - choose the best and explain why.
- If behavior changes, add or update tests (написать/обновить — да; **прогон только по запросу**, см. `## Test policy`).

## Test policy
**Канонический источник правды по тестам.** Переопределяет любые сгенерированные блоки в этом файле.
- Тесты **пишем/обновляем** при изменении поведения — это часть работы.
- **Прогон тестов НЕ автоматический.** Запускать только когда пользователь явно попросил («прогони тесты», «проверь тестами») или в рамках явно вызванного флоу.
- Если прогоняем — **точечно**: конкретный тест или файл, а не весь набор.
- **Запрещены** параллельные прогоны и прогон всего набора без явного запроса: несколько агентов делят одну тестовую БД и затирают её друг у друга.
- **Destructive-команды над БД** (пересоздание схемы, полный пересев, wipe) — ТОЛЬКО по явному запросу пользователя.

## Quality checks before final answer
- Authorization: no cross-role or cross-tenant data leaks.
- Transactions: multi-step writes must be atomic; state invariants.
- Performance: avoid N+1, prefer eager loading.
- Backward compatibility: contracts consumed by other code must stay stable; list breaking changes if unavoidable.

## Quick review prompts
- Review this diff for correctness, authorization, and edge-cases. Return issues only.
- Propose minimal fix plus test. Plan, diff, notes.
- Find N+1 and fix with eager loading.

## Non-goals
- Do not auto-apply changes.
- Do not refactor the entire repository.
- Do not propose speculative architecture changes.

## Working principle
Correctness first, minimal diff second, tests third, reviewability always.
<!-- pipelines:claude-core end -->

<!-- pipelines:deploy start -->
## Deployment rules
- Все изменения на prod/test серверах — ТОЛЬКО через git (pull/merge).
- Прямое редактирование файлов на серверах запрещено.
- Hotfix-патчи оформляются как коммиты и деплоятся стандартным процессом.

### Deploy flow (Claude Code)

**Деплой выполняется ТОЛЬКО по явному запросу пользователя** («задеплой», «пуш на прод», «выкати»). После коммита автоматически НЕ пушить и НЕ деплоить — остановиться на коммите и ждать команды.

**Исключение — флоу `/ship`:** вызов `/ship` сам по себе является явным запросом на полный цикл до деплоя. Внутри `/ship` коммит и деплой выполняются автоматически, без остановок и подтверждений (см. `.claude/commands/ship.md`). Это исключение действует ТОЛЬКО в рамках `/ship`; вне его — правило выше в силе.

Деплой автоматический через **Forgejo Actions** self-hosted runner. **Не** подключаться по SSH для запуска деплоя вручную.

**Где живёт CI:** Forgejo (`origin` = `git.processing.systems`, репозиторий `devteam/canban`). Пуш в `origin` запускает деплой. Пайплайн — `.forgejo/workflows/deploy-bo.yml`: Forgejo читает `.github/workflows/` наравне с `.forgejo/workflows/`, отдельного файла не нужно.

```bash
# 1. Коммит — см. "Commit rules" выше (на этом шаге останавливаемся)

# Дальнейшие шаги — только когда пользователь явно попросил деплой:

# 2. Пуш в Forgejo — запускает деплой автоматически
git push origin main
# 3. Статус деплоя — по логу раннера
ssh s01 "sudo journalctl -u forgejo-runner-op -n 40 --no-pager"
```
<!-- pipelines:deploy end -->

<!-- pipelines:common-commands start -->
## Common commands

### Development
```bash
bin/compose up
```

### Тесты
```bash
bundle exec rspec spec/path/to/relevant_spec.rb  # по файлу
bundle exec rspec  # весь сьют
cd frontend && npm test  # фронтенд
```

### Качество кода
```bash
bin/dirty-rubocop --uncommitted
cd frontend && npx eslint <изменённые файлы>
```
<!-- pipelines:common-commands end -->

<!-- pipelines:graphify start -->
## graphify

This project has a knowledge graph at graphify-out/ with god nodes, community structure, and cross-file relationships.

Rules:
- For codebase questions, first run `graphify query "<question>"` when graphify-out/graph.json exists. Use `graphify path "<A>" "<B>"` for relationships and `graphify explain "<concept>"` for focused concepts. These return a scoped subgraph, usually much smaller than GRAPH_REPORT.md or raw grep output.
- If graphify-out/wiki/index.md exists, use it for broad navigation instead of raw source browsing.
- Read graphify-out/GRAPH_REPORT.md only for broad architecture review or when query/path/explain do not surface enough context.
- After modifying code, run `graphify update .` to keep the graph current (AST-only, no API cost).
<!-- pipelines:graphify end -->

> **Note for developers**: You can create `AGENTS.local.md` (or `CLAUDE.local.md`) in this directory to add your own custom instructions or preferences for AI coding agents. These files are git-ignored and will not be committed to the repository.

## Repository Overview

**OpenProject** is a web-based, open-source project management software written in Ruby on Rails with PostgreSQL for data persistence.

- **Size**: Large monorepo (~840MB, ~1M+ lines of code)
- **Backend**: Ruby 3.4.7, Rails ~8.0.3
- **Frontend**: Node.js 24.x (>= 24.15.0), npm 11.x, TypeScript
- **Database**: PostgreSQL (required)
- **Architecture**: Server-rendered HTML with Hotwire (Turbo + Stimulus). Legacy Angular components exist and are being migrated to custom elements. Uses GitHub's Primer Design System via ViewComponent.
- **Editions**: Community, Enterprise (SSO, LDAP, SCIM), and BIM (construction industry, code in `modules/bim/`)

## Critical Setup Requirements

**ALWAYS verify versions before building:**
- Ruby: `3.4.7` (see `.ruby-version`)
- Node: `^24.15.0` (see `package.json` engines)
- Bundler: Latest 2.x

### Local Development Setup

```bash
bundle install                    # Install Ruby gems
cd frontend && npm ci && cd ..   # Install Node packages
bundle exec rails db:migrate      # Setup database
bin/dev                          # Start all services (Rails, frontend, Good Job worker)
# Access at http://localhost:3000
```

### Docker Development Setup

See [`docker/dev/AGENTS.md`](docker/dev/AGENTS.md) for full Docker setup and commands.

## Project Structure

### Key Directories

- `app/` — Rails application code
- `config/` — Rails configuration, routes, locales
- `db/` — Database migrations and seeds
- `docker/dev/` — Docker development environment
- `frontend/` — TypeScript/Angular/Stimulus frontend
- `lib/` — Ruby libraries and extensions
- `lookbook/` — ViewComponent previews (<https://qa.openproject-edge.com/lookbook/>)
- `modules/` — OpenProject plugin modules
- `spec/` — RSpec test suite

### Configuration Files

- `.ruby-version` - Ruby version
- `.rubocop.yml` - Ruby linting rules
- `.erb_lint.yml` - ERB template linting
- `frontend/eslint.config.mjs` - JavaScript/TypeScript linting
- `Gemfile` - Ruby dependencies
- `package.json` / `frontend/package.json` - Node.js dependencies
- `lefthook.yml` - Git hooks configuration

### Linting (Run Before Committing)

```bash
# Ruby
bundle exec rubocop                              # Check all files
bin/dirty-rubocop --uncommitted                  # Check only uncommitted changes

# JavaScript/TypeScript
cd frontend && npx eslint src/ && cd ..

# ERB Templates
erb_lint {files}

# Install Git Hooks (recommended)
bundle exec lefthook install
```

## Commit Messages
- First line: < 72 characters, then blank line, then detailed description
- Reference work packages when applicable
- Merge strategy: "Merge pull request" (not squash), except single-commit PRs can use "Rebase and merge"

## Additional Documentation

- `docs/development/` — Development documentation
- `docs/development/running-tests/` — Testing guide
- `docs/development/code-review-guidelines/` — Code review standards
- `CONTRIBUTING.md` — Contribution workflow
- `.github/copilot-instructions.md` — Extended agent instructions with troubleshooting

<!-- SPECKIT START -->
For additional context about technologies to be used, project structure,
shell commands, and other important information, read the current plan
<!-- SPECKIT END -->

