defmodule Jido.Chat.Telegram.SendAnimation do
  @moduledoc """
  Runs one Telegram send_animation operation with an explicit Client.

  Use `Jido.Exec.run/3`, Jido Flow, or a Router-selected Instruction. Inputs and
  outputs use `%{signal: signal}`. Add `signal_definitions/0` to the host catalog.
  """
  alias Jido.Chat.Telegram.Signal.Schemas

  use Jido.ChatAction,
    name: "telegram_send_animation",
    signal: Jido.Chat.Telegram.Signal.SendAnimation,
    result_schema: Schemas.media_result()

  @impl Jido.ChatAction
  def invoke(client, signal, opts),
    do: Jido.Chat.Telegram.Operations.invoke(:send_animation, client, signal, opts)
end
