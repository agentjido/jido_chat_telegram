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

  - `:rich` / `:rich_markdown` -> `:markdown`
  - `:rich_html` -> `:html`

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
      _ -> nil
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
