defmodule Jido.Chat.Telegram.FileInfo do
  @moduledoc """
  Metadata returned by Telegram when resolving a file reference.
  """

  @schema Zoi.struct(
            __MODULE__,
            %{
              file_id: Zoi.string(),
              file_unique_id: Zoi.string() |> Zoi.nullish(),
              file_size: Zoi.integer() |> Zoi.nullish(),
              file_path: Zoi.string() |> Zoi.nullish(),
              raw: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for FileInfo."
  def schema, do: @schema

  @doc "Creates typed Telegram file metadata."
  def new(%__MODULE__{} = file), do: file

  def new(attrs) when is_map(attrs),
    do: Jido.Chat.Schema.parse!(__MODULE__, @schema, attrs)
end
