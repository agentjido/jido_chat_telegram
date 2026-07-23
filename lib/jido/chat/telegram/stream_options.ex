defmodule Jido.Chat.Telegram.StreamOptions do
  @moduledoc """
  Typed options for Telegram `stream/3`.
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
              draft_id: Zoi.integer() |> Zoi.nullish(),
              stream_update_interval_ms: Zoi.integer() |> Zoi.default(250),
              parse_mode: Zoi.string() |> Zoi.nullish(),
              rich_format: Zoi.enum([:markdown, :html]) |> Zoi.nullish(),
              disable_notification: Zoi.boolean() |> Zoi.nullish(),
              reply_markup: Zoi.any() |> Zoi.nullish(),
              thread_id: Zoi.any() |> Zoi.nullish(),
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

  @doc "Returns the Zoi schema for stream options."
  def schema, do: @schema

  @doc "Builds typed stream options from keyword, map, or struct input."
  def new(%__MODULE__{} = opts), do: opts
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    opts
    |> normalize_rich_format()
    |> normalize_parse_mode()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds the Telegram method and payload for a draft update."
  @spec draft_request(t(), integer(), String.t()) :: {String.t(), map()}
  def draft_request(%__MODULE__{rich_format: nil} = opts, draft_id, text)
      when is_integer(draft_id) and is_binary(text) do
    payload =
      %{}
      |> maybe_put("message_thread_id", opts.thread_id)
      |> Map.put("draft_id", draft_id)
      |> Map.put("text", text)
      |> maybe_put("parse_mode", opts.parse_mode)
      |> maybe_put("entities", opts.entities)

    {"sendMessageDraft", payload}
  end

  def draft_request(%__MODULE__{rich_format: rich_format} = opts, draft_id, text)
      when is_integer(draft_id) and is_binary(text) do
    payload =
      %{}
      |> maybe_put("message_thread_id", opts.thread_id)
      |> Map.put("draft_id", draft_id)
      |> Map.put("rich_message", %{Atom.to_string(rich_format) => text})

    {"sendRichMessageDraft", payload}
  end

  @doc "Builds keyword options for the final `send_message/3` call."
  @spec send_opts(t()) :: keyword()
  def send_opts(%__MODULE__{} = opts) do
    []
    |> maybe_kw(:token, opts.token)
    |> maybe_kw(:transport, opts.transport)
    |> maybe_kw(:parse_mode, opts.parse_mode)
    |> maybe_kw(:rich_format, opts.rich_format)
    |> maybe_kw(:disable_notification, opts.disable_notification)
    |> maybe_kw(:reply_markup, opts.reply_markup)
    |> maybe_kw(:thread_id, opts.thread_id)
    |> maybe_kw(:disable_web_page_preview, opts.disable_web_page_preview)
    |> maybe_kw(:entities, opts.entities)
    |> maybe_kw(:link_preview_options, opts.link_preview_options)
    |> maybe_kw(:debug, opts.debug)
    |> maybe_kw(:check_params, opts.check_params)
    |> maybe_kw(:ex_gram_module, opts.ex_gram_module)
    |> maybe_kw(:ex_gram_adapter, opts.ex_gram_adapter)
    |> maybe_kw(:url, opts.url)
    |> maybe_kw(:adapter_opts, opts.adapter_opts)
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
