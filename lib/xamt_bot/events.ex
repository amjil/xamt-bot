defmodule XamtBot.Events do
  @moduledoc """
  Event inbox persistence, deduplication, and job enqueueing.
  """

  require Logger
  import Ecto.Query

  alias XamtBot.Repo
  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events.EventInbox
  alias XamtBot.Workers.EventProcessor

  @doc """
  Accepts a verified webhook delivery.

  Returns:
  - `{:ok, :queued, event}` for a newly accepted event
  - `{:ok, :duplicate, event}` when the Event ID was already stored
  - `{:error, reason}` for permanent rejection cases
  """
  def accept_delivery(%BotInstance{} = bot, attrs) do
    external_event_id = Map.fetch!(attrs, :external_event_id)
    event_type = Map.fetch!(attrs, :event_type)
    payload = Map.fetch!(attrs, :payload)

    if Bots.active?(bot) do
      insert_and_enqueue(bot, external_event_id, event_type, payload)
    else
      {:error, :bot_disabled}
    end
  end

  def get_event!(id), do: Repo.get!(EventInbox, id)

  def get_by_external_id(external_event_id) do
    Repo.get_by(EventInbox, external_event_id: external_event_id)
  end

  def mark_processing(%EventInbox{} = event) do
    event
    |> EventInbox.changeset(%{
      status: "processing",
      attempt_count: event.attempt_count + 1
    })
    |> Repo.update()
  end

  def mark_processed(%EventInbox{} = event) do
    event
    |> EventInbox.changeset(%{
      status: "processed",
      processed_at: DateTime.utc_now(),
      last_error: nil
    })
    |> Repo.update()
  end

  def mark_ignored(%EventInbox{} = event, reason) when is_binary(reason) do
    event
    |> EventInbox.changeset(%{
      status: "ignored",
      processed_at: DateTime.utc_now(),
      last_error: reason
    })
    |> Repo.update()
  end

  def mark_failed(%EventInbox{} = event, reason) when is_binary(reason) do
    event
    |> EventInbox.changeset(%{
      status: "failed",
      last_error: String.slice(reason, 0, 2000)
    })
    |> Repo.update()
  end

  def list_recent(opts \\ []) do
    limit = Keyword.get(opts, :limit, 50)

    EventInbox
    |> order_by([e], desc: e.received_at)
    |> limit(^limit)
    |> preload(:bot_instance)
    |> Repo.all()
  end

  defp insert_and_enqueue(bot, external_event_id, event_type, payload) do
    now = DateTime.utc_now()

    changeset =
      EventInbox.changeset(%EventInbox{}, %{
        external_event_id: external_event_id,
        event_type: event_type,
        bot_instance_id: bot.id,
        payload: payload,
        status: "queued",
        received_at: now
      })

    Ecto.Multi.new()
    |> Ecto.Multi.insert(:event, changeset)
    |> Oban.insert(:job, fn %{event: event} ->
      EventProcessor.new(%{event_inbox_id: event.id})
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{event: event}} ->
        {:ok, :queued, event}

      {:error, :event, %Ecto.Changeset{errors: errors} = changeset, _} ->
        if unique_event_conflict?(errors) do
          {:ok, :duplicate, get_by_external_id(external_event_id)}
        else
          {:error, changeset}
        end

      {:error, :job, reason, _} ->
        Logger.error("failed to enqueue event processor",
          event_id: external_event_id,
          reason: inspect(reason)
        )

        {:error, :enqueue_failed}
    end
  end

  defp unique_event_conflict?(errors) do
    Enum.any?(errors, fn
      {:external_event_id, {_, opts}} -> opts[:constraint] == :unique
      _ -> false
    end)
  end
end
