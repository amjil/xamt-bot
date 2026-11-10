defmodule XamtBotWeb.OpsController do
  use XamtBotWeb, :controller

  import Ecto.Query

  alias XamtBot.Repo
  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events.EventInbox
  alias XamtBot.Audit.ExecutionLog

  def bots(conn, _params) do
    bots =
      Bots.list_instances()
      |> Enum.map(&serialize_bot/1)

    json(conn, %{ok: true, data: bots})
  end

  def show_bot(conn, %{"id" => id}) do
    case Repo.get(BotInstance, id) do
      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "not_found"})

      bot ->
        json(conn, %{ok: true, data: serialize_bot(bot)})
    end
  end

  def events(conn, params) do
    limit = parse_limit(params["limit"], 50)

    events =
      EventInbox
      |> maybe_filter_status(params["status"])
      |> maybe_filter_bot(params["bot_instance_id"])
      |> order_by([e], desc: e.received_at)
      |> limit(^limit)
      |> preload(:bot_instance)
      |> Repo.all()
      |> Enum.map(&serialize_event/1)

    json(conn, %{ok: true, data: events})
  end

  def show_event(conn, %{"id" => id}) do
    case Repo.get(EventInbox, id) |> maybe_preload_bot() do
      nil ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "not_found"})

      event ->
        json(conn, %{ok: true, data: serialize_event(event)})
    end
  end

  def executions(conn, params) do
    limit = parse_limit(params["limit"], 50)

    logs =
      ExecutionLog
      |> maybe_filter_status(params["status"])
      |> maybe_filter_bot(params["bot_instance_id"])
      |> order_by([l], desc: l.started_at)
      |> limit(^limit)
      |> Repo.all()
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

  defp maybe_preload_bot(nil), do: nil
  defp maybe_preload_bot(event), do: Repo.preload(event, :bot_instance)

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: from(q in query, where: q.status == ^status)

  defp maybe_filter_bot(query, nil), do: query
  defp maybe_filter_bot(query, ""), do: query

  defp maybe_filter_bot(query, bot_instance_id),
    do: from(q in query, where: q.bot_instance_id == ^bot_instance_id)

  defp parse_limit(nil, default), do: default

  defp parse_limit(value, default) when is_binary(value) do
    case Integer.parse(value) do
      {n, _} when n > 0 and n <= 200 -> n
      _ -> default
    end
  end

  defp parse_limit(value, _default) when is_integer(value) and value > 0 and value <= 200,
    do: value

  defp parse_limit(_, default), do: default
end
