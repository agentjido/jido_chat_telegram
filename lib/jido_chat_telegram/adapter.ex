defmodule Jido.Chat.Telegram.Adapter do
  @moduledoc """
  Telegram `Jido.Chat.Adapter` implementation using ExGram.
  """

  use Jido.Chat.Adapter

  alias Jido.Chat.{Binding, FileUpload, WebhookRequest, WebhookResponse}

  alias Jido.Chat.Markdown.StreamRenderer

  alias Jido.Chat.Telegram.{
    DeleteOptions,
    EditOptions,
    Extensions,
    Ingress,
    MetadataOptions,
    Normalizer,
    PollingWorker,
    ReactionOptions,
    SendOptions,
    StreamOptions,
    TypingOptions
  }

  alias Jido.Chat.Telegram.Transport.ExGramClient

  @impl true
  def channel_type, do: :telegram

  @impl true
  @spec capabilities() :: map()
  def capabilities,
    do: %{
      initialize: :fallback,
      shutdown: :fallback,
      send_message: :native,
      send_file: :native,
      edit_message: :native,
      delete_message: :native,
      start_typing: :native,
      fetch_metadata: :native,
      fetch_thread: :fallback,
      fetch_message: :unsupported,
      fetch_media: :native,
      add_reaction: :native,
      remove_reaction: :native,
      post_ephemeral: :fallback,
      open_dm: :native,
      fetch_messages: :unsupported,
      fetch_channel_messages: :unsupported,
      list_threads: :unsupported,
      open_thread: :native,
      post_channel_message: :fallback,
      stream: :native,
      open_modal: :unsupported,
      webhook: :native,
      verify_webhook: :native,
      normalize_event: :native,
      membership: :native,
      format_webhook_response: :native
    }

  @impl true
  def signal_protocol, do: 1

  @impl true
  def configure_binding(opts) do
    ingress = Ingress.normalize_opts(opts)
    credentials = Keyword.get(opts, :credentials, %{})

    token =
      opts[:token] || map_get(credentials, [:token, "token"]) ||
        map_get(ingress, [:token, "token"]) || Application.get_env(:jido_chat_telegram, :telegram_bot_token)

    if is_binary(token) and token != "" do
      captured =
        opts
        |> Keyword.put(:token, token)
        |> Keyword.put(:transport, opts[:transport] || map_get(ingress, [:transport, "transport"]) || ExGramClient)
        |> Keyword.put(
          :secret_token,
          opts[:secret_token] || map_get(ingress, [:secret_token, "secret_token"]) ||
            Application.get_env(:jido_chat_telegram, :telegram_webhook_secret)
        )
        |> Keyword.put(:ingress, ingress)

      {:ok, captured}
    else
      {:error, :missing_token}
    end
  end

  @impl true
  def normalize_event(%Binding{} = binding, input), do: Normalizer.normalize(binding, input)

  @doc """
  Returns Telegram extension capability statuses for features outside core adapter contract.
  """
  @spec extension_capabilities() :: map()
  def extension_capabilities, do: Jido.Chat.Telegram.Extensions.capabilities()

  @doc """
  Fetches the bytes behind an inbound media reference.

  Accepts a raw Telegram file id, a `telegram://file/<file_id>` reference, or a normalized
  media value carrying either form — the `telegram://` scheme is minted here, so it is
  resolved here rather than by the caller.
  """
  @spec fetch_media(String.t() | map(), keyword() | map()) ::
          {:ok, binary()} | {:error, term()}
  @impl true
  defdelegate fetch_media(reference, opts \\ []), to: Extensions, as: :download_file

  @impl true
  def listener_child_specs(bridge_id, opts \\ []) when is_binary(bridge_id) and is_list(opts) do
    ingress = Ingress.normalize_opts(opts)

    case Ingress.mode(ingress) do
      :webhook ->
        {:ok, []}

      :polling ->
        with %Binding{} = binding <- Keyword.get(opts, :binding),
             {:ok, sink_mfa} <- validate_sink_mfa(Keyword.get(opts, :sink_mfa)) do
          worker_opts = polling_worker_opts(bridge_id, ingress, binding, sink_mfa)

          {:ok,
           [
             Supervisor.child_spec(
               {PollingWorker, worker_opts},
               id: {:telegram_polling_worker, bridge_id}
             )
           ]}
        else
          nil -> {:error, :invalid_binding}
          {:error, _} = error -> error
        end

      :invalid ->
        {:error, :invalid_ingress_mode}
    end
  end

  @doc """
  Ensures Telegram webhook ingress for a messaging bridge.

  Telegram supports one webhook per bot token, so the subscription id is
  deterministic for the bridge and maps to the bot's current webhook.
  """
  @spec ensure_ingress_subscription(String.t(), keyword()) :: {:ok, map()} | {:error, term()}
  def ensure_ingress_subscription(bridge_id, opts \\ [])
      when is_binary(bridge_id) and is_list(opts) do
    Ingress.ensure_subscription(bridge_id, opts)
  end

  @doc """
  Lists the Telegram webhook ingress subscription for a messaging bridge.
  """
  @spec list_ingress_subscriptions(String.t(), keyword()) :: {:ok, [map()]} | {:error, term()}
  def list_ingress_subscriptions(bridge_id, opts \\ []) when is_binary(bridge_id) and is_list(opts) do
    Ingress.list_subscriptions(bridge_id, opts)
  end

  @doc """
  Deletes the Telegram webhook ingress subscription for a messaging bridge.
  """
  @spec delete_ingress_subscription(String.t(), String.t(), keyword()) ::
          {:ok, map()} | {:error, term()}
  def delete_ingress_subscription(bridge_id, subscription_id, opts \\ [])
      when is_binary(bridge_id) and is_binary(subscription_id) and is_list(opts) do
    Ingress.delete_subscription(bridge_id, subscription_id, opts)
  end

  @impl true
  def send_message(chat_id, text, opts \\ []) do
    opts = SendOptions.new(opts)
    token = fetch_token(opts.token)

    {method, payload} = build_send_request(chat_id, text, opts)

    with {:ok, result} <-
           transport(opts).call(token, method, payload, SendOptions.transport_opts(opts)) do
      {:ok, message_result(result, chat_id, text, "sent")}
    end
  end

  # Rich messages (Bot API 10.1) are sent through `sendRichMessage`, which takes the
  # whole body as Markdown or HTML inside `rich_message` and parses it server-side —
  # that is what renders tables, headings, and nested lists that `sendMessage` cannot.
  defp build_send_request(chat_id, text, %SendOptions{rich_format: nil} = opts) do
    {"sendMessage", Map.merge(%{"chat_id" => chat_id, "text" => text}, SendOptions.payload_opts(opts))}
  end

  defp build_send_request(chat_id, text, %SendOptions{rich_format: rich_format} = opts) do
    rich_message = %{Atom.to_string(rich_format) => text}

    {"sendRichMessage",
     Map.merge(
       %{"chat_id" => chat_id, "rich_message" => rich_message},
       SendOptions.rich_payload_opts(opts)
     )}
  end

  # Bot API 10.1 made `text` optional on `editMessageText` so an existing message can
  # be replaced with rich content — which is how a plain status placeholder becomes a
  # table-bearing answer.
  defp build_edit_payload(chat_id, message_id, text, %EditOptions{rich_format: nil} = opts) do
    EditOptions.payload_opts(opts)
    |> Map.merge(%{"chat_id" => chat_id, "message_id" => message_id, "text" => text})
  end

  defp build_edit_payload(chat_id, message_id, text, %EditOptions{rich_format: rich} = opts) do
    EditOptions.rich_payload_opts(opts)
    |> Map.merge(%{
      "chat_id" => chat_id,
      "message_id" => message_id,
      "rich_message" => %{Atom.to_string(rich) => text}
    })
  end

  @impl true
  def stream(chat_id, chunks, opts \\ []) do
    opts = StreamOptions.new(opts)
    token = fetch_token(opts.token)
    draft_id = opts.draft_id || System.unique_integer([:positive])
    interval_ms = normalize_stream_update_interval(opts.stream_update_interval_ms)

    with {:ok, draft_chat_id} <- draft_chat_id(chat_id),
         {:ok, state} <-
           consume_stream_chunks(chunks, draft_chat_id, token, opts, draft_id, interval_ms) do
      case StreamRenderer.flush(state.renderer) do
        nil ->
          {:error, :empty_stream}

        text ->
          send_message(chat_id, text, StreamOptions.send_opts(opts))
      end
    else
      :fallback ->
        fallback_stream_send(chat_id, chunks, opts)

      {:error, :empty_stream} = error ->
        error

      {:error, _reason} = error ->
        error
    end
  end

  @impl true
  def send_file(chat_id, file, opts \\ []) do
    upload = FileUpload.normalize(file)

    with {:ok, input} <- upload_input(upload),
         {:ok, media} <- deliver_upload(chat_id, upload, input, opts) do
      {:ok, upload_response(upload, media, chat_id)}
    end
  end

  @impl true
  def edit_message(chat_id, message_id, text, opts \\ []) do
    opts = EditOptions.new(opts)
    token = fetch_token(opts.token)

    payload = build_edit_payload(chat_id, message_id, text, opts)

    with {:ok, result} <-
           transport(opts).call(
             token,
             "editMessageText",
             payload,
             EditOptions.transport_opts(opts)
           ) do
      {:ok, message_result(result, chat_id, text, "updated", message_id)}
    end
  end

  @impl true
  def delete_message(chat_id, message_id, opts \\ []) do
    opts =
      opts
      |> pick_opts([
        :token,
        :transport,
        :debug,
        :check_params,
        :ex_gram_module,
        :ex_gram_adapter,
        :url,
        :adapter_opts
      ])
      |> DeleteOptions.new()

    token = fetch_token(opts.token)

    with {:ok, _result} <-
           transport(opts).call(
             token,
             "deleteMessage",
             %{"chat_id" => chat_id, "message_id" => message_id},
             DeleteOptions.transport_opts(opts)
           ) do
      :ok
    end
  end

  @impl true
  def start_typing(chat_id, opts \\ []) do
    status = Keyword.get(opts, :status) || Keyword.get(opts, :action)

    opts =
      opts
      |> pick_opts([
        :token,
        :transport,
        :thread_id,
        :debug,
        :check_params,
        :ex_gram_module,
        :ex_gram_adapter,
        :url,
        :adapter_opts
      ])
      |> maybe_put_action(status)
      |> TypingOptions.new()

    token = fetch_token(opts.token)

    payload =
      TypingOptions.payload_opts(opts)
      |> Map.put("chat_id", chat_id)

    with {:ok, _result} <-
           transport(opts).call(
             token,
             "sendChatAction",
             payload,
             TypingOptions.transport_opts(opts)
           ) do
      :ok
    end
  end

  @impl true
  def fetch_metadata(chat_id, opts \\ []) do
    opts =
      opts
      |> pick_opts([
        :token,
        :transport,
        :debug,
        :check_params,
        :ex_gram_module,
        :ex_gram_adapter,
        :url,
        :adapter_opts
      ])
      |> MetadataOptions.new()

    token = fetch_token(opts.token)

    with {:ok, result} <-
           transport(opts).call(
             token,
             "getChat",
             %{"chat_id" => chat_id},
             MetadataOptions.transport_opts(opts)
           ) do
      {:ok,
       %{
         "id" => stringify(map_get(result, [:id, "id"]) || chat_id),
         "name" => map_get(result, [:title, "title", :username, "username", :first_name, "first_name"]),
         "kind" => conversation_kind(map_get(result, [:type, "type"]))
       }
       |> Map.reject(fn {_key, value} -> is_nil(value) end)}
    end
  end

  @impl true
  def add_reaction(chat_id, message_id, emoji, opts \\ []) when is_binary(emoji) do
    opts =
      opts
      |> pick_opts([
        :token,
        :transport,
        :is_big,
        :debug,
        :check_params,
        :ex_gram_module,
        :ex_gram_adapter,
        :url,
        :adapter_opts
      ])
      |> ReactionOptions.new()

    token = fetch_token(opts.token)

    payload =
      ReactionOptions.payload_opts(opts)
      |> Map.merge(%{
        "chat_id" => chat_id,
        "message_id" => message_id,
        "reaction" => [%{"type" => "emoji", "emoji" => emoji}]
      })

    case transport(opts).call(
           token,
           "setMessageReaction",
           payload,
           ReactionOptions.transport_opts(opts)
         ) do
      {:ok, _result} -> :ok
      {:error, :unsupported_method} -> {:error, :unsupported}
      {:error, {:unsupported_method, _method}} -> {:error, :unsupported}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def remove_reaction(chat_id, message_id, _emoji, opts \\ []) do
    opts =
      opts
      |> pick_opts([
        :token,
        :transport,
        :is_big,
        :debug,
        :check_params,
        :ex_gram_module,
        :ex_gram_adapter,
        :url,
        :adapter_opts
      ])
      |> ReactionOptions.new()

    token = fetch_token(opts.token)

    payload =
      ReactionOptions.payload_opts(opts)
      |> Map.merge(%{"chat_id" => chat_id, "message_id" => message_id, "reaction" => []})

    case transport(opts).call(
           token,
           "setMessageReaction",
           payload,
           ReactionOptions.transport_opts(opts)
         ) do
      {:ok, _result} -> :ok
      {:error, :unsupported_method} -> {:error, :unsupported}
      {:error, {:unsupported_method, _method}} -> {:error, :unsupported}
      {:error, _reason} = error -> error
    end
  end

  @impl true
  def open_dm(external_user_id, _opts \\ []), do: {:ok, external_user_id}

  @impl true
  def open_thread(chat_id, _message_id, opts \\ []) do
    if Keyword.get(opts, :supports_forum_topics, true) do
      token = fetch_token(opts[:token])
      topic_name = Keyword.get(opts, :topic_name, "New thread")

      transport_opts =
        pick_opts(opts, [
          :transport,
          :debug,
          :check_params,
          :ex_gram_module,
          :ex_gram_adapter,
          :url,
          :adapter_opts
        ])

      with {:ok, result} <-
             transport(opts).call(
               token,
               "createForumTopic",
               %{"chat_id" => chat_id, "name" => topic_name},
               transport_opts
             ) do
        {:ok,
         %{
           external_thread_id: stringify(map_get(result, [:message_thread_id, "message_thread_id"])),
           delivery_external_room_id: stringify(chat_id)
         }}
      end
    else
      {:error, :unsupported}
    end
  end

  @impl true
  def post_ephemeral(_chat_id, user_id, text, opts \\ []) do
    if Keyword.get(opts, :fallback_to_dm, false),
      do: send_message(user_id, text, Keyword.drop(opts, [:fallback_to_dm])),
      else: {:error, :unsupported}
  end

  @impl true
  def verify_webhook(%WebhookRequest{} = request, opts \\ []) do
    verify_webhook_secret(opts, request.headers)
  end

  @impl true
  def format_webhook_response(result, _opts \\ [])
  def format_webhook_response({:ok, _}, _opts), do: WebhookResponse.accepted(%{ok: true})

  def format_webhook_response({:error, :invalid_webhook_secret}, _opts),
    do: WebhookResponse.error(401, %{error: "invalid_signature"})

  def format_webhook_response({:error, _}, _opts), do: WebhookResponse.error(400, %{error: "ingress_rejected"})

  defp deliver_upload(chat_id, %FileUpload{kind: :image} = upload, input, opts) do
    Extensions.send_photo(chat_id, input, upload_opts(upload, opts))
  end

  defp deliver_upload(chat_id, %FileUpload{} = upload, input, opts) do
    Extensions.send_document(chat_id, input, upload_opts(upload, opts))
  end

  defp upload_opts(%FileUpload{} = upload, opts) do
    opts
    |> pick_opts([
      :token,
      :transport,
      :caption,
      :text,
      :format,
      :parse_mode,
      :reply_to_id,
      :reply_to_message_id,
      :thread_id,
      :external_thread_id,
      :reply_markup,
      :disable_notification,
      :debug,
      :check_params,
      :ex_gram_module,
      :ex_gram_adapter,
      :url,
      :adapter_opts
    ])
    |> maybe_put_option(:caption, upload_caption(upload))
  end

  defp upload_response(%FileUpload{} = upload, media, chat_id) do
    %{
      "id" => stringify(media.message_id),
      "room_id" => stringify(media.chat_id || chat_id),
      "text" => upload_caption(upload),
      "status" => "sent"
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp upload_input(%FileUpload{url: url}) when is_binary(url) and url != "", do: {:ok, url}

  defp upload_input(%FileUpload{path: path}) when is_binary(path) and path != "" do
    {:ok, {:file, path}}
  end

  defp upload_input(%FileUpload{data: data, filename: filename})
       when is_binary(data) and data != "" and is_binary(filename) and filename != "" do
    {:ok, {:file_content, data, filename}}
  end

  defp upload_input(%FileUpload{data: data}) when is_binary(data) and data != "" do
    {:error, :missing_filename}
  end

  defp upload_input(_upload), do: {:error, :missing_file_source}

  defp upload_caption(%FileUpload{} = upload) do
    metadata = upload.metadata

    metadata[:caption] || metadata["caption"] || metadata[:alt_text] || metadata["alt_text"] ||
      metadata[:transcript] || metadata["transcript"]
  end

  defp maybe_put_option(opts, _key, value) when value in [nil, ""], do: opts
  defp maybe_put_option(opts, key, value), do: Keyword.put_new(opts, key, value)

  defp verify_webhook_secret(opts, headers) do
    expected =
      opts[:secret_token]

    if is_nil(expected) do
      :ok
    else
      actual = header_value(headers, "x-telegram-bot-api-secret-token")
      if actual == expected, do: :ok, else: {:error, :invalid_webhook_secret}
    end
  end

  defp fetch_token(token) when is_binary(token) and token != "", do: token
  defp fetch_token(_token), do: raise(ArgumentError, "missing captured Telegram token")

  defp message_result(result, room, text, status, fallback_id \\ nil) do
    %{
      "id" => stringify(map_get(result, [:message_id, "message_id"]) || fallback_id),
      "room_id" => stringify(map_get(result, [:chat, "chat"]) |> map_get([:id, "id"]) || room),
      "text" => text,
      "status" => status,
      "timestamp" => provider_timestamp(map_get(result, [:date, "date"]))
    }
    |> Map.reject(fn {_key, value} -> is_nil(value) end)
  end

  defp provider_timestamp(value) when is_integer(value) do
    case DateTime.from_unix(value) do
      {:ok, time} -> DateTime.to_iso8601(time)
      _ -> nil
    end
  end

  defp provider_timestamp(_value), do: nil

  defp conversation_kind("private"), do: "direct"
  defp conversation_kind(kind) when kind in ["group", "supergroup"], do: "group"
  defp conversation_kind("channel"), do: "channel"
  defp conversation_kind(_), do: "unknown"

  defp transport(opts) when is_list(opts), do: transport(Map.new(opts))
  defp transport(%{transport: transport}) when not is_nil(transport), do: transport
  defp transport(_opts), do: ExGramClient

  defp maybe_put_action(opts, nil), do: opts
  defp maybe_put_action(opts, ""), do: opts
  defp maybe_put_action(opts, status), do: Keyword.put(opts, :action, status)

  defp consume_stream_chunks(chunks, draft_chat_id, token, opts, draft_id, interval_ms) do
    initial = %{renderer: StreamRenderer.new(), last_draft_text: nil, last_update_ms: nil}

    Enum.reduce_while(chunks, {:ok, initial}, fn chunk, {:ok, state} ->
      if draft_update_due?(state.last_update_ms, interval_ms) do
        {renderer, snapshot} = StreamRenderer.push(state.renderer, chunk)
        next_state = %{state | renderer: renderer}

        case maybe_send_draft_update(
               next_state,
               snapshot,
               draft_chat_id,
               token,
               opts,
               draft_id
             ) do
          {:ok, updated_state} -> {:cont, {:ok, updated_state}}
          {:error, reason} -> {:halt, {:error, reason}}
          :skip -> {:cont, {:ok, next_state}}
        end
      else
        {:cont, {:ok, %{state | renderer: StreamRenderer.append(state.renderer, chunk)}}}
      end
    end)
  rescue
    Protocol.UndefinedError -> {:error, :invalid_stream_chunk}
  end

  defp maybe_send_draft_update(
         _state,
         nil,
         _draft_chat_id,
         _token,
         _opts,
         _draft_id
       ),
       do: :skip

  defp maybe_send_draft_update(
         %{last_draft_text: text},
         text,
         _draft_chat_id,
         _token,
         _opts,
         _draft_id
       ),
       do: :skip

  defp maybe_send_draft_update(
         state,
         text,
         draft_chat_id,
         token,
         opts,
         draft_id
       ) do
    now_ms = System.monotonic_time(:millisecond)

    {method, draft_payload} = StreamOptions.draft_request(opts, draft_id, text)
    payload = Map.put(draft_payload, "chat_id", draft_chat_id)

    case transport(opts).call(
           token,
           method,
           payload,
           StreamOptions.transport_opts(opts)
         ) do
      {:ok, _result} ->
        {:ok, %{state | last_draft_text: text, last_update_ms: now_ms}}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp draft_update_due?(last_update_ms, interval_ms) do
    send_draft_now?(last_update_ms, System.monotonic_time(:millisecond), interval_ms)
  end

  defp send_draft_now?(nil, _now_ms, _interval_ms), do: true
  defp send_draft_now?(_last_update_ms, _now_ms, 0), do: true

  defp send_draft_now?(last_update_ms, now_ms, interval_ms),
    do: now_ms - last_update_ms >= interval_ms

  defp fallback_stream_send(chat_id, chunks, opts) do
    text = StreamRenderer.render(chunks)

    if is_nil(text) do
      {:error, :empty_stream}
    else
      send_message(chat_id, text, StreamOptions.send_opts(StreamOptions.new(opts)))
    end
  rescue
    Protocol.UndefinedError -> {:error, :invalid_stream_chunk}
  end

  defp draft_chat_id(chat_id) when is_integer(chat_id) and chat_id > 0, do: {:ok, chat_id}

  defp draft_chat_id(chat_id) when is_binary(chat_id) do
    case Integer.parse(chat_id) do
      {parsed, ""} when parsed > 0 -> {:ok, parsed}
      _ -> :fallback
    end
  end

  defp draft_chat_id(_chat_id), do: :fallback

  defp normalize_stream_update_interval(nil), do: 250
  defp normalize_stream_update_interval(value) when value < 0, do: 0
  defp normalize_stream_update_interval(value), do: value

  defp header_value(headers, name) when is_map(headers) do
    Enum.find_value(headers, fn
      {key, value} when is_binary(key) -> if String.downcase(key) == name, do: value
      {key, value} when is_atom(key) -> if String.downcase(to_string(key)) == name, do: value
      _ -> nil
    end)
  end

  defp header_value(headers, name) when is_list(headers) do
    headers
    |> Enum.into(%{})
    |> header_value(name)
  end

  defp header_value(_, _), do: nil

  defp map_get(nil, _keys), do: nil

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.reduce_while(keys, nil, fn key, _acc ->
      case Map.fetch(map, key) do
        {:ok, nil} -> {:cont, nil}
        {:ok, value} -> {:halt, value}
        :error -> {:cont, nil}
      end
    end)
  end

  defp map_get(_other, _keys), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp pick_opts(opts, allowed_keys) when is_list(opts), do: Keyword.take(opts, allowed_keys)

  defp validate_sink_mfa({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: {:ok, {module, function, args}}

  defp validate_sink_mfa(_), do: {:error, :invalid_sink_mfa}

  defp polling_worker_opts(bridge_id, ingress, binding, sink_mfa) do
    opts = binding.options

    transport_opts =
      normalize_transport_opts(map_get(ingress, [:transport_opts, "transport_opts"]))
      |> Keyword.merge(
        Keyword.take(opts, [:debug, :check_params, :ex_gram_module, :ex_gram_adapter, :url, :adapter_opts])
      )

    [
      bridge_id: bridge_id,
      binding: binding,
      sink_mfa: sink_mfa,
      sink_opts: [],
      token: opts[:token],
      transport: opts[:transport],
      transport_opts: transport_opts,
      timeout_s: map_get(ingress, [:timeout_s, "timeout_s"]) || 20,
      poll_interval_ms: map_get(ingress, [:poll_interval_ms, "poll_interval_ms"]) || 250,
      allowed_updates: map_get(ingress, [:allowed_updates, "allowed_updates"]),
      max_backoff_ms: map_get(ingress, [:max_backoff_ms, "max_backoff_ms"]) || 5_000
    ]
  end

  defp normalize_transport_opts(opts) when is_list(opts) do
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

  defp normalize_transport_opts(opts) when is_map(opts), do: opts |> Map.to_list() |> normalize_transport_opts()
  defp normalize_transport_opts(_opts), do: []

  defp transport_key("debug"), do: :debug
  defp transport_key("check_params"), do: :check_params
  defp transport_key("ex_gram_module"), do: :ex_gram_module
  defp transport_key("ex_gram_adapter"), do: :ex_gram_adapter
  defp transport_key("url"), do: :url
  defp transport_key("base_url"), do: :base_url
  defp transport_key("adapter_opts"), do: :adapter_opts
  defp transport_key(_key), do: nil
end
