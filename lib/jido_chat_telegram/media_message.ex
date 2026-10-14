defmodule Jido.Chat.Telegram.MediaMessage do
  @moduledoc """
  Typed Telegram media send result (photo/document/media-group).
  """

  alias Jido.Chat.Wire

  @schema Zoi.struct(
            __MODULE__,
            %{
              id: Zoi.string(),
              kind: Zoi.enum([:photo, :document, :media_group]),
              message_id: Zoi.string() |> Zoi.nullish(),
              chat_id: Zoi.any() |> Zoi.nullish(),
              date: Zoi.any() |> Zoi.nullish(),
              caption: Zoi.string() |> Zoi.nullish(),
              file_id: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish(),
              metadata: Zoi.map() |> Zoi.default(%{})
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for MediaMessage."
  def schema, do: @schema

  @doc "Creates a typed media send result."
  @spec new(map()) :: t()
  def new(attrs) when is_map(attrs) do
    attrs
    |> Map.put_new(:id, Jido.Chat.ID.generate!())
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Serializes media message into plain map with type marker."
  @spec to_map(t()) :: map()
  def to_map(%__MODULE__{} = result) do
    result
    |> Map.from_struct()
    |> Wire.to_plain()
    |> Map.put("__type__", "telegram_media_message")
  end

  @doc "Builds media message from serialized map data."
  @spec from_map(map()) :: t()
  def from_map(map) when is_map(map), do: new(map)
end
