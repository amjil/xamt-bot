defmodule XamtBot.Events.EventInbox do
  @moduledoc """
  Durable inbox for signed events delivered by Xamt.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(received queued processing processed failed ignored)

  schema "event_inbox" do
    field :external_event_id, :string
    field :event_type, :string
    field :payload, :map, default: %{}
    field :status, :string, default: "received"
    field :attempt_count, :integer, default: 0
    field :received_at, :utc_datetime_usec
    field :processed_at, :utc_datetime_usec
    field :last_error, :string

    belongs_to :bot_instance, XamtBot.Bots.BotInstance

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(event, attrs) do
    event
    |> cast(attrs, [
      :external_event_id,
      :event_type,
      :bot_instance_id,
      :payload,
      :status,
      :attempt_count,
      :received_at,
      :processed_at,
      :last_error
    ])
    |> validate_required([
      :external_event_id,
      :event_type,
      :bot_instance_id,
      :payload,
      :status,
      :received_at
    ])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:bot_instance_id, :external_event_id],
      name: :event_inbox_bot_instance_id_external_event_id_index
    )
    |> foreign_key_constraint(:bot_instance_id)
  end
end
