defmodule Jido.Chat.Telegram.SendOptions do
  @moduledoc """
  Typed options for Telegram `send_message/3`.
  """

  alias Jido.Chat.Telegram.Transport.ExGramClient
  alias Jido.Chat.Telegram.ParseMode

  @schema Zoi.struct(
            __MODULE__,
            %{
              token: Zoi.string() |> Zoi.nullish(),
              transport: Zoi.any() |> Zoi.default(ExGramClient),
              parse_mode: Zoi.string() |> Zoi.nullish(),
              reply_to_message_id: Zoi.any() |> Zoi.nullish(),
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

  @doc "Returns the Zoi schema for send options."
  def schema, do: @schema

  @doc "Builds typed send options from keyword, map, or struct input."
  def new(%__MODULE__{} = opts), do: opts
  def new(opts) when is_list(opts), do: opts |> Map.new() |> new()

  def new(opts) when is_map(opts) do
    opts
    |> normalize_parse_mode()
    |> normalize_generic_reply_and_thread()
    |> then(&Jido.Chat.Schema.parse!(__MODULE__, @schema, &1))
  end

  @doc "Builds Telegram API payload options for `sendMessage`."
  @spec payload_opts(t()) :: map()
  def payload_opts(%__MODULE__{} = opts) do
    %{}
    |> maybe_put("parse_mode", opts.parse_mode)
    |> maybe_put("reply_to_message_id", opts.reply_to_message_id)
    |> maybe_put("disable_notification", opts.disable_notification)
    |> maybe_put("reply_markup", opts.reply_markup)
    |> maybe_put("message_thread_id", opts.thread_id)
    |> maybe_put("disable_web_page_preview", opts.disable_web_page_preview)
    |> maybe_put("entities", opts.entities)
    |> maybe_put("link_preview_options", opts.link_preview_options)
  end

  @doc "Builds transport-level options consumed by `ExGramClient`."
  @spec transport_opts(t()) :: keyword()
  def transport_opts(%__MODULE__{} = opts) do
    []
    |> maybe_kw(:debug, opts.debug)
    |> maybe_kw(:check_params, opts.check_params)
    |> maybe_kw(:ex_gram_module, opts.ex_gram_module)
    |> maybe_kw(:ex_gram_adapter, opts.ex_gram_adapter)
  end

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp maybe_kw(keyword, _key, nil), do: keyword
  defp maybe_kw(keyword, key, value), do: Keyword.put(keyword, key, value)

  defp normalize_parse_mode(opts) do
    case ParseMode.resolve_from_opts(opts) do
      nil -> opts
      parse_mode -> Map.put(opts, :parse_mode, parse_mode)
    end
  end

  defp normalize_generic_reply_and_thread(opts) do
    opts
    |> maybe_put_alias(:reply_to_message_id, [:reply_to_id])
    |> maybe_put_alias(:thread_id, [:external_thread_id])
  end

  defp maybe_put_alias(opts, target_key, source_keys) do
    target_value =
      Map.get(opts, target_key) ||
        Map.get(opts, Atom.to_string(target_key))

    source_value =
      Enum.find_value(source_keys, fn key ->
        Map.get(opts, key) || Map.get(opts, Atom.to_string(key))
      end)

    case {target_value, source_value} do
      {nil, nil} -> opts
      {nil, value} -> Map.put(opts, target_key, value)
      _ -> opts
    end
  end
end
