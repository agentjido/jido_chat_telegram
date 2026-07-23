defmodule Jido.Chat.Telegram.RichMessageTest do
  @moduledoc """
  Covers the Bot API 10.1 `sendRichMessage` path.

  `sendMessage` cannot render tables — its HTML parse mode has a closed tag set with
  no `<table>`. Rich messages carry the whole body as Markdown or HTML inside
  `rich_message` and Telegram parses it server-side, which is what makes tables,
  headings, and nested lists render.
  """

  use ExUnit.Case, async: true

  alias ExGram.Model.{InputRichMessage, ReplyParameters}
  alias Jido.Chat.Telegram.Adapter
  alias Jido.Chat.Telegram.DocumentOptions
  alias Jido.Chat.Telegram.EditOptions
  alias Jido.Chat.Telegram.ParseMode
  alias Jido.Chat.Telegram.PhotoOptions
  alias Jido.Chat.Telegram.SendOptions
  alias Jido.Chat.Telegram.StreamOptions
  alias Jido.Chat.Telegram.Transport.ExGramClient

  @table """
  | Symbol | Last | Day % |
  |--------|------|-------|
  | ES=F   | 7511 | +0.6% |
  """

  defmodule CapturingTransport do
    @behaviour Jido.Chat.Telegram.Transport

    @impl true
    def call(token, method, payload, opts) do
      send(self(), {:sent, token, method, payload, opts})
      {:ok, %{"message_id" => 42, "chat" => %{"id" => 99}, "date" => 1}}
    end
  end

  defmodule CapturingExGram do
    def send_rich_message(chat_id, rich_message, opts) do
      send(self(), {:ex_gram_rich, chat_id, rich_message, opts})
      {:ok, %{"message_id" => 7}}
    end

    def send_message(chat_id, text, opts) do
      send(self(), {:ex_gram_send, chat_id, text, opts})
      {:ok, %{"message_id" => 7}}
    end

    # Bot API 10.1 made `text` optional, so ex_gram exposes both arities.
    def edit_message_text(opts) do
      send(self(), {:ex_gram_edit_rich, opts})
      {:ok, %{"message_id" => 7}}
    end

    def edit_message_text(text, opts) do
      send(self(), {:ex_gram_edit_plain, text, opts})
      {:ok, %{"message_id" => 7}}
    end
  end

  describe "format routing" do
    test "defaults to sendMessage when no rich format is requested" do
      assert {:ok, _response} =
               Adapter.send_message(99, "plain body",
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :html
               )

      assert_received {:sent, "bot-token", "sendMessage", payload, _opts}
      assert payload["text"] == "plain body"
      assert payload["parse_mode"] == "HTML"
      refute Map.has_key?(payload, "rich_message")
    end

    test "plain messages pass protect_content to sendMessage" do
      assert {:ok, _response} =
               Adapter.send_message(99, "plain body",
                 token: "bot-token",
                 transport: CapturingTransport,
                 protect_content: true
               )

      assert_received {:sent, "bot-token", "sendMessage", payload, _opts}
      assert payload["protect_content"] == true
    end

    test "format: :rich_markdown routes the body to sendRichMessage as markdown" do
      assert {:ok, _response} =
               Adapter.send_message(99, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_markdown
               )

      assert_received {:sent, "bot-token", "sendRichMessage", payload, _opts}
      assert payload["rich_message"] == %{"markdown" => @table}
      assert payload["chat_id"] == 99
    end

    # Callers speak plain `:markdown` — mapping it to rich delivery here is what keeps
    # Telegram's `sendRichMessage`/MarkdownV2 split an adapter concern.
    test "format: :markdown routes the body to sendRichMessage as markdown" do
      assert {:ok, _response} =
               Adapter.send_message(99, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :markdown
               )

      assert_received {:sent, "bot-token", "sendRichMessage", payload, _opts}
      assert payload["rich_message"] == %{"markdown" => @table}
      refute Map.has_key?(payload, "parse_mode")
    end

    test "format: :markdown with an explicit parse_mode still uses sendMessage" do
      assert {:ok, _response} =
               Adapter.send_message(99, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :markdown,
                 parse_mode: "MarkdownV2"
               )

      assert_received {:sent, "bot-token", "sendMessage", payload, _opts}
      assert payload["text"] == @table
      assert payload["parse_mode"] == "MarkdownV2"
      refute Map.has_key?(payload, "rich_message")
    end

    test "format: :rich_html routes the body to sendRichMessage as html" do
      assert {:ok, _response} =
               Adapter.send_message(99, "<b>hi</b>",
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_html
               )

      assert_received {:sent, "bot-token", "sendRichMessage", payload, _opts}
      assert payload["rich_message"] == %{"html" => "<b>hi</b>"}
    end

    test "rich payloads drop options sendRichMessage does not accept" do
      assert {:ok, _response} =
               Adapter.send_message(99, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_markdown,
                 disable_web_page_preview: true,
                 entities: [%{type: "bold"}],
                 disable_notification: true,
                 thread_id: 5
               )

      assert_received {:sent, "bot-token", "sendRichMessage", payload, _opts}
      refute Map.has_key?(payload, "parse_mode")
      refute Map.has_key?(payload, "disable_web_page_preview")
      refute Map.has_key?(payload, "entities")
      assert payload["disable_notification"] == true
      assert payload["message_thread_id"] == 5
    end

    test "rich messages preserve generic reply routing" do
      assert {:ok, _response} =
               Adapter.send_message(99, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_markdown,
                 reply_to_id: 42
               )

      assert_received {:sent, "bot-token", "sendRichMessage", payload, _opts}
      assert payload["reply_parameters"] == %{"message_id" => 42}
      refute Map.has_key?(payload, "reply_to_message_id")
    end
  end

  describe "SendOptions" do
    test "rich formats do not set parse_mode" do
      assert %SendOptions{rich_format: :markdown, parse_mode: nil} =
               SendOptions.new(format: :rich_markdown)
    end

    test "an explicit rich_format wins over an inferred one" do
      assert %SendOptions{rich_format: :html} =
               SendOptions.new(format: :rich_markdown, rich_format: :html)
    end

    test "plain markdown resolves to rich without a parse_mode" do
      assert %SendOptions{rich_format: :markdown, parse_mode: nil} =
               SendOptions.new(format: :markdown)

      assert %EditOptions{rich_format: :markdown, parse_mode: nil} =
               EditOptions.new(format: "markdown")

      assert %StreamOptions{rich_format: :markdown, parse_mode: nil} =
               StreamOptions.new(format: :markdown)
    end

    # `sendPhoto`/`sendDocument` captions have no rich variant, so markdown captions
    # keep the MarkdownV2 parse_mode instead of silently shipping raw markup.
    test "caption options keep MarkdownV2 for markdown" do
      assert PhotoOptions.new(format: :markdown).parse_mode == "MarkdownV2"
      assert DocumentOptions.new(format: "markdown").parse_mode == "MarkdownV2"
    end

    test "rejects invalid explicit rich formats" do
      assert_raise Jido.Chat.Errors.Validation, fn ->
        SendOptions.new(rich_format: "bogus")
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        EditOptions.new(rich_format: :bogus)
      end

      assert_raise Jido.Chat.Errors.Validation, fn ->
        StreamOptions.new(rich_format: "bogus")
      end
    end
  end

  describe "edit routing" do
    # This is the path real traffic takes: a status placeholder is posted first and
    # then edited with the answer, so a rich format that survives only `send_message`
    # would still ship raw markdown to users.
    test "defaults to a plain text edit when no rich format is requested" do
      assert {:ok, _response} =
               Adapter.edit_message(99, 7, "plain body",
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :html
               )

      assert_received {:sent, "bot-token", "editMessageText", payload, _opts}
      assert payload["text"] == "plain body"
      assert payload["parse_mode"] == "HTML"
      refute Map.has_key?(payload, "rich_message")
    end

    test "format: :rich_markdown edits the message into rich content" do
      assert {:ok, _response} =
               Adapter.edit_message(99, 7, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_markdown
               )

      assert_received {:sent, "bot-token", "editMessageText", payload, _opts}
      assert payload["rich_message"] == %{"markdown" => @table}
      assert payload["chat_id"] == 99
      assert payload["message_id"] == 7
      refute Map.has_key?(payload, "text")
    end

    test "rich edits drop options editMessageText does not accept alongside rich_message" do
      assert {:ok, _response} =
               Adapter.edit_message(99, 7, @table,
                 token: "bot-token",
                 transport: CapturingTransport,
                 format: :rich_markdown,
                 entities: [%{type: "bold"}],
                 disable_web_page_preview: true
               )

      assert_received {:sent, "bot-token", "editMessageText", payload, _opts}
      refute Map.has_key?(payload, "parse_mode")
      refute Map.has_key?(payload, "entities")
      refute Map.has_key?(payload, "disable_web_page_preview")
    end

    test "EditOptions resolves rich formats without setting parse_mode" do
      assert %EditOptions{rich_format: :markdown, parse_mode: nil} =
               EditOptions.new(format: :rich_markdown)
    end
  end

  describe "stream options" do
    # `stream/3` rebuilds its own opts before the final send. Without rich_format in
    # that struct the format is silently dropped and the answer degrades to plain text.
    test "carries rich_format through to the final send" do
      opts = StreamOptions.new(format: :rich_markdown, token: "bot-token")

      assert opts.rich_format == :markdown
      assert StreamOptions.send_opts(opts)[:rich_format] == :markdown
    end

    test "omits rich_format when the stream is not rich" do
      opts = StreamOptions.new(format: :html, token: "bot-token")

      assert opts.rich_format == nil
      refute Keyword.has_key?(StreamOptions.send_opts(opts), :rich_format)
    end

    test "uses rich draft updates for a rich stream" do
      assert {:ok, _response} =
               Adapter.stream(99, ["| A |", " B |"],
                 token: "bot-token",
                 transport: CapturingTransport,
                 stream_update_interval_ms: 0,
                 draft_id: 7,
                 format: :rich_markdown
               )

      assert_received {:sent, "bot-token", "sendRichMessageDraft", first_payload, _opts}
      assert first_payload["draft_id"] == 7
      assert first_payload["rich_message"] == %{"markdown" => "| A |"}
      refute Map.has_key?(first_payload, "text")

      assert_received {:sent, "bot-token", "sendRichMessageDraft", second_payload, _opts}
      assert second_payload["rich_message"] == %{"markdown" => "| A | B |"}

      assert_received {:sent, "bot-token", "sendRichMessage", final_payload, _opts}
      assert final_payload["rich_message"] == %{"markdown" => "| A | B |"}
    end
  end

  describe "ParseMode.resolve_rich_format/1" do
    test "maps rich format aliases" do
      assert ParseMode.resolve_rich_format(%{format: :rich}) == :markdown
      assert ParseMode.resolve_rich_format(%{format: :rich_markdown}) == :markdown
      assert ParseMode.resolve_rich_format(%{format: "rich_markdown"}) == :markdown
      assert ParseMode.resolve_rich_format(%{format: :rich_html}) == :html
      assert ParseMode.resolve_rich_format(%{format: "rich_html"}) == :html
    end

    # Plain markdown belongs here, not on MarkdownV2: MarkdownV2 is a Telegram subset
    # with no tables, headings, or nested lists, so a caller asking for markdown gets
    # the renderer that can actually express it.
    test "maps plain markdown to rich delivery" do
      assert ParseMode.resolve_rich_format(%{format: :markdown}) == :markdown
      assert ParseMode.resolve_rich_format(%{format: "markdown"}) == :markdown
    end

    test "an explicit parse_mode opts markdown back out to sendMessage" do
      assert ParseMode.resolve_rich_format(%{format: :markdown, parse_mode: "MarkdownV2"}) == nil
      assert ParseMode.resolve_rich_format(%{"format" => "markdown", "parse_mode" => "HTML"}) == nil

      assert ParseMode.resolve_from_opts(%{format: :markdown, parse_mode: "MarkdownV2"}) ==
               "MarkdownV2"
    end

    # An explicitly requested rich format is not an inference, so parse_mode cannot veto it.
    test "an explicit parse_mode does not suppress an explicit rich format" do
      assert ParseMode.resolve_rich_format(%{format: :rich_markdown, parse_mode: "HTML"}) ==
               :markdown
    end

    test "ignores non-rich and unknown formats" do
      assert ParseMode.resolve_rich_format(%{format: :html}) == nil
      assert ParseMode.resolve_rich_format(%{format: :plain_text}) == nil
      assert ParseMode.resolve_rich_format(%{}) == nil
    end

    test "an explicit rich_format wins over an inferred one" do
      assert ParseMode.resolve_rich_format(%{format: :rich_markdown, rich_format: :html}) == :html
      assert ParseMode.resolve_rich_format(%{rich_format: "markdown"}) == :markdown
    end

    test "rich formats never produce a parse_mode" do
      assert ParseMode.resolve_from_opts(%{format: :rich_markdown}) == nil
      assert ParseMode.resolve_from_opts(%{format: :rich_html}) == nil
    end
  end

  describe "ExGramClient" do
    test "builds an InputRichMessage struct for ex_gram" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => %{"markdown" => @table}, "disable_notification" => true},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{} = rich_message, opts}
      assert rich_message.markdown == @table
      assert rich_message.html == nil
      assert opts[:disable_notification] == true
    end

    test "builds ReplyParameters for a rich reply" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{
          "chat_id" => 99,
          "rich_message" => %{"markdown" => @table},
          "reply_parameters" => %{"message_id" => 42}
        },
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{}, opts}
      assert %ReplyParameters{message_id: 42} = opts[:reply_parameters]
    end

    test "passes an already-built InputRichMessage through untouched" do
      built = %InputRichMessage{html: "<b>hi</b>"}

      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => built},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, ^built, _opts}
    end

    test "drops unknown keys when building an InputRichMessage" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{"chat_id" => 99, "rich_message" => %{"markdown" => "hi", "bogus" => "x"}},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, %InputRichMessage{markdown: "hi"}, _opts}
    end

    test "supports every InputRichMessage field" do
      ExGramClient.call(
        "bot-token",
        "sendRichMessage",
        %{
          "chat_id" => 99,
          "rich_message" => %{
            "html" => "<b>hi</b>",
            "is_rtl" => true,
            "skip_entity_detection" => true
          }
        },
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_rich, 99, rich_message, _opts}
      assert rich_message.html == "<b>hi</b>"
      assert rich_message.is_rtl == true
      assert rich_message.skip_entity_detection == true
    end

    test "editMessageText dispatches rich edits to edit_message_text/1" do
      ExGramClient.call(
        "bot-token",
        "editMessageText",
        %{"chat_id" => 99, "message_id" => 7, "rich_message" => %{"markdown" => @table}},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_edit_rich, opts}
      assert %InputRichMessage{markdown: @table} = opts[:rich_message]
      assert opts[:chat_id] == 99
      assert opts[:message_id] == 7
    end

    test "editMessageText still dispatches plain edits to edit_message_text/2" do
      ExGramClient.call(
        "bot-token",
        "editMessageText",
        %{"chat_id" => 99, "message_id" => 7, "text" => "plain", "parse_mode" => "HTML"},
        ex_gram_module: CapturingExGram
      )

      assert_received {:ex_gram_edit_plain, "plain", opts}
      assert opts[:parse_mode] == "HTML"
      refute Keyword.has_key?(opts, :rich_message)
    end
  end
end
