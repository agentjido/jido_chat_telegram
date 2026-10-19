defmodule Jido.Chat.Telegram.GetFile do
  @moduledoc """
  Runs one Telegram get_file operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction. Inputs and
  outputs use `%{signal: signal}`. Add `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_get_file",
    signal: Jido.Chat.Telegram.Signal.GetFile,
    result_schema: Schemas.file_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:get_file, client, signal, opts)
end
