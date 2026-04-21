# LLM Usage Rules for Jido Chat Telegram

`jido_chat_telegram` adapts Telegram Bot API behavior to the `Jido.Chat.Adapter`
contract.

## Working Rules

- Keep shared chat behavior in `Jido.Chat.Adapter` callbacks.
- Put Telegram-only helpers in `Jido.Chat.Telegram.Extensions`.
- Keep live API tests tagged `:live` and excluded by default.
- Do not commit `.env` or token values.
- Preserve the adapter boundary; runtime supervision belongs in `jido_messaging`.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
