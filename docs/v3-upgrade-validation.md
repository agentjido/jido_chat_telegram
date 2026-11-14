# Consolidated Jido upgrade validation: telegram

Date: 2026-11-14 (America/Chicago).

Start: `release/v3` at `9fe12435e961d8910300c6e1b126c9a88e0222bd`. The working tree was clean.
Origin: `agentjido/jido_chat_telegram`. The remote head matched the starting revision.

## Changes

The adapter uses Chat `7652b6d74c4fc8170149ae1cfd08f981cfb1ea27` in all environments.
The GitHub `release/v3` API confirmed this revision before selection.
The old Chat revision was `0b6f16d9b91b37c61f2ad913dcdd4adea1713f88`.
The local path override was removed. Dotenvy `~> 1.2` is a runtime dependency, as required by LLMDB.
The lock removes separate Action and Signal providers. No package version or quality gate was changed.

Calls to removed Signal APIs use Codec, Context, Trace, and Id APIs where needed.
Discord and Slack test Agents use the current Plugin and state declarations where needed.
Agent state reads use committed snapshots where needed. Existing assertions remain in place.

Changed files:

- `README.md`
- `examples/live_proof.exs`
- `examples/text_api_proof.exs`
- `lib/jido_chat_telegram/internal/operations.ex`
- `lib/jido_chat_telegram/internal/streaming.ex`
- `lib/jido_chat_telegram/source.ex`
- `mix.exs`
- `mix.lock`
- `test/contracts/actions_contract_test.exs`
- `test/contracts/adapter_contract_test.exs`
- `test/contracts/signals_contract_test.exs`
- `test/contracts/support/fixtures_helper.exs`
- `test/jido/chat/telegram/api_hardening_test.exs`
- `test/jido/chat/telegram/channel_test.exs`
- `test/jido/chat/telegram/live_integration_test.exs`
- `test/jido/chat/telegram/membership_test.exs`
- `test/jido/chat/telegram/native_actions_test.exs`
- `test/jido/chat/telegram/normalizer_test.exs`
- `test/jido/chat/telegram/public_api_live_test.exs`
- `test/jido/chat/telegram/send_poll_test.exs`
- `test/jido/chat/telegram/stream_text_test.exs`
- `docs/v3-upgrade-validation.md`

## Checks

Checks ran in an isolated copy made from the starting revision.
The candidate source files were copied without changes after checks.
Toolchain: Elixir 1.20.4, Erlang/OTP 29.1.2, macOS arm64.
GitHub was the canary. Its first quality gate passed before shared changes were applied.
The pinned Chat owner test suite passed all 358 tests in a separate copy.

| Command | Exit | Result |
| --- | ---: | --- |
| `mix deps.update jido_chat jido nimble_options dotenvy` | 0 | Pass |
| `mix deps.get` | 0 | Pass |
| `mix deps.unlock --unused` | 0 | Pass |
| `mix quality` | 0 | Pass |
| `mix test` | 0 | Pass |
| `mix test.contracts` | 0 | Pass |
| `MIX_ENV=test mix covenant.check --static` | 0 | Pass |
| `mix coveralls` | 0 | Pass |
| `mix docs -f html -f markdown` | 0 | Pass |
| `MIX_ENV=prod mix compile --warnings-as-errors` | 0 | Pass |
| `MIX_ENV=prod mix hex.build` | 1 | Blocked: Git dependency is not valid for Hex publication |
| `MIX_ENV=test mix deps.tree` | 0 | Pass |
| `mix deps.unlock --check-unused` | 0 | Pass |
| `mix hex.audit` | 0 | Pass |
| Module owner and split provider check | 0 | All four module owners are `:jido`; no split providers |

Test result:

```text
Excluding tags: [:live]
Finished in 4.8 seconds (4.6s async, 0.1s sync)
Result: 172 passed, 38 excluded
```

Coverage: `[TOTAL]  93.0%`. The configured threshold was kept.

## Final dependency graph

```text
jido_chat_telegram
└── jido_chat 7652b6d74c4fc8170149ae1cfd08f981cfb1ea27
    ├── jido 05723b96c6ead47dec04fe69b1c34ad62f999c54
    │   ├── req_llm 1.30.0
    │   └── zoi 0.19.0
    └── zoi 0.19.0
```

