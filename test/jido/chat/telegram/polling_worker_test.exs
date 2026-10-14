defmodule Jido.Chat.Telegram.PollingWorkerTest do
  use ExUnit.Case, async: false
  alias Jido.Chat.Delivery
  alias Jido.Chat.Telegram.{Adapter, PollingWorker}

  defmodule PollingTransport do
    @behaviour Jido.Chat.Telegram.Transport
    @impl true
    def call(token, "getUpdates", payload, opts) do
      send(Keyword.fetch!(opts, :test_pid), {:get_updates_call, token, payload})

      Agent.get_and_update(Keyword.fetch!(opts, :responses_agent), fn
        [next | rest] -> {next, rest}
        [] -> {{:ok, []}, []}
      end)
    end

    def call(_token, method, _payload, _opts), do: {:error, {:unsupported_method, method}}
  end

  defmodule Sink do
    def emit(test_pid, mode, delivery, opts) do
      send(test_pid, {:sink_emit, delivery, opts})

      case mode do
        :ok -> {:ok, :accepted}
        :error -> {:error, :sink_failed}
        :raise -> raise "private-sink-detail"
        :throw -> throw(:private_sink_detail)
        :exit -> exit(:private_sink_detail)
        :invalid -> :invalid_result
      end
    end
  end

  defp update(id, text \\ "hello") do
    %{
      "update_id" => id,
      "message" => %{"message_id" => id, "text" => text, "chat" => %{"id" => -123}, "from" => %{"id" => 42}}
    }
  end

  defp start_worker(responses, mode \\ :ok, extra \\ []) do
    agent = start_supervised!({Agent, fn -> responses end})
    {:ok, binding} = Jido.Chat.bind(Adapter, id: "polling", token: "captured-token", transport: PollingTransport)

    opts =
      [
        binding: binding,
        bridge_id: binding.id,
        sink_mfa: {Sink, :emit, [self(), mode]},
        transport_opts: [test_pid: self(), responses_agent: agent],
        poll_interval_ms: 60_000,
        timeout_s: 1,
        max_backoff_ms: 120_000
      ] ++ extra

    {start_supervised!({PollingWorker, opts}), binding}
  end

  test "listener specs use the captured binding before polling starts" do
    assert {:ok, []} = Adapter.listener_child_specs("bridge_tg", ingress: %{mode: "webhook"})
    assert {:error, :invalid_binding} = Adapter.listener_child_specs("bridge_tg", ingress: %{mode: "polling"})

    {:ok, binding} =
      Jido.Chat.bind(Adapter,
        id: "bridge_tg",
        token: "fixture-token",
        ingress: %{mode: "polling", transport_opts: %{"url" => "http://localhost:8081"}}
      )

    assert {:error, :invalid_sink_mfa} =
             Adapter.listener_child_specs(binding.id, binding: binding, ingress: %{mode: "polling"})

    assert {:ok, [spec]} =
             Adapter.listener_child_specs(binding.id,
               binding: binding,
               ingress: %{mode: "polling", transport_opts: %{"url" => "http://localhost:8081"}},
               sink_mfa: {Sink, :emit, [self(), :ok]}
             )

    assert spec.id == {:telegram_polling_worker, binding.id}
    assert {PollingWorker, :start_link, [worker_opts]} = spec.start
    assert worker_opts[:binding] == binding
    assert worker_opts[:transport_opts][:url] == "http://localhost:8081"
  end

  test "one complete typed batch advances offset only after sink acceptance" do
    {pid, binding} = start_worker([{:ok, [update(10), update(11)]}, {:ok, []}])
    assert_receive {:get_updates_call, "captured-token", first}
    refute Map.has_key?(first, "offset")
    assert_receive {:sink_emit, %Delivery{} = delivery, []}
    assert {:ok, ^delivery} = Delivery.validate(binding, delivery)
    assert Enum.map(delivery.signals, & &1.data["message_id"]) == ["10", "11"]
    assert :sys.get_state(pid).offset == 12
    send(pid, :poll)
    assert_receive {:get_updates_call, "captured-token", second}
    assert second["offset"] == 12
    assert :sys.get_state(pid).offset == 12
    refute_received {:sink_emit, _, _}
  end

  for mode <- [:error, :raise, :throw, :exit, :invalid] do
    test "sink #{mode} retains the original batch offset and every retry item" do
      mode = unquote(mode)
      batch = [update(5), update(6)]
      {pid, _binding} = start_worker([{:ok, batch}, {:ok, batch}], mode, offset: 3)
      assert_receive {:get_updates_call, _, first}
      assert first["offset"] == 3
      assert_receive {:sink_emit, %Delivery{} = delivery, []}
      assert :sys.get_state(pid).offset == 3
      send(pid, :poll)
      assert_receive {:get_updates_call, _, second}
      assert second["offset"] == 3
      assert_receive {:sink_emit, %Delivery{} = retry, []}
      assert Enum.map(retry.signals, & &1.data["item_id"]) == Enum.map(delivery.signals, & &1.data["item_id"])
      assert :sys.get_state(pid).offset == 3
    end
  end

  test "whole-batch size failure prevents every sink call and offset change" do
    batch = [update(5), update(6, String.duplicate("x", 262_144))]
    {pid, _binding} = start_worker([{:ok, batch}, {:ok, batch}], :ok, offset: 3)
    assert_receive {:get_updates_call, _, first}
    assert first["offset"] == 3
    assert :sys.get_state(pid).offset == 3
    refute_received {:sink_emit, _, _}
    send(pid, :poll)
    assert_receive {:get_updates_call, _, second}
    assert second["offset"] == 3
    assert :sys.get_state(pid).offset == 3
    refute_received {:sink_emit, _, _}
  end

  test "membership polling emits typed evidence without a message item" do
    membership = %{
      "update_id" => 5,
      "my_chat_member" => %{
        "chat" => %{"id" => -123},
        "old_chat_member" => %{"status" => "left", "user" => %{"id" => 99}},
        "new_chat_member" => %{"status" => "member", "user" => %{"id" => 99}}
      }
    }

    {pid, _binding} = start_worker([{:ok, [membership]}])
    assert_receive {:get_updates_call, _, _}
    assert_receive {:sink_emit, %Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.membership.changed"
    assert fact.data["bot_self"]
    assert :sys.get_state(pid).offset == 6
  end

  test "membership sink rejection prevents checkpoint advancement" do
    member = %{
      "update_id" => 5,
      "chat_member" => %{
        "chat" => %{"id" => -123},
        "old_chat_member" => %{"status" => "member", "user" => %{"id" => 42}},
        "new_chat_member" => %{"status" => "restricted", "is_member" => false, "user" => %{"id" => 42}}
      }
    }

    {pid, _binding} = start_worker([{:ok, [member]}, {:ok, [member]}], :error, offset: 3)
    assert_receive {:get_updates_call, _, first}
    assert first["offset"] == 3
    assert_receive {:sink_emit, %Delivery{signals: [fact]}, []}
    assert fact.type == "jido.chat.membership.changed"
    assert fact.data["transition"] == "left"
    assert :sys.get_state(pid).offset == 3
    send(pid, :poll)
    assert_receive {:get_updates_call, _, second}
    assert second["offset"] == 3
    assert_receive {:sink_emit, %Delivery{signals: [retry]}, []}
    assert retry.data["item_id"] == fact.data["item_id"]
    assert :sys.get_state(pid).offset == 3
  end

  test "transport error and invalid batch do not call the sink" do
    {pid, _binding} = start_worker([{:error, :private_transport_failure}, {:ok, :invalid_batch}])
    assert_receive {:get_updates_call, _, _}
    assert :sys.get_state(pid).offset == nil
    send(pid, :poll)
    assert_receive {:get_updates_call, _, _}
    assert :sys.get_state(pid).offset == nil
    refute_received {:sink_emit, _, _}
  end

  for limit <- [:count, :failures, :aggregate] do
    test "complete #{limit} rejection keeps the checkpoint and makes zero sink calls" do
      batch =
        case unquote(limit) do
          :count -> Enum.map(1..101, &update/1)
          :failures -> Enum.map(1..21, &%{"update_id" => &1, "message" => %{}})
          :aggregate -> Enum.map(1..6, &update(&1, String.duplicate("x", 200_000)))
        end

      {pid, _binding} = start_worker([{:ok, batch}, {:ok, batch}], :ok, offset: 3)
      assert_receive {:get_updates_call, _, first}
      assert first["offset"] == 3
      assert :sys.get_state(pid).offset == 3
      refute_received {:sink_emit, _, _}
      send(pid, :poll)
      assert_receive {:get_updates_call, _, second}
      assert second["offset"] == 3
      assert :sys.get_state(pid).offset == 3
      refute_received {:sink_emit, _, _}
    end
  end
end
