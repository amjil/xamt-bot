defmodule XamtBot.Bots.BotInstance do
  @moduledoc """
  Local runtime configuration for a Bot whose identity lives in Xamt.
  """

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  @statuses ~w(active disabled)

  schema "bot_instances" do
    field :external_bot_id, :binary_id
    field :name, :string
    field :handler_key, :string, default: "echo"
    field :status, :string, default: "active"
    field :config, :map, default: %{}
    field :signing_secret, :string
    field :api_token, :string

    has_many :event_inbox, XamtBot.Events.EventInbox
    has_many :execution_logs, XamtBot.Audit.ExecutionLog

    timestamps(type: :utc_datetime_usec)
  end

  def statuses, do: @statuses

  def changeset(instance, attrs) do
    instance
    |> cast(attrs, [
      :external_bot_id,
      :name,
      :handler_key,
      :status,
      :config,
      :signing_secret,
      :api_token
    ])
    |> validate_required([
      :external_bot_id,
      :name,
      :handler_key,
      :status,
      :signing_secret,
      :api_token
    ])
    |> validate_inclusion(:status, @statuses)
    |> validate_length(:name, min: 1, max: 120)
    |> validate_length(:handler_key, min: 1, max: 64)
    |> unique_constraint(:external_bot_id)
  end
end
