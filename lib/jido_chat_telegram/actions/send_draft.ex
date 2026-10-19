defmodule Jido.Chat.Telegram.SendDraft do
  @moduledoc """
  Runs one Telegram send_draft operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction. Inputs and
  outputs use `%{signal: signal}`. Add `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_send_draft",
    signal: Jido.Chat.Telegram.Signal.SendDraft,
    result_schema: Schemas.draft_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:send_draft, client, signal, opts)
end
