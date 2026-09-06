# AGENTS

This file provides guidance to AI coding agents working with this repository.

## What is GetCourt?

Website: https://getcourt.co/

GetCourt is a Ruby on Rails app for organizing local racket-sport games:
- Create and manage **courts** (moderated, with **court suggestions** from players)
- Create **games** and **trainings** (one-off or recurring), optionally with **coaches**
- Join/leave games via **participations**
- Optional **prebooking** slots for upcoming occurrences
- **Telegram bot** for reminders + filling post-game stats via chat flows
- **Tournaments** and **matches** (stats/extensible JSON), **player statistics** and ratings
- **Tennis Life** feed, **featured matches** and game **photos/clips**
- **AI** assistant, opponent matching and score recognition on top of RubyLLM (Gemini)
- Public games JSON API (`/api/v1/games`) and an **MCP** endpoint (`/mcp`) over it — see `docs/api-and-mcp.md`

Main technologies:
- Ruby 4.0 / Rails 8.1
- Hotwire (Turbo + Stimulus), Propshaft + importmap
- Tailwind CSS
- SQLite (dev + production), Solid Queue / Solid Cache / Solid Cable
- Active Storage with libvips for media
- Geocoding (Google / Nominatim), Google Maps in the browser

Project entry points:
- Web UI: controllers/views in `app/`
- Telegram bot: `app/services/telegram/**` (webhook in production, polling in dev)
- Domain services: `app/services/**`
- Jobs: `app/jobs/**`

## Goal
- Minimize token usage and changes.
- Prefer smallest diff that solves the task.

## Scope Rules
- Do **not** scan the whole repository.
- Work only with files explicitly mentioned by the user.
- If a change spans multiple files, confirm the list first.

## Output Rules
- Provide minimal patch only.
- Avoid repeating large code blocks.
- No large logs or full-file dumps.

## Development Commands

### Setup + Server
```bash
bin/setup
bin/dev
```

`bin/dev` uses [Procfile.dev](Procfile.dev) and runs (at least):
- `web: bin/rails server`
- `css: bin/rails tailwindcss:watch`
- `telegram-poll: bin/rails telegram:poll`

Default dev URL (unless `PORT` is set): `http://localhost:3000`

### Tests / Lint / Security (what CI runs)
```bash
bin/rails db:test:prepare test test:system
bin/rubocop
bin/brakeman --no-pager
bin/importmap audit
```

Every CI job installs Ruby from [.ruby-version](.ruby-version), so that file — not
this document — is the source of truth for the runtime.

CI config lives in [.github/workflows/ci.yml](.github/workflows/ci.yml).

### Database
```bash
bin/rails db:prepare
bin/rails db:migrate
bin/rails db:reset
bin/rails db:fixtures:load
bin/rails g migration MigrationName
```

SQLite configuration: [config/database.yml](config/database.yml)

## Architecture Notes (project-specific)

### Rails app shape
- Standard CRUD web endpoints in [config/routes.rb](config/routes.rb)
- Controllers in `app/controllers/**`
- Views in `app/views/**`
- Models in `app/models/**`

### Telegram bot
Primary implementation is in `app/services/telegram/**`.

Conversations/state are stored via cache-backed helpers:
- Conversation helper: `Telegram::Helpers::Conversation` ([app/services/telegram/helpers/conversation.rb](app/services/telegram/helpers/conversation.rb))

Stats flows are implemented as service objects under:
- `app/services/telegram/flows/**` (example: `Telegram::Flows::StatsFlow` in [app/services/telegram/flows/stats_flow.rb](app/services/telegram/flows/stats_flow.rb))

### Background jobs / queue
Production uses Solid Queue (DB-backed):
- Adapter configured in production env (see [config/environments/production.rb](config/environments/production.rb))
- Worker config: [config/queue.yml](config/queue.yml)
- Recurring tasks: [config/recurring.yml](config/recurring.yml)

### Caching differences
- Development uses memory cache store (see [config/environments/development.rb](config/environments/development.rb))
- Test uses null store (see [config/environments/test.rb](config/environments/test.rb))
- Production uses Solid Cache (see [config/environments/production.rb](config/environments/production.rb)),
  which also holds data no table owns — geocoded court addresses, Telegram conversation state

## Working Agreements (token-saving defaults)
- Assume “smallest diff” unless explicitly told to refactor.
- Don’t broaden scope: no drive-by cleanups.
- Before making multi-file changes, confirm the exact file list.
- Prefer targeted commands and targeted tests; avoid full-suite runs unless requested.

## Default Summary
- 3–5 bullets max.