defmodule Jido.Chat.Telegram.ParseMode do
  @moduledoc """
  Resolves Telegram `parse_mode` from adapter option maps.

  Precedence:

  - explicit `parse_mode` option
  - canonical top-level `format` mapping
  - `nil` (no parse mode)
  """

  @doc """
  Returns the Telegram `parse_mode` for normalized option maps.

  Supported `format` mappings:

  - `:markdown` / `"markdown"` -> `"MarkdownV2"`
  - `:html` / `"html"` -> `"HTML"`
  - `:plain_text` / `"plain_text"` -> `nil`

  Unknown values are ignored and return `nil`.

  Methods that support rich messages resolve `resolve_rich_format/1` first and skip
  `parse_mode` entirely when it returns a format; captions (`sendPhoto`,
  `sendDocument`) have no rich variant and always land here.
  """
  @spec resolve_from_opts(map()) :: String.t() | nil
  def resolve_from_opts(opts) when is_map(opts) do
    explicit_parse_mode(opts) || infer_from_format(opts)
  end

  defp explicit_parse_mode(opts) do
    value = Map.get(opts, :parse_mode) || Map.get(opts, "parse_mode")

    case value do
      value when is_binary(value) and value != "" -> value
      _ -> nil
    end
  end

  @doc """
  Returns the rich-message body field for normalized option maps, or `nil`.

  Rich messages (Bot API 10.1) carry the whole body as Markdown or HTML inside
  `rich_message` and are parsed server-side, so they use no `parse_mode`.

  Supported `format` mappings:

  - `:markdown` / `:rich` / `:rich_markdown` -> `:markdown`
  - `:rich_html` -> `:html`

  Plain `:markdown` maps here, not to `"MarkdownV2"`: `MarkdownV2` is a Telegram
  subset that cannot express tables, headings, or nested lists, so callers asking
  for markdown get the renderer that handles all of it. Callers that specifically
  want the `sendMessage` subset opt out with an explicit `parse_mode` — that
  suppresses the inference, while an explicitly requested `:rich_*` format still
  wins.

  An explicit `rich_format` option wins over an inferred one.
  """
  @spec resolve_rich_format(map()) :: :markdown | :html | nil
  def resolve_rich_format(opts) when is_map(opts) do
    explicit_rich_format(opts) || infer_rich_from_format(opts)
  end

  defp explicit_rich_format(opts) do
    case Map.get(opts, :rich_format) || Map.get(opts, "rich_format") do
      value when value in [:markdown, :html] -> value
      "markdown" -> :markdown
      "html" -> :html
      _ -> nil
    end
  end

  defp infer_rich_from_format(opts) do
    case Map.get(opts, :format) || Map.get(opts, "format") do
      format when format in [:rich, "rich", :rich_markdown, "rich_markdown"] -> :markdown
      format when format in [:rich_html, "rich_html"] -> :html
      format when format in [:markdown, "markdown"] -> markdown_unless_parse_mode(opts)
      _ -> nil
    end
  end

  # An explicit `parse_mode` is the opt-out back to `sendMessage`. Option modules must
  # therefore resolve the rich format before normalizing `parse_mode`, or an inferred
  # `"MarkdownV2"` would look like a caller opting out of rich delivery.
  defp markdown_unless_parse_mode(opts) do
    case explicit_parse_mode(opts) do
      nil -> :markdown
      _parse_mode -> nil
    end
  end

  defp infer_from_format(opts) do
    format = Map.get(opts, :format) || Map.get(opts, "format")

    case format do
      :markdown -> "MarkdownV2"
      "markdown" -> "MarkdownV2"
      :html -> "HTML"
      "html" -> "HTML"
      :plain_text -> nil
      "plain_text" -> nil
      _ -> nil
    end
  end
end
