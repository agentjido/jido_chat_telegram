defmodule Jido.Chat.Telegram.Adapter do
  @moduledoc """
  Telegram `Jido.Chat.Adapter` implementation using ExGram.
  """

  use Jido.Chat.Adapter

  alias Jido.Chat.{
    ChannelInfo,
    EphemeralMessage,
    EventEnvelope,
    FileUpload,
    Incoming,
    Response,
    WebhookRequest,
    WebhookResponse
  }

  alias Jido.Chat.Telegram.{
    DeleteOptions,
    EditOptions,
    Extensions,
    Ingress,
    MetadataOptions,
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
      parse_event: :native,
      format_webhook_response: :native
    }

  @doc """
  Returns Telegram extension capability statuses for features outside core adapter contract.
  """
  @spec extension_capabilities() :: map()
  def extension_capabilities, do: Jido.Chat.Telegram.Extensions.capabilities()

  @impl true
  def listener_child_specs(bridge_id, opts \\ []) when is_binary(bridge_id) and is_list(opts) do
    ingress = Ingress.normalize_opts(opts)

    case Ingress.mode(ingress) do
      :webhook ->
        {:ok, []}

      :polling ->
        with {:ok, sink_mfa} <- validate_sink_mfa(Keyword.get(opts, :sink_mfa)) do
          worker_opts = polling_worker_opts(bridge_id, ingress, opts, sink_mfa)

          {:ok,
           [
             Supervisor.child_spec(
               {PollingWorker, worker_opts},
               id: {:telegram_polling_worker, bridge_id}
             )
           ]}
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
  def transform_incoming(%{"message" => nil}), do: {:error, :no_message}
  def transform_incoming(%{message: nil}), do: {:error, :no_message}

  def transform_incoming(%{"message" => message}) when is_map(message),
    do: transform_message(message)

  def transform_incoming(%{message: message}) when is_map(message), do: transform_message(message)

  def transform_incoming(%{"channel_post" => message}) when is_map(message),
    do: transform_message(message)

  def transform_incoming(%{channel_post: message}) when is_map(message),
    do: transform_message(message)

  def transform_incoming(%{"edited_channel_post" => message}) when is_map(message),
    do: transform_message(message)

  def transform_incoming(%{edited_channel_post: message}) when is_map(message),
    do: transform_message(message)

  def transform_incoming(_), do: {:error, :unsupported_update_type}

  @impl true
  def send_message(chat_id, text, opts \\ []) do
    opts = SendOptions.new(opts)
    token = fetch_token(opts.token)

    payload =
      Map.merge(%{"chat_id" => chat_id, "text" => text}, SendOptions.payload_opts(opts))

    with {:ok, result} <-
           transport(opts).call(token, "sendMessage", payload, SendOptions.transport_opts(opts)) do
      {:ok,
       Response.new(%{
         message_id: map_get(result, [:message_id, "message_id"]),
         chat_id: map_get(result, [:chat, "chat"]) |> map_get([:id, "id"]),
         date: map_get(result, [:date, "date"]),
         channel_type: :telegram,
         status: :sent,
         raw: result
       })}
    end
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
      case state.text do
        "" ->
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

    payload =
      EditOptions.payload_opts(opts)
      |> Map.merge(%{"chat_id" => chat_id, "message_id" => message_id, "text" => text})

    with {:ok, result} <-
           transport(opts).call(
             token,
             "editMessageText",
             payload,
             EditOptions.transport_opts(opts)
           ) do
      {:ok,
       Response.new(%{
         message_id: map_get(result, [:message_id, "message_id"]) || message_id,
         chat_id: map_get(result, [:chat, "chat"]) |> map_get([:id, "id"]) || chat_id,
         date: map_get(result, [:date, "date"]),
         channel_type: :telegram,
         status: :edited,
         raw: result
       })}
    end
  end

  @impl true
  def delete_message(chat_id, message_id, opts \\ []) do
    opts =
      opts
      |> pick_opts([:token, :transport, :debug, :check_params, :ex_gram_module, :ex_gram_adapter])
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
        :ex_gram_adapter
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
      |> pick_opts([:token, :transport, :debug, :check_params, :ex_gram_module, :ex_gram_adapter])
      |> MetadataOptions.new()

    token = fetch_token(opts.token)

    with {:ok, result} <-
           transport(opts).call(
             token,
             "getChat",
             %{"chat_id" => chat_id},
             MetadataOptions.transport_opts(opts)
           ) do
      metadata = normalize_metadata(result)
      chat_type = parse_chat_type(map_get(metadata, [:type, "type"]))

      {:ok,
       ChannelInfo.new(%{
         id: to_string(map_get(metadata, [:id, "id"]) || chat_id),
         name:
           map_get(metadata, [:title, "title"]) ||
             map_get(metadata, [:username, "username"]) ||
             map_get(metadata, [:first_name, "first_name"]),
         is_dm: chat_type == :private,
         member_count: nil,
         metadata: metadata
       })}
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
        :ex_gram_adapter
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
        :ex_gram_adapter
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
        pick_opts(opts, [:transport, :debug, :check_params, :ex_gram_module, :ex_gram_adapter])

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
    if Keyword.get(opts, :fallback_to_dm, false) do
      send_opts = Keyword.drop(opts, [:fallback_to_dm])

      with {:ok, dm_room_id} <- open_dm(user_id, send_opts),
           {:ok, %Response{} = response} <- send_message(dm_room_id, text, send_opts) do
        {:ok,
         EphemeralMessage.new(%{
           id: response.external_message_id || Jido.Chat.ID.generate!(),
           thread_id: "telegram:#{dm_room_id}",
           used_fallback: true,
           raw: response.raw,
           metadata: %{chat_id: dm_room_id}
         })}
      end
    else
      {:error, :unsupported}
    end
  end

  @impl true
  def fetch_messages(_chat_id, _opts), do: {:error, :unsupported}

  @impl true
  def fetch_channel_messages(_chat_id, _opts), do: {:error, :unsupported}

  @impl true
  def list_threads(_chat_id, _opts), do: {:error, :unsupported}

  @impl true
  def verify_webhook(%WebhookRequest{} = request, opts \\ []) do
    verify_webhook_secret(opts, request.headers)
  end

  @impl true
  def parse_event(%WebhookRequest{} = request, _opts \\ []) do
    parse_payload_event(request.payload)
  end

  @impl true
  def format_webhook_response(result, opts \\ [])

  def format_webhook_response({:ok, _chat, _event}, _opts) do
    WebhookResponse.accepted(%{ok: true})
  end

  def format_webhook_response({:error, :invalid_webhook_secret}, _opts) do
    WebhookResponse.error(401, %{error: "invalid_webhook_secret"})
  end

  def format_webhook_response({:error, reason}, _opts) do
    WebhookResponse.error(400, %{error: to_string(reason)})
  end

  @impl true
  def handle_webhook(%Jido.Chat{} = chat, payload, opts \\ []) when is_map(payload) do
    request =
      WebhookRequest.new(%{
        adapter_name: :telegram,
        headers: opts[:headers] || %{},
        payload: payload,
        raw: opts[:raw_body] || payload,
        metadata: %{raw_body: opts[:raw_body]}
      })

    with :ok <- verify_webhook(request, opts),
         {:ok, parsed_event} <- parse_event(request, opts),
         {:ok, updated_chat, incoming} <- route_parsed_event(chat, parsed_event, opts) do
      {:ok, updated_chat, incoming}
    end
  end

  defp route_parsed_event(_chat, :noop, _opts), do: {:error, :unsupported_update_type}

  defp route_parsed_event(chat, %EventEnvelope{event_type: :slash_command} = envelope, opts) do
    with {:ok, slash_chat, routed_envelope} <-
           Jido.Chat.process_event(chat, :telegram, envelope, opts),
         {:ok, incoming} <- incoming_from_event(routed_envelope),
         thread_id <- thread_id(incoming),
         {:ok, final_chat, _incoming} <-
           Jido.Chat.process_message(slash_chat, :telegram, thread_id, incoming, opts) do
      {:ok, final_chat, incoming}
    end
  end

  defp route_parsed_event(chat, %EventEnvelope{} = envelope, opts) do
    with {:ok, updated_chat, routed_envelope} <-
           Jido.Chat.process_event(chat, :telegram, envelope, opts),
         {:ok, incoming} <- incoming_from_event(routed_envelope) do
      {:ok, updated_chat, incoming}
    end
  end

  defp incoming_from_event(%EventEnvelope{event_type: :message, payload: %Incoming{} = incoming}),
    do: {:ok, incoming}

  defp incoming_from_event(%EventEnvelope{event_type: :slash_command, raw: raw}) do
    case update_message(raw) do
      message when is_map(message) -> transform_message(message)
      _ -> {:error, :unsupported_update_type}
    end
  end

  defp incoming_from_event(%EventEnvelope{event_type: :action, raw: raw}) do
    callback_query = map_get(raw, [:callback_query, "callback_query"]) || %{}
    message = map_get(callback_query, [:message, "message"]) || %{}
    chat_map = map_get(message, [:chat, "chat"]) || %{}
    from = map_get(callback_query, [:from, "from"]) || %{}

    {:ok,
     synthetic_incoming(
       map_get(chat_map, [:id, "id"]),
       map_get(from, [:id, "id"]),
       map_get(callback_query, [:id, "id"]),
       callback_query,
       :action
     )}
  end

  defp incoming_from_event(%EventEnvelope{event_type: :reaction, raw: raw}) do
    reaction = map_get(raw, [:message_reaction, "message_reaction"]) || %{}
    chat_map = map_get(reaction, [:chat, "chat"]) || %{}
    user = map_get(reaction, [:user, "user"]) || %{}

    {:ok,
     synthetic_incoming(
       map_get(chat_map, [:id, "id"]),
       map_get(user, [:id, "id"]),
       map_get(reaction, [:message_id, "message_id"]),
       reaction,
       :reaction
     )}
  end

  defp incoming_from_event(_), do: {:error, :unsupported_update_type}

  defp parse_payload_event(payload) when is_map(payload) do
    cond do
      is_map(map_get(payload, [:message_reaction, "message_reaction"])) ->
        {:ok, reaction_envelope(payload)}

      is_map(map_get(payload, [:callback_query, "callback_query"])) ->
        {:ok, action_envelope(payload)}

      is_map(update_message(payload)) ->
        build_message_or_slash_envelope(update_message(payload), payload)

      true ->
        {:ok, :noop}
    end
  end

  defp parse_payload_event(_payload), do: {:ok, :noop}

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
      :ex_gram_adapter
    ])
    |> maybe_put_option(:caption, upload_caption(upload))
  end

  defp upload_response(%FileUpload{} = upload, media, chat_id) do
    delivered_kind =
      case media.kind do
        :photo -> :image
        _ -> upload.kind
      end

    Response.new(%{
      message_id: media.message_id,
      chat_id: media.chat_id || chat_id,
      date: media.date,
      channel_type: :telegram,
      status: :sent,
      raw: media.raw,
      metadata:
        media.metadata
        |> Map.put(:file_id, media.file_id)
        |> Map.put(:upload_kind, upload.kind)
        |> Map.put(:delivered_kind, delivered_kind)
    })
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

  defp update_message(payload) when is_map(payload) do
    map_get(payload, [:message, "message"]) ||
      map_get(payload, [:edited_message, "edited_message"]) ||
      map_get(payload, [:channel_post, "channel_post"]) ||
      map_get(payload, [:edited_channel_post, "edited_channel_post"])
  end

  defp reaction_envelope(payload) do
    reaction = map_get(payload, [:message_reaction, "message_reaction"]) || %{}
    chat_map = map_get(reaction, [:chat, "chat"]) || %{}
    user = map_get(reaction, [:user, "user"]) || %{}
    message_id = map_get(reaction, [:message_id, "message_id"])
    new_reaction = map_get(reaction, [:new_reaction, "new_reaction"]) || []
    old_reaction = map_get(reaction, [:old_reaction, "old_reaction"]) || []

    added = new_reaction != []
    emoji = extract_reaction_emoji(if(added, do: new_reaction, else: old_reaction))
    room_id = map_get(chat_map, [:id, "id"])
    thread_id = "telegram:#{room_id}"

    EventEnvelope.new(%{
      adapter_name: :telegram,
      event_type: :reaction,
      thread_id: thread_id,
      channel_id: stringify(room_id),
      message_id: stringify(message_id),
      payload: %{
        adapter_name: :telegram,
        thread_id: thread_id,
        message_id: stringify(message_id),
        emoji: emoji,
        added: added,
        user: %{
          user_id: stringify(map_get(user, [:id, "id"]) || "unknown"),
          user_name: map_get(user, [:username, "username"]) || "unknown",
          full_name: map_get(user, [:first_name, "first_name"])
        },
        raw: reaction,
        metadata: %{chat_id: room_id}
      },
      raw: payload,
      metadata: %{}
    })
  end

  defp action_envelope(payload) do
    callback_query = map_get(payload, [:callback_query, "callback_query"]) || %{}
    message = map_get(callback_query, [:message, "message"]) || %{}
    chat_map = map_get(message, [:chat, "chat"]) || %{}
    from = map_get(callback_query, [:from, "from"]) || %{}
    room_id = map_get(chat_map, [:id, "id"])
    thread_id = "telegram:#{room_id}"
    message_id = stringify(map_get(message, [:message_id, "message_id"]))

    EventEnvelope.new(%{
      adapter_name: :telegram,
      event_type: :action,
      thread_id: thread_id,
      channel_id: stringify(room_id),
      message_id: message_id,
      payload: %{
        adapter_name: :telegram,
        thread_id: thread_id,
        message_id: message_id,
        action_id: stringify(map_get(callback_query, [:data, "data"]) || map_get(callback_query, [:id, "id"])),
        value: map_get(callback_query, [:data, "data"]),
        user: %{
          user_id: stringify(map_get(from, [:id, "id"]) || "unknown"),
          user_name:
            map_get(from, [:username, "username"]) ||
              stringify(map_get(from, [:id, "id"]) || "unknown"),
          full_name: map_get(from, [:first_name, "first_name"])
        },
        raw: callback_query,
        metadata: %{chat_id: room_id}
      },
      raw: payload,
      metadata: %{}
    })
  end

  defp build_message_or_slash_envelope(message, payload) do
    with {:ok, incoming} <- transform_message(message) do
      case parse_slash_command(map_get(message, [:text, "text"])) do
        nil ->
          {:ok,
           EventEnvelope.new(%{
             adapter_name: :telegram,
             event_type: :message,
             thread_id: thread_id(incoming),
             channel_id: stringify(incoming.external_room_id),
             message_id: stringify(incoming.external_message_id),
             payload: incoming,
             raw: payload,
             metadata: %{}
           })}

        {command, arguments} ->
          slash_payload = %{
            adapter_name: :telegram,
            channel_id: stringify(incoming.external_room_id),
            command: command,
            text: arguments,
            user: incoming.author,
            raw: message,
            metadata: %{thread_id: thread_id(incoming)}
          }

          {:ok,
           EventEnvelope.new(%{
             adapter_name: :telegram,
             event_type: :slash_command,
             thread_id: thread_id(incoming),
             channel_id: stringify(incoming.external_room_id),
             message_id: stringify(incoming.external_message_id),
             payload: slash_payload,
             raw: payload,
             metadata: %{}
           })}
      end
    end
  end

  defp verify_webhook_secret(opts, headers) do
    expected =
      opts[:secret_token] || Application.get_env(:jido_chat_telegram, :telegram_webhook_secret)

    if is_nil(expected) do
      :ok
    else
      actual = header_value(headers, "x-telegram-bot-api-secret-token")
      if actual == expected, do: :ok, else: {:error, :invalid_webhook_secret}
    end
  end

  defp transform_message(message) do
    chat = map_get(message, [:chat, "chat"]) || %{}
    from = map_get(message, [:from, "from"]) || %{}
    chat_type = parse_chat_type(map_get(chat, [:type, "type"]))

    thread_id = map_get(message, [:message_thread_id, "message_thread_id"])

    {:ok,
     Incoming.new(%{
       external_room_id: map_get(chat, [:id, "id"]),
       external_user_id: map_get(from, [:id, "id"]),
       text: map_get(message, [:text, "text"]),
       media: extract_media(message),
       username: map_get(from, [:username, "username"]),
       display_name: map_get(from, [:first_name, "first_name"]),
       external_message_id: map_get(message, [:message_id, "message_id"]),
       timestamp: map_get(message, [:date, "date"]),
       external_thread_id: stringify(thread_id),
       chat_type: chat_type,
       chat_title: map_get(chat, [:title, "title"]),
       channel_meta: %{
         adapter_name: :telegram,
         external_room_id: map_get(chat, [:id, "id"]),
         external_thread_id: stringify(thread_id),
         chat_type: chat_type,
         chat_title: map_get(chat, [:title, "title"]),
         is_dm: chat_type == :private,
         metadata: %{}
       },
       raw: message
     })}
  end

  defp parse_slash_command(text) when is_binary(text) do
    case Regex.run(~r/^\/(\w+)(?:@\w+)?(?:\s+(.*))?$/, text) do
      [_, command] -> {"/" <> command, ""}
      [_, command, arguments] -> {"/" <> command, String.trim(arguments)}
      _ -> nil
    end
  end

  defp parse_slash_command(_), do: nil

  defp extract_reaction_emoji([first | _]) when is_map(first),
    do: map_get(first, [:emoji, "emoji"]) || ""

  defp extract_reaction_emoji(_), do: ""

  defp synthetic_incoming(chat_id, user_id, message_id, raw, event_type) do
    Incoming.new(%{
      external_room_id: chat_id || "unknown",
      external_user_id: user_id,
      external_message_id: message_id,
      text: nil,
      raw: raw,
      metadata: %{event_type: event_type}
    })
  end

  defp thread_id(%Incoming{external_room_id: room_id, external_thread_id: nil}),
    do: "telegram:#{room_id}"

  defp thread_id(%Incoming{external_room_id: room_id, external_thread_id: thread_id}),
    do: "telegram:#{room_id}:#{thread_id}"

  defp fetch_token(token) do
    token || Application.get_env(:jido_chat_telegram, :telegram_bot_token) ||
      raise ArgumentError,
            "missing Telegram bot token; pass :token option or configure :jido_chat_telegram, :telegram_bot_token"
  end

  defp transport(opts) when is_list(opts), do: transport(Map.new(opts))
  defp transport(%{transport: transport}) when not is_nil(transport), do: transport
  defp transport(_opts), do: ExGramClient

  defp maybe_put_action(opts, nil), do: opts
  defp maybe_put_action(opts, ""), do: opts
  defp maybe_put_action(opts, status), do: Keyword.put(opts, :action, status)

  defp consume_stream_chunks(chunks, draft_chat_id, token, opts, draft_id, interval_ms) do
    initial = %{text: "", last_draft_text: nil, last_update_ms: nil}

    Enum.reduce_while(chunks, {:ok, initial}, fn chunk, {:ok, state} ->
      next_state = %{state | text: state.text <> to_string(chunk)}

      case maybe_send_draft_update(next_state, draft_chat_id, token, opts, draft_id, interval_ms) do
        {:ok, updated_state} -> {:cont, {:ok, updated_state}}
        {:error, reason} -> {:halt, {:error, reason}}
        :skip -> {:cont, {:ok, next_state}}
      end
    end)
  rescue
    Protocol.UndefinedError -> {:error, :invalid_stream_chunk}
  end

  defp maybe_send_draft_update(
         %{text: ""},
         _draft_chat_id,
         _token,
         _opts,
         _draft_id,
         _interval_ms
       ),
       do: :skip

  defp maybe_send_draft_update(
         %{text: text, last_draft_text: text},
         _draft_chat_id,
         _token,
         _opts,
         _draft_id,
         _interval_ms
       ),
       do: :skip

  defp maybe_send_draft_update(state, draft_chat_id, token, opts, draft_id, interval_ms) do
    now_ms = System.monotonic_time(:millisecond)

    if send_draft_now?(state.last_update_ms, now_ms, interval_ms) do
      payload =
        StreamOptions.draft_payload_opts(opts, draft_id)
        |> Map.merge(%{"chat_id" => draft_chat_id, "text" => state.text})

      case transport(opts).call(
             token,
             "sendMessageDraft",
             payload,
             StreamOptions.transport_opts(opts)
           ) do
        {:ok, _result} ->
          {:ok, %{state | last_draft_text: state.text, last_update_ms: now_ms}}

        {:error, reason} ->
          {:error, reason}
      end
    else
      :skip
    end
  end

  defp send_draft_now?(nil, _now_ms, _interval_ms), do: true
  defp send_draft_now?(_last_update_ms, _now_ms, 0), do: true

  defp send_draft_now?(last_update_ms, now_ms, interval_ms),
    do: now_ms - last_update_ms >= interval_ms

  defp fallback_stream_send(chat_id, chunks, opts) do
    text = chunks |> Enum.map(&to_string/1) |> Enum.join("")

    if text == "" do
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

  defp parse_chat_type("private"), do: :private
  defp parse_chat_type("group"), do: :group
  defp parse_chat_type("supergroup"), do: :supergroup
  defp parse_chat_type("channel"), do: :channel
  defp parse_chat_type(:private), do: :private
  defp parse_chat_type(:group), do: :group
  defp parse_chat_type(:supergroup), do: :supergroup
  defp parse_chat_type(:channel), do: :channel
  defp parse_chat_type(_), do: :unknown

  defp extract_media(message) when is_map(message) do
    photos = map_get(message, [:photo, "photo"])
    audio = map_get(message, [:audio, "audio"])
    voice = map_get(message, [:voice, "voice"])
    video = map_get(message, [:video, "video"])
    document = map_get(message, [:document, "document"])

    []
    |> maybe_append_photo(photos)
    |> maybe_append_media(:audio, audio)
    |> maybe_append_media(:audio, voice)
    |> maybe_append_media(:video, video)
    |> maybe_append_media(:file, document)
  end

  defp maybe_append_photo(media, photos) when is_list(photos) and photos != [] do
    photo = List.last(photos)

    case normalize_telegram_media(:image, photo) do
      nil -> media
      entry -> media ++ [entry]
    end
  end

  defp maybe_append_photo(media, _), do: media

  defp maybe_append_media(media, kind, value) do
    case normalize_telegram_media(kind, value) do
      nil -> media
      entry -> media ++ [entry]
    end
  end

  defp normalize_telegram_media(_kind, nil), do: nil

  defp normalize_telegram_media(kind, media) when is_map(media) do
    media_type = map_get(media, [:mime_type, "mime_type"])
    resolved_kind = resolve_kind(kind, media_type)

    media_ref =
      map_get(media, [:file_id, "file_id", :id, "id"])
      |> normalize_file_ref()

    if is_nil(media_ref) do
      nil
    else
      %{
        kind: resolved_kind,
        url: media_ref,
        media_type: media_type,
        filename: map_get(media, [:file_name, "file_name"]),
        size_bytes: map_get(media, [:file_size, "file_size"]),
        width: map_get(media, [:width, "width"]),
        height: map_get(media, [:height, "height"]),
        duration: map_get(media, [:duration, "duration"])
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()
    end
  end

  defp normalize_telegram_media(_kind, _), do: nil

  defp normalize_file_ref(nil), do: nil
  defp normalize_file_ref(value) when is_binary(value), do: "telegram://file/#{value}"
  defp normalize_file_ref(value), do: "telegram://file/#{to_string(value)}"

  defp resolve_kind(:file, media_type) when is_binary(media_type) do
    cond do
      String.starts_with?(media_type, "image/") -> :image
      String.starts_with?(media_type, "audio/") -> :audio
      String.starts_with?(media_type, "video/") -> :video
      true -> :file
    end
  end

  defp resolve_kind(kind, _), do: kind

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
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp map_get(_other, _keys), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)

  defp pick_opts(opts, allowed_keys) when is_list(opts), do: Keyword.take(opts, allowed_keys)

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

  defp validate_sink_mfa({module, function, args})
       when is_atom(module) and is_atom(function) and is_list(args),
       do: {:ok, {module, function, args}}

  defp validate_sink_mfa(_), do: {:error, :invalid_sink_mfa}

  defp polling_worker_opts(bridge_id, ingress, opts, sink_mfa) do
    bridge_config = Keyword.get(opts, :bridge_config)
    credentials = bridge_credentials(bridge_config)

    transport_opts =
      ingress
      |> map_get([:transport_opts, "transport_opts"])
      |> case do
        value when is_list(value) -> value
        value when is_map(value) -> Enum.into(value, [])
        _ -> []
      end

    [
      bridge_id: bridge_id,
      sink_mfa: sink_mfa,
      sink_opts: [bridge_id: bridge_id],
      token: map_get(ingress, [:token, "token"]) || map_get(credentials, [:token, "token"]),
      transport: map_get(ingress, [:transport, "transport"]) || ExGramClient,
      transport_opts: transport_opts,
      timeout_s: map_get(ingress, [:timeout_s, "timeout_s"]) || 20,
      poll_interval_ms: map_get(ingress, [:poll_interval_ms, "poll_interval_ms"]) || 250,
      allowed_updates: map_get(ingress, [:allowed_updates, "allowed_updates"]),
      max_backoff_ms: map_get(ingress, [:max_backoff_ms, "max_backoff_ms"]) || 5_000
    ]
  end

  defp bridge_credentials(%{credentials: credentials}) when is_map(credentials), do: credentials
  defp bridge_credentials(_), do: %{}
end
