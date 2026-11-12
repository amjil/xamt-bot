defmodule XamtBot.Handlers.Echo do
  @moduledoc """
  Infrastructure acceptance bot.

  On `message.created` from a human user, replies with `Echo: <content>`.
  Ignores bot-authored messages to prevent infinite loops.
  """

  @behaviour XamtBot.Runtime.Handler

  alias XamtBot.Bots.BotInstance
  alias XamtBot.Clients.XamtClient
  alias XamtBot.Events.EventInbox

  @impl true
  def handle_event(%BotInstance{} = bot, %EventInbox{} = event) do
    case event.event_type do
      "message.created" -> handle_message_created(bot, event)
      _other -> {:ignored, :unsupported_event}
    end
  end

  defp handle_message_created(bot, event) do
    payload = event.payload || %{}
    data = Map.get(payload, "data") || %{}
    message = Map.get(payload, "message") || %{}

    author = Map.get(data, "author") || Map.get(message, "author") || %{}
    author_type = Map.get(author, "type") || Map.get(author, :type)
    content = Map.get(data, "content") || Map.get(message, "body") || ""
    channel_id = Map.get(data, "channel_id") || Map.get(payload, "channel_id")
    message_id = Map.get(data, "message_id") || Map.get(message, "id")

    cond do
      author_type in ["bot", :bot] ->
        {:ignored, :bot_author}

      not is_binary(channel_id) or channel_id == "" ->
        {:error, :missing_channel_id}

      true ->
        body = "Echo: #{normalize_content(content)}"
        nonce = "echo:#{event.external_event_id}"

        case XamtClient.create_message(bot, channel_id, %{
               body: body,
               reply_to_id: message_id,
               nonce: nonce
             }) do
          {:ok, :replayed, _existing} ->
            {:ok, %{"replayed" => true, "channel_id" => channel_id}}

          {:ok, %{body: resp}} ->
            reply_id = get_in(resp, ["data", "id"])
            {:ok, %{"channel_id" => channel_id, "reply_message_id" => reply_id}}

          {:error, {:unauthorized, _} = err} ->
            {:error, err}

          {:error, {:forbidden, _} = err} ->
            {:error, err}

          {:error, :in_flight} ->
            {:error, :retry, :in_flight}

          {:error, {:rate_limited, _} = err} ->
            {:error, :retry, err}

          {:error, {:server_error, _, _} = err} ->
            {:error, :retry, err}

          {:error, {:transport_error, _} = err} ->
            {:error, :retry, err}

          {:error, reason} ->
            {:error, reason}
        end
    end
  end

  defp normalize_content(nil), do: ""
  defp normalize_content(content) when is_binary(content), do: String.trim(content)
  defp normalize_content(other), do: other |> to_string() |> String.trim()
end
