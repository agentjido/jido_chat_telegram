defmodule Jido.Chat.Telegram.InlineKeyboardButton do
  @moduledoc """
  Typed inline keyboard button payload.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              text: Zoi.string(),
              callback_data: Zoi.string() |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              switch_inline_query: Zoi.string() |> Zoi.nullish(),
              switch_inline_query_current_chat: Zoi.string() |> Zoi.nullish(),
              pay: Zoi.boolean() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for InlineKeyboardButton."
  def schema, do: @schema

  @doc "Creates a typed inline keyboard button."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)

  @doc "Converts button to Telegram API wire map."
  @spec to_wire(t()) :: map()
  def to_wire(%__MODULE__{} = button) do
    button
    |> Map.from_struct()
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
    |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)
  end
end
