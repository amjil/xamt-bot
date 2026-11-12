defmodule XamtBot.Audit do
  @moduledoc """
  Execution and outbound request logging helpers.
  """

  import Ecto.Query

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

  @doc """
  Atomically claims an outbound idempotency slot as `pending`.

  Returns:
  - `{:ok, :claimed, record}` when this caller owns the in-flight request
  - `{:ok, :replayed, record}` when a prior call already succeeded
  - `{:error, :in_flight}` when another caller currently holds `pending`
  """
  def claim_outbound(attrs) do
    now = DateTime.utc_now()
    bot_instance_id = Map.fetch!(attrs, :bot_instance_id)
    idempotency_key = Map.fetch!(attrs, :idempotency_key)
    operation = Map.fetch!(attrs, :operation)
    target_id = Map.get(attrs, :target_id)

    attrs =
      attrs
      |> Map.put(:status, "pending")
      |> Map.put_new(:metadata, %{})

    changeset = OutboundRequest.changeset(%OutboundRequest{}, attrs)

    conflict_query =
      from(o in OutboundRequest,
        where: o.status == "failed",
        update: [
          set: [
            status: "pending",
            operation: ^operation,
            target_id: ^target_id,
            response_code: nil,
            request_id: nil,
            metadata: ^%{},
            updated_at: ^now
          ]
        ]
      )

    case Repo.insert(changeset,
           on_conflict: conflict_query,
           conflict_target: [:bot_instance_id, :idempotency_key],
           returning: true,
           stale_error_field: :status
         ) do
      {:ok, record} ->
        {:ok, :claimed, record}

      {:error, %Ecto.Changeset{errors: errors} = changeset} ->
        if stale_status_error?(errors) do
          case get_outbound(bot_instance_id, idempotency_key) do
            %{status: "succeeded"} = existing ->
              {:ok, :replayed, existing}

            %{status: "pending"} ->
              {:error, :in_flight}

            _other ->
              {:error, :in_flight}
          end
        else
          {:error, changeset}
        end
    end
  end

  defp stale_status_error?(errors) do
    Enum.any?(errors, fn
      {:status, {_, opts}} -> opts[:stale] == true
      _ -> false
    end)
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

  def list_executions(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)
    status = Keyword.get(opts, :status)
    bot_instance_id = Keyword.get(opts, :bot_instance_id)

    ExecutionLog
    |> maybe_filter_status(status)
    |> maybe_filter_bot(bot_instance_id)
    |> order_by([l], desc: l.started_at)
    |> limit(^limit)
    |> Repo.all()
  end

  defp maybe_filter_status(query, nil), do: query
  defp maybe_filter_status(query, ""), do: query
  defp maybe_filter_status(query, status), do: from(q in query, where: q.status == ^status)

  defp maybe_filter_bot(query, nil), do: query
  defp maybe_filter_bot(query, ""), do: query

  defp maybe_filter_bot(query, bot_instance_id) when is_binary(bot_instance_id) do
    case Ecto.UUID.cast(bot_instance_id) do
      {:ok, uuid} -> from(q in query, where: q.bot_instance_id == ^uuid)
      :error -> from(q in query, where: false)
    end
  end

  defp maybe_filter_bot(query, _), do: from(q in query, where: false)
end
