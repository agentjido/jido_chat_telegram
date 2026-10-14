defmodule Jido.Chat.Telegram.PollingWorker do
  @moduledoc """
  Bridge-ingress polling worker for Telegram `getUpdates`.

  This worker is adapter-owned and runtime-agnostic. It validates the complete
  fetched batch through the captured binding before it calls the typed sink.
  """

  use GenServer

  alias Jido.Chat.Binding

  @type sink_mfa :: {module(), atom(), [term()]}

  @type state :: %{
          bridge_id: String.t(),
          binding: Binding.t(),
          sink_mfa: sink_mfa(),
          sink_opts: keyword(),
          token: String.t(),
          transport: module(),
          transport_opts: keyword(),
          timeout_s: pos_integer(),
          poll_interval_ms: pos_integer(),
          max_backoff_ms: pos_integer(),
          backoff_ms: pos_integer(),
          allowed_updates: [String.t()] | nil,
          offset: integer() | nil
        }

  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    GenServer.start_link(__MODULE__, opts)
  end

  @impl true
  def init(opts) do
    bridge_id = Keyword.fetch!(opts, :bridge_id)
    sink_mfa = Keyword.fetch!(opts, :sink_mfa)

    binding = Keyword.fetch!(opts, :binding)
    %Binding{} = binding
    token = Keyword.fetch!(binding.options, :token)

    poll_interval_ms = normalize_pos_integer(opts[:poll_interval_ms], 250)

    state = %{
      bridge_id: bridge_id,
      binding: binding,
      sink_mfa: sink_mfa,
      sink_opts: Keyword.get(opts, :sink_opts, []),
      token: token,
      transport: Keyword.fetch!(binding.options, :transport),
      transport_opts: Keyword.get(opts, :transport_opts, []),
      timeout_s: normalize_pos_integer(opts[:timeout_s], 20),
      poll_interval_ms: poll_interval_ms,
      max_backoff_ms: normalize_pos_integer(opts[:max_backoff_ms], 5_000),
      backoff_ms: poll_interval_ms,
      allowed_updates: normalize_allowed_updates(opts[:allowed_updates]),
      offset: normalize_offset(opts[:offset])
    }

    send(self(), :poll)
    {:ok, state}
  end

  @impl true
  def handle_info(:poll, state) do
    payload = get_updates_payload(state)

    case state.transport.call(state.token, "getUpdates", payload, state.transport_opts) do
      {:ok, updates} when is_list(updates) ->
        case emit_updates(updates, state) do
          {:ok, next_state} ->
            schedule_poll(next_state.poll_interval_ms)
            {:noreply, %{next_state | backoff_ms: next_state.poll_interval_ms}}

          {:error, _reason, next_state} ->
            delay = min(next_state.backoff_ms, next_state.max_backoff_ms)
            schedule_poll(delay)

            {:noreply,
             %{
               next_state
               | backoff_ms: min(max(delay * 2, next_state.poll_interval_ms), next_state.max_backoff_ms)
             }}
        end

      {:ok, _invalid} ->
        delay = min(state.backoff_ms, state.max_backoff_ms)
        schedule_poll(delay)

        {:noreply, %{state | backoff_ms: min(max(delay * 2, state.poll_interval_ms), state.max_backoff_ms)}}

      {:error, _reason} ->
        delay = min(state.backoff_ms, state.max_backoff_ms)
        schedule_poll(delay)

        {:noreply, %{state | backoff_ms: min(max(delay * 2, state.poll_interval_ms), state.max_backoff_ms)}}
    end
  end

  defp emit_updates([], state), do: {:ok, state}

  defp emit_updates(updates, state) do
    with {:ok, delivery} <- Jido.Chat.normalize_event(state.binding, updates),
         :ok <- emit_delivery(state, delivery) do
      offset = Enum.reduce(updates, state.offset, &next_offset/2)
      {:ok, %{state | offset: offset}}
    else
      {:error, reason} -> {:error, reason, state}
    end
  rescue
    _ -> {:error, :invalid_sink_result, state}
  catch
    _, _ -> {:error, :invalid_sink_result, state}
  end

  defp emit_delivery(state, delivery) do
    case invoke_sink(state.sink_mfa, delivery, state.sink_opts) do
      {:ok, _result} -> :ok
      :ok -> :ok
      _ -> {:error, :sink_rejected}
    end
  end

  defp invoke_sink({module, function, base_args}, payload, opts)
       when is_atom(module) and is_atom(function) and is_list(base_args) and is_list(opts) do
    apply(module, function, base_args ++ [payload, opts])
  end

  defp invoke_sink(_sink_mfa, _payload, _opts), do: {:error, :invalid_sink_mfa}

  defp get_updates_payload(state) do
    %{"timeout" => state.timeout_s}
    |> maybe_put("offset", state.offset)
    |> maybe_put("allowed_updates", state.allowed_updates)
  end

  defp next_offset(update, current_offset) do
    update_id =
      Map.get(update, "update_id") ||
        Map.get(update, :update_id)

    case update_id do
      id when is_integer(id) ->
        max(current_offset || 0, id + 1)

      _ ->
        current_offset
    end
  end

  defp schedule_poll(delay_ms) when is_integer(delay_ms) and delay_ms >= 0 do
    Process.send_after(self(), :poll, delay_ms)
  end

  defp normalize_allowed_updates(nil), do: nil

  defp normalize_allowed_updates(list) when is_list(list) do
    values =
      list
      |> Enum.map(&to_string/1)
      |> Enum.reject(&(&1 == ""))

    if values == [], do: nil, else: values
  end

  defp normalize_allowed_updates(_), do: nil

  defp normalize_offset(nil), do: nil
  defp normalize_offset(value) when is_integer(value) and value >= 0, do: value

  defp normalize_offset(value) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed >= 0 -> parsed
      _ -> nil
    end
  end

  defp normalize_offset(_), do: nil

  defp normalize_pos_integer(value, default)
  defp normalize_pos_integer(nil, default), do: default
  defp normalize_pos_integer(value, _default) when is_integer(value) and value > 0, do: value

  defp normalize_pos_integer(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {parsed, ""} when parsed > 0 -> parsed
      _ -> default
    end
  end

  defp normalize_pos_integer(_value, default), do: default

  defp maybe_put(map, _key, nil), do: map
  defp maybe_put(map, key, value), do: Map.put(map, key, value)
end
