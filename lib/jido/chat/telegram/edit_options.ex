defmodule Jido.Chat.Telegram.EditOptions do
  @moduledoc """
  Typed options for Telegram `edit_message/4`.
  """

  alias Jido.Chat.Telegram.Transport.ExGramClient
  alias Jido.Chat.Telegram.ParseMode

  @schema Zoi.struct(
            __MODULE__,
            %{
              token: Zoi.string() |> Zoi.nullish(),
              transport: Zoi.any() |> Zoi.default(ExGramClient),
              url: Zoi.string() |> Zoi.nullish(),
              adapter_opts: Zoi.any() |> Zoi.nullish(),
              parse_mode: Zoi.string() |> Zoi.nullish(),
              rich_format: Zoi.any() |> Zoi.nullish(),
              reply_markup: Zoi.any() |> Zoi.nullish(),
              disable_web_page_preview: Zoi.boolean() |> Zoi.nullish(),
              entities: Zoi.any() |> Zoi.nullish(),
              link_preview_options: Zoi.any() |> Zoi.nullish(),
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

  @doc "Returns the Zoi schema for edit options."
  def schema, do: @schema

  @doc "Builds typed edit options from keyword, map, or struct input."
  def new(%__MODULE__{} = opts), do: opts
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    opts
    |> normalize_rich_format()
    |> normalize_parse_mode()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds Telegram API payload options for `editMessageText`."
  @spec payload_opts(t()) :: map()
  def payload_opts(%__MODULE__{} = opts) do
    %{}
    |> maybe_put("parse_mode", opts.parse_mode)
    |> maybe_put("reply_markup", opts.reply_markup)
    |> maybe_put("disable_web_page_preview", opts.disable_web_page_preview)
    |> maybe_put("entities", opts.entities)
    |> maybe_put("link_preview_options", opts.link_preview_options)
  end

  @doc """
  Builds Telegram API payload options for a rich `editMessageText`.

  Rich messages carry their own formatting inside `rich_message`, so `parse_mode`,
  `entities`, and the link-preview options are not valid here and are dropped.
  """
  @spec rich_payload_opts(t()) :: map()
  def rich_payload_opts(%__MODULE__{} = opts) do
    %{}
    |> maybe_put("reply_markup", opts.reply_markup)
  end

  @doc "Builds transport-level options consumed by `ExGramClient`."
  @spec transport_opts(t()) :: keyword()
  def transport_opts(%__MODULE__{} = opts) do
    []
    |> maybe_kw(:debug, opts.debug)
    |> maybe_kw(:check_params, opts.check_params)
    |> maybe_kw(:ex_gram_module, opts.ex_gram_module)
    |> maybe_kw(:ex_gram_adapter, opts.ex_gram_adapter)
    |> maybe_kw(:url, opts.url)
    |> maybe_kw(:adapter_opts, opts.adapter_opts)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_kw(keyword, _key, nil), do: keyword
  defp maybe_kw(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp normalize_rich_format(opts) do
    case ParseMode.resolve_rich_format(opts) do
      nil -> opts
      rich_format -> Map.put(opts, :rich_format, rich_format)
    end
  end

  # Rich messages are parsed server-side: `parse_mode` is not a valid `sendRichMessage`
  # option and is dropped from the payload, so inferring one here would only mislead.
  defp normalize_parse_mode(%{rich_format: rich_format} = opts) when not is_nil(rich_format),
    do: opts

  defp normalize_parse_mode(opts) do
    case ParseMode.resolve_from_opts(opts) do
      nil -> opts
      parse_mode -> Map.put(opts, :parse_mode, parse_mode)
    end
  end
end
