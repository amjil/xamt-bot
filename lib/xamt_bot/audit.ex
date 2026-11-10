defmodule XamtBot.Audit do
  @moduledoc """
  Execution and outbound request logging helpers.
  """

  alias XamtBot.Repo
  alias XamtBot.Audit.{ExecutionLog, OutboundRequest}

  def start_execution(attrs) do
    attrs =
      attrs
      |> Map.put_new(:status, "started")
      |> Map.put_new(:started_at, DateTime.utc_now())

    %ExecutionLog{}
    |> ExecutionLog.changeset(attrs)
    |> Repo.insert()
  end

  def finish_execution(%ExecutionLog{} = log, attrs) do
    finished_at = Map.get(attrs, :finished_at) || DateTime.utc_now()
    duration_ms = DateTime.diff(finished_at, log.started_at, :millisecond)

    log
    |> ExecutionLog.changeset(
      Map.merge(attrs, %{
        finished_at: finished_at,
        duration_ms: max(duration_ms, 0)
      })
    )
    |> Repo.update()
  end

  def remember_outbound(attrs) do
    %OutboundRequest{}
    |> OutboundRequest.changeset(attrs)
    |> Repo.insert(
      on_conflict: {:replace, [:status, :response_code, :request_id, :metadata, :updated_at]},
      conflict_target: [:bot_instance_id, :idempotency_key],
      returning: true
    )
  end

  def get_outbound(bot_instance_id, idempotency_key) do
    Repo.get_by(OutboundRequest,
      bot_instance_id: bot_instance_id,
      idempotency_key: idempotency_key
    )
  end
end
