defmodule Jido.Chat.Telegram.StreamRendererTest do
  use ExUnit.Case, async: true

  alias Jido.Chat.Markdown.StreamRenderer
  alias Jido.Chat.Telegram.Adapter

  @fixtures [
    {:split_emphasis, "Before **bold _and italic_** after"},
    {:split_link, "Read [the guide](https://jido.run/docs?q=chat) now."},
    {:list, "Plan:\n\n- first\n- second\n\nDone."},
    {:code_fence, "```elixir\nIO.puts(\"hello\")\n```\n\nDone."},
    {:structural_whitespace, "Heading\n\nParagraph  \nnext line\n\n"},
    {:empty_table_cells, "| Name |  | State |\n| --- | --- | --- |\n| alpha |  | ready |\n|  | beta |  |"}
  ]

  defmodule CapturingTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, method, payload, _opts) do
      send(self(), {:telegram_call, method, payload})

      case method do
        draft when draft in ["sendMessageDraft", "sendRichMessageDraft"] ->
          {:ok, true}

        _send ->
          {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}, "date" => 1}}
      end
    end
  end

  defmodule RejectingDraftTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(_token, method, payload, _opts) do
      send(self(), {:telegram_call, method, payload})

      case method do
        "sendMessageDraft" -> {:error, :draft_rejected}
        _send -> {:ok, %{"message_id" => 42, "chat" => %{"id" => payload["chat_id"]}}}
      end
    end
  end

  test "native rich drafts use the canonical snapshots and flush exact Markdown" do
    for {name, markdown} <- @fixtures do
      chunks = String.codepoints(markdown)

      assert {:ok, _response} =
               Adapter.stream(123, chunks,
                 token: "bot-token",
                 transport: CapturingTransport,
                 stream_update_interval_ms: 0,
                 draft_id: 7,
                 format: :rich_markdown
               )

      calls = collect_calls()
      {draft_calls, [final_call]} = Enum.split(calls, -1)

      assert Enum.map(draft_calls, &rich_markdown/1) == expected_snapshots(chunks),
             "fixture #{name} did not use the canonical partial snapshots"

      assert {"sendRichMessage", final_payload} = final_call
      assert final_payload["rich_message"] == %{"markdown" => markdown}
    end
  end

  test "possible tables stay buffered until a safe draft exists" do
    chunks = [
      "| Name |  | State |\n",
      "| --- | ---",
      " | --- |\n",
      "| alpha |  ",
      "| ready |\n"
    ]

    assert {:ok, _response} = stream(chunks)

    calls = collect_calls()
    {draft_calls, [final_call]} = Enum.split(calls, -1)

    assert Enum.map(draft_calls, &rich_markdown/1) == expected_snapshots(chunks)
    assert length(draft_calls) == 2
    assert rich_markdown(final_call) == Enum.join(chunks)
  end

  test "structured chunks use deterministic Markdown and tool-only streams stay empty" do
    chunks = [
      %{kind: :status, text: "Working"},
      %{kind: :plan, payload: ["Inspect", "Change"]},
      %{kind: :step_finish, payload: %{label: "Inspect"}},
      %{kind: :timeline, payload: [%{at: "10:00", label: "Started"}]}
    ]

    assert {:ok, _response} = stream(chunks)
    calls = collect_calls()
    {_draft_calls, [final_call]} = Enum.split(calls, -1)

    assert rich_markdown(final_call) == StreamRenderer.render(chunks)

    assert {:error, :empty_stream} = stream([%{kind: :data, payload: %{tool: "search"}}])
    assert collect_calls() == []
  end

  test "update cadence still limits drafts without changing the final flush" do
    chunks = ["alpha", " beta", " gamma"]

    assert {:ok, _response} =
             Adapter.stream(123, chunks,
               token: "bot-token",
               transport: CapturingTransport,
               stream_update_interval_ms: 60_000,
               draft_id: 7,
               format: :rich_markdown
             )

    calls = collect_calls()
    {draft_calls, [final_call]} = Enum.split(calls, -1)

    assert length(draft_calls) == 1
    assert rich_markdown(final_call) == "alpha beta gamma"
  end

  test "unsupported draft targets use the same final renderer" do
    chunks = [
      "Before **bo",
      "ld**\n",
      %{kind: :plan, payload: ["Inspect", "Change"]}
    ]

    assert {:ok, _response} =
             Adapter.stream("@channel", chunks,
               token: "bot-token",
               transport: CapturingTransport,
               format: :rich_markdown
             )

    assert [{"sendRichMessage", payload}] = collect_calls()
    assert payload["rich_message"] == %{"markdown" => StreamRenderer.render(chunks)}
  end

  test "Telegram draft errors are returned without a final send" do
    assert {:error, :draft_rejected} =
             Adapter.stream(123, ["hello"],
               token: "bot-token",
               transport: RejectingDraftTransport,
               stream_update_interval_ms: 0,
               draft_id: 7
             )

    assert [{"sendMessageDraft", %{"text" => "hello"}}] = collect_calls()
  end

  defp stream(chunks) do
    Adapter.stream(123, chunks,
      token: "bot-token",
      transport: CapturingTransport,
      stream_update_interval_ms: 0,
      draft_id: 7,
      format: :rich_markdown
    )
  end

  defp expected_snapshots(chunks) do
    chunks
    |> Enum.reduce({StreamRenderer.new(), []}, fn chunk, {renderer, snapshots} ->
      {renderer, snapshot} = StreamRenderer.push(renderer, chunk)
      snapshots = if is_nil(snapshot), do: snapshots, else: [snapshot | snapshots]
      {renderer, snapshots}
    end)
    |> elem(1)
    |> Enum.reverse()
  end

  defp rich_markdown({_method, payload}) do
    payload["rich_message"]["markdown"]
  end

  defp collect_calls(calls \\ []) do
    receive do
      {:telegram_call, method, payload} -> collect_calls([{method, payload} | calls])
    after
      0 -> Enum.reverse(calls)
    end
  end
end
