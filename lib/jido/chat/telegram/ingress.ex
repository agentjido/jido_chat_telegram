defmodule Jido.Chat.Telegram.Ingress do
  @moduledoc """
  Telegram ingress configuration and webhook subscription helpers.

  `jido_messaging` treats ingress subscription callbacks as optional adapter
  extensions. Telegram maps those callbacks to the bot webhook control plane.
  Polling ingress is host-supervised, so subscription provisioning is not
  applicable there.
  """

  alias Jido.Chat.Telegram.Transport.ExGramClient

  @type mode :: :webhook | :polling | :invalid
  @type subscription_result :: {:ok, map()} | {:error, term()}
  @type subscription_list_result :: {:ok, [map()]} | {:error, term()}

  @doc "Normalizes ingress settings from adapter callback options."
  @spec normalize_opts(keyword()) :: map()
  def normalize_opts(opts) when is_list(opts) do
    settings_ingress =
      opts
      |> Keyword.get(:settings, %{})
      |> ensure_map()
      |> map_get([:ingress, "ingress"])
      |> ensure_map()
      |> normalize_ingress_map()

    ingress =
      opts
      |> Keyword.get(:ingress, %{})
      |> ensure_map()
      |> normalize_ingress_map()

    Map.merge(settings_ingress, ingress)
  end

  @doc "Returns the effective ingress mode."
  @spec mode(map()) :: mode()
  def mode(ingress) when is_map(ingress) do
    case map_get(ingress, [:mode, "mode"]) do
      nil -> :webhook
      :webhook -> :webhook
      :polling -> :polling
      value when is_binary(value) -> string_mode(value)
      _ -> :invalid
    end
  end

  @doc "Ensures the Telegram webhook subscription for a bridge."
  @spec ensure_subscription(String.t(), keyword()) :: subscription_result()
  def ensure_subscription(bridge_id, opts) when is_binary(bridge_id) and is_list(opts) do
    ingress = normalize_opts(opts)

    with :ok <- ensure_webhook_mode(ingress),
         {:ok, target_url} <- target_url(opts, ingress),
         {:ok, token} <- token(opts, ingress),
         {:ok, result} <-
           transport(opts).call(
             token,
             "setWebhook",
             webhook_payload(target_url, opts, ingress),
             transport_opts(opts, ingress)
           ) do
      {:ok, subscription(bridge_id, target_url, :active, provider_raw("setWebhook", result))}
    end
  end

  @doc "Lists the active Telegram webhook subscription for a bridge."
  @spec list_subscriptions(String.t(), keyword()) :: subscription_list_result()
  def list_subscriptions(bridge_id, opts) when is_binary(bridge_id) and is_list(opts) do
    ingress = normalize_opts(opts)

    with :ok <- ensure_webhook_mode(ingress),
         {:ok, token} <- token(opts, ingress),
         {:ok, result} <-
           transport(opts).call(
             token,
             "getWebhookInfo",
             %{},
             transport_opts(opts, ingress)
           ) do
      {:ok, subscriptions_from_webhook_info(bridge_id, result)}
    end
  end

  @doc "Deletes the Telegram webhook subscription for a bridge."
  @spec delete_subscription(String.t(), String.t(), keyword()) :: subscription_result()
  def delete_subscription(bridge_id, subscription_id, opts)
      when is_binary(bridge_id) and is_binary(subscription_id) and is_list(opts) do
    ingress = normalize_opts(opts)

    with :ok <- ensure_webhook_mode(ingress),
         {:ok, token} <- token(opts, ingress),
         {:ok, result} <-
           transport(opts).call(
             token,
             "deleteWebhook",
             delete_webhook_payload(opts, ingress),
             transport_opts(opts, ingress)
           ) do
      {:ok,
       subscription(bridge_id, target_url(opts, ingress, nil), :deleted, provider_raw("deleteWebhook", result),
         subscription_id: subscription_id
       )}
    end
  end

  defp string_mode(value) do
    case value |> String.trim() |> String.downcase() do
      "webhook" -> :webhook
      "polling" -> :polling
      _ -> :invalid
    end
  end

  defp normalize_ingress_map(map) when is_map(map) do
    Map.new(map, fn {key, value} -> {ingress_key(key), value} end)
  end

  defp ingress_key("allowed_updates"), do: :allowed_updates
  defp ingress_key("certificate"), do: :certificate
  defp ingress_key("drop_pending_updates"), do: :drop_pending_updates
  defp ingress_key("ip_address"), do: :ip_address
  defp ingress_key("max_connections"), do: :max_connections
  defp ingress_key("mode"), do: :mode
  defp ingress_key("raw"), do: :raw
  defp ingress_key("raw_payload"), do: :raw_payload
  defp ingress_key("secret_token"), do: :secret_token
  defp ingress_key("target_url"), do: :target_url
  defp ingress_key("token"), do: :token
  defp ingress_key("transport"), do: :transport
  defp ingress_key("transport_opts"), do: :transport_opts
  defp ingress_key("url"), do: :url
  defp ingress_key("webhook_url"), do: :webhook_url
  defp ingress_key(key), do: key

  defp ensure_webhook_mode(ingress) do
    case mode(ingress) do
      :webhook -> :ok
      :polling -> {:error, :unsupported}
      :invalid -> {:error, :invalid_ingress_mode}
    end
  end

  defp target_url(opts, ingress) do
    case target_url(opts, ingress, nil) do
      nil -> {:error, :missing_webhook_url}
      target_url -> {:ok, stringify(target_url)}
    end
  end

  defp target_url(opts, ingress, default) do
    first_present([
      Keyword.get(opts, :target_url),
      Keyword.get(opts, :webhook_url),
      Keyword.get(opts, :url),
      map_get(ingress, [:target_url, "target_url"]),
      map_get(ingress, [:webhook_url, "webhook_url"]),
      map_get(ingress, [:url, "url"]),
      default
    ])
  end

  defp token(opts, ingress) do
    case first_present([
           Keyword.get(opts, :token),
           map_get(ingress, [:token, "token"]),
           map_get(credentials(opts), [:token, "token"]),
           Application.get_env(:jido_chat_telegram, :telegram_bot_token)
         ]) do
      nil -> {:error, :missing_token}
      token -> {:ok, stringify(token)}
    end
  end

  defp credentials(opts) do
    opts
    |> Keyword.get(:bridge_config)
    |> bridge_credentials()
    |> Map.merge(opts |> Keyword.get(:credentials, %{}) |> ensure_map())
  end

  defp bridge_credentials(%{credentials: credentials}), do: ensure_map(credentials)
  defp bridge_credentials(_), do: %{}

  defp webhook_payload(target_url, opts, ingress) do
    opts
    |> raw_webhook_payload(ingress)
    |> Map.put("url", target_url)
    |> maybe_put("certificate", option(opts, ingress, :certificate))
    |> maybe_put("ip_address", option(opts, ingress, :ip_address))
    |> maybe_put("max_connections", option(opts, ingress, :max_connections))
    |> maybe_put("allowed_updates", option(opts, ingress, :allowed_updates))
    |> maybe_put("drop_pending_updates", option(opts, ingress, :drop_pending_updates))
    |> maybe_put("secret_token", option(opts, ingress, :secret_token))
  end

  defp delete_webhook_payload(opts, ingress) do
    %{}
    |> maybe_put("drop_pending_updates", option(opts, ingress, :drop_pending_updates))
  end

  defp raw_webhook_payload(opts, ingress) do
    first_present([
      Keyword.get(opts, :raw),
      Keyword.get(opts, :raw_payload),
      map_get(ingress, [:raw, "raw"]),
      map_get(ingress, [:raw_payload, "raw_payload"])
    ])
    |> payload_map()
  end

  defp payload_map(nil), do: %{}

  defp payload_map(map) when is_map(map) do
    Enum.reduce(map, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc when is_binary(key) -> Map.put(acc, key, value)
      {_key, _value}, acc -> acc
    end)
  end

  defp payload_map(pairs) when is_list(pairs) do
    Enum.reduce(pairs, %{}, fn
      {key, value}, acc when is_atom(key) -> Map.put(acc, Atom.to_string(key), value)
      {key, value}, acc when is_binary(key) -> Map.put(acc, key, value)
      _other, acc -> acc
    end)
  end

  defp payload_map(_), do: %{}

  defp option(opts, ingress, key) when is_atom(key) do
    first_present([
      Keyword.get(opts, key),
      map_get(ingress, [key, Atom.to_string(key)])
    ])
  end

  defp transport_opts(opts, ingress) do
    ingress
    |> map_get([:transport_opts, "transport_opts"])
    |> normalize_keyword_opts()
    |> Keyword.merge(Keyword.take(opts, [:debug, :check_params, :ex_gram_module, :ex_gram_adapter]))
  end

  defp normalize_keyword_opts(opts) when is_list(opts) do
    Enum.reduce(opts, [], fn
      {key, value}, acc when is_atom(key) ->
        Keyword.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case transport_key(key) do
          nil -> acc
          atom_key -> Keyword.put(acc, atom_key, value)
        end

      _other, acc ->
        acc
    end)
  end

  defp normalize_keyword_opts(opts) when is_map(opts), do: opts |> Map.to_list() |> normalize_keyword_opts()
  defp normalize_keyword_opts(_), do: []

  defp transport_key("debug"), do: :debug
  defp transport_key("check_params"), do: :check_params
  defp transport_key("ex_gram_module"), do: :ex_gram_module
  defp transport_key("ex_gram_adapter"), do: :ex_gram_adapter
  defp transport_key(_), do: nil

  defp subscriptions_from_webhook_info(bridge_id, result) do
    info = normalize_metadata(result)

    case map_get(info, [:url, "url"]) do
      url when is_binary(url) and url != "" ->
        [
          subscription(bridge_id, url, :active, provider_raw("getWebhookInfo", result),
            metadata: webhook_info_metadata(info)
          )
        ]

      _ ->
        []
    end
  end

  defp subscription(bridge_id, target_url, status, raw, opts \\ []) do
    subscription_id = Keyword.get(opts, :subscription_id, telegram_webhook_subscription_id(bridge_id))
    metadata = opts |> Keyword.get(:metadata, %{}) |> Map.merge(%{provider: :telegram, mode: :webhook})

    %{
      bridge_id: bridge_id,
      adapter_name: :telegram,
      subscription_id: subscription_id,
      external_id: subscription_id,
      target_url: target_url,
      status: status,
      metadata: metadata,
      raw: raw
    }
  end

  defp webhook_info_metadata(info) do
    %{
      pending_update_count: map_get(info, [:pending_update_count, "pending_update_count"]),
      last_error_date: map_get(info, [:last_error_date, "last_error_date"]),
      last_error_message: map_get(info, [:last_error_message, "last_error_message"]),
      last_synchronization_error_date:
        map_get(info, [:last_synchronization_error_date, "last_synchronization_error_date"]),
      max_connections: map_get(info, [:max_connections, "max_connections"]),
      allowed_updates: map_get(info, [:allowed_updates, "allowed_updates"]),
      ip_address: map_get(info, [:ip_address, "ip_address"])
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp provider_raw(method, result), do: %{method: method, result: normalize_metadata(result)}

  defp telegram_webhook_subscription_id(bridge_id), do: "telegram:webhook:#{bridge_id}"

  defp transport(opts), do: Keyword.get(opts, :transport, ExGramClient) || ExGramClient

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)

  defp first_present(values), do: Enum.find(values, &present?/1)

  defp present?(nil), do: false
  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: true

  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp ensure_map(%{} = map), do: map

  defp ensure_map(keyword) when is_list(keyword) do
    Enum.reduce(keyword, %{}, fn
      {key, value}, acc when is_atom(key) or is_binary(key) -> Map.put(acc, key, value)
      _other, acc -> acc
    end)
  end

  defp ensure_map(_), do: %{}

  defp normalize_metadata(%_{} = struct) do
    struct
    |> Map.from_struct()
    |> normalize_metadata()
  end

  defp normalize_metadata(map) when is_map(map) do
    map
    |> Enum.map(fn {key, value} -> {key, normalize_metadata(value)} end)
    |> Map.new()
  end

  defp normalize_metadata(list) when is_list(list), do: Enum.map(list, &normalize_metadata/1)
  defp normalize_metadata(other), do: other

  defp map_get(nil, _keys), do: nil

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      if Map.has_key?(map, key) do
        {:halt, Map.get(map, key)}
      else
        {:cont, nil}
      end
    end)
  end

  defp map_get(_other, _keys), do: nil
end
