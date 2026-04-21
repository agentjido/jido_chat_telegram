defmodule Jido.Chat.Telegram.Extensions do
  @moduledoc """
  Telegram-specific extension API for features outside core `Jido.Chat.Adapter`.

  This module is intentionally platform-specific and keeps Telegram-only semantics
  out of `jido_chat` core abstractions.
  """

  alias Jido.Chat.Telegram.{
    CallbackAnswerOptions,
    CallbackAnswerResult,
    CallbackQuery,
    DocumentOptions,
    MediaMessage,
    PhotoOptions,
    UpdateEnvelope
  }

  alias Jido.Chat.Telegram.Transport.ExGramClient

  @type extension_status :: :native | :fallback | :unsupported
  @type extension_capabilities :: %{optional(atom()) => extension_status()}

  @doc """
  Returns Telegram extension capability statuses.
  """
  @spec capabilities() :: extension_capabilities()
  def capabilities do
    %{
      send_photo: :native,
      send_document: :native,
      answer_callback_query: :native,
      parse_update_envelope: :native,
      inline_keyboard: :native,
      send_media_group: :unsupported,
      forum_topics: :unsupported
    }
  end

  @doc """
  Parses a Telegram update into a typed extension envelope.
  """
  @spec parse_update(map()) :: {:ok, UpdateEnvelope.t()} | {:error, term()}
  def parse_update(update) when is_map(update) do
    update_id = map_get(update, [:update_id, "update_id"])

    cond do
      is_map(map_get(update, [:callback_query, "callback_query"])) ->
        callback_query = map_get(update, [:callback_query, "callback_query"])

        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :callback_query,
           payload: normalize_callback_query(callback_query),
           raw: update,
           metadata: %{}
         })}

      is_map(map_get(update, [:message_reaction, "message_reaction"])) ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :message_reaction,
           payload: map_get(update, [:message_reaction, "message_reaction"]),
           raw: update,
           metadata: %{}
         })}

      is_map(map_get(update, [:edited_channel_post, "edited_channel_post"])) ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :edited_channel_post,
           payload: map_get(update, [:edited_channel_post, "edited_channel_post"]),
           raw: update,
           metadata: %{}
         })}

      is_map(map_get(update, [:channel_post, "channel_post"])) ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :channel_post,
           payload: map_get(update, [:channel_post, "channel_post"]),
           raw: update,
           metadata: %{}
         })}

      is_map(map_get(update, [:edited_message, "edited_message"])) ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :edited_message,
           payload: map_get(update, [:edited_message, "edited_message"]),
           raw: update,
           metadata: %{}
         })}

      is_map(map_get(update, [:message, "message"])) ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :message,
           payload: map_get(update, [:message, "message"]),
           raw: update,
           metadata: %{}
         })}

      true ->
        {:ok,
         UpdateEnvelope.new(%{
           update_id: update_id,
           update_type: :noop,
           payload: nil,
           raw: update,
           metadata: %{reason: :unsupported_update_type}
         })}
    end
  end

  @doc """
  Sends a Telegram photo message and returns a typed media result.
  """
  @spec send_photo(
          String.t() | integer(),
          String.t() | {:file, String.t()} | {:file_content, binary(), String.t()},
          keyword() | map() | PhotoOptions.t()
        ) ::
          {:ok, MediaMessage.t()} | {:error, term()}
  def send_photo(chat_id, photo, opts \\ []) do
    opts = PhotoOptions.new(opts)
    token = fetch_token(opts.token)

    payload =
      PhotoOptions.payload_opts(opts)
      |> Map.merge(%{"chat_id" => chat_id, "photo" => photo})

    with {:ok, result} <-
           transport(opts).call(token, "sendPhoto", payload, PhotoOptions.transport_opts(opts)) do
      {:ok, normalize_media_result(:photo, result, chat_id)}
    end
  end

  @doc """
  Sends a Telegram document message and returns a typed media result.
  """
  @spec send_document(
          String.t() | integer(),
          String.t() | {:file, String.t()} | {:file_content, binary(), String.t()},
          keyword() | map() | DocumentOptions.t()
        ) ::
          {:ok, MediaMessage.t()} | {:error, term()}
  def send_document(chat_id, document, opts \\ []) do
    opts = DocumentOptions.new(opts)
    token = fetch_token(opts.token)

    payload =
      DocumentOptions.payload_opts(opts)
      |> Map.merge(%{"chat_id" => chat_id, "document" => document})

    with {:ok, result} <-
           transport(opts).call(
             token,
             "sendDocument",
             payload,
             DocumentOptions.transport_opts(opts)
           ) do
      {:ok, normalize_media_result(:document, result, chat_id)}
    end
  end

  @doc """
  Answers a Telegram callback query.
  """
  @spec answer_callback_query(
          String.t(),
          keyword() | map() | CallbackAnswerOptions.t()
        ) ::
          {:ok, CallbackAnswerResult.t()} | {:error, term()}
  def answer_callback_query(callback_query_id, opts \\ []) when is_binary(callback_query_id) do
    opts = CallbackAnswerOptions.new(opts)
    token = fetch_token(opts.token)

    payload =
      CallbackAnswerOptions.payload_opts(opts)
      |> Map.put("callback_query_id", callback_query_id)

    with {:ok, result} <-
           transport(opts).call(
             token,
             "answerCallbackQuery",
             payload,
             CallbackAnswerOptions.transport_opts(opts)
           ) do
      {:ok,
       CallbackAnswerResult.new(%{
         callback_query_id: callback_query_id,
         answered: true,
         raw: result
       })}
    end
  end

  defp normalize_callback_query(callback_query) when is_map(callback_query) do
    message = map_get(callback_query, [:message, "message"]) || %{}
    chat = map_get(message, [:chat, "chat"]) || %{}

    CallbackQuery.new(%{
      id: to_string(map_get(callback_query, [:id, "id"]) || Jido.Chat.ID.generate!()),
      data: map_get(callback_query, [:data, "data"]),
      from: map_get(callback_query, [:from, "from"]),
      chat_id: map_get(chat, [:id, "id"]),
      message_id: map_get(message, [:message_id, "message_id"]),
      inline_message_id: map_get(callback_query, [:inline_message_id, "inline_message_id"]),
      raw: callback_query
    })
  end

  defp normalize_media_result(kind, result, chat_id) when is_map(result) do
    file_id =
      case kind do
        :photo ->
          result
          |> map_get([:photo, "photo"])
          |> pick_photo_file_id()

        :document ->
          result
          |> map_get([:document, "document"])
          |> map_get([:file_id, "file_id"])
      end

    MediaMessage.new(%{
      kind: kind,
      message_id: to_string(map_get(result, [:message_id, "message_id"]) || Jido.Chat.ID.generate!()),
      chat_id: map_get(result, [:chat, "chat"]) |> map_get([:id, "id"]) || chat_id,
      date: map_get(result, [:date, "date"]),
      caption: map_get(result, [:caption, "caption"]),
      file_id: stringify(file_id),
      raw: result
    })
  end

  defp normalize_media_result(kind, result, chat_id) do
    MediaMessage.new(%{
      kind: kind,
      chat_id: chat_id,
      raw: result,
      metadata: %{coerced: true}
    })
  end

  defp pick_photo_file_id(list) when is_list(list) do
    list
    |> List.last()
    |> map_get([:file_id, "file_id"])
  end

  defp pick_photo_file_id(_), do: nil

  defp transport(%{transport: transport}) when not is_nil(transport), do: transport
  defp transport(_opts), do: ExGramClient

  defp fetch_token(token) do
    token || Application.get_env(:jido_chat_telegram, :telegram_bot_token) ||
      raise ArgumentError,
            "missing Telegram bot token; pass :token option or configure :jido_chat_telegram, :telegram_bot_token"
  end

  defp map_get(nil, _keys), do: nil

  defp map_get(map, keys) when is_map(map) and is_list(keys) do
    Enum.find_value(keys, fn key -> Map.get(map, key) end)
  end

  defp map_get(_other, _keys), do: nil

  defp stringify(nil), do: nil
  defp stringify(value) when is_binary(value), do: value
  defp stringify(value), do: to_string(value)
end