The BEAM module owner check returned `:jido` for `Jido.Agent`, `Jido.Action`, `Jido.Signal`, and `Jido.AI`.
The resolved graph and lock have no `jido_action`, `jido_signal`, or `jido_ai` package.
No sibling path dependency is selected. The same Chat Git pin applies in production.

Full dependency tree:

```text
jido_chat_telegram
├── covenant ~> 0.2.0 (Hex package)
│   └── yaml_elixir ~> 2.12 (Hex package)
│       └── yamerl ~> 0.10 (Hex package)
├── credo ~> 1.7 (Hex package)
│   ├── bunt ~> 0.2.1 or ~> 1.0 (Hex package)
│   ├── file_system ~> 0.2 or ~> 1.0 (Hex package)
│   └── jason ~> 1.0 (Hex package)
├── dialyxir ~> 1.4 (Hex package)
│   └── erlex >= 0.2.8 (Hex package)
├── doctor ~> 0.21 (Hex package)
│   └── decimal ~> 3.1 (Hex package)
├── dotenvy ~> 1.2 (Hex package)
├── ex_doc ~> 0.40.4 (Hex package)
│   ├── earmark_parser ~> 1.4.46 (Hex package)
│   ├── makeup_elixir ~> 0.14 or ~> 1.0 (Hex package)
│   │   ├── makeup ~> 1.0 (Hex package)
│   │   │   └── nimble_parsec ~> 1.4 (Hex package)
│   │   └── nimble_parsec ~> 1.2.3 or ~> 1.3 (Hex package)
│   └── makeup_erlang ~> 0.1 or ~> 1.0 (Hex package)
│       └── makeup ~> 1.0 (Hex package)
├── ex_gram ~> 0.69 (Hex package)
│   ├── jason >= 1.0.0 (Hex package)
│   ├── mdex ~> 0.11 (Hex package)
│   │   ├── jason ~> 1.0 (Hex package)
│   │   ├── mdex_native >= 0.2.11 (Hex package)
│   │   │   └── rustler_precompiled ~> 0.8 (Hex package)
│   │   ├── nimble_options ~> 1.0 (Hex package)
│   │   └── nimble_parsec ~> 1.0 (Hex package)
│   ├── nimble_ownership ~> 1.0 (Hex package)
│   ├── req ~> 0.6.1 or ~> 0.7 (Hex package)
│   └── telemetry ~> 0.4.3 or ~> 1.0 (Hex package)
├── excoveralls ~> 0.18 (Hex package)
│   └── jason ~> 1.0 (Hex package)
├── git_hooks ~> 0.8 (Hex package)
│   └── recase ~> 0.9.1 (Hex package)
├── git_ops ~> 2.9 (Hex package)
│   ├── git_cli ~> 0.2 (Hex package)
│   ├── jason ~> 1.0 (Hex package)
│   ├── nimble_parsec ~> 1.0 (Hex package)
│   └── req ~> 0.5 (Hex package)
├── jason ~> 1.4 (Hex package)
│   └── decimal ~> 1.0 or ~> 2.0 or ~> 3.0 (Hex package)
├── jido_chat (https://github.com/agentjido/jido_chat.git - 7652b6d74c4fc8170149ae1cfd08f981cfb1ea27)
│   ├── boundary ~> 0.11 (Hex package)
│   ├── jason ~> 1.4 (Hex package)
│   ├── jido (https://github.com/agentjido/jido.git - 05723b96c6ead47dec04fe69b1c34ad62f999c54) *override*
│   │   ├── multigraph ~> 0.16.1-mg.5 (Hex package)
│   │   ├── req_llm ~> 1.30 (Hex package)
│   │   │   ├── dotenvy ~> 1.2 (Hex package)
│   │   │   ├── finch ~> 0.24 (Hex package)
│   │   │   │   ├── mime ~> 1.0 or ~> 2.0 (Hex package)
│   │   │   │   ├── mint ~> 1.8 (Hex package)
│   │   │   │   │   └── hpax ~> 1.1 (Hex package)
│   │   │   │   ├── nimble_options ~> 0.4 or ~> 1.0 (Hex package)
│   │   │   │   ├── nimble_pool ~> 1.1 (Hex package)
│   │   │   │   └── telemetry ~> 0.4 or ~> 1.0 (Hex package)
│   │   │   ├── jason ~> 1.4 (Hex package)
│   │   │   ├── jsv >= 0.26.2 and < 1.0.0-0 (Hex package)
│   │   │   │   ├── abnf_parsec ~> 2.0 (Hex package)
│   │   │   │   │   └── nimble_parsec ~> 1.4 (Hex package)
│   │   │   │   ├── decimal ~> 2.0 or ~> 3.0 (Hex package)
│   │   │   │   ├── idna ~> 6.0 or ~> 7.0 (Hex package)
│   │   │   │   ├── jason ~> 1.0 (Hex package)
│   │   │   │   └── texture >= 1.2.1 (Hex package)
│   │   │   │       └── abnf_parsec ~> 2.0 (Hex package)
│   │   │   ├── llm_db ~> 2026.11.0 (Hex package)
│   │   │   │   ├── dotenvy ~> 1.2 (Hex package)
│   │   │   │   ├── jason ~> 1.4 (Hex package)
│   │   │   │   ├── req ~> 0.7 (Hex package)
│   │   │   │   ├── toml ~> 0.7 (Hex package)
│   │   │   │   └── zoi ~> 0.19.0 (Hex package)
│   │   │   ├── nimble_options ~> 1.2 (Hex package)
│   │   │   ├── req ~> 0.7 (Hex package)
│   │   │   ├── server_sent_events ~> 1.1.0 (Hex package)
│   │   │   ├── splode ~> 0.3.3 (Hex package)
│   │   │   ├── websockex ~> 0.5.1 (Hex package)
│   │   │   │   └── telemetry ~> 1.0 (Hex package)
│   │   │   └── zoi ~> 0.19.0 (Hex package)
│   │   ├── runic ~> 0.1.0-alpha.13 (Hex package)
│   │   │   ├── flow ~> 1.2 (Hex package)
│   │   │   │   └── gen_stage ~> 1.0 (Hex package)
│   │   │   ├── gen_stage ~> 1.2 (Hex package)
│   │   │   ├── multigraph ~> 0.16.1-mg.5 (Hex package)
│   │   │   ├── telemetry ~> 1.0 (Hex package)
│   │   │   └── uniq ~> 0.6.1 (Hex package)
│   │   ├── sched_ex ~> 1.2.1 (Hex package)
│   │   │   └── crontab ~> 1.1 (Hex package)
│   │   ├── spark ~> 2.7.3 (Hex package)
│   │   ├── splode ~> 0.3.0 (Hex package)
│   │   ├── telemetry ~> 1.3 (Hex package)
│   │   ├── telemetry_metrics ~> 1.2 (Hex package)
│   │   │   └── telemetry ~> 0.4 or ~> 1.0 (Hex package)
│   │   ├── yaml_elixir ~> 2.12 (Hex package)
│   │   └── zoi ~> 0.19.0 (Hex package)
│   ├── mdex ~> 0.14.2 (Hex package)
│   ├── spark ~> 2.7 (Hex package)
│   │   └── jason ~> 1.4 (Hex package)
│   ├── splode ~> 0.3.0 (Hex package)
│   └── zoi ~> 0.19.0 (Hex package)
│       └── decimal ~> 2.2 or ~> 3.0 (Hex package)
└── req ~> 0.7.1 (Hex package)
    ├── finch ~> 0.21 (Hex package)
    ├── jason ~> 1.0 (Hex package)
    └── mime ~> 2.0.6 or ~> 2.1 (Hex package)
```

## Publication limit and remaining work

`MIX_ENV=prod mix hex.build` fails with:

```text
Dependencies excluded from the package (only Hex packages can be dependencies): jido_chat
```

This is a Hex publication limit. Production compilation and the package behavior checks passed.
Keep the Git pin for this candidate. Do not remove the Hex validation gate.
Release consolidated Jido first, then Chat, then the adapters.
Before an adapter Hex release, replace the Git dependency with the released Chat constraint,
resolve the lock again, and run the same checks.

No live or paid provider calls ran. Live tests stayed excluded.
Provider credentials, permissions, remote delivery, webhooks, sockets, and external service behavior remain untested.
The current CI toolchain matrix was not reproduced locally. The verdict is self-checked.
No Chat/core, Mattermost, Messaging, or workspace task-list file was changed.
