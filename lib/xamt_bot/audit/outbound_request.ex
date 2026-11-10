defmodule XamtBot.Audit.OutboundRequest do
  @moduledoc """
  Tracks outbound Xamt API calls for idempotency and debugging.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(pending succeeded failed)

  schema "outbound_requests" do
    field :idempotency_key, :string
    field :operation, :string
    field :target_id, :string
    field :status, :string, default: "pending"
    field :response_code, :integer
    field :request_id, :string
    field :metadata, :map, default: %{}

    belongs_to :bot_instance, XamtBot.Bots.BotInstance

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(request, attrs) do
    request
    |> cast(attrs, [
      :bot_instance_id,
      :idempotency_key,
      :operation,
      :target_id,
      :status,
      :response_code,
      :request_id,
      :metadata
    ])
    |> validate_required([:bot_instance_id, :idempotency_key, :operation, :status])
    |> validate_inclusion(:status, @statuses)
    |> unique_constraint([:bot_instance_id, :idempotency_key])
  end
end
