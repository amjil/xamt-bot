defmodule XamtBot.Audit.ExecutionLog do
  @moduledoc """
  Records handler execution outcomes. Never store tokens or secrets here.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(started succeeded failed ignored)

  schema "bot_execution_logs" do
    field :handler_key, :string
    field :status, :string
    field :started_at, :utc_datetime_usec
    field :finished_at, :utc_datetime_usec
    field :duration_ms, :integer
    field :error_code, :string
    field :error_message, :string
    field :metadata, :map, default: %{}

    belongs_to :bot_instance, XamtBot.Bots.BotInstance
    belongs_to :event_inbox, XamtBot.Events.EventInbox

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(log, attrs) do
    log
    |> cast(attrs, [
      :bot_instance_id,
      :event_inbox_id,
      :handler_key,
      :status,
      :started_at,
      :finished_at,
      :duration_ms,
      :error_code,
      :error_message,
      :metadata
    ])
    |> validate_required([:bot_instance_id, :handler_key, :status, :started_at])
    |> validate_inclusion(:status, @statuses)
  end
end
