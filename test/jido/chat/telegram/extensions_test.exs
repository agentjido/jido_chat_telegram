defmodule Jido.Chat.Telegram.ExtensionsTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Telegram.{
    CallbackQuery,
    Extensions,
    FileInfo,
    InlineKeyboard,
    MediaMessage,
    UpdateEnvelope
  }

  defmodule MockTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, "sendPhoto", payload, _opts) do
      {:ok,
       %{
         "message_id" => 200,
         "chat" => %{"id" => payload["chat_id"]},
         "caption" => payload["caption"],
         "photo" => [%{"file_id" => "photo-file-id"}]
       }}
    end

    @impl true
    def call(_token, "sendDocument", payload, _opts) do
      {:ok,
       %{
         "message_id" => 201,
         "chat" => %{"id" => payload["chat_id"]},
         "caption" => payload["caption"],
         "document" => %{"file_id" => "doc-file-id"}
       }}
    end

    @impl true
    def call(_token, "answerCallbackQuery", payload, _opts) do
      {:ok, %{"ok" => true, "callback_query_id" => payload["callback_query_id"]}}
    end

    @impl true
    def call(token, "getFile", payload, opts) do
      send(self(), {:get_file, token, payload, opts})

      case payload["file_id"] do
        "invalid-metadata" ->
          {:ok, true}

        "invalid-fields" ->
          {:ok, %{"file_id" => "invalid-fields", "file_size" => %{unexpected: true}}}

        "missing-path" ->
          {:ok, %{"file_id" => "missing-path", "file_unique_id" => "unique-missing"}}

        file_id ->
          {:ok,
           %{
             "file_id" => file_id,
             "file_unique_id" => "unique-1",
             "file_size" => 12,
             "file_path" => "documents/#{file_id}.txt"
           }}
      end
    end
  end

  defmodule MockHttpClient do
    def get(url, opts) do
      send(self(), {:download, url, opts})

      cond do
        String.contains?(url, "http-error") -> {:ok, %{status: 404, body: "not found"}}
        String.contains?(url, "decoded-body") -> {:ok, %{status: 200, body: %{decoded: true}}}
        String.contains?(url, "invalid-response") -> {:ok, :unexpected}
        true -> {:ok, %{status: 200, body: "file contents"}}
      end
    end
  end

  test "capabilities/0 exposes extension-specific surface" do
    caps = Extensions.capabilities()
    assert caps.send_photo == :native
    assert caps.get_file == :native
    assert caps.download_file == :native
    assert caps.answer_callback_query == :native
    assert caps.send_media_group == :unsupported
  end

  test "get_file/2 resolves normalized Telegram media references" do
    assert {:ok,
            %FileInfo{
              file_id: "telegram-file-id",
              file_unique_id: "unique-1",
              file_size: 12,
              file_path: "documents/telegram-file-id.txt"
            }} =
             Extensions.get_file(%{url: "telegram://file/telegram-file-id"},
               token: "bot-token",
               transport: MockTransport,
               url: "http://localhost:8081"
             )

    assert_received {:get_file, "bot-token", %{"file_id" => "telegram-file-id"}, opts}
    assert Keyword.get(opts, :url) == "http://localhost:8081"
  end

  test "download_file/2 downloads bytes without returning the token-bearing URL" do
    assert {:ok, "file contents"} =
             Extensions.download_file("telegram://file/telegram-file-id",
               token: "bot-token",
               transport: MockTransport,
               adapter_opts: [url: "http://localhost:8081"],
               http_client: MockHttpClient,
               request_opts: [receive_timeout: 1_000]
             )

    assert_received {:download, "http://localhost:8081/file/botbot-token/documents/telegram-file-id.txt", request_opts}

    assert Keyword.get(request_opts, :receive_timeout) == 1_000
    assert Keyword.get(request_opts, :decode_body) == false
  end

  test "get_file/2 rejects empty and unsupported references" do
    assert {:error, :invalid_file_reference} =
             Extensions.get_file(%{}, token: "bot-token", transport: MockTransport)

    assert {:error, :invalid_file_reference} =
             Extensions.get_file("telegram://file/",
               token: "bot-token",
               transport: MockTransport
             )

    assert {:error, :invalid_file_reference} =
             Extensions.get_file(" \t\n", token: "bot-token", transport: MockTransport)
  end

  test "file helpers return stable errors for invalid successful responses" do
    opts = [token: "bot-token", transport: MockTransport, http_client: MockHttpClient]

    assert {:error, :invalid_file_response} = Extensions.get_file("invalid-metadata", opts)
    assert {:error, :invalid_file_response} = Extensions.get_file("invalid-fields", opts)
    assert {:error, :invalid_file_response} = Extensions.download_file("invalid-metadata", opts)
    assert {:error, :file_path_missing} = Extensions.download_file("missing-path", opts)
    assert {:error, {:file_download_failed, 404}} = Extensions.download_file("http-error", opts)
    assert {:error, :invalid_download_body} = Extensions.download_file("decoded-body", opts)
    assert {:error, :invalid_download_response} = Extensions.download_file("invalid-response", opts)
  end

  test "parse_update/1 normalizes callback_query into typed envelope" do
    update = %{
      "update_id" => 10,
      "callback_query" => %{
        "id" => "cb-1",
        "data" => "approve",
        "from" => %{"id" => 50, "username" => "bob"},
        "message" => %{
          "message_id" => 100,
          "chat" => %{"id" => 123, "type" => "private"}
        }
      }
    }

    assert {:ok, %UpdateEnvelope{} = envelope} = Extensions.parse_update(update)
    assert envelope.update_type == :callback_query

    assert %CallbackQuery{id: "cb-1", data: "approve", chat_id: 123, message_id: 100} =
             envelope.payload
  end

  test "parse_update/1 returns noop envelope for unsupported updates" do
    assert {:ok, %UpdateEnvelope{update_type: :noop}} =
             Extensions.parse_update(%{"update_id" => 11, "poll" => %{}})
  end

  test "send_photo/send_document return typed media messages" do
    assert {:ok, %MediaMessage{} = photo} =
             Extensions.send_photo(123, "photo-id",
               token: "bot-token",
               transport: MockTransport,
               caption: "hello"
             )

    assert photo.kind == :photo
    assert photo.chat_id == 123
    assert photo.file_id == "photo-file-id"

    assert {:ok, %MediaMessage{} = doc} =
             Extensions.send_document(123, "doc-id",
               token: "bot-token",
               transport: MockTransport,
               caption: "readme"
             )

    assert doc.kind == :document
    assert doc.file_id == "doc-file-id"
  end

  test "answer_callback_query/2 returns typed callback answer result" do
    assert {:ok, result} =
             Extensions.answer_callback_query("cb-2",
               token: "bot-token",
               transport: MockTransport,
               text: "done"
             )

    assert result.answered == true
    assert result.callback_query_id == "cb-2"
  end

  test "InlineKeyboard.to_reply_markup/1 builds telegram wire shape" do
    keyboard =
      InlineKeyboard.new(%{
        rows: [
          [
            %{text: "Approve", callback_data: "approve"},
            %{text: "Docs", url: "https://example.com"}
          ]
        ]
      })

    assert %{
             "inline_keyboard" => [
               [
                 %{"text" => "Approve", "callback_data" => "approve"},
                 %{"text" => "Docs", "url" => "https://example.com"}
               ]
             ]
           } = InlineKeyboard.to_reply_markup(keyboard)
  end
end
