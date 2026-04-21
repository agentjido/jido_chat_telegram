defmodule Jido.Chat.Telegram.AdapterSurfaceTest do
  use ExUnit.Case, async: true

  alias Jido.Chat
  alias Jido.Chat.Adapter, as: ChatAdapter
  alias Jido.Chat.{Capabilities, FileUpload, PostPayload}
  alias Jido.Chat.Telegram.Adapter

  setup_all do
    Code.ensure_loaded!(Adapter)
    :ok
  end

  defmodule MockTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(token, method, payload, _opts) do
      send(self(), {:transport_call, token, method, payload})

      case method do
        "sendMessage" ->
          {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}, "date" => 1_706_745_600}}

        "sendMessageDraft" ->
          {:ok, true}

        "editMessageText" ->
          {:ok, true}

        "deleteMessage" ->
          {:ok, true}

        "sendChatAction" ->
          {:ok, true}

        "getChat" ->
          {:ok,
           %{
             "id" => payload["chat_id"],
             "type" => "private",
             "first_name" => "Alice",
             "username" => "alice"
           }}

        "setMessageReaction" ->
          {:ok, true}

        "sendPhoto" ->
          {:ok,
           %{
             "message_id" => 77,
             "chat" => %{"id" => payload["chat_id"]},
             "date" => 1_706_745_601,
             "photo" => [%{"file_id" => "photo-file-id"}],
             "caption" => payload["caption"]
           }}

        "sendDocument" ->
          {:ok,
           %{
             "message_id" => 78,
             "chat" => %{"id" => payload["chat_id"]},
             "date" => 1_706_745_602,
             "document" => %{"file_id" => "document-file-id"},
             "caption" => payload["caption"]
           }}

        "createForumTopic" ->
          {:ok,
           %{
             "message_thread_id" => 321,
             "name" => payload["name"]
           }}
      end
    end
  end

  defmodule MockChatFullInfo do
    @schema Zoi.struct(
              __MODULE__,
              %{
                id: Zoi.any() |> Zoi.nullish(),
                type: Zoi.any() |> Zoi.nullish(),
                first_name: Zoi.any() |> Zoi.nullish(),
                username: Zoi.any() |> Zoi.nullish(),
                permissions: Zoi.any() |> Zoi.nullish()
              },
              coerce: true
            )

    @enforce_keys Zoi.Struct.enforce_keys(@schema)
    defstruct Zoi.Struct.struct_fields(@schema)
  end

  defmodule StructMetadataTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(token, method, payload, _opts) do
      send(self(), {:transport_call, token, method, payload})

      case method do
        "getChat" ->
          {:ok,
           %MockChatFullInfo{
             id: payload["chat_id"],
             type: "private",
             first_name: "Alice",
             username: "alice",
             permissions: %{can_send_messages: true}
           }}

        _ ->
          {:error, {:unsupported_method, method}}
      end
    end
  end

  defmodule ReactionUnsupportedTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, "setMessageReaction", _payload, _opts), do: {:error, :unsupported_method}
    def call(_token, method, _payload, _opts), do: {:error, {:unsupported_method, method}}
  end

  test "channel metadata" do
    caps = Adapter.capabilities()

    assert Adapter.channel_type() == :telegram
    assert caps.send_message == :native
    assert caps.edit_message == :native
    assert caps.delete_message == :native
  end

  test "adapter capabilities matrix declares supported and unsupported surfaces" do
    caps = Jido.Chat.Telegram.Adapter.capabilities()

    assert caps.send_message == :native
    assert caps.send_file == :native
    assert caps.edit_message == :native
    assert caps.fetch_messages == :unsupported
    assert caps.list_threads == :unsupported
    assert caps.open_modal == :unsupported
    assert caps.post_ephemeral == :fallback

    assert :ok = Jido.Chat.Adapter.validate_capabilities(Jido.Chat.Telegram.Adapter)
  end

  test "delivery capabilities include canonical single-file media support but not multi-file" do
    caps = Capabilities.channel_capabilities(Jido.Chat.Telegram.Adapter)

    assert :image in caps
    assert :file in caps
    refute :multi_file in caps
  end

  test "adapter extension capabilities expose telegram-only surface" do
    caps = Jido.Chat.Telegram.Adapter.extension_capabilities()
    assert caps.send_photo == :native
    assert caps.send_document == :native
    assert caps.send_media_group == :unsupported
  end

  test "transform_incoming/1 normalizes a telegram message map" do
    update = %{
      "message" => %{
        "message_id" => 456,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "group", "title" => "Test Group"},
        "from" => %{"id" => 111, "first_name" => "Jane", "username" => "jane_doe"},
        "message_thread_id" => 999,
        "text" => "Hello group!"
      }
    }

    assert {:ok, incoming} = Adapter.transform_incoming(update)
    assert incoming.external_room_id == 789
    assert incoming.external_user_id == 111
    assert incoming.text == "Hello group!"
    assert incoming.username == "jane_doe"
    assert incoming.display_name == "Jane"
    assert incoming.chat_type == :group
    assert incoming.chat_title == "Test Group"
    assert incoming.external_thread_id == "999"
    assert incoming.channel_meta.adapter_name == :telegram
    assert incoming.channel_meta.external_room_id == 789
    assert incoming.channel_meta.external_thread_id == "999"
    assert incoming.channel_meta.is_dm == false
  end

  test "transform_incoming/1 extracts media" do
    update = %{
      "message" => %{
        "message_id" => 456,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "group"},
        "photo" => [
          %{"file_id" => "photo-small", "width" => 64, "height" => 64, "file_size" => 128},
          %{"file_id" => "photo-large", "width" => 512, "height" => 512, "file_size" => 4096}
        ],
        "text" => nil
      }
    }

    assert {:ok, incoming} = Adapter.transform_incoming(update)
    assert [%{kind: :image, url: "telegram://file/photo-large"}] = incoming.media
  end

  test "transform_incoming/1 errors for missing/unsupported updates" do
    assert {:error, :no_message} = Adapter.transform_incoming(%{"message" => nil})

    assert {:error, :unsupported_update_type} =
             Adapter.transform_incoming(%{"edited_message" => %{}})
  end

  test "send_message/3 uses configured transport and returns normalized send result" do
    assert {:ok, result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               parse_mode: "HTML"
             )

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["chat_id"] == 123
    assert payload["text"] == "hello"
    assert payload["parse_mode"] == "HTML"

    assert result.message_id == 42
    assert result.chat_id == 123
    assert result.date == 1_706_745_600
  end

  test "adapter stream uses telegram draft updates for private chats and final sendMessage" do
    assert {:ok, result} =
             Jido.Chat.Adapter.stream(
               Jido.Chat.Telegram.Adapter,
               123,
               ["hel", "lo"],
               token: "bot-token",
               transport: MockTransport,
               stream_update_interval_ms: 0,
               draft_id: 7
             )

    assert_received {:transport_call, "bot-token", "sendMessageDraft", first_payload}
    assert first_payload["chat_id"] == 123
    assert first_payload["draft_id"] == 7
    assert first_payload["text"] == "hel"

    assert_received {:transport_call, "bot-token", "sendMessageDraft", second_payload}
    assert second_payload["chat_id"] == 123
    assert second_payload["draft_id"] == 7
    assert second_payload["text"] == "hello"

    assert_received {:transport_call, "bot-token", "sendMessage", final_payload}
    assert final_payload["chat_id"] == 123
    assert final_payload["text"] == "hello"

    assert result.message_id == "42"
    assert result.external_message_id == "42"
    assert result.chat_id == 123
  end

  test "adapter stream skips duplicate partial draft updates" do
    assert {:ok, _result} =
             Jido.Chat.Adapter.stream(
               Jido.Chat.Telegram.Adapter,
               123,
               ["hi", "", "", "!"],
               token: "bot-token",
               transport: MockTransport,
               stream_update_interval_ms: 0,
               draft_id: 9
             )

    assert_received {:transport_call, "bot-token", "sendMessageDraft", %{"text" => "hi"}}
    assert_received {:transport_call, "bot-token", "sendMessageDraft", %{"text" => "hi!"}}
    assert_received {:transport_call, "bot-token", "sendMessage", %{"text" => "hi!"}}

    refute_received {:transport_call, "bot-token", "sendMessageDraft", %{"text" => ""}}
  end

  test "adapter stream falls back to one-shot send for unsupported targets" do
    assert {:ok, result} =
             Jido.Chat.Adapter.stream(
               Jido.Chat.Telegram.Adapter,
               "@channelname",
               ["hello", " world"],
               token: "bot-token",
               transport: MockTransport,
               draft_id: 7
             )

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["chat_id"] == "@channelname"
    assert payload["text"] == "hello world"

    refute_received {:transport_call, "bot-token", "sendMessageDraft", _payload}

    assert result.external_message_id == "42"
  end

  test "adapter stream returns empty_stream when no content is produced" do
    assert {:error, :empty_stream} =
             Jido.Chat.Adapter.stream(
               Jido.Chat.Telegram.Adapter,
               123,
               ["", ""],
               token: "bot-token",
               transport: MockTransport
             )

    refute_received {:transport_call, "bot-token", "sendMessageDraft", _payload}
    refute_received {:transport_call, "bot-token", "sendMessage", _payload}
  end

  test "send_message/3 maps generic reply and thread routing to telegram payload fields" do
    assert {:ok, _result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               reply_to_id: 456,
               external_thread_id: "999"
             )

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["reply_to_message_id"] == 456
    assert payload["message_thread_id"] == "999"
  end

  test "edit_message/4 handles boolean telegram response" do
    assert {:ok, result} =
             Adapter.edit_message(123, 42, "updated",
               token: "bot-token",
               transport: MockTransport
             )

    assert_received {:transport_call, "bot-token", "editMessageText", payload}
    assert payload["chat_id"] == 123
    assert payload["message_id"] == 42
    assert payload["text"] == "updated"

    assert result.message_id == 42
    assert result.chat_id == 123
    assert result.date == nil
  end

  test "delete_message/3 delegates to transport" do
    assert :ok = Adapter.delete_message(123, 42, token: "bot-token", transport: MockTransport)

    assert_received {:transport_call, "bot-token", "deleteMessage", payload}
    assert payload["chat_id"] == 123
    assert payload["message_id"] == 42
  end

  test "start_typing/2 delegates to transport" do
    assert :ok =
             Adapter.start_typing(123,
               token: "bot-token",
               action: "upload_photo",
               transport: MockTransport
             )

    assert_received {:transport_call, "bot-token", "sendChatAction", payload}
    assert payload["chat_id"] == 123
    assert payload["action"] == "upload_photo"
  end

  test "fetch_metadata/2 returns normalized channel info" do
    assert {:ok, info} =
             Adapter.fetch_metadata(123,
               token: "bot-token",
               transport: MockTransport
             )

    assert_received {:transport_call, "bot-token", "getChat", payload}
    assert payload["chat_id"] == 123
    assert info.id == "123"
    assert info.name == "alice"
    assert info.is_dm == true
  end

  test "fetch_metadata/2 normalizes struct metadata into plain map" do
    assert {:ok, info} =
             Adapter.fetch_metadata(123,
               token: "bot-token",
               transport: StructMetadataTransport
             )

    assert_received {:transport_call, "bot-token", "getChat", payload}
    assert payload["chat_id"] == 123
    assert is_map(info.metadata)
    refute Map.has_key?(info.metadata, :__struct__)
    assert info.metadata.permissions == %{can_send_messages: true}
  end

  test "open_dm/2 maps to user id on telegram" do
    assert {:ok, "99"} = Adapter.open_dm("99", [])
  end

  test "post_ephemeral/4 uses fallback dm flow" do
    assert {:ok, ephemeral} =
             Adapter.post_ephemeral(123, "99", "secret",
               fallback_to_dm: true,
               token: "bot-token",
               transport: MockTransport
             )

    assert ephemeral.used_fallback == true
    assert ephemeral.thread_id == "telegram:99"

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["chat_id"] == "99"
    assert payload["text"] == "secret"
  end

  test "add/remove reaction delegate through transport" do
    assert :ok =
             Adapter.add_reaction(123, 42, "👍",
               token: "bot-token",
               transport: MockTransport
             )

    assert_received {:transport_call, "bot-token", "setMessageReaction", payload}
    assert payload["chat_id"] == 123
    assert payload["message_id"] == 42
    assert payload["reaction"] == [%{"type" => "emoji", "emoji" => "👍"}]

    assert :ok =
             Adapter.remove_reaction(123, 42, "👍",
               token: "bot-token",
               transport: MockTransport
             )

    assert_received {:transport_call, "bot-token", "setMessageReaction", payload2}
    assert payload2["reaction"] == []
  end

  test "send_file/3 sends images and maps generic reply/thread options" do
    assert {:ok, response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :image,
                 url: "https://example.com/test.png",
                 metadata: %{"caption" => "hello"}
               },
               token: "bot-token",
               transport: MockTransport,
               reply_to_id: 42,
               external_thread_id: 99
             )

    assert response.external_message_id == "77"
    assert response.external_room_id == 123
    assert response.metadata.file_id == "photo-file-id"
    assert response.metadata.upload_kind == :image

    assert_received {:transport_call, "bot-token", "sendPhoto", payload}
    assert payload["chat_id"] == 123
    assert payload["photo"] == "https://example.com/test.png"
    assert payload["caption"] == "hello"
    assert payload["reply_to_message_id"] == 42
    assert payload["message_thread_id"] == 99
  end

  test "send_file/3 supports filesystem paths and raw byte uploads" do
    path =
      Path.join(
        System.tmp_dir!(),
        "jido-telegram-upload-#{System.unique_integer([:positive])}.txt"
      )

    File.write!(path, "telegram path upload\n")

    on_exit(fn ->
      File.rm(path)
    end)

    assert {:ok, path_response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :file,
                 path: path,
                 filename: Path.basename(path)
               },
               token: "bot-token",
               transport: MockTransport
             )

    assert path_response.external_message_id == "78"
    assert_received {:transport_call, "bot-token", "sendDocument", path_payload}
    assert path_payload["document"] == {:file, path}

    assert {:ok, data_response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :file,
                 data: "telegram bytes upload\n",
                 filename: "bytes.txt"
               },
               token: "bot-token",
               transport: MockTransport
             )

    assert data_response.external_message_id == "78"
    assert_received {:transport_call, "bot-token", "sendDocument", data_payload}
    assert data_payload["document"] == {:file_content, "telegram bytes upload\n", "bytes.txt"}
  end

  test "send_file/3 returns explicit validation errors for missing upload data" do
    assert {:error, :missing_filename} =
             Adapter.send_file(
               123,
               %FileUpload{kind: :file, data: "telegram bytes upload\n"},
               token: "bot-token",
               transport: MockTransport
             )

    assert {:error, :missing_file_source} =
             Adapter.send_file(
               123,
               %FileUpload{kind: :file, filename: "missing.txt"},
               token: "bot-token",
               transport: MockTransport
             )
  end

  test "core post_message/4 uses telegram send_file support for canonical uploads" do
    payload =
      PostPayload.new(%{
        text: "doc caption",
        files: [
          %{
            kind: :file,
            url: "https://example.com/test.pdf",
            filename: "test.pdf"
          }
        ]
      })

    assert {:ok, response} =
             ChatAdapter.post_message(
               Jido.Chat.Telegram.Adapter,
               123,
               payload,
               token: "bot-token",
               transport: MockTransport,
               reply_to_id: 41,
               external_thread_id: 88
             )

    assert response.external_message_id == "78"
    assert response.external_room_id == 123
    assert response.metadata.file_id == "document-file-id"
    assert response.metadata.upload_kind == :file

    assert_received {:transport_call, "bot-token", "sendDocument", payload}
    assert payload["document"] == "https://example.com/test.pdf"
    assert payload["caption"] == "doc caption"
    assert payload["reply_to_message_id"] == 41
    assert payload["message_thread_id"] == 88
  end

  test "add/remove reaction map unsupported transport method to unsupported" do
    assert {:error, :unsupported} =
             Adapter.add_reaction(123, 42, "👍",
               token: "bot-token",
               transport: ReactionUnsupportedTransport
             )

    assert {:error, :unsupported} =
             Adapter.remove_reaction(123, 42, "👍",
               token: "bot-token",
               transport: ReactionUnsupportedTransport
             )
  end

  test "history/list_threads remain unsupported in telegram phase 2" do
    assert {:error, :unsupported} = Adapter.fetch_messages(123, [])
    assert {:error, :unsupported} = Adapter.fetch_channel_messages(123, [])
    assert {:error, :unsupported} = Adapter.list_threads(123, [])
  end

  test "open_thread/3 creates forum topics and normalizes room/thread ids" do
    assert {:ok, thread} =
             Adapter.open_thread(123, nil,
               token: "bot-token",
               topic_name: "Live Review",
               transport: MockTransport
             )

    assert thread.external_thread_id == "321"
    assert thread.delivery_external_room_id == "123"

    assert_received {:transport_call, "bot-token", "createForumTopic", payload}
    assert payload["chat_id"] == 123
    assert payload["name"] == "Live Review"
  end

  test "open_thread/3 can be explicitly disabled" do
    assert {:error, :unsupported} =
             Adapter.open_thread(123, nil,
               token: "bot-token",
               supports_forum_topics: false,
               transport: MockTransport
             )
  end

  test "handle_webhook/3 normalizes and routes through Jido.Chat.process_message/5" do
    chat =
      Chat.new(user_name: "jido", adapters: %{telegram: Jido.Chat.Telegram.Adapter})
      |> Chat.on_new_mention(fn _thread, _incoming -> send(self(), :mention) end)

    update = %{
      "message" => %{
        "message_id" => 999,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "first_name" => "Jane", "username" => "jane_doe"},
        "text" => "@jido hello"
      }
    }

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{} = incoming} =
             Adapter.handle_webhook(chat, update, [])

    assert incoming.external_room_id == 123
    assert incoming.external_message_id == 999
    assert_received :mention
  end

  test "handle_webhook/3 parses slash commands from Telegram text messages" do
    chat =
      Chat.new(adapters: %{telegram: Jido.Chat.Telegram.Adapter})
      |> Chat.on_slash_command(fn _event -> send(self(), :slash_hit) end)

    update = %{
      "message" => %{
        "message_id" => 222,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "/help topic-a"
      }
    }

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{external_message_id: 222}} =
             Adapter.handle_webhook(chat, update, [])

    assert_received :slash_hit
  end

  test "handle_webhook/3 keeps slash messages on the core message routing path" do
    chat =
      Chat.new(user_name: "jido", adapters: %{telegram: Jido.Chat.Telegram.Adapter})
      |> Chat.on_slash_command(fn _event -> send(self(), :slash_hit) end)
      |> Chat.on_new_message(~r/^\/help/u, fn _thread, _incoming -> send(self(), :message_hit) end)

    update = %{
      "message" => %{
        "message_id" => 223,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "/help topic-a"
      }
    }

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{external_message_id: 223}} =
             Adapter.handle_webhook(chat, update, [])

    assert_received :slash_hit
    assert_received :message_hit
  end

  test "handle_webhook/3 accepts edited_message update family" do
    chat = Chat.new(adapters: %{telegram: Jido.Chat.Telegram.Adapter})

    update = %{
      "edited_message" => %{
        "message_id" => 333,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "edited text"
      }
    }

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{external_message_id: 333, text: "edited text"}} =
             Adapter.handle_webhook(chat, update, [])
  end

  test "handle_webhook/3 accepts channel_post and edited_channel_post update families" do
    chat = Chat.new(adapters: %{telegram: Jido.Chat.Telegram.Adapter})

    channel_post = %{
      "channel_post" => %{
        "message_id" => 444,
        "chat" => %{"id" => -100_123, "type" => "channel", "title" => "announcements"},
        "text" => "posted"
      }
    }

    edited_channel_post = %{
      "edited_channel_post" => %{
        "message_id" => 445,
        "chat" => %{"id" => -100_123, "type" => "channel", "title" => "announcements"},
        "text" => "edited"
      }
    }

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{external_room_id: -100_123, external_message_id: 444}} =
             Adapter.handle_webhook(chat, channel_post, [])

    assert {:ok, _updated_chat, %Jido.Chat.Incoming{external_room_id: -100_123, external_message_id: 445}} =
             Adapter.handle_webhook(chat, edited_channel_post, [])
  end

  test "handle_webhook/3 routes callback_query and reaction updates into process_* handlers" do
    chat =
      Chat.new(adapters: %{telegram: Jido.Chat.Telegram.Adapter})
      |> Chat.on_action(fn _event -> send(self(), :action_hit) end)
      |> Chat.on_reaction(fn _event -> send(self(), :reaction_hit) end)

    callback_update = %{
      "callback_query" => %{
        "id" => "cb1",
        "data" => "approve",
        "from" => %{"id" => 50, "username" => "bob"},
        "message" => %{
          "message_id" => 100,
          "chat" => %{"id" => 123, "type" => "private"}
        }
      }
    }

    assert {:ok, _chat, %Jido.Chat.Incoming{metadata: %{event_type: :action}}} =
             Adapter.handle_webhook(chat, callback_update, [])

    assert_received :action_hit

    reaction_update = %{
      "message_reaction" => %{
        "chat" => %{"id" => 123},
        "message_id" => 101,
        "user" => %{"id" => 50, "username" => "bob"},
        "new_reaction" => [%{"type" => "emoji", "emoji" => "👍"}],
        "old_reaction" => []
      }
    }

    assert {:ok, _chat, %Jido.Chat.Incoming{metadata: %{event_type: :reaction}}} =
             Adapter.handle_webhook(chat, reaction_update, [])

    assert_received :reaction_hit
  end

  test "handle_webhook/3 rejects invalid webhook secret when configured" do
    chat = Chat.new(adapters: %{telegram: Jido.Chat.Telegram.Adapter})

    update = %{
      "message" => %{
        "message_id" => 1,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 1},
        "text" => "hello"
      }
    }

    assert {:error, :invalid_webhook_secret} =
             Adapter.handle_webhook(chat, update,
               secret_token: "expected",
               headers: %{"x-telegram-bot-api-secret-token" => "wrong"}
             )
  end

  test "parse_event/2 returns noop for unsupported update types" do
    request =
      Jido.Chat.WebhookRequest.new(%{
        adapter_name: :telegram,
        payload: %{"poll" => %{"id" => "p1"}}
      })

    assert {:ok, :noop} = Jido.Chat.Telegram.Adapter.parse_event(request, [])
  end
end
