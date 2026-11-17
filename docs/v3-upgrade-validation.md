# Jido Chat V3 validation: Telegram

Date: 2026-11-16 (America/Chicago).

## Scope

The Telegram `release/v3` branch is validated against the current sibling
`../jido_chat` working tree. The core uses consolidated Jido V3. This is local
integration evidence. It is not Hex publication or live provider evidence.

The adapter keeps the V3 boundaries:

- one stateless `Jido.Chat.Adapter`;
- strict native or unsupported capability values;
- core and Telegram-only typed Actions and Signals;
- one `Jido.Chat.Sensor.Source` for host-owned polling;
- provider credentials in `Client.credentials`;
- adapter settings in `Client.config`;
- provider transport in `Client.transport`;
- no managed process tree in the adapter.

## Current migration changes

- Replaced the fixed remote Jido Chat source with `path: "../jido_chat"` for
  every local environment.
- Removed the stale Jido Chat lock entry and selected the consolidated Jido V3
  commit required by the local core.
- Replaced the removed credential-merging client helper with explicit field
  access. Credentials no longer enter the private transport option list.
- Kept bot identity settings in `Client.config` and the token and webhook
  secret in `Client.credentials`.
- Made a missing or empty polling token return no source key.
- Updated package rules and guides to place managed Runtime and bridge binding
  ownership in Jido Chat core.

## Offline evidence

Normal tests use fixed fixtures and local recording transports. They make no
Telegram request. Live tests keep the `:live` tag and remain excluded by
default.

The full offline result is 172 tests passed and 38 live tests excluded.
Covenant passed 25 tests and all 18 obligations. Coverage is 93.0%. Quality,
documentation, production compile, unused-dependency, compile-graph, and diff
checks pass. The compile graph has 40 files, 39 compile edges, and zero cycles.
The completed design review and exact evidence are in the unit plan.

## Dependency boundary

```text
jido_chat_telegram
└── jido_chat (path: ../jido_chat)
    └── jido (consolidated V3 source selected by Jido Chat)
```

The adapter lock contains no Jido Chat remote source. Package publication must
later replace the local path with the released Jido Chat V3 Hex constraint and
repeat the same gates.

## Live evidence

No live or paid provider call ran. Telegram credentials, permissions, remote
delivery, webhooks, polling coexistence, and external service behavior are not
verified by this local unit.
