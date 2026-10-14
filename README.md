# Jido Chat Telegram

[![Hex.pm](https://img.shields.io/hexpm/v/jido_chat_telegram.svg)](https://hex.pm/packages/jido_chat_telegram)
[![Hex Docs](https://img.shields.io/badge/hex-docs-lightgreen.svg)](https://hexdocs.pm/jido_chat_telegram/)
[![CI](https://github.com/agentjido/jido_chat_telegram/actions/workflows/ci.yml/badge.svg)](https://github.com/agentjido/jido_chat_telegram/actions/workflows/ci.yml)
[![License](https://img.shields.io/hexpm/l/jido_chat_telegram.svg)](https://github.com/agentjido/jido_chat_telegram/blob/main/LICENSE)
[![Website](https://img.shields.io/badge/website-jido.run-0f172a.svg)](https://jido.run)
[![Ecosystem](https://img.shields.io/badge/ecosystem-jido.run-0ea5e9.svg)](https://jido.run/ecosystem)
[![Discord](https://img.shields.io/badge/discord-join-5865F2.svg?logo=discord&logoColor=white)](https://jido.run/discord)

`jido_chat_telegram` provides the `Jido.Chat.Telegram.Adapter` adapter for the public Chat Signal contract.

## Release status

This branch proposes version 2.0. It changes the public communication API.
Use the immutable PR source commits for review and tests. The new Hex releases
are not yet published. Production requires Chat 2.0 and compatible upstream
Signal releases. The dependency helpers keep source pins in development and test.

## Typed operations

The application supplies private binding options and a provider room ID:

```elixir
{:ok, binding} = Jido.Chat.bind(Jido.Chat.Telegram.Adapter, private_binding_options)
request = Jido.Chat.Signal.SendMessage.new!(%{
  "request_id" => "request-1",
  "room_id" => provider_room_id,
  "text" => "Hello"
})
{:ok, result} = Jido.Chat.execute(binding, request)
```

The result is an OperationCompleted or OperationFailed signal. Repeating an
admitted request uses its saved result. Private tokens, clients and resources
stay outside signal data. Unsupported operations return a defined typed result.

## Inbound delivery

Normalize one complete verified provider input unit with the configured binding:

```elixir
{:ok, delivery} = Jido.Chat.normalize_event(binding, verified_provider_input)
{:ok, observations} = MyApp.Messaging.accept_delivery(delivery)
```

The Messaging instance owns runtime acceptance. Deliveries retain ordered facts
and explicit item failures. Membership evidence does not create grants or start
message handlers. A rejected listener sink follows the provider checkpoint rule.
Configure protocol version 1 before starting provider listeners.

## Operation support

Native: `send_message`, `send_file`, `edit_message`, `delete_message`, `start_typing`, `fetch_metadata`, `fetch_media`, `add_reaction`, `remove_reaction`, `stream`, `open_thread`, `open_dm`.

Fallback: `post_message`, `fetch_thread`, `post_ephemeral`, `post_channel_message`.

All other operations are explicitly unsupported. See the frozen [adapter matrix](https://github.com/agentjido/jido_chat/blob/codex/public-signal-v3/docs/migration/adapter-matrix.json).

## Provider setup

Telegram uses ExGram. Webhooks and polling use the same native mapper. Private chat drafts support streaming. Group and channel targets use the declared fallback. Telegram extension helpers remain available for provider-specific media work.

## Checks and migration

Run `mix test` and `mix quality`. Live tests stay excluded by default. The fixed
provider fixtures do not need credentials or live traffic.

See the [migration guide](https://github.com/agentjido/jido_chat/blob/codex/public-signal-v3/docs/migration/MIGRATION_GUIDE.md)
for API mappings, the complete runnable local example, limits, release order and
rollback pins. Run `mix docs` to build this package's API documentation.
