defmodule Jido.Chat.Telegram.OperationMatrixTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.AdapterTestKit.Factories
  alias Jido.Chat.Telegram.Adapter

  @operations ~w(send_message send_file post_message edit_message delete_message start_typing fetch_metadata fetch_thread fetch_message get_user fetch_subject get_thread_participants mark_as_read fetch_media add_reaction remove_reaction post_ephemeral post_channel_message stream open_modal load_options fetch_messages fetch_channel_messages list_threads open_thread open_dm)a
  @methods %{
    send_message: ["sendMessage"],
    send_file: ["sendDocument"],
    post_message: ["sendMessage"],
    edit_message: ["editMessageText"],
    delete_message: ["deleteMessage"],
    start_typing: ["sendChatAction"],
    fetch_metadata: ["getChat"],
    fetch_media: ["getFile", "download"],
    add_reaction: ["setMessageReaction"],
    remove_reaction: ["setMessageReaction"],
    post_ephemeral: ["sendMessage"],
    post_channel_message: ["sendMessage"],
    stream: ["sendMessageDraft", "sendMessageDraft", "sendMessage"],
    open_thread: ["createForumTopic"]
  }

  defmodule Transport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(_token, method, payload, _opts) do
      send(self(), {:provider, method})
      if Process.get(:matrix_failure), do: {:error, :timeout}, else: response(method, payload)
    end

    defp response("getChat", payload), do: {:ok, %{"id" => payload["chat_id"], "title" => "Room", "type" => "private"}}
    defp response("createForumTopic", _), do: {:ok, %{"message_thread_id" => 8}}
    defp response("getFile", _), do: {:ok, %{"file_id" => "file", "file_path" => "file.txt"}}

    defp response("sendDocument", payload),
      do: {:ok, %{"message_id" => 7, "chat" => %{"id" => payload["chat_id"]}, "document" => %{"file_id" => "file"}}}

    defp response(_method, payload), do: {:ok, %{"message_id" => 7, "chat" => %{"id" => payload["chat_id"]}}}
  end

  defmodule Http do
    def get(_url, _opts) do
      send(self(), {:provider, "download"})
      {:ok, %{status: 200, body: "private-bytes"}}
    end
  end

  setup do
    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "matrix",
        token: "fixture-token",
        transport: Transport,
        http_client: Http,
        fallback_to_dm: true,
        stream_update_interval_ms: 0
      )

    %{binding: binding}
  end

  defp request(binding, operation) do
    overrides = %{"request_id" => "matrix:" <> Atom.to_string(operation)}

    fields =
      Jido.Chat.Operations.Definitions.all()
      |> Enum.find(fn {_, {_, op, _, _, _}} -> op == operation end)
      |> elem(1)
      |> elem(2)

    overrides = if "room_id" in fields, do: Map.put(overrides, "room_id", "123"), else: overrides

    overrides =
      if operation == :fetch_media do
        {:ok, ref} = Jido.Chat.put_resource(binding, "media", %{url: "telegram://file/file"})
        Map.put(overrides, "media_ref", ref)
      else
        overrides
      end

    Factories.operation_request(binding, operation, overrides)
  end

  test "the finite operation inventory is complete" do
    actual = Enum.map(Jido.Chat.Operations.Definitions.all(), fn {_, {_, operation, _, _, _}} -> operation end)
    assert MapSet.new(actual) == MapSet.new(@operations)
    assert length(actual) == 26
  end

  for operation <- @operations do
    methods = Map.get(@methods, operation, [])

    test "#{operation} matches its declared native/fallback/unsupported result and exact calls", %{binding: binding} do
      operation = unquote(operation)
      status = Jido.Chat.Adapter.capabilities(Adapter)[operation]
      parent = request(binding, operation)
      assert {:ok, result} = Jido.Chat.execute(binding, parent)

      if status == :unsupported do
        assert result.type == "jido.chat.operation.failed"
        assert result.data["code"] == "unsupported"
      else
        assert result.type == "jido.chat.operation.completed"
      end

      for method <- unquote(methods), do: assert_receive({:provider, ^method})
      refute_received {:provider, _}
      assert {:ok, ^result} = Jido.Chat.execute(binding, parent)
      refute_received {:provider, _}
      assert Jido.Signal.Context.get(result, "causationid") == parent.id
      assert Jido.Signal.Trace.get(result).trace_id == Jido.Signal.Trace.get(parent).trace_id
      catalog = Jido.Signal.Catalog.new!(Jido.Chat.signal_definitions())
      assert {:ok, json} = Jido.Signal.Serialization.serialize(result)
      assert {:ok, ^result} = Jido.Signal.Catalog.decode(catalog, json)
      refute json =~ "fixture-token"
      refute json =~ "private-bytes"
    end
  end

  test "provider failure is typed and cached without repeat calls", %{binding: binding} do
    Process.put(:matrix_failure, true)
    parent = request(binding, :send_message)
    assert {:ok, result} = Jido.Chat.execute(binding, parent)
    assert result.data["code"] == "provider_failure"
    assert result.data["retryable"]
    assert_receive {:provider, "sendMessage"}
    assert {:ok, ^result} = Jido.Chat.execute(binding, parent)
    refute_received {:provider, _}
  end
end
