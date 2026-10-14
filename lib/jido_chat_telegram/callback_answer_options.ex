defmodule Jido.Chat.Telegram.CallbackAnswerOptions do
  @moduledoc """
  Typed options for Telegram `answer_callback_query/2`.
  """

  alias Jido.Chat.Telegram.Transport.ExGramClient

  @schema Zoi.struct(
            __MODULE__,
            %{
              token: Zoi.string() |> Zoi.nullish(),
              transport: Zoi.any() |> Zoi.default(ExGramClient),
              adapter_opts: Zoi.any() |> Zoi.nullish(),
              text: Zoi.string() |> Zoi.nullish(),
              show_alert: Zoi.boolean() |> Zoi.nullish(),
              url: Zoi.string() |> Zoi.nullish(),
              cache_time: Zoi.integer() |> Zoi.nullish(),
              debug: Zoi.boolean() |> Zoi.nullish(),
              check_params: Zoi.boolean() |> Zoi.nullish(),
              ex_gram_module: Zoi.any() |> Zoi.nullish(),
              ex_gram_adapter: Zoi.any() |> Zoi.nullish()
            },
            coerce: true
          )

  @type t :: unquote(Zoi.type_spec(@schema))

  @enforce_keys Zoi.Struct.enforce_keys(@schema)
  defstruct Zoi.Struct.struct_fields(@schema)

  @doc "Returns the Zoi schema for callback answer options."
  def schema, do: @schema

  @doc "Builds typed callback answer options from keyword/map/struct input."
  def new(%__MODULE__{} = opts), do: opts
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()
  def new(opts) when is_map(opts), do: Jido.Chat.Schema.parse!(__MODULE__, @schema, opts)

  @doc "Builds Telegram API payload options for `answerCallbackQuery`."
  @spec payload_opts(t()) :: map()
  def payload_opts(%__MODULE__{} = opts) do
    %{}
    |> maybe_put("text", opts.text)
    |> maybe_put("show_alert", opts.show_alert)
    |> maybe_put("url", opts.url)
    |> maybe_put("cache_time", opts.cache_time)
  end

  @doc "Builds transport-level options consumed by `ExGramClient`."
  @spec transport_opts(t()) :: keyword()
  def transport_opts(%__MODULE__{} = opts) do
    []
    |> maybe_kw(:debug, opts.debug)
    |> maybe_kw(:check_params, opts.check_params)
    |> maybe_kw(:ex_gram_module, opts.ex_gram_module)
    |> maybe_kw(:ex_gram_adapter, opts.ex_gram_adapter)
    |> maybe_kw(:adapter_opts, opts.adapter_opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_kw(keyword, _key, nil), do: keyword
  defp maybe_kw(keyword, key, value), do: Keyword.put(keyword, key, value)
end
