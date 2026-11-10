defmodule XamtBot.Workers.EventProcessor do
  @moduledoc """
  Oban worker that runs bot handlers for inbox events.
  """

  use Oban.Worker,
    queue: :bot_events,
    max_attempts: 5,
    unique: [
      period: :infinity,
      keys: [:event_inbox_id],
      states: [:available, :scheduled, :executing, :retryable]
    ]

  alias XamtBot.Events
  alias XamtBot.Runtime

  @impl Oban.Worker
  def backoff(%Oban.Job{attempt: attempt}) do
    trunc(:math.pow(2, attempt - 1) * 15)
  end

  @impl Oban.Worker
  def perform(%Oban.Job{args: %{"event_inbox_id" => event_inbox_id}}) do
    event = Events.get_event!(event_inbox_id)

    case Runtime.process_event(event) do
      {:ok, _} -> :ok
      {:cancel, reason} -> {:cancel, reason}
      {:error, reason} -> {:error, reason}
    end
  end
end
