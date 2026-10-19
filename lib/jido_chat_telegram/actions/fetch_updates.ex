defmodule Jido.Chat.Telegram.FetchUpdates do
  @moduledoc """
  Runs one Telegram fetch_updates operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction. Inputs and
  outputs use `%{signal: signal}`. Add `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_fetch_updates",
    signal: Jido.Chat.Telegram.Signal.FetchUpdates,
    result_schema: Schemas.updates_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:fetch_updates, client, signal, opts)
end
