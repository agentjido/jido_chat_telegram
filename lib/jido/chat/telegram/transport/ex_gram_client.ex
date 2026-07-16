defmodule Jido.Chat.Telegram.Transport.ExGramClient do
  @moduledoc """
  Default Telegram transport backed by `ExGram`.
  """

  @behaviour Jido.Chat.Telegram.Transport

  alias ExGram.Model.{ReactionTypeCustomEmoji, ReactionTypeEmoji, ReactionTypePaid}
  alias Jido.Chat.Telegram.ExGramAdapter

  @adapter_opt_keys [
    :url,
    :base_url,
    :connect_timeout,
    :connect_options,
    :pool_timeout,
    :receive_timeout,
    :finch
  ]

  @payload_keys %{
    "chat_id" => :chat_id,
    "callback_query_id" => :callback_query_id,
    "message_id" => :message_id,
    "message_thread_id" => :message_thread_id,
    "name" => :name,
    "offset" => :offset,
    "timeout" => :timeout,
    "limit" => :limit,
    "allowed_updates" => :allowed_updates,
    "certificate" => :certificate,
    "drop_pending_updates" => :drop_pending_updates,
    "ip_address" => :ip_address,
    "max_connections" => :max_connections,
    "secret_token" => :secret_token,
    "text" => :text,
    "draft_id" => :draft_id,
    "caption" => :caption,
    "photo" => :photo,
    "document" => :document,
    "file_id" => :file_id,
    "media" => :media,
    "action" => :action,
    "reaction" => :reaction,
    "is_big" => :is_big,
    "show_alert" => :show_alert,
    "url" => :url,
    "cache_time" => :cache_time,
    "parse_mode" => :parse_mode,
    "reply_to_message_id" => :reply_to_message_id,
    "disable_notification" => :disable_notification,
    "reply_markup" => :reply_markup,
    "disable_web_page_preview" => :disable_web_page_preview,
    "entities" => :entities,
    "link_preview_options" => :link_preview_options
  }

  @impl true
  def call(token, "sendMessage", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    text = Map.fetch!(params, :text)
    method_opts = params |> Map.drop([:chat_id, :text]) |> Map.to_list()

    ex_gram_module(opts).send_message(
      chat_id,
      text,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "editMessageText", payload, opts) do
    params = atomize_payload(payload)
    text = Map.fetch!(params, :text)
    method_opts = params |> Map.drop([:text]) |> Map.to_list()

    ex_gram_module(opts).edit_message_text(
      text,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "sendMessageDraft", payload, opts) do
    params = atomize_payload(payload)
    adapter = ex_gram_http_adapter(opts)

    request_adapter(adapter, :post, build_path(token, "sendMessageDraft"), params, direct_adapter_request_opts(opts))
  end

  def call(token, "deleteMessage", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    message_id = Map.fetch!(params, :message_id)

    ex_gram_module(opts).delete_message(
      chat_id,
      message_id,
      ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "sendChatAction", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    action = Map.get(params, :action, "typing")
    method_opts = params |> Map.drop([:chat_id, :action]) |> Map.to_list()

    ex_gram_module(opts).send_chat_action(
      chat_id,
      action,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "getChat", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)

    ex_gram_module(opts).get_chat(
      chat_id,
      ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "getFile", payload, opts) do
    params = atomize_payload(payload)
    file_id = Map.fetch!(params, :file_id)

    ex_gram_module(opts).get_file(
      file_id,
      ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "setMessageReaction", payload, opts) do
    params = atomize_payload(payload)
    chat_id = params |> Map.fetch!(:chat_id) |> normalize_numeric_identifier()
    message_id = params |> Map.fetch!(:message_id) |> normalize_numeric_identifier()
    reaction = params |> Map.get(:reaction, []) |> normalize_reaction_types()
    method_opts = params |> Map.drop([:chat_id, :message_id, :reaction]) |> Map.to_list()
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :set_message_reaction, 4) ->
        apply(module, :set_message_reaction, [
          chat_id,
          message_id,
          reaction,
          method_opts ++ ex_gram_runtime_opts(token, opts)
        ])

      function_exported?(module, :set_message_reaction, 3) ->
        apply(module, :set_message_reaction, [
          chat_id,
          message_id,
          method_opts ++ [reaction: reaction] ++ ex_gram_runtime_opts(token, opts)
        ])

      true ->
        {:error, :unsupported_method}
    end
  end

  def call(token, "sendPhoto", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    photo = Map.fetch!(params, :photo)
    method_opts = params |> Map.drop([:chat_id, :photo]) |> Map.to_list()

    ex_gram_module(opts).send_photo(
      chat_id,
      photo,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "sendDocument", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    document = Map.fetch!(params, :document)
    method_opts = params |> Map.drop([:chat_id, :document]) |> Map.to_list()

    ex_gram_module(opts).send_document(
      chat_id,
      document,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "answerCallbackQuery", payload, opts) do
    params = atomize_payload(payload)
    callback_query_id = Map.fetch!(params, :callback_query_id)
    method_opts = params |> Map.drop([:callback_query_id]) |> Map.to_list()

    ex_gram_module(opts).answer_callback_query(
      callback_query_id,
      method_opts ++ ex_gram_runtime_opts(token, opts)
    )
  end

  def call(token, "getUpdates", payload, opts) do
    params = atomize_payload(payload)
    method_opts = Map.to_list(params)
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :get_updates, 1) ->
        apply(module, :get_updates, [method_opts ++ ex_gram_runtime_opts(token, opts)])

      function_exported?(module, :get_updates, 0) ->
        apply(module, :get_updates, [])

      true ->
        {:error, {:unsupported_method, "getUpdates"}}
    end
  end

  def call(token, "setWebhook", payload, opts) do
    params = atomize_payload(payload)
    url = Map.fetch!(params, :url)
    method_opts = params |> Map.drop([:url]) |> Map.to_list()
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :set_webhook, 2) ->
        apply(module, :set_webhook, [url, method_opts ++ ex_gram_runtime_opts(token, opts)])

      function_exported?(module, :set_webhook, 1) ->
        apply(module, :set_webhook, [url])

      true ->
        {:error, {:unsupported_method, "setWebhook"}}
    end
  end

  def call(token, "getWebhookInfo", _payload, opts) do
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :get_webhook_info, 1) ->
        apply(module, :get_webhook_info, [ex_gram_runtime_opts(token, opts)])

      function_exported?(module, :get_webhook_info, 0) ->
        apply(module, :get_webhook_info, [])

      true ->
        {:error, {:unsupported_method, "getWebhookInfo"}}
    end
  end

  def call(token, "deleteWebhook", payload, opts) do
    params = atomize_payload(payload)
    method_opts = Map.to_list(params)
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :delete_webhook, 1) ->
        apply(module, :delete_webhook, [method_opts ++ ex_gram_runtime_opts(token, opts)])

      function_exported?(module, :delete_webhook, 0) ->
        apply(module, :delete_webhook, [])

      true ->
        {:error, {:unsupported_method, "deleteWebhook"}}
    end
  end

  def call(token, "createForumTopic", payload, opts) do
    params = atomize_payload(payload)
    chat_id = Map.fetch!(params, :chat_id)
    name = Map.fetch!(params, :name)
    method_opts = params |> Map.drop([:chat_id, :name]) |> Map.to_list()
    module = ex_gram_module(opts)

    cond do
      function_exported?(module, :create_forum_topic, 3) ->
        apply(module, :create_forum_topic, [
          chat_id,
          name,
          method_opts ++ ex_gram_runtime_opts(token, opts)
        ])

      function_exported?(module, :create_forum_topic, 2) ->
        apply(module, :create_forum_topic, [
          chat_id,
          [name: name] ++ method_opts ++ ex_gram_runtime_opts(token, opts)
        ])

      true ->
        {:error, :unsupported_method}
    end
  end

  def call(_token, method, _payload, _opts), do: {:error, {:unsupported_method, method}}

  defp atomize_payload(payload) when is_map(payload) do
    Enum.reduce(payload, %{}, fn
      {key, value}, acc when is_atom(key) ->
        Map.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case Map.fetch(@payload_keys, key) do
          {:ok, atom_key} -> Map.put(acc, atom_key, value)
          :error -> acc
        end
    end)
  end

  defp ex_gram_module(opts), do: Keyword.get(opts, :ex_gram_module, ExGram)

  defp ex_gram_http_adapter(opts) do
    ex_gram_adapter(opts)
  end

  defp request_adapter(adapter, verb, path, body, opts) do
    cond do
      Code.ensure_loaded?(adapter) and function_exported?(adapter, :request, 4) ->
        adapter.request(verb, path, body, opts)

      Code.ensure_loaded?(adapter) and function_exported?(adapter, :request, 3) ->
        adapter.request(verb, path, body)

      true ->
        {:error, :unsupported_adapter}
    end
  end

  defp adapter_request_opts(opts) do
    adapter_request_opts(opts, @adapter_opt_keys)
  end

  defp direct_adapter_request_opts(opts) do
    adapter_request_opts(opts, @adapter_opt_keys ++ [:debug, :check_params])
  end

  defp adapter_request_opts(opts, top_level_keys) do
    opts
    |> Keyword.get(:adapter_opts, [])
    |> normalize_adapter_opts()
    |> Keyword.merge(Keyword.take(opts, top_level_keys))
  end

  defp build_path(token, name) do
    token_part = "/bot#{token}"

    if ExGram.test_environment?() do
      Path.join([token_part, "test", name])
    else
      Path.join([token_part, name])
    end
  end

  defp ex_gram_runtime_opts(token, opts) do
    runtime_opts = [token: token, adapter: ex_gram_adapter(opts)] ++ Keyword.take(opts, [:debug, :check_params])

    case adapter_request_opts(opts) do
      [] -> runtime_opts
      adapter_opts -> Keyword.put(runtime_opts, :adapter_opts, adapter_opts)
    end
  end

  defp normalize_adapter_opts(opts) when is_list(opts) do
    Enum.reduce(opts, [], fn
      {key, value}, acc when is_atom(key) ->
        Keyword.put(acc, key, value)

      {key, value}, acc when is_binary(key) ->
        case adapter_opt_key(key) do
          nil -> acc
          atom_key -> Keyword.put(acc, atom_key, value)
        end

      _other, acc ->
        acc
    end)
  end

  defp normalize_adapter_opts(opts) when is_map(opts), do: opts |> Map.to_list() |> normalize_adapter_opts()
  defp normalize_adapter_opts(_opts), do: []

  defp adapter_opt_key("url"), do: :url
  defp adapter_opt_key("base_url"), do: :base_url
  defp adapter_opt_key("connect_timeout"), do: :connect_timeout
  defp adapter_opt_key("connect_options"), do: :connect_options
  defp adapter_opt_key("pool_timeout"), do: :pool_timeout
  defp adapter_opt_key("receive_timeout"), do: :receive_timeout
  defp adapter_opt_key("finch"), do: :finch
  defp adapter_opt_key("debug"), do: :debug
  defp adapter_opt_key("check_params"), do: :check_params
  defp adapter_opt_key(_key), do: nil

  defp ex_gram_adapter(opts) do
    Keyword.get(
      opts,
      :ex_gram_adapter,
      Application.get_env(:jido_chat_telegram, :ex_gram_adapter, ExGramAdapter)
    )
  end

  defp normalize_reaction_types(reactions) when is_list(reactions) do
    Enum.map(reactions, &normalize_reaction_type/1)
  end

  defp normalize_reaction_types(other), do: other

  defp normalize_reaction_type(%{"type" => "emoji", "emoji" => emoji}) do
    %ReactionTypeEmoji{type: "emoji", emoji: emoji}
  end

  defp normalize_reaction_type(%{type: "emoji", emoji: emoji}) do
    %ReactionTypeEmoji{type: "emoji", emoji: emoji}
  end

  defp normalize_reaction_type(%{"type" => "custom_emoji", "custom_emoji_id" => custom_emoji_id}) do
    %ReactionTypeCustomEmoji{type: "custom_emoji", custom_emoji_id: custom_emoji_id}
  end

  defp normalize_reaction_type(%{type: "custom_emoji", custom_emoji_id: custom_emoji_id}) do
    %ReactionTypeCustomEmoji{type: "custom_emoji", custom_emoji_id: custom_emoji_id}
  end

  defp normalize_reaction_type(%{"type" => "paid"}) do
    %ReactionTypePaid{type: "paid"}
  end

  defp normalize_reaction_type(%{type: "paid"}) do
    %ReactionTypePaid{type: "paid"}
  end

  defp normalize_reaction_type(other), do: other

  defp normalize_numeric_identifier(value) when is_binary(value) do
    case Integer.parse(value) do
      {int, ""} -> int
      _ -> value
    end
  end

  defp normalize_numeric_identifier(value), do: value
end
