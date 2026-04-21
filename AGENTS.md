# AGENTS.md - Jido Chat Telegram Development Guide

`jido_chat_telegram` is the Telegram adapter for `Jido.Chat`.

## Commands

- `mix setup` - Fetch dependencies.
- `mix test` - Run the default non-live test suite.
- `mix test --include live` - Run explicitly enabled live Telegram tests.
- `mix quality` - Run the Jido package quality gate.
- `mix coveralls` - Run coverage.
- `mix install_hooks` - Explicitly install local git hooks.

## Rules

- Keep live Telegram tests excluded by default with the `:live` tag.
- Do not commit `.env` or credentials.
- Prefer `Jido.Chat.Adapter` callbacks for shared behavior and `Jido.Chat.Telegram.Extensions` for Telegram-only APIs.
- Preserve the adapter boundary; supervised runtime concerns belong in `jido_messaging`.
