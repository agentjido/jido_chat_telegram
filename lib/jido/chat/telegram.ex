defmodule Jido.Chat.Telegram do
  @moduledoc """
  Telegram adapter package for `Jido.Chat`.

  This package avoids Telegex and uses ExGram as the Telegram client.
  """

  alias Jido.Chat.Telegram.Adapter

  @doc "Returns the canonical Telegram adapter module."
  @spec adapter() :: module()
  def adapter, do: Adapter
end
