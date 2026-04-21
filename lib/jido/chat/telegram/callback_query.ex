defmodule Jido.Chat.Telegram.CallbackQuery do
  @moduledoc """
  Typed callback query payload for Telegram action-style updates.
  """

  alias Jido.Chat.Author
  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              data: Zoi.string() |> Zoi.nullish(),
              from: Zoi.struct(Author) |> Zoi.nullish(),
              chat_id: Zoi.any() |> Zoi.nullish(),
              message_id: Zoi.any() |> Zoi.nullish(),
              inline_message_id: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for CallbackQuery."
  def schema, do: @schema

  @doc "Creates a typed callback query struct."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> normalize_from()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes callback query into a plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = callback_query) do
    callback_query
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "telegram_callback_query")
  end

  @doc "Builds callback query from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)

  defp normalize_from(attrs) do
    from = attrs[:from] || attrs["from"]

    author =
      case from do
        %Author{} = author ->
          author

        map when is_map(map) ->
          Author.new(%{
            user_id: to_string(map[:id] || map["id"] || "unknown"),
            user_name: map[:username] || map["username"] || to_string(map[:id] || map["id"] || "unknown"),
            full_name: map[:first_name] || map["first_name"],
            is_bot: map[:is_bot] || map["is_bot"] || false
          })

        _ ->
          nil
      end

    if is_nil(author), do: attrs, else: Map.put(attrs, :from, author)
  end
end
