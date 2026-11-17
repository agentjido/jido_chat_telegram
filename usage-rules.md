# LLM Usage Rules for Jido Chat Telegram

`jido_chat_telegram` adapts Telegram Bot API behavior to the `Jido.Chat.Adapter`
contract.

## Working Rules

- Keep shared chat behavior in `Jido.Chat.Adapter` callbacks.
- Use flat Telegram Actions and native request/result Signals for Telegram-only operations.
- Keep live API tests tagged `:live` and excluded by default.
- Do not commit `.env` or token values.
- Preserve the adapter boundary; managed runtime supervision belongs in Jido Chat core.
- Run `mix test`, `mix quality`, and `mix coveralls` before release work.
