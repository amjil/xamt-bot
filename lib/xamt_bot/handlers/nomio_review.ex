defmodule XamtBot.Handlers.NomioReview do
  @moduledoc """
  Receives review notifications from Nomio and posts formatted messages to a Xamt channel.
  """

  @behaviour XamtBot.Runtime.Handler

  alias XamtBot.Bots.BotInstance
  alias XamtBot.Clients.XamtClient
  alias XamtBot.Events.EventInbox

  @supported_events [
    "review.created",
    "review.updated",
    "review.completed",
    "nomio.review.created",
    "nomio.review.updated",
    "review.submitted"
  ]

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
    content = Map.get(data, "content") || %{}
    destination = Map.get(data, "destination") || %{}

    channel_id =
      Map.get(destination, "channel_id") ||
        Map.get(data, "channel_id") ||
        Map.get(payload, "channel_id") ||
        Map.get(bot.config || %{}, "default_channel_id")

    if not is_binary(channel_id) or String.trim(channel_id) == "" do
      {:error, :missing_channel_id}
    else
      body = format_review_message(event.event_type, data, content)
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

  defp format_review_message(event_type, data, content) do
    decision = Map.get(data, "decision") || %{}

    title =
      Map.get(content, "title") ||
        Map.get(data, "title") ||
        "未命名审核项"

    submitter =
      Map.get(content, "author_display_name") ||
        Map.get(data, "submitter") ||
        "未知用户"

    status = Map.get(data, "status") || "待审核"

    url =
      Map.get(content, "review_url") ||
        Map.get(data, "review_url") ||
        Map.get(data, "url") ||
        Map.get(content, "content_url") ||
        Map.get(data, "content_url")

    summary =
      Map.get(content, "summary") ||
        Map.get(data, "summary") ||
        Map.get(decision, "reason_summary")

    headline =
      case event_type do
        "review.completed" -> "**[Nomio 审核结果]** #{title}"
        _ -> "**[Nomio 审核通知]** #{title}"
      end

    decision_line =
      case Map.get(decision, "action") do
        nil -> nil
        action -> "- **决定：** #{action}"
      end

    reviewer_line =
      case Map.get(decision, "reviewer_display_name") do
        nil -> nil
        name -> "- **审核人：** #{name}"
      end

    [
      headline,
      "- **状态：** #{status}",
      "- **提交人：** #{submitter}",
      decision_line,
      reviewer_line,
      if(summary, do: "- **摘要：** #{summary}"),
      if(url, do: "- **详情链接：** #{url}")
    ]
    |> Enum.reject(&is_nil/1)
    |> Enum.join("\n")
  end
end
