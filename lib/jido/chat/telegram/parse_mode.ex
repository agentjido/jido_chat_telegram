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
