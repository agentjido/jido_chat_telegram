defmodule Jido.Chat.Telegram.InlineKeyboard do
  @moduledoc """
  Typed inline keyboard wrapper for Telegram reply_markup payloads.
  """

  alias Jido.Chat.Telegram.InlineKeyboardButton

  @schema Zoi.struct(
            __MODULE__,
            %{
              rows:
                Zoi.array(Zoi.array(Zoi.struct(InlineKeyboardButton)))
                |> Zoi.default([])
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for InlineKeyboard."
  def schema, do: @schema

  @doc "Creates a typed inline keyboard from rows."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_rows()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Converts inline keyboard to Telegram reply_markup wire shape."
  @spec to_reply_markup(t()) :: map()
  def to_reply_markup(%__MODULE__{} = keyboard) do
    %{
      "inline_keyboard" =>
        Enum.map(keyboard.rows, fn row ->
          Enum.map(row, &InlineKeyboardButton.to_wire/1)
        end)
    }
  end

  defp normalize_rows(attrs) do
    rows = attrs[:rows] || attrs["rows"] || []

    normalized =
      Enum.map(rows, fn
        row when is_list(row) ->
          Enum.map(row, fn
            %InlineKeyboardButton{} = button -> button
            map when is_map(map) -> InlineKeyboardButton.new(map)
            other -> other
          end)

        other ->
          other
      end)

    Map.put(attrs, :rows, normalized)
  end
end
