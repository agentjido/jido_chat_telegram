# Telegram Covenant verification — 2026-10-18

Covenant 0.2.0 now defines the adapter, Telegram Actions, and Signal contracts in
`test/contracts`. It is a development and test dependency with `runtime: false`.
The contract tests make no network call. This change adds no production runtime
or provider API.

## Contract scope

| Component | Active obligations | Tests | Boundary |
| --- | ---: | ---: | --- |
| Adapter | 6 | 8 | Six public module export sets; 12 supported core operations; ten incoming event types; two clients; files; offsets; stream delivery |
| Actions | 6 | 9 | All 14 extensions through Exec and Chat; exact provider calls; typed results; safe failures; private webhooks; Flow, Router, Instruction, and Dispatch; agent input |
| Signals | 6 | 8 | All 42 identities and JSON data schemas; constructors; serialization; causal context; private data checks at execution; Telegram constraints; encoded size and batch limits |
| Total | 18 | 25 | Every active obligation has a passing tagged test |

The [contract index](../test/contracts/README.md) links definitions to tests.
The tests use fake credentials and a recording transport. Fixed fixtures contain
14 independent provider call examples, nine incoming updates, all 42 schemas,
capabilities, admitted events, and public exports. Tests never update fixtures.
CI now runs `mix test && mix test.contracts`.

## Results

All provider checks used the local `jido_chat` dependency.

| Check | Result |
| --- | --- |
| Telegram `mix test.contracts` | 25 tests passed; 18/18 active obligations covered |
| Static Covenant check | Three test modules; 25 tagged tests; 18/18 obligations found |
| Telegram `mix coveralls` | 165 tests passed; 38 live tests excluded; 93.1% code coverage |
| Core `mix coveralls` | 258 tests passed; 93.7% code coverage |
| Telegram `mix quality` | Passed format, compile, Credo, Dialyzer, and Doctor |
| Telegram `mix docs --warnings-as-errors` | Passed |
| Telegram public API live suite | 21 tests passed |
| Telegram Action live suite | 16 automatic tests passed; final Desktop callback passed in a focused repeat |
| `git diff --check` | Passed |

The public API live run ID was `1792324298670501`. It checked all eleven main
operation helpers, capabilities, real file bytes, draft and edit streams, replies,
keyboards, reactions, room metadata, typing, forum topic creation, provider
rejection, and one explicit normalized update pull. No live test was skipped.

The Action live suite passed its first 16 tests. The final Desktop callback test
first timed out after ten minutes without a click. A longer repeat stopped on a
provider failure while pulling updates. The next focused repeat passed in 9.1
seconds, with callback run ID `1792327187394348`. Telegram Desktop showed the fresh
verification button before the click. The test received the click as a native
Signal, answered it through AnswerCallbackQuery, edited the source message, and
passed the Dispatch and Bus checks. The test then removed its temporary message.

All 38 distinct live tests passed across these completed runs: 21 public API
tests, 16 automatic Action tests, and the final Desktop callback test. This was
not one uninterrupted run of all 38 tests. No production code change was needed
for the successful repeat.

## Focused mutation check

An isolated Covenant worker changed `Telegram.Adapter.channel_type/0` from
`:telegram` to `nil`. The discovery contract detected the change. The original
eight adapter tests passed before the mutation. The adapter source file hash was
unchanged after the run. This was one selected mutation, not a complete mutation
assessment of the package.

The command used an explicit project root to avoid the Covenant 0.2.0 root
discovery issue found in the core verification. An absolute core dependency path
also lets the isolated worker find the local SDK:

```sh
env JIDO_CHAT_PATH="$PWD/../jido_chat" COVENANT_ROOT="$PWD" MIX_ENV=test \
  mix covenant.mutate jido_chat_telegram.adapter \
  --module Jido.Chat.Telegram.Adapter --only m001 --timeout 1500 \
  --max-runtime 120000 --out tmp/covenant/adapter_probe.json
```

The `m001` selection applies to this source revision. Check the printed mutation
site before reusing it after a source change.

## Limits

Obligation coverage and code coverage are separate measurements. Static tag
coverage does not execute behavior. Constructor schemas define typed data; the
shared Chat Action boundary also enforces accepted request privacy, context,
client references, and encoded size. Incoming update tests compare stable
projections because Signal IDs and trace context are generated on each call.
HTTP transport details remain in regular unit tests. Startup metadata checks do
not prove the absence of every possible hidden state. The host continues to own
polling loops, acknowledgements, offsets, storage, and retries.
