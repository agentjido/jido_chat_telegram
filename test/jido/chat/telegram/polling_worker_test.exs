defmodule Jido.Chat.Telegram.PollingWorkerTest do
  use ExUnit.Case, async: false

  alias Jido.Chat.Telegram.{Adapter, PollingWorker}

  defmodule PollingTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(token, "getUpdates", payload, opts) do
      test_pid = Keyword.fetch!(opts, :test_pid)
      responses_agent = Keyword.fetch!(opts, :responses_agent)
      send(test_pid, {:get_updates_call, token, payload})

      Agent.get_and_update(responses_agent, fn
        [next | rest] -> {next, rest}
        [] -> {{:ok, []}, []}
      end)
    end

    def call(_token, method, _payload, _opts), do: {:error, {:unsupported_method, method}}
  end

  defmodule OkSink do
    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:ok, :accepted}
    end
  end

  defmodule ErrorSink do
    def emit(test_pid, payload, opts) do
      send(test_pid, {:sink_emit, payload, opts})
      {:error, :sink_failed}
    end
  end

  test "adapter listener_child_specs/2 returns expected polling/webhook specs" do
    assert {:ok, []} = Adapter.listener_child_specs("bridge_tg", ingress: %{mode: "webhook"})

    assert {:error, :invalid_sink_mfa} =
             Adapter.listener_child_specs("bridge_tg", ingress: %{mode: "polling"})

    assert {:ok, [spec]} =
             Adapter.listener_child_specs("bridge_tg",
               ingress: %{
                 mode: "polling",
                 token: "bot-token",
                 transport_opts: %{"url" => "http://localhost:8081"}
               },
               sink_mfa: {OkSink, :emit, [self()]}
             )

    assert spec.id == {:telegram_polling_worker, "bridge_tg"}
    assert {PollingWorker, :start_link, [worker_opts]} = spec.start
    assert worker_opts[:transport_opts][:url] == "http://localhost:8081"
  end

  test "polling worker emits updates through sink and advances offset on success" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [%{"update_id" => 10, "message" => %{"message_id" => 1, "text" => "hello"}}]},
          {:ok, []}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         bridge_id: "bridge_tg",
         sink_mfa: {OkSink, :emit, [self()]},
         token: "bot-token",
         transport: PollingTransport,
         transport_opts: [test_pid: self(), responses_agent: responses_agent],
         timeout_s: 1,
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:get_updates_call, "bot-token", first_payload}, 200
    assert Map.get(first_payload, "offset") == nil

    assert_receive {:sink_emit, %{"update_id" => 10}, sink_opts}, 200
    assert sink_opts[:mode] == :payload

    assert_receive {:get_updates_call, "bot-token", second_payload}, 400
    assert second_payload["offset"] == 11
  end

  test "polling worker keeps offset unchanged when sink returns error" do
    {:ok, responses_agent} =
      Agent.start_link(fn ->
        [
          {:ok, [%{"update_id" => 5, "message" => %{"message_id" => 3, "text" => "retry"}}]},
          {:ok, [%{"update_id" => 5, "message" => %{"message_id" => 3, "text" => "retry"}}]}
        ]
      end)

    {:ok, _pid} =
      start_supervised(
        {PollingWorker,
         bridge_id: "bridge_tg",
         sink_mfa: {ErrorSink, :emit, [self()]},
         token: "bot-token",
         transport: PollingTransport,
         transport_opts: [test_pid: self(), responses_agent: responses_agent],
         timeout_s: 1,
         poll_interval_ms: 10,
         max_backoff_ms: 50}
      )

    assert_receive {:get_updates_call, "bot-token", first_payload}, 200
    assert Map.get(first_payload, "offset") == nil
    assert_receive {:sink_emit, %{"update_id" => 5}, _sink_opts}, 200

    assert_receive {:get_updates_call, "bot-token", second_payload}, 400
    assert Map.get(second_payload, "offset") == nil
  end
end
