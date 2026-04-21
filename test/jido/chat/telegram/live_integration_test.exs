defmodule Jido.Chat.Telegram.LiveIntegrationTest do
  use ExUnit.Case, async: false

  alias Jido.Chat
  alias Jido.Chat.Telegram.Adapter
  alias Jido.Chat.Telegram.Extensions
  alias Jido.Chat.FileUpload

  @run_live System.get_env("RUN_LIVE_TELEGRAM_TESTS") in ["1", "true", "TRUE", "yes", "on"]
  @token System.get_env("TELEGRAM_BOT_TOKEN")
  @chat_id System.get_env("TELEGRAM_TEST_CHAT_ID")
  @forum_chat_id System.get_env("TELEGRAM_TEST_FORUM_CHAT_ID")
  @thread_id (case System.get_env("TELEGRAM_TEST_THREAD_ID") do
                nil ->
                  nil

                "" ->
                  nil

                value ->
                  case Integer.parse(value) do
                    {int, ""} -> int
                    _ -> value
                  end
              end)
  @callback_query_id System.get_env("TELEGRAM_TEST_CALLBACK_QUERY_ID")
  @reaction System.get_env("TELEGRAM_TEST_REACTION") || "👍"
  @photo_ref System.get_env("TELEGRAM_TEST_PHOTO_REF")
  @document_ref System.get_env("TELEGRAM_TEST_DOCUMENT_REF")

  @moduletag :live
  @moduletag :telegram_live

  if not @run_live do
    @moduletag skip: "set RUN_LIVE_TELEGRAM_TESTS=true to run live Telegram integration tests"
  end

  if @run_live and (is_nil(@token) or @token == "" or is_nil(@chat_id) or @chat_id == "") do
    @moduletag skip: "set TELEGRAM_BOT_TOKEN and TELEGRAM_TEST_CHAT_ID when RUN_LIVE_TELEGRAM_TESTS=true"
  end

  setup_all do
    {:ok, token: @token, chat_id: @chat_id, opts: adapter_opts(@token)}
  end

  test "send/edit/delete message against live Telegram Bot API", ctx do
    text = "jido live integration #{System.system_time(:millisecond)}"

    assert {:ok, sent} = Adapter.send_message(ctx.chat_id, text, ctx.opts)
    message_id = sent.message_id || sent.external_message_id
    assert message_id

    assert {:ok, edited} =
             Adapter.edit_message(ctx.chat_id, message_id, text <> " (edited)", ctx.opts)

    assert (edited.message_id || edited.external_message_id) == message_id
    assert :ok = Adapter.delete_message(ctx.chat_id, message_id, ctx.opts)
  end

  test "typing and metadata calls succeed against live Telegram API", ctx do
    assert :ok = Adapter.start_typing(ctx.chat_id, ctx.opts)

    assert {:ok, info} = Adapter.fetch_metadata(ctx.chat_id, ctx.opts)
    assert info.id == to_string(ctx.chat_id)
  end

  test "stream sends draft updates and a final message against live Telegram Bot API", ctx do
    parts = [
      "jido",
      " telegram",
      " streaming",
      " draft",
      " updates",
      " should",
      " be",
      " visible"
    ]

    chunk_stream =
      Stream.concat([
        [hd(parts)],
        Stream.map(tl(parts), fn chunk ->
          Process.sleep(650)
          chunk
        end)
      ])

    assert {:ok, sent} =
             Adapter.stream(
               ctx.chat_id,
               chunk_stream,
               Keyword.merge(ctx.opts,
                 draft_id: System.unique_integer([:positive]),
                 stream_update_interval_ms: 500
               )
             )

    message_id = sent.message_id || sent.external_message_id
    assert message_id

    Process.sleep(2_000)
    assert :ok = Adapter.delete_message(ctx.chat_id, message_id, ctx.opts)
  end

  test "reply continuity preserves reply_to metadata and optional topic routing", ctx do
    root_text = "jido telegram reply root #{System.system_time(:millisecond)}"
    reply_text = "jido telegram reply child #{System.system_time(:millisecond)}"

    assert {:ok, root} = Adapter.send_message(ctx.chat_id, root_text, ctx.opts)
    root_id = message_id(root)

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, root_id, ctx.opts)
      end)
    end)

    assert {:ok, reply} =
             Adapter.send_message(
               ctx.chat_id,
               reply_text,
               Keyword.put(ctx.opts, :reply_to_id, root_id)
             )

    reply_id = message_id(reply)

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, reply_id, ctx.opts)
      end)
    end)

    reply_to_message = map_get(reply.raw, [:reply_to_message, "reply_to_message"])

    if is_map(reply_to_message) do
      assert to_string(map_get(reply_to_message, [:message_id, "message_id"])) == root_id
    else
      assert reply_id != root_id

      assert to_string(map_get(reply.raw, [:chat, "chat"]) |> map_get([:id, "id"])) ==
               to_string(ctx.chat_id)
    end

    if @thread_id do
      assert to_string(map_get(reply.raw, [:message_thread_id, "message_thread_id"])) ==
               to_string(@thread_id)
    end
  end

  test "reaction flow is either native or explicitly unsupported", ctx do
    assert {:ok, sent} =
             Adapter.send_message(
               ctx.chat_id,
               "jido telegram reaction target #{System.system_time(:millisecond)}",
               ctx.opts
             )

    message_id = message_id(sent)

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, message_id, ctx.opts)
      end)
    end)

    case Adapter.add_reaction(ctx.chat_id, message_id, @reaction, ctx.opts) do
      :ok ->
        assert :ok = Adapter.remove_reaction(ctx.chat_id, message_id, @reaction, ctx.opts)

      {:error, :unsupported} ->
        assert {:error, :unsupported} =
                 Adapter.remove_reaction(ctx.chat_id, message_id, @reaction, ctx.opts)
    end
  end

  test "webhook handling pipeline processes Telegram-shaped payload", ctx do
    chat =
      Chat.new(user_name: "jido", adapters: %{telegram: Adapter})
      |> Chat.on_slash_command(fn _event -> send(self(), :slash_seen) end)

    payload = %{
      "message" => %{
        "message_id" => 9_999_001,
        "chat" => %{"id" => ctx.chat_id, "type" => "private"},
        "from" => %{"id" => 9_999_002, "username" => "live_user"},
        "text" => "/help integration"
      }
    }

    assert {:ok, _chat, _incoming} = Adapter.handle_webhook(chat, payload, ctx.opts)
    assert_received :slash_seen
  end

  test "extension media sends succeed against live Telegram Bot API", ctx do
    photo_ref = @photo_ref || "https://httpbin.org/image/png"

    document_ref =
      @document_ref || "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"

    assert {:ok, photo} =
             Extensions.send_photo(ctx.chat_id, photo_ref,
               token: ctx.token,
               caption: "jido live photo #{System.system_time(:millisecond)}"
             )

    assert photo.kind == :photo
    assert to_string(photo.chat_id) == to_string(ctx.chat_id)
    photo_id = message_id(photo)

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, photo_id, ctx.opts)
      end)
    end)

    assert {:ok, document} =
             Extensions.send_document(ctx.chat_id, document_ref,
               token: ctx.token,
               caption: "jido live document #{System.system_time(:millisecond)}"
             )

    assert document.kind == :document
    assert to_string(document.chat_id) == to_string(ctx.chat_id)
    document_id = message_id(document)

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, document_id, ctx.opts)
      end)
    end)
  end

  test "canonical media sends succeed through send_file and core post_message", ctx do
    photo_ref = @photo_ref || "https://httpbin.org/image/png"

    document_ref =
      @document_ref || "https://www.w3.org/WAI/ER/tests/xhtml/testfiles/resources/pdf/dummy.pdf"

    photo_upload =
      FileUpload.new(%{
        kind: :image,
        url: photo_ref,
        filename: "live-photo.png",
        metadata: %{caption: "jido canonical photo #{System.system_time(:millisecond)}"}
      })

    assert {:ok, photo} = Adapter.send_file(ctx.chat_id, photo_upload, ctx.opts)
    photo_id = photo.external_message_id || photo.message_id

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, photo_id, ctx.opts)
      end)
    end)

    payload =
      Jido.Chat.PostPayload.new(%{
        text: "jido canonical document #{System.system_time(:millisecond)}",
        files: [
          %{
            kind: :file,
            url: document_ref,
            filename: "live-document.pdf"
          }
        ]
      })

    assert {:ok, document} =
             Jido.Chat.Adapter.post_message(Adapter, ctx.chat_id, payload, ctx.opts)

    document_id = document.external_message_id || document.message_id

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, document_id, ctx.opts)
      end)
    end)

    assert photo_id
    assert document_id
  end

  test "send_file accepts local filesystem paths and raw byte uploads", ctx do
    path =
      write_temp_file(
        "jido-telegram-live-",
        ".txt",
        "telegram live file #{System.system_time(:millisecond)}\n"
      )

    on_exit(fn ->
      File.rm(path)
    end)

    path_upload =
      FileUpload.new(%{
        kind: :file,
        path: path,
        filename: Path.basename(path)
      })

    assert {:ok, path_response} = Adapter.send_file(ctx.chat_id, path_upload, ctx.opts)
    path_message_id = path_response.external_message_id || path_response.message_id

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, path_message_id, ctx.opts)
      end)
    end)

    bytes_upload =
      FileUpload.new(%{
        kind: :file,
        data: "telegram live bytes #{System.system_time(:millisecond)}\n",
        filename: "telegram-live-bytes.txt",
        media_type: "text/plain"
      })

    assert {:ok, bytes_response} = Adapter.send_file(ctx.chat_id, bytes_upload, ctx.opts)
    bytes_message_id = bytes_response.external_message_id || bytes_response.message_id

    on_exit(fn ->
      cleanup_delete(fn ->
        Adapter.delete_message(ctx.chat_id, bytes_message_id, ctx.opts)
      end)
    end)

    assert path_message_id
    assert bytes_message_id
  end

  if @forum_chat_id not in [nil, ""] do
    test "open_thread creates a forum topic when TELEGRAM_TEST_FORUM_CHAT_ID is provided", ctx do
      topic_name = "jido live topic #{System.system_time(:millisecond)}"

      assert {:ok, topic} =
               Adapter.open_thread(@forum_chat_id, nil,
                 token: ctx.token,
                 supports_forum_topics: true,
                 topic_name: topic_name
               )

      assert topic.external_thread_id
      assert to_string(topic.delivery_external_room_id) == to_string(@forum_chat_id)

      assert {:ok, sent} =
               Adapter.send_message(
                 @forum_chat_id,
                 "jido live topic message #{System.system_time(:millisecond)}",
                 token: ctx.token,
                 thread_id: topic.external_thread_id
               )

      message_id = message_id(sent)
      assert message_id

      on_exit(fn ->
        cleanup_delete(fn ->
          Adapter.delete_message(@forum_chat_id, message_id, token: ctx.token)
        end)
      end)
    end
  else
    test "open_thread requires TELEGRAM_TEST_FORUM_CHAT_ID for live forum coverage" do
      assert is_nil(@forum_chat_id) or @forum_chat_id == ""
    end
  end

  test "webhook handling supports channel_post and edited_channel_post shapes", ctx do
    chat = Chat.new(user_name: "jido", adapters: %{telegram: Adapter})

    channel_post = %{
      "channel_post" => %{
        "message_id" => 9_999_011,
        "chat" => %{"id" => ctx.chat_id, "type" => "channel", "title" => "live"},
        "from" => %{"id" => 9_999_012, "username" => "live_user"},
        "text" => "live channel post"
      }
    }

    edited_channel_post = %{
      "edited_channel_post" => %{
        "message_id" => 9_999_013,
        "chat" => %{"id" => ctx.chat_id, "type" => "channel", "title" => "live"},
        "from" => %{"id" => 9_999_014, "username" => "live_user"},
        "text" => "live edited channel post"
      }
    }

    assert {:ok, _chat, incoming_1} = Adapter.handle_webhook(chat, channel_post, ctx.opts)
    assert incoming_1.external_message_id == 9_999_011

    assert {:ok, _chat, incoming_2} = Adapter.handle_webhook(chat, edited_channel_post, ctx.opts)
    assert incoming_2.external_message_id == 9_999_013
  end

  test "unsupported core surfaces remain explicit unsupported contracts", ctx do
    assert {:error, :unsupported} = Adapter.fetch_messages(ctx.chat_id, ctx.opts)
    assert {:error, :unsupported} = Adapter.fetch_channel_messages(ctx.chat_id, ctx.opts)
    assert {:error, :unsupported} = Adapter.list_threads(ctx.chat_id, ctx.opts)

    assert {:error, :unsupported} =
             Adapter.post_ephemeral(ctx.chat_id, "telegram-user", "secret", ctx.opts)

    assert {:error, :unsupported} =
             Jido.Chat.Adapter.open_modal(Adapter, ctx.chat_id, %{title: "modal"}, ctx.opts)
  end

  if @callback_query_id not in [nil, ""] do
    test "manual callback query answer succeeds when TELEGRAM_TEST_CALLBACK_QUERY_ID is provided",
         ctx do
      case Extensions.answer_callback_query(@callback_query_id,
             token: ctx.token,
             text: "ack from live integration test",
             show_alert: false
           ) do
        {:ok, result} ->
          assert result.answered == true
          assert result.callback_query_id == @callback_query_id

        {:error, error} ->
          message = Exception.message(error)

          assert message =~ "query is too old" or
                   message =~ "query ID is invalid"
      end
    end
  else
    test "manual callback query answer requires TELEGRAM_TEST_CALLBACK_QUERY_ID" do
      assert is_nil(@callback_query_id) or @callback_query_id == ""
    end
  end

  defp adapter_opts(token) do
    opts = [token: token]

    case @thread_id do
      nil -> opts
      thread_id -> Keyword.put(opts, :thread_id, thread_id)
    end
  end

  defp message_id(%{message_id: value}) when not is_nil(value), do: to_string(value)
  defp message_id(%{external_message_id: value}) when not is_nil(value), do: to_string(value)

  defp cleanup_delete(fun) when is_function(fun, 0) do
    case fun.() do
      :ok -> :ok
      {:ok, _result} -> :ok
      {:error, :not_found} -> :ok
      {:error, _reason} -> :ok
    end
  end

  defp write_temp_file(prefix, suffix, contents) do
    path =
      Path.join(
        System.tmp_dir!(),
        "#{prefix}#{System.unique_integer([:positive])}#{suffix}"
      )

    File.write!(path, contents)
    path
  end

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp map_get(_map, _keys), do: nil
end
