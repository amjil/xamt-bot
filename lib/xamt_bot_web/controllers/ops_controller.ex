defmodule XamtBotWeb.OpsController do
  use XamtBotWeb, :controller

  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events
  alias XamtBot.Events.EventInbox
  alias XamtBot.Audit
  alias XamtBot.Audit.ExecutionLog

  def bots(conn, _params) do
    bots =
      Bots.list_instances()
      |> Enum.map(&serialize_bot/1)

    json(conn, %{ok: true, data: bots})
  end

  def show_bot(conn, %{"id" => id}) do
    case Bots.get_instance(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "not_found"})

      bot ->
        json(conn, %{ok: true, data: serialize_bot(bot)})
    end
  end

  def events(conn, params) do
    events =
      Events.list_recent(
        limit: parse_limit(params["limit"], 50),
        status: params["status"],
        bot_instance_id: params["bot_instance_id"]
      )
      |> Enum.map(&serialize_event/1)

    json(conn, %{ok: true, data: events})
  end

  def show_event(conn, %{"id" => id}) do
    case Events.get_event(id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "not_found"})

      event ->
        json(conn, %{ok: true, data: serialize_event(event)})
    end
  end

  def executions(conn, params) do
    logs =
      Audit.list_executions(
        limit: parse_limit(params["limit"], 50),
        status: params["status"],
        bot_instance_id: params["bot_instance_id"]
      )
      |> Enum.map(&serialize_execution/1)

    json(conn, %{ok: true, data: logs})
  end

  defp serialize_bot(%BotInstance{} = bot) do
    %{
      id: bot.id,
      external_bot_id: bot.external_bot_id,
      name: bot.name,
      handler_key: bot.handler_key,
      status: bot.status,
      webhook_path: "/webhooks/xamt/#{bot.external_bot_id}",
      nomio_webhook_path:
        if(bot.handler_key == "nomio_review", do: "/webhooks/nomio/reviews", else: nil),
      inserted_at: bot.inserted_at,
      updated_at: bot.updated_at
    }
  end

  defp serialize_event(%EventInbox{} = event) do
    %{
      id: event.id,
      external_event_id: event.external_event_id,
      event_type: event.event_type,
      status: event.status,
      attempt_count: event.attempt_count,
      bot_instance_id: event.bot_instance_id,
      bot_name: event.bot_instance && event.bot_instance.name,
      last_error: event.last_error,
      received_at: event.received_at,
      processed_at: event.processed_at
    }
  end

  defp serialize_execution(%ExecutionLog{} = log) do
    %{
      id: log.id,
      bot_instance_id: log.bot_instance_id,
      event_inbox_id: log.event_inbox_id,
      handler_key: log.handler_key,
      status: log.status,
      duration_ms: log.duration_ms,
      error_code: log.error_code,
      error_message: log.error_message,
      metadata: log.metadata,
      started_at: log.started_at,
      finished_at: log.finished_at
    }
  end

  defp parse_limit(nil, default), do: default

  defp parse_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> min(n, 200)
      _ -> default
    end
  end

  defp parse_limit(value, _default) when is_integer(value) and value > 0, do: min(value, 200)

  defp parse_limit(_, default), do: default
end
