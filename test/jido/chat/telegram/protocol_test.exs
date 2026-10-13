defmodule Jido.Chat.Telegram.ProtocolTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Telegram.Adapter

  defmodule Transport do
    use Agent
    @behaviour Jido.Chat.Telegram.Transport
    def start_link(_opts), do: Agent.start_link(fn -> [] end, name: __MODULE__)
    @impl true
    def call(token, method, payload, opts) do
      Agent.update(__MODULE__, &(&1 ++ [{token, method, payload, opts}]))

      result =
        case method do
          "getChat" -> %{"id" => -123, "title" => "Group", "type" => "supergroup", "private" => self()}
          "createForumTopic" -> %{"message_thread_id" => 8}
          "sendPhoto" -> %{"message_id" => 9, "chat" => %{"id" => -123}, "photo" => [%{"file_id" => "photo"}]}
          "sendDocument" -> %{"message_id" => 9, "chat" => %{"id" => -123}, "document" => %{"file_id" => "document"}}
          _ -> %{"message_id" => 7, "chat" => %{"id" => -123}, "raw_token" => token}
        end

      {:ok, result}
    end

    def calls, do: Agent.get(__MODULE__, & &1)
  end

  setup do
    start_supervised!(Transport)
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "protocol", token: "captured-token", transport: Transport)
    %{binding: binding}
  end

  test "binding capture keeps transport and credentials after environment changes" do
    prior = Application.get_env(:jido_chat_telegram, :telegram_bot_token)

    on_exit(fn ->
      if prior,
        do: Application.put_env(:jido_chat_telegram, :telegram_bot_token, prior),
        else: Application.delete_env(:jido_chat_telegram, :telegram_bot_token)
    end)

    Application.put_env(:jido_chat_telegram, :telegram_bot_token, "first-token")
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "captured", transport: Transport)
    Application.put_env(:jido_chat_telegram, :telegram_bot_token, "second-token")
    request = Jido.Chat.Signal.SendMessage.new!(%{"request_id" => "one", "room_id" => "-123", "text" => "hello"})
    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.type == "jido.chat.operation.completed"
    assert [{"first-token", "sendMessage", _, _}] = Transport.calls()
    refute Jason.encode!(Jido.Signal.to_map(result)) =~ "token"
    assert {:ok, ^result} = Jido.Chat.execute(binding, request)
    assert length(Transport.calls()) == 1
  end

  for {operation, definition, data, method} <- [
        {"send", Jido.Chat.Signal.SendMessage,
         %{"room_id" => "-123", "text" => "hello", "thread_id" => "8", "reply_to_id" => "6"}, "sendMessage"},
        {"edit", Jido.Chat.Signal.EditMessage, %{"room_id" => "-123", "message_id" => "7", "text" => "edited"},
         "editMessageText"},
        {"metadata", Jido.Chat.Signal.FetchMetadata, %{"room_id" => "-123"}, "getChat"},
        {"thread", Jido.Chat.Signal.OpenThread, %{"room_id" => "-123", "message_id" => "7", "topic_name" => "Topic"},
         "createForumTopic"},
        {"delete", Jido.Chat.Signal.DeleteMessage, %{"room_id" => "-123", "message_id" => "7"}, "deleteMessage"},
        {"typing", Jido.Chat.Signal.StartTyping, %{"room_id" => "-123"}, "sendChatAction"},
        {"reaction", Jido.Chat.Signal.AddReaction, %{"room_id" => "-123", "message_id" => "7", "reaction" => "👍"},
         "setMessageReaction"}
      ] do
    test "#{operation} returns a bounded native result and invokes one selected callback", %{binding: binding} do
      request = unquote(definition).new!(Map.put(unquote(Macro.escape(data)), "request_id", unquote(operation)))
      assert {:ok, result} = Jido.Chat.execute(binding, request)
      assert result.type == "jido.chat.operation.completed"
      assert [{"captured-token", unquote(method), _, _}] = Transport.calls()
      assert {:ok, ^result} = Jido.Chat.execute(binding, request)
      assert length(Transport.calls()) == 1
      assert Jido.Signal.Context.get(result, "causationid") == request.id
      catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())
      assert {:ok, json} = Jido.Signal.Serialization.serialize(result)
      assert {:ok, ^result} = Jido.Signal.Catalog.decode(catalog, json)
    end
  end

  test "send file uses a private resource and returns the portable message ID", %{binding: binding} do
    {:ok, ref} =
      Jido.Chat.put_resource(
        binding,
        "file",
        Jido.Chat.FileUpload.new(%{data: "private-bytes", filename: "report.txt"})
      )

    request = Jido.Chat.Signal.SendFile.new!(%{"request_id" => "file", "room_id" => "-123", "resource_ref" => ref})
    assert {:ok, result} = Jido.Chat.execute(binding, request)
    assert result.data["result"]["id"] == "9"
    assert [{_, "sendDocument", _, _}] = Transport.calls()
    refute Jason.encode!(Jido.Signal.to_map(result)) =~ "private-bytes"
  end
end
