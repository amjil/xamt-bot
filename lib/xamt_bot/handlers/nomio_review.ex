defmodule XamtBot.Handlers.NomioReview do
  @moduledoc """
  Receives review notifications from Nomio and posts formatted messages to a Xamt channel.
  """

  @behaviour XamtBot.Runtime.Handler

  alias XamtBot.Bots.BotInstance
  alias XamtBot.Clients.XamtClient
  alias XamtBot.Events.EventInbox

  @supported_events ["nomio.review.created", "nomio.review.updated", "review.submitted"]

  @impl true
  def handle_event(%BotInstance{} = bot, %EventInbox{} = event) do
    if event.event_type in @supported_events do
      forward_review_to_xamt(bot, event)
    else
      {:ignored, :unsupported_event}
    end
  end

  defp forward_review_to_xamt(bot, event) do
    payload = event.payload || %{}
    data = Map.get(payload, "data") || payload

    channel_id =
      Map.get(data, "channel_id") ||
        Map.get(bot.config || %{}, "default_channel_id")

    if not is_binary(channel_id) or String.trim(channel_id) == "" do
      {:error, :missing_channel_id}
    else
      body = format_review_message(data)
      nonce = "nomio_review:#{event.external_event_id}"

      case XamtClient.create_message(bot, channel_id, %{body: body, nonce: nonce}) do
        {:ok, :replayed, _existing} ->
          {:ok, %{"replayed" => true, "channel_id" => channel_id}}

        {:ok, %{body: resp}} ->
          reply_id = get_in(resp, ["data", "id"])
          {:ok, %{"channel_id" => channel_id, "message_id" => reply_id}}

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

  defp format_review_message(data) do
    title = Map.get(data, "title", "未命名审核项")
    submitter = Map.get(data, "submitter", "未知用户")
    status = Map.get(data, "status", "待审核")
    url = Map.get(data, "review_url") || Map.get(data, "url")
    summary = Map.get(data, "summary") || Map.get(data, "content")

    [
      "**[Nomio 审核通知]** #{title}",
      "- **状态：** #{status}",
      "- **提交人：** #{submitter}",
      if(summary, do: "- **摘要：** #{summary}"),
      if(url, do: "- **详情链接：** #{url}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end
end
