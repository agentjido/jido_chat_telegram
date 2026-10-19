# Jido Chat Telegram contracts

## V3 checkpoint

This branch requires the Jido v3 Chat API. All dependencies use Hex.
`jido_chat ~> 3.0.0-dev` is not published as of 2026-10-19.
Dependency resolution and tests remain blocked until a compatible release is available.
The lock file retains existing Hex entries; resolve it again after publication.

Covenant defines the public Telegram boundary under `test/contracts`. Each active
obligation has a literal tag on a named ExUnit test. The contract gate runs these
tests and requires a passing test for every active obligation.

| Component | Definition | Tests | Active obligations |
| --- | --- | --- | ---: |
| Adapter | [adapter.obligations.md](jido_chat_telegram/adapter.obligations.md) | [adapter_contract_test.exs](adapter_contract_test.exs) | 6 |
| Actions | [actions.obligations.md](jido_chat_telegram/actions.obligations.md) | [actions_contract_test.exs](actions_contract_test.exs) | 6 |
| Signals | [signals.obligations.md](jido_chat_telegram/signals.obligations.md) | [signals_contract_test.exs](signals_contract_test.exs) | 6 |

There are 18 active obligations and 25 tests. The tests cover all 14 Telegram
Actions, 42 Signal definitions, 12 supported core operations, and ten admitted
incoming event types. They use two client identities and fake credentials. A
recording transport checks exact provider methods and payloads without network I/O.

## Run

From the package root, with the local core dependency:

```sh
mix deps.get
mix test.contracts
mix coveralls
mix quality
```

Dependencies come from Hex. Normal `mix test`
also runs every contract test. CI runs both the full suite and `mix test.contracts`.
Covenant is a development and test dependency with `runtime: false`. It adds no
provider runtime. Live tests remain excluded by default.

To check tags without running tests:

```sh
mix covenant.check --static \
  --contracts test/contracts --test-path 'test/contracts/**/*_test.exs'
```

`coverage.json` records obligation coverage. `coverage.static.json` records static
tag coverage. ExCoveralls measures code coverage separately. Complete obligation
coverage does not mean complete code coverage or prove every possible behavior.

## Fixed fixtures

- `fixtures/telegram_signals.json`: all 42 literal identities, data schemas, and valid examples.
- `fixtures/provider_cases.json`: 14 independent request, wire payload, provider reply, and result examples.
- `fixtures/adapter_api.json`: public exports of six modules, core support statuses, and admitted events.
- `fixtures/incoming_updates.json`: nine provider updates with expected ordered facts for all ten event types.
- `support/fixtures_helper.exs`: recording transport, explicit clients, public API helpers, and a mixed core/provider Flow.

Tests do not regenerate these fixtures. Review every export, schema, or provider
payload change. Keep existing obligation IDs stable. Retire an obsolete
obligation with `status: retired`; do not reuse its number or skip its test to
accept an accidental breaking change.

The Signal schema fixture fixes JSON data schemas. The shared Chat Action
boundary enforces accepted request privacy, causal context, client references,
and encoded size. Provider request construction alone is not the complete
execution boundary. FetchUpdates returns serialized incoming facts; decode them
with the configured Chat catalog. The host owns acknowledgement and offset storage.

Rendering details and HTTP transport cases remain in regular unit tests. The two
provider live suites prove real Telegram behavior and include an explicit Desktop
callback. The startup metadata checks have a narrow scope; they do not prove the
absence of all possible hidden state.
