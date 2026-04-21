# Jido Chat Telegram

`jido_chat_telegram` is the Telegram adapter package for `jido_chat`.

## Release Status

This package is being prepared for the Jido 1.x chat package release line.
It is part of the Elixir implementation aligned to the Vercel Chat SDK
([chat-sdk.dev/docs](https://www.chat-sdk.dev/docs)).

`Jido.Chat.Telegram.Adapter` is the canonical adapter module and uses `ExGram` as the Telegram client.
No Telegex dependency is required.

## Installation

```elixir
def deps do
  [
    {:jido_chat, github: "agentjido/jido_chat", branch: "main"},
    {:jido_chat_telegram, github: "agentjido/jido_chat_telegram", branch: "main"}
  ]
end
```

## Usage

```elixir
alias Jido.Chat.Telegram.Adapter

{:ok, incoming} =
  Adapter.transform_incoming(%{
    "message" => %{
      "message_id" => 42,
      "date" => 1_706_745_600,
      "chat" => %{"id" => 123, "type" => "private"},
      "from" => %{"id" => 99, "first_name" => "Alice"},
      "text" => "hello"
    }
  })

{:ok, sent} =
  Adapter.send_message(123, "hi", token: System.fetch_env!("TELEGRAM_BOT_TOKEN"))
```

`ExGram` is used under the hood, with a Req-backed adapter by default.

## Streaming Responses

Telegram live-response streaming is supported for private chats with numeric chat IDs.
The adapter uses Telegram Bot API drafts to progressively render text in the client,
then sends one final canonical message when generation completes.

```elixir
chunks =
  Stream.concat([
    ["Hello"],
    Stream.map([" from Telegram"], fn chunk ->
      Process.sleep(300)
      chunk
    end)
  ])

{:ok, sent} =
  Jido.Chat.Adapter.stream(
    Jido.Chat.Telegram.Adapter,
    123_456_789,
    chunks,
    token: System.fetch_env!("TELEGRAM_BOT_TOKEN")
  )
```

Notes:

- This is Telegram UI streaming, not a change to Elixir stream semantics.
- Draft streaming is only attempted for private chats with numeric chat IDs.
- Group/channel targets fall back to a single final `sendMessage`.
- The returned response always comes from the final sent message.
- For manual verification in the Telegram client, use a long payload with
  noticeable pauses between chunks. Very short payloads can appear to land as a
  single final message even when draft updates are being accepted by the API.

## Telegram Extension Surface

For Telegram-specific features that are intentionally outside core `Jido.Chat.Adapter`,
use `Jido.Chat.Telegram.Extensions`:

```elixir
alias Jido.Chat.Telegram.Extensions

# Telegram-only media send helpers
{:ok, photo} =
  Extensions.send_photo(123, "AgACAg...", token: System.fetch_env!("TELEGRAM_BOT_TOKEN"))

{:ok, document} =
  Extensions.send_document(123, "BQACAg...", token: System.fetch_env!("TELEGRAM_BOT_TOKEN"))

# Telegram-only callback query answer helper
:ok =
  Extensions.answer_callback_query("1234567890", token: System.fetch_env!("TELEGRAM_BOT_TOKEN"))
  |> case do
    {:ok, _result} -> :ok
    other -> other
  end
```

Typed extension structs are provided for:

- `Jido.Chat.Telegram.UpdateEnvelope`
- `Jido.Chat.Telegram.CallbackQuery`
- `Jido.Chat.Telegram.InlineKeyboard` / `InlineKeyboardButton`
- `Jido.Chat.Telegram.MediaMessage`

## Config

You can pass `:token` per call, or configure globally:

```elixir
config :jido_chat_telegram, :telegram_bot_token, System.get_env("TELEGRAM_BOT_TOKEN")
```

For tests, this package will automatically load `.env` and `.env.test` via `dotenvy`
from `test/test_helper.exs`.

## Ingress Modes (`listener_child_specs/2`)

The Telegram adapter ingress callback supports:

- `ingress.mode = "webhook"`: no listener workers (`{:ok, []}`), host HTTP handles webhook ingress.
- `ingress.mode = "polling"`: starts `PollingWorker` and emits updates via `sink_mfa`.

Example:

```elixir
{:ok, specs} =
  Jido.Chat.Telegram.Adapter.listener_child_specs("bridge_tg",
    ingress: %{mode: "polling", token: System.fetch_env!("TELEGRAM_BOT_TOKEN")},
    sink_mfa: {Jido.Messaging.IngressSink, :emit, [MyApp.Messaging, "bridge_tg"]}
  )
```

## Live Integration Test

There is a live test module at:

- `test/jido/chat/telegram/live_integration_test.exs`

It is skipped by default. To run it:

1. Start a private chat with your bot and send at least one message (`/start` is fine).
2. Copy and fill local env file:

```bash
cp .env.example .env
```

3. Run:

```bash
mix test test/jido/chat/telegram/live_integration_test.exs
```

Current live coverage in that file includes:

- send, edit, and delete
- typing and metadata
- streaming draft updates and final message send
- reply continuity and optional topic routing
- local file uploads from disk paths and in-memory byte payloads
- forum topic creation via `open_thread/3` when `TELEGRAM_TEST_FORUM_CHAT_ID` is set
- reactions, with explicit unsupported acceptance when the Bot API feature is unavailable
- media sends through `Jido.Chat.Telegram.Extensions`
- canonical media sends through `send_file/3` and core `post_message/4`
- webhook-shaped ingress
- unsupported-core contract checks

If you need `TELEGRAM_TEST_CHAT_ID`, use the helper script:

```bash
scripts/telegram_get_chat_id.sh --clear-webhook
```

For live update logs while chatting with your bot from Telegram:

```bash
scripts/telegram_watch_updates.sh --clear-webhook
```

Additional helper:

- `scripts/telegram_delete_webhook.sh`
