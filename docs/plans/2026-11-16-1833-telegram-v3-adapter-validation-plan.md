---
title: Telegram adapter current Jido Chat V3 validation
type: implementation-plan
date: 2026-11-16
last_reviewed: 2026-11-16
artifact_contract: kata-plan/v1
artifact_readiness: complete
domain: software
execution: code
product_contract_source: approved-goal
---

# Telegram Adapter Current Jido Chat V3 Validation

## Goal Capsule

- Objective: Make the existing Telegram `release/v3` migration work with the
  current local Jido Chat V3 source and leave no retired messaging dependency
  or ownership reference.
- Means: Use the local Jido Chat path, resolve contract drift, keep native
  Signal and Source boundaries, update tests and documentation, run all
  offline gates, and complete an Elixir design review.
- Authority: Local Telegram and Jido Chat checks and local Telegram edits. No
  live Telegram request, credential use, commit, push, release, or remote
  update.
- Stop conditions: Stop before provider I/O, a core provider branch, managed
  runtime code in the adapter, or a compatibility API.
- Next executor: Elixir package engineer.

## Starting Evidence

- `release/v3` starts at `b909a31` and is clean.
- `main` and `origin/main` are at `fec15c9`; the V3 branch retains its existing
  migration history.
- The branch already uses `channel_type/0`, strict native or unsupported
  capabilities, `invoke/3`, `normalize/3`, extension operations, event
  definitions, the shared Adapter Test Kit, and `Jido.Chat.Sensor.Source`.
- Its Jido Chat dependency is an older fixed Git commit. This unit must
  test the current local Jido Chat V3 working tree, which includes completed
  durable runtime Units 1 through 3.
- `AGENTS.md`, `usage-rules.md`, one contract test, and the validation document
  still name the retired package or the old core commit.

## Product Contract

### Requirements

- **R1:** All environments use `path: "../jido_chat"` for this local migration.
  The dependency does not select an old Hex or Git Jido Chat source.
- **R2:** The public adapter remains stateless and implements the current V3
  callbacks and strict capability status values.
- **R3:** Polling uses `Jido.Chat.Sensor.Source`; webhook input can normalize
  directly. The adapter starts no managed process.
- **R4:** Core and Telegram-only native operations return current typed Signals.
  Unsupported operations stop before transport I/O.
- **R5:** Stable normalization identity, operation fixtures, streaming limits,
  checkpoint behavior, and secret isolation remain covered offline.
- **R6:** Package rules and documentation place managed chat runtime ownership
  in Jido Chat core and contain no retired package reference.
- **R7:** Normal tests make no live Telegram request. Live checks remain tagged
  and are reported as not run when credentials are not used.
- **R8:** Focused tests, full tests, contracts, coverage, quality, docs, unused
  dependencies, compile graph, diff check, and design review pass.

## Implementation Units

1. Replace the fixed Git core dependency with the local V3 path and refresh the
   lock without changing unrelated dependency versions.
2. Compile and run the offline suite to identify contract drift. Change only
   the adapter, Source, tests, or docs that the current V3 contract requires.
3. Remove obsolete package ownership references and replace old commit
   evidence with current local-source evidence.
4. Run the full verification contract and Elixir design review. Fix each
   supported finding and repeat affected checks.

## Verification Contract

Run from `/Users/mhostetler/Source/Jido/jido_chat/jido_chat_telegram`.

- `mix test` excludes all `:live` tests and passes without provider access.
- `mix test.contracts`, `mix coveralls`, `mix quality`, and `mix docs` pass.
- `mix deps.unlock --check-unused`, compile-connected xref cycles and stats,
  and `git diff --check` pass.
- Dependency evidence resolves Jido Chat from `../jido_chat`.
- A repository search finds no retired messaging package name, old Jido Chat
  Git pin, or V2 core API reference outside historical Git data.
- No accepted Elixir design-review finding remains.

## Risks and Mitigations

- Risk: the old V3 branch hides drift behind its locked core commit.
  Mitigation: use the current local path in every environment and regenerate
  the lock before tests.
- Risk: local dependency changes make release metadata look final. Mitigation:
  describe the path as local integration evidence; package publication remains
  outside this unit.
- Risk: polling tests call Telegram. Mitigation: keep live tests excluded and
  use transport fixtures for all normal tests.

## Definition of Done

- R1 through R8 have current evidence.
- Telegram is verified against the same Jido Chat V3 working tree that Assembly
  will use.
- The repository has no retired messaging dependency or ownership reference.
- No live provider check or remote change occurred.

## Execution Result

Completed in the local working tree on 2026-11-16. The branch and HEAD remain
`release/v3` at `b909a31`; no commit was created.

- Selected `../jido_chat` in every environment and removed the stale remote
  Jido Chat lock entry.
- Replaced the removed client option helper with explicit credentials, config,
  and transport fields.
- Kept credentials out of transport option lists and added direct contract
  evidence for that boundary.
- Kept bot identity settings in client config and provider tokens and webhook
  secrets in credentials.
- Updated package rules, README content, contract guidance, and validation
  evidence for the Jido Chat-owned Runtime and bridge boundary.
- Kept all live tests excluded. No Telegram credential or provider endpoint was
  used.

## Design Review Result

The Elixir design review found and fixed three issues.

1. An empty polling token produced a valid source identity. Empty and missing
   tokens now return no source key.
2. The suite did not prove that the new explicit client field access keeps
   credentials out of transport options. The Action contract now proves token
   and webhook secret keys are absent while normal adapter config remains.
3. V3 dependency, Runtime ownership, and sibling-guide text was stale. The
   documentation now describes the local path and Jido Chat ownership, and the
   generated documentation has no broken local guide link.

No accepted finding remains.

## Verification Result

- Focused review-fix tests: 22 passed.
- Full offline suite: 172 passed; 38 live tests excluded.
- Covenant: 25 tests passed; 18 of 18 obligations hold.
- Coverage: 93.0%.
- `mix quality`: passed, including Credo, Dialyzer, and Doctor.
- Documentation: HTML and Markdown generated without a package warning.
- Production compile with warnings as errors: passed. Dependency compiler
  warnings remain outside this package.
- Unused dependencies: none.
- Compile graph: 40 files, 39 compile edges, zero cycles.
- Dependency tree: Jido Chat resolves from `../jido_chat` and consolidated Jido
  resolves at `ec96da60`.
- Retired-package, removed-helper, old Hex constraint, and old Git-source scan:
  no matches.
- `git diff --check`: passed.

