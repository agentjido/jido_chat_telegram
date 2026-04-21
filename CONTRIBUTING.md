# Contributing to Jido Chat Telegram

## Development Setup

```bash
mix setup
```

Install local git hooks explicitly from the primary checkout when needed:

```bash
mix install_hooks
```

## Tests

```bash
mix test
mix test test/jido/chat/telegram/live_integration_test.exs --include live
```

Live tests require `.env` values based on `.env.example` and must remain excluded
from the default test suite.

## Quality Checks

```bash
mix quality
mix coveralls
mix docs
```

## Release Workflow

Releases are prepared through the GitHub Actions release workflow. Before a
release, verify `mix quality`, `mix coveralls`, `mix docs`, and the changelog.
