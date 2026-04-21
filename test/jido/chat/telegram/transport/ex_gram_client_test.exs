defmodule Jido.Chat.Telegram.Transport.ExGramClientTest do
  use ExUnit.Case, async: true

  alias ExGram.Model.ReactionTypeEmoji
  alias Jido.Chat.Telegram.ExGramAdapter
  alias Jido.Chat.Telegram.Transport.ExGramClient

  defmodule MockExGram do
    def send_message(chat_id, text, opts) do
      send(self(), {:send_message, chat_id, text, opts})
      {:ok, %{message_id: 99, chat: %{id: chat_id}, date: 1_706_745_600}}
    end

    def edit_message_text(text, opts) do
      send(self(), {:edit_message_text, text, opts})
      {:ok, true}
    end

    def delete_message(chat_id, message_id, opts) do
      send(self(), {:delete_message, chat_id, message_id, opts})
      {:ok, true}
    end

    def send_chat_action(chat_id, action, opts) do
      send(self(), {:send_chat_action, chat_id, action, opts})
      {:ok, true}
    end

    def get_chat(chat_id, opts) do
      send(self(), {:get_chat, chat_id, opts})
      {:ok, %{id: chat_id, type: "private", first_name: "Alice"}}
    end

    def set_message_reaction(chat_id, message_id, opts) do
      send(self(), {:set_message_reaction, chat_id, message_id, opts})
      {:ok, true}
    end

    def send_photo(chat_id, photo, opts) do
      send(self(), {:send_photo, chat_id, photo, opts})
      {:ok, %{message_id: 100, chat: %{id: chat_id}, photo: [%{file_id: "photo-file"}]}}
    end

    def send_document(chat_id, document, opts) do
      send(self(), {:send_document, chat_id, document, opts})
      {:ok, %{message_id: 101, chat: %{id: chat_id}, document: %{file_id: "doc-file"}}}
    end

    def answer_callback_query(callback_query_id, opts) do
      send(self(), {:answer_callback_query, callback_query_id, opts})
      {:ok, true}
    end

    def get_updates(opts) do
      send(self(), {:get_updates, opts})
      {:ok, [%{"update_id" => 11, "message" => %{"message_id" => 1}}]}
    end
  end

  defmodule MockHttpAdapter do
    @behaviour ExGram.Adapter

    @impl true
    def request(verb, path, body, _opts) do
      send(self(), {:http_request, verb, path, body})
      {:ok, true}
    end
  end

  test "call/4 dispatches sendMessage via ExGram" do
    assert {:ok, %{message_id: 99}} =
             ExGramClient.call(
               "abc",
               "sendMessage",
               %{"chat_id" => 1, "text" => "hi", "parse_mode" => "HTML"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_message, 1, "hi", opts}
    assert Keyword.get(opts, :parse_mode) == "HTML"
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches editMessageText via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "editMessageText",
               %{"chat_id" => 1, "message_id" => 7, "text" => "updated"},
               ex_gram_module: MockExGram
             )

    assert_received {:edit_message_text, "updated", opts}
    assert Keyword.get(opts, :chat_id) == 1
    assert Keyword.get(opts, :message_id) == 7
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches deleteMessage via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "deleteMessage",
               %{"chat_id" => 1, "message_id" => 7},
               ex_gram_module: MockExGram
             )

    assert_received {:delete_message, 1, 7, opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches sendChatAction via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendChatAction",
               %{"chat_id" => 1, "action" => "typing", "message_thread_id" => 9},
               ex_gram_module: MockExGram
             )

    assert_received {:send_chat_action, 1, "typing", opts}
    assert Keyword.get(opts, :message_thread_id) == 9
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches getChat via ExGram" do
    assert {:ok, %{id: 1}} =
             ExGramClient.call(
               "abc",
               "getChat",
               %{"chat_id" => 1},
               ex_gram_module: MockExGram
             )

    assert_received {:get_chat, 1, opts}
    assert Keyword.get(opts, :token) == "abc"
    assert Keyword.get(opts, :adapter) == ExGramAdapter
  end

  test "call/4 dispatches getUpdates via ExGram" do
    assert {:ok, [%{"update_id" => 11}]} =
             ExGramClient.call(
               "abc",
               "getUpdates",
               %{"offset" => 10, "timeout" => 25, "allowed_updates" => ["message"]},
               ex_gram_module: MockExGram
             )

    assert_received {:get_updates, opts}
    assert Keyword.get(opts, :offset) == 10
    assert Keyword.get(opts, :timeout) == 25
    assert Keyword.get(opts, :allowed_updates) == ["message"]
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 returns unsupported for unknown methods" do
    assert {:error, {:unsupported_method, "unknownMethod"}} =
             ExGramClient.call("abc", "unknownMethod", %{}, [])
  end

  test "call/4 dispatches sendMessageDraft via the configured HTTP adapter" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "sendMessageDraft",
               %{
                 "chat_id" => 1,
                 "message_thread_id" => 9,
                 "draft_id" => 77,
                 "text" => "hello",
                 "parse_mode" => "Markdown",
                 "entities" => [%{"type" => "bold", "offset" => 0, "length" => 5}]
               },
               ex_gram_adapter: MockHttpAdapter
             )

    assert_received {:http_request, :post, "/botabc/sendMessageDraft", body}
    assert body.chat_id == 1
    assert body.message_thread_id == 9
    assert body.draft_id == 77
    assert body.text == "hello"
    assert body.parse_mode == "Markdown"
    assert body.entities == [%{"type" => "bold", "offset" => 0, "length" => 5}]
  end

  test "call/4 dispatches setMessageReaction via ExGram when available" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "setMessageReaction",
               %{
                 "chat_id" => 1,
                 "message_id" => 7,
                 "reaction" => [%{"type" => "emoji", "emoji" => "👍"}],
                 "is_big" => true
               },
               ex_gram_module: MockExGram
             )

    assert_received {:set_message_reaction, 1, 7, opts}
    assert Keyword.get(opts, :reaction) == [%ReactionTypeEmoji{type: "emoji", emoji: "👍"}]
    assert Keyword.get(opts, :is_big) == true
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches sendPhoto via ExGram" do
    assert {:ok, %{message_id: 100}} =
             ExGramClient.call(
               "abc",
               "sendPhoto",
               %{"chat_id" => 1, "photo" => "photo-id", "caption" => "hello"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_photo, 1, "photo-id", opts}
    assert Keyword.get(opts, :caption) == "hello"
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches sendDocument via ExGram" do
    assert {:ok, %{message_id: 101}} =
             ExGramClient.call(
               "abc",
               "sendDocument",
               %{"chat_id" => 1, "document" => "doc-id", "caption" => "doc"},
               ex_gram_module: MockExGram
             )

    assert_received {:send_document, 1, "doc-id", opts}
    assert Keyword.get(opts, :caption) == "doc"
    assert Keyword.get(opts, :token) == "abc"
  end

  test "call/4 dispatches answerCallbackQuery via ExGram" do
    assert {:ok, true} =
             ExGramClient.call(
               "abc",
               "answerCallbackQuery",
               %{"callback_query_id" => "cb1", "text" => "done", "show_alert" => true},
               ex_gram_module: MockExGram
             )

    assert_received {:answer_callback_query, "cb1", opts}
    assert Keyword.get(opts, :text) == "done"
    assert Keyword.get(opts, :show_alert) == true
    assert Keyword.get(opts, :token) == "abc"
  end
end
