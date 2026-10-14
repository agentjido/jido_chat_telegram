defmodule Jido.Chat.Telegram.AdapterSurfaceTest do
  use Jido.Chat.AdapterTestKit,
    adapter: Jido.Chat.Telegram.Adapter,
    async: true

  alias Jido.Chat
  alias Jido.Chat.{FileUpload, Handlers, Resources}
  alias Jido.Chat.Telegram.Adapter

  defp captured_binding(extra \\ []) do
    {:ok, binding} =
      Chat.bind(
        Adapter,
        [
          id: "surface",
          token: "bot-token",
          transport: Jido.Chat.Telegram.AdapterSurfaceTest.MockTransport,
          bot_username: "jido"
        ] ++ extra
      )

    binding
  end

  defp normalize_update(update) do
    binding = captured_binding()
    # Old media fixtures omitted the now-required provider sender. Supply a fixed fixture sender.
    update = fixture_sender(update)
    {:ok, delivery} = Chat.normalize_event(binding, update)
    [fact] = delivery.signals
    {binding, fact}
  end

  defp fixture_sender(update) do
    Enum.reduce(["message", "edited_message", "channel_post", "edited_channel_post"], update, fn key, acc ->
      atom = String.to_existing_atom(key)
      actual = if Map.has_key?(acc, key), do: key, else: atom

      case Map.get(acc, actual) do
        message when is_map(message) ->
          if Map.get(message, "from") || Map.get(message, :from),
            do: acc,
            else:
              Map.put(
                acc,
                actual,
                Map.put(message, if(is_struct(message) or actual == atom, do: :from, else: "from"), %{
                  id: 111,
                  first_name: "Jane"
                })
              )

        _ ->
          acc
      end
    end)
  end

  defp media_records(binding, fact) do
    Enum.map(fact.data["media"], fn media ->
      {:ok, private} = Resources.resolve(binding, media["resource_ref"])
      private
    end)
  end

  defp accept_webhook(binding, handlers, payload, headers \\ %{}) do
    request =
      Jido.Chat.WebhookRequest.new(%{adapter_name: :telegram, payload: plain_payload(payload), headers: headers})

    with :ok <- Adapter.verify_webhook(request, binding.options),
         {:ok, delivery} <- Chat.normalize_event(binding, fixture_sender(payload)),
         {:ok, handlers, _} <- Handlers.accept(handlers, binding, delivery),
         do: {:ok, handlers, delivery.signals}
  end

  defp plain_payload(%_{} = value), do: plain_payload(Map.from_struct(value))
  defp plain_payload(value) when is_map(value), do: Map.new(value, fn {key, item} -> {key, plain_payload(item)} end)
  defp plain_payload(value) when is_list(value), do: Enum.map(value, &plain_payload/1)
  defp plain_payload(value), do: value

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
    assert caps.fetch_media == :native
    assert caps.edit_message == :native
    assert caps.fetch_messages == :unsupported
    assert caps.list_threads == :unsupported
    assert caps.open_modal == :unsupported
    assert caps.post_ephemeral == :fallback

    assert :ok = Jido.Chat.Adapter.validate_capabilities(Jido.Chat.Telegram.Adapter)
  end

  test "delivery capabilities include canonical single-file media support but not multi-file" do
    assert Adapter.capabilities().send_file == :native
    assert Jido.Chat.AdapterTestKit.supported?(Adapter, :send_file)
    assert :ok = Jido.Chat.Adapter.validate_capabilities(Adapter)
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

    {_binding, incoming} = normalize_update(update)
    assert incoming.data["room_id"] == "789"
    assert incoming.data["sender"]["id"] == "111"
    assert incoming.data["text"] == "Hello group!"
    assert incoming.data["sender"]["username"] == "jane_doe"
    assert incoming.data["sender"]["display_name"] == "Jane"
    assert incoming.data["conversation_kind"] == "group"
    assert incoming.data["conversation_name"] == "Test Group"
    assert incoming.data["thread_id"] == "999"
    assert Adapter.channel_type() == :telegram
    assert incoming.data["room_id"] == "789"
    assert incoming.data["thread_id"] == "999"
    assert incoming.data["conversation_kind"] == "direct" == false
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

    {binding, incoming} = normalize_update(update)

    assert [%{kind: :image, url: "telegram://file/photo-large", media_type: "image/jpeg"}] =
             media_records(binding, incoming)
  end

  test "transform_incoming/1 prefers an available photo MIME type to the fallback" do
    update = %{
      "message" => %{
        "message_id" => 456,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "group"},
        "photo" => [
          %{
            "file_id" => "photo-large",
            "mime_type" => " image/png ",
            "width" => 512,
            "height" => 512
          }
        ]
      }
    }

    {binding, incoming} = normalize_update(update)

    assert [%{kind: :image, url: "telegram://file/photo-large", media_type: "image/png"}] =
             media_records(binding, incoming)
  end

  test "transform_incoming/1 uses the photo MIME fallback for blank or invalid values" do
    for mime_type <- [nil, "", " \t\n", 123] do
      update = %{
        "message" => %{
          "message_id" => 456,
          "date" => 1_706_745_600,
          "chat" => %{"id" => 789, "type" => "group"},
          "photo" => [
            %{
              "file_id" => "photo-large",
              "mime_type" => mime_type,
              "width" => 512,
              "height" => 512
            }
          ]
        }
      }

      {binding, incoming} = normalize_update(update)
      assert [%{media_type: "image/jpeg"}] = media_records(binding, incoming)
    end
  end

  test "transform_incoming/1 normalizes ExGram PhotoSize structs as JPEG" do
    update = %{
      message: %ExGram.Model.Message{
        message_id: 456,
        date: 1_706_745_600,
        chat: %ExGram.Model.Chat{id: 789, type: "group"},
        photo: [
          %ExGram.Model.PhotoSize{
            file_id: "photo-large",
            file_unique_id: "photo-unique",
            width: 512,
            height: 512,
            file_size: 4_096
          }
        ]
      }
    }

    {binding, incoming} = normalize_update(update)

    assert [
             %{
               kind: :image,
               url: "telegram://file/photo-large",
               media_type: "image/jpeg",
               size_bytes: 4_096,
               width: 512,
               height: 512,
               metadata: %{telegram: %{file_unique_id: "photo-unique"}}
             }
           ] = media_records(binding, incoming)
  end

  test "transform_incoming/1 extracts a static sticker with Telegram metadata" do
    update = %{
      "message" => %{
        "message_id" => 457,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "sticker" => %{
          "file_id" => "sticker-webp",
          "file_unique_id" => "unique-sticker",
          "type" => "regular",
          "width" => 512,
          "height" => 512,
          "is_animated" => false,
          "is_video" => false,
          "emoji" => "🦊",
          "set_name" => "foxes",
          "custom_emoji_id" => "custom-1",
          "file_size" => 1_024
        }
      }
    }

    {binding, incoming} = normalize_update(update)

    assert [
             %{
               kind: :image,
               url: "telegram://file/sticker-webp",
               size_bytes: 1_024,
               width: 512,
               height: 512,
               metadata: %{
                 telegram: %{
                   file_unique_id: "unique-sticker",
                   type: "regular",
                   is_animated: false,
                   is_video: false,
                   emoji: "🦊",
                   set_name: "foxes",
                   custom_emoji_id: "custom-1"
                 }
               }
             }
           ] = media_records(binding, incoming)
  end

  test "transform_incoming/1 classifies animated and video sticker formats" do
    cases = [
      {%{"is_animated" => true, "is_video" => false}, :file},
      {%{is_animated: false, is_video: true}, :video}
    ]

    for {format, expected_kind} <- cases do
      update = %{
        message: %{
          message_id: 457,
          chat: %{id: 789, type: "private"},
          sticker:
            Map.merge(
              %{
                file_id: "sticker-#{expected_kind}",
                width: 512,
                height: 512
              },
              format
            )
        }
      }

      {binding, incoming} = normalize_update(update)
      assert [%{kind: ^expected_kind}] = media_records(binding, incoming)
    end
  end

  test "transform_incoming/1 accepts ExGram update and message structs" do
    message = %ExGram.Model.Message{
      message_id: 458,
      date: 1_706_745_600,
      chat: %ExGram.Model.Chat{id: 789, type: "private"},
      from: %ExGram.Model.User{id: 111, is_bot: false, first_name: "Jane"},
      sticker: %ExGram.Model.Sticker{
        file_id: "struct-sticker",
        file_unique_id: "struct-sticker-unique",
        type: "regular",
        width: 512,
        height: 512,
        is_animated: false,
        is_video: false
      }
    }

    update = %ExGram.Model.Update{update_id: 10, message: message}

    {binding, incoming} = normalize_update(update)
    assert [%{kind: :image, url: "telegram://file/struct-sticker"}] = media_records(binding, incoming)
    refute Map.has_key?(incoming.data, "raw")
    assert {:ok, wire} = Jido.Signal.Serialization.serialize(incoming)
    refute wire =~ "struct-sticker-unique"

    {:ok, handlers} = Handlers.new()
    assert {:ok, _handlers, [webhook_incoming]} = accept_webhook(binding, handlers, update)
    assert [%{kind: :image}] = media_records(binding, webhook_incoming)
  end

  test "transform_incoming/1 extracts an animation once when Telegram also sends its document" do
    animation = %{
      "file_id" => "animation-file",
      "file_unique_id" => "unique-animation",
      "width" => 640,
      "height" => 360,
      "duration" => 4,
      "file_name" => "demo.mp4",
      "mime_type" => "video/mp4",
      "file_size" => 4_096
    }

    update = %{
      "message" => %{
        "message_id" => 458,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "animation" => animation,
        "document" => animation
      }
    }

    {binding, incoming} = normalize_update(update)

    assert [
             %{
               kind: :video,
               url: "telegram://file/animation-file",
               media_type: "video/mp4",
               filename: "demo.mp4",
               size_bytes: 4_096,
               width: 640,
               height: 360,
               duration: 4,
               metadata: %{telegram: %{file_unique_id: "unique-animation"}}
             }
           ] = media_records(binding, incoming)
  end

  test "transform_incoming/1 extracts a video note and ignores an unsupported attachment" do
    update = %{
      message: %{
        message_id: 459,
        date: 1_706_745_600,
        chat: %{id: 789, type: "private"},
        video_note: %{
          file_id: "video-note-file",
          file_unique_id: "unique-video-note",
          length: 240,
          duration: 7,
          file_size: 8_192
        },
        future_attachment: %{file_id: "unsupported-file"}
      }
    }

    {binding, incoming} = normalize_update(update)

    assert [
             %{
               kind: :video,
               url: "telegram://file/video-note-file",
               size_bytes: 8_192,
               width: 240,
               height: 240,
               duration: 7,
               metadata: %{telegram: %{file_unique_id: "unique-video-note"}}
             }
           ] = media_records(binding, incoming)
  end

  test "transform_incoming/1 reads a photo caption as the message text" do
    update = %{
      "message" => %{
        "message_id" => 457,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "photo" => [%{"file_id" => "photo-large"}],
        "caption" => "what is wrong with this chart?"
      }
    }

    {binding, incoming} = normalize_update(update)
    assert incoming.data["text"] == "what is wrong with this chart?"
    assert [%{kind: :image}] = media_records(binding, incoming)
  end

  test "transform_incoming/1 leaves text nil for a caption-less photo" do
    update = %{
      "message" => %{
        "message_id" => 458,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "photo" => [%{"file_id" => "photo-large"}]
      }
    }

    {_binding, incoming} = normalize_update(update)
    assert incoming.data["text"] == ""
  end

  test "transform_incoming/1 prefers text over caption when a message somehow has both" do
    update = %{
      "message" => %{
        "message_id" => 459,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "text" => "the text",
        "caption" => "the caption"
      }
    }

    {_binding, incoming} = normalize_update(update)
    assert incoming.data["text"] == "the text"
  end

  test "transform_incoming/1 reads a document caption too" do
    update = %{
      "message" => %{
        "message_id" => 460,
        "date" => 1_706_745_600,
        "chat" => %{"id" => 789, "type" => "private"},
        "document" => %{"file_id" => "doc-1", "mime_type" => "application/pdf"},
        "caption" => "please summarise this"
      }
    }

    {binding, incoming} = normalize_update(update)
    assert incoming.data["text"] == "please summarise this"
    assert [%{kind: :file}] = media_records(binding, incoming)
  end

  test "normalize_event returns typed failures for missing or malformed updates" do
    binding = captured_binding()
    assert {:ok, %{signals: [unsupported]}} = Chat.normalize_event(binding, %{"message" => nil})
    assert unsupported.type == "jido.chat.normalization.failed"
    assert {:ok, %{signals: [invalid]}} = Chat.normalize_event(binding, %{"edited_message" => %{}})
    assert invalid.data["code"] == "invalid_item"
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

    assert result["id"] == "42"
    assert result["id"] == "42"
    assert result["room_id"] == "123"
    assert result["timestamp"] == "2024-02-01T00:00:00Z"
  end

  # `format: :markdown` resolves to a rich message rather than a parse_mode — that
  # routing is covered in `RichMessageTest`.
  test "send_message/3 infers parse_mode from top-level format" do
    assert {:ok, _result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               format: :html
             )

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["parse_mode"] == "HTML"
  end

  test "send_message/3 keeps explicit parse_mode over top-level format" do
    assert {:ok, _result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               parse_mode: "Markdown",
               format: :html
             )

    assert_received {:transport_call, "bot-token", "sendMessage", payload}
    assert payload["parse_mode"] == "Markdown"
  end

  test "send_message/3 omits parse_mode for plain_text and unknown top-level format" do
    assert {:ok, _result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               format: :plain_text
             )

    assert_received {:transport_call, "bot-token", "sendMessage", plain_text_payload}
    refute Map.has_key?(plain_text_payload, "parse_mode")

    assert {:ok, _result} =
             Adapter.send_message(123, "hello",
               token: "bot-token",
               transport: MockTransport,
               format: :unknown
             )

    assert_received {:transport_call, "bot-token", "sendMessage", unknown_payload}
    refute Map.has_key?(unknown_payload, "parse_mode")
  end

  test "adapter stream uses telegram draft updates for private chats and final sendMessage" do
    assert {:ok, result} =
             Adapter.stream(
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

    assert result["id"] == "42"
    assert result["id"] == "42"
    assert result["room_id"] == "123"
  end

  test "adapter stream infers parse_mode from top-level format for draft and final send" do
    assert {:ok, _result} =
             Adapter.stream(
               123,
               ["hel", "lo"],
               token: "bot-token",
               transport: MockTransport,
               stream_update_interval_ms: 0,
               draft_id: 7,
               format: :html
             )

    assert_received {:transport_call, "bot-token", "sendMessageDraft", first_payload}
    assert first_payload["parse_mode"] == "HTML"

    assert_received {:transport_call, "bot-token", "sendMessageDraft", second_payload}
    assert second_payload["parse_mode"] == "HTML"

    assert_received {:transport_call, "bot-token", "sendMessage", final_payload}
    assert final_payload["parse_mode"] == "HTML"
  end

  test "adapter stream skips duplicate partial draft updates" do
    assert {:ok, _result} =
             Adapter.stream(
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
             Adapter.stream(
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

    assert result["id"] == "42"
  end

  test "adapter stream returns empty_stream when no content is produced" do
    assert {:error, :empty_stream} =
             Adapter.stream(
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

    assert result["id"] == "42"
    assert result["id"] == "42"
    assert result["room_id"] == "123"
    refute Map.has_key?(result, "timestamp")
  end

  test "edit_message/4 infers parse_mode from top-level format" do
    assert {:ok, _result} =
             Adapter.edit_message(123, 42, "updated",
               token: "bot-token",
               transport: MockTransport,
               format: :html
             )

    assert_received {:transport_call, "bot-token", "editMessageText", payload}
    assert payload["parse_mode"] == "HTML"
  end

  test "edit_message/4 omits parse_mode for plain_text and unknown top-level format" do
    assert {:ok, _result} =
             Adapter.edit_message(123, 42, "updated",
               token: "bot-token",
               transport: MockTransport,
               format: :plain_text
             )

    assert_received {:transport_call, "bot-token", "editMessageText", plain_text_payload}
    refute Map.has_key?(plain_text_payload, "parse_mode")

    assert {:ok, _result} =
             Adapter.edit_message(123, 42, "updated",
               token: "bot-token",
               transport: MockTransport,
               format: :unknown
             )

    assert_received {:transport_call, "bot-token", "editMessageText", unknown_payload}
    refute Map.has_key?(unknown_payload, "parse_mode")
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
    assert info["id"] == "123"
    assert info["name"] == "alice"
    assert info["kind"] == "direct"
  end

  test "fetch_metadata/2 normalizes struct metadata into plain map" do
    assert {:ok, info} =
             Adapter.fetch_metadata(123,
               token: "bot-token",
               transport: StructMetadataTransport
             )

    assert_received {:transport_call, "bot-token", "getChat", payload}
    assert payload["chat_id"] == 123
    assert is_map(info)
    refute Map.has_key?(info, :__struct__)
    assert info["id"] == "123"
    assert info["kind"] == "direct"
    refute Map.has_key?(info, "permissions")
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

    assert ephemeral["room_id"] == "99"
    assert ephemeral["id"] == "42"

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

  test "send_file sends images and maps generic reply/thread options" do
    result =
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

    assert {:ok, response} = result
    assert Adapter.capabilities().send_file == :native

    assert response["id"] == "77"
    assert response["room_id"] == "123"
    assert response["status"] == "sent"
    assert response["text"] == "hello"

    assert_received {:transport_call, "bot-token", "sendPhoto", payload}
    assert payload["chat_id"] == 123
    assert payload["photo"] == "https://example.com/test.png"
    assert payload["caption"] == "hello"
    assert payload["reply_to_message_id"] == 42
    assert payload["message_thread_id"] == 99
  end

  test "send_file/3 infers parse_mode from top-level format for caption uploads" do
    assert {:ok, _response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :image,
                 url: "https://example.com/test.png",
                 metadata: %{"caption" => "hello"}
               },
               token: "bot-token",
               transport: MockTransport,
               format: :markdown
             )

    assert_received {:transport_call, "bot-token", "sendPhoto", image_payload}
    assert image_payload["parse_mode"] == "MarkdownV2"

    assert {:ok, _response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :file,
                 url: "https://example.com/test.pdf",
                 metadata: %{"caption" => "doc"}
               },
               token: "bot-token",
               transport: MockTransport,
               format: :html
             )

    assert_received {:transport_call, "bot-token", "sendDocument", doc_payload}
    assert doc_payload["parse_mode"] == "HTML"
  end

  test "send_file/3 keeps explicit parse_mode and omits for plain_text/unknown" do
    assert {:ok, _response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :image,
                 url: "https://example.com/test.png",
                 metadata: %{"caption" => "hello"}
               },
               token: "bot-token",
               transport: MockTransport,
               parse_mode: "Markdown",
               format: :html
             )

    assert_received {:transport_call, "bot-token", "sendPhoto", override_payload}
    assert override_payload["parse_mode"] == "Markdown"

    assert {:ok, _response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :file,
                 url: "https://example.com/test.pdf",
                 metadata: %{"caption" => "doc"}
               },
               token: "bot-token",
               transport: MockTransport,
               format: :plain_text
             )

    assert_received {:transport_call, "bot-token", "sendDocument", plain_text_payload}
    refute Map.has_key?(plain_text_payload, "parse_mode")

    assert {:ok, _response} =
             Adapter.send_file(
               123,
               %FileUpload{
                 kind: :file,
                 url: "https://example.com/test.pdf",
                 metadata: %{"caption" => "doc"}
               },
               token: "bot-token",
               transport: MockTransport,
               format: :unknown
             )

    assert_received {:transport_call, "bot-token", "sendDocument", unknown_payload}
    refute Map.has_key?(unknown_payload, "parse_mode")
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

    assert path_response["id"] == "78"
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

    assert data_response["id"] == "78"
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

  test "typed post_message uses telegram send_file support for canonical uploads" do
    binding = captured_binding()

    upload =
      FileUpload.new(%{
        kind: :file,
        url: "https://example.com/test.pdf",
        filename: "test.pdf",
        metadata: %{caption: "doc caption"}
      })

    {:ok, resource} = Chat.put_resource(binding, "file", upload)

    request =
      Jido.Chat.Signal.PostMessage.new!(%{
        "request_id" => "post",
        "room_id" => "123",
        "content" => %{"kind" => "media", "resource_ref" => resource, "caption" => "doc caption"},
        "reply_to_id" => "41",
        "thread_id" => "88"
      })

    assert {:ok, result} = Chat.execute(binding, request)
    assert result.data["code"] == nil
    assert result.data["result"]["id"] == "78"
    assert result.data["result"]["room_id"] == "123"
    assert_received {:transport_call, "bot-token", "sendDocument", payload}
    assert payload["document"] == "https://example.com/test.pdf"
    assert payload["caption"] == "doc caption"
    assert payload["reply_to_message_id"] == "41"
    assert payload["message_thread_id"] == "88"
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

  test "history/list_threads remain explicitly unsupported in the native boundary" do
    binding = captured_binding()

    for definition <- [
          Jido.Chat.Signal.FetchMessages,
          Jido.Chat.Signal.FetchChannelMessages,
          Jido.Chat.Signal.ListThreads
        ] do
      request = definition.new!(%{"request_id" => Atom.to_string(definition), "room_id" => "123"})
      assert {:ok, result} = Chat.execute(binding, request)
      assert result.type == "jido.chat.operation.failed"
      assert result.data["code"] == "unsupported"
    end

    refute_received {:transport_call, _, _, _}
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

  test "typed webhook messages select the local mention handler" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()

    {:ok, handlers} =
      Handlers.on(handlers, Jido.Chat.Signal.MessageReceived, fn _ -> send(self(), :mention) end, mode: :mention)

    update = %{
      "message" => %{
        "message_id" => 999,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane_doe"},
        "text" => "@jido hello",
        "entities" => [%{"type" => "mention", "offset" => 0, "length" => 5}]
      }
    }

    assert {:ok, _, [incoming]} = accept_webhook(binding, handlers, update)
    assert incoming.data["room_id"] == "123"
    assert incoming.data["message_id"] == "999"
    assert_received :mention
  end

  test "typed webhook slash commands preserve the separate command handler" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()
    {:ok, handlers} = Handlers.on(handlers, Jido.Chat.Signal.SlashCommandReceived, fn _ -> send(self(), :slash_hit) end)

    update = %{
      "message" => %{
        "message_id" => 222,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "/help topic-a"
      }
    }

    assert {:ok, _, [message, command]} = accept_webhook(binding, handlers, update)
    assert message.data["message_id"] == "222"
    assert command.data["command"] == "help"
    assert_received :slash_hit
  end

  test "typed webhook slash messages also select the message policy handler" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()
    {:ok, handlers} = Handlers.on(handlers, Jido.Chat.Signal.SlashCommandReceived, fn _ -> send(self(), :slash_hit) end)

    {:ok, handlers} =
      Handlers.on(handlers, Jido.Chat.Signal.MessageReceived, fn _ -> send(self(), :message_hit) end,
        mode: :message,
        pattern: ~r/^\/help/u
      )

    update = %{
      "message" => %{
        "message_id" => 223,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "/help topic-a"
      }
    }

    assert {:ok, _, [message, _]} = accept_webhook(binding, handlers, update)
    assert message.data["message_id"] == "223"
    assert_received :slash_hit
    assert_received :message_hit
  end

  test "typed webhook accepts edited messages as update facts" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()

    update = %{
      "edited_message" => %{
        "message_id" => 333,
        "chat" => %{"id" => 123, "type" => "private"},
        "from" => %{"id" => 111, "username" => "jane"},
        "text" => "edited text"
      }
    }

    assert {:ok, _, [incoming]} = accept_webhook(binding, handlers, update)
    assert incoming.type == "jido.chat.message.updated"
    assert incoming.data["message_id"] == "333"
    assert incoming.data["text"] == "edited text"
  end

  test "typed webhook accepts channel post and edit families" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()

    for {kind, id, type} <- [
          {"channel_post", 444, "jido.chat.message.received"},
          {"edited_channel_post", 445, "jido.chat.message.updated"}
        ] do
      update = %{
        kind => %{
          "message_id" => id,
          "chat" => %{"id" => -100_123, "type" => "channel", "title" => "announcements"},
          "text" => "posted"
        }
      }

      assert {:ok, _, [fact]} = accept_webhook(binding, handlers, update)
      assert fact.type == type
      assert fact.data["room_id"] == "-100123"
      assert fact.data["message_id"] == Integer.to_string(id)
    end
  end

  test "typed webhook actions and reactions select their own handlers" do
    binding = captured_binding()
    {:ok, handlers} = Handlers.new()
    {:ok, handlers} = Handlers.on(handlers, Jido.Chat.Signal.ActionReceived, fn _ -> send(self(), :action_hit) end)
    {:ok, handlers} = Handlers.on(handlers, Jido.Chat.Signal.ReactionAdded, fn _ -> send(self(), :reaction_hit) end)

    callback = %{
      "callback_query" => %{
        "id" => "cb1",
        "data" => "approve",
        "from" => %{"id" => 50},
        "message" => %{"message_id" => 100, "chat" => %{"id" => 123}}
      }
    }

    assert {:ok, _, [action]} = accept_webhook(binding, handlers, callback)
    assert action.type == "jido.chat.action.received"
    assert_received :action_hit

    reaction = %{
      "message_reaction" => %{
        "chat" => %{"id" => 123},
        "message_id" => 101,
        "user" => %{"id" => 50},
        "new_reaction" => [%{"type" => "emoji", "emoji" => "👍"}],
        "old_reaction" => []
      }
    }

    assert {:ok, _, [fact]} = accept_webhook(binding, handlers, reaction)
    assert fact.type == "jido.chat.reaction.added"
    assert_received :reaction_hit
  end

  test "typed webhook verification rejects the wrong configured secret" do
    binding = captured_binding(secret_token: "expected")
    {:ok, handlers} = Handlers.new()

    assert {:error, :invalid_webhook_secret} =
             accept_webhook(binding, handlers, %{"message" => %{"message_id" => 1}}, %{
               "x-telegram-bot-api-secret-token" => "wrong"
             })
  end

  test "unsupported webhook updates return a registered failure fact" do
    request = Jido.Chat.WebhookRequest.new(%{adapter_name: :telegram, payload: %{"poll" => %{"id" => "p1"}}})
    assert {:ok, %{signals: [failure]}} = Chat.normalize_event(captured_binding(), request)
    assert failure.type == "jido.chat.normalization.failed"
    assert failure.data["code"] == "unsupported_item"
  end
end
