defmodule Jido.Chat.Telegram.CallbackAnswerResult do
  @moduledoc """
  Typed callback query answer result.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              callback_query_id: Zoi.string(),
              answered: Zoi.boolean() |> Zoi.default(true),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for CallbackAnswerResult."
  def schema, do: @schema

  @doc "Creates a typed callback answer result."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end
end
