defmodule Jido.Chat.Telegram.AnswerCallbackQuery do
  @moduledoc """
  Runs one Telegram answer_callback_query operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction. Inputs and
  outputs use `%{signal: signal}`. Add `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_answer_callback_query",
    signal: Jido.Chat.Telegram.Signal.AnswerCallbackQuery,
    result_schema: Schemas.callback_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:answer_callback_query, client, signal, opts)
end
