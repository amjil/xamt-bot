defmodule XamtBot.Repo.Migrations.CreateBotRuntimeTables do
  use Ecto.Migration

  def change do
    create table(:bot_instances, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_bot_id, :binary_id, null: false
      add :name, :string, null: false
      add :handler_key, :string, null: false, default: "echo"
      add :status, :string, null: false, default: "active"
      add :config, :map, null: false, default: %{}
      # Used only to verify Xamt webhook signatures; never log or expose.
      add :signing_secret, :string, null: false
      # Bearer token for calling Xamt Bot API; never log or expose.
      add :api_token, :string, null: false

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:bot_instances, [:external_bot_id])
    create index(:bot_instances, [:handler_key])
    create index(:bot_instances, [:status])

    create table(:event_inbox, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :external_event_id, :string, null: false
      add :event_type, :string, null: false

      add :bot_instance_id, references(:bot_instances, type: :binary_id, on_delete: :delete_all),
        null: false

      add :payload, :map, null: false, default: %{}
      add :status, :string, null: false, default: "received"
      add :attempt_count, :integer, null: false, default: 0
      add :received_at, :utc_datetime_usec, null: false
      add :processed_at, :utc_datetime_usec
      add :last_error, :text

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:event_inbox, [:bot_instance_id, :external_event_id])
    create index(:event_inbox, [:bot_instance_id])
    create index(:event_inbox, [:status])
    create index(:event_inbox, [:event_type])
    create index(:event_inbox, [:received_at])

    create table(:bot_execution_logs, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bot_instance_id, references(:bot_instances, type: :binary_id, on_delete: :delete_all),
        null: false

      add :event_inbox_id, references(:event_inbox, type: :binary_id, on_delete: :nilify_all)
      add :handler_key, :string, null: false
      add :status, :string, null: false
      add :started_at, :utc_datetime_usec, null: false
      add :finished_at, :utc_datetime_usec
      add :duration_ms, :integer
      add :error_code, :string
      add :error_message, :text
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create index(:bot_execution_logs, [:bot_instance_id])
    create index(:bot_execution_logs, [:event_inbox_id])
    create index(:bot_execution_logs, [:status])
    create index(:bot_execution_logs, [:started_at])

    create table(:outbound_requests, primary_key: false) do
      add :id, :binary_id, primary_key: true

      add :bot_instance_id, references(:bot_instances, type: :binary_id, on_delete: :delete_all),
        null: false

      add :idempotency_key, :string, null: false
      add :operation, :string, null: false
      add :target_id, :string
      add :status, :string, null: false, default: "pending"
      add :response_code, :integer
      add :request_id, :string
      add :metadata, :map, null: false, default: %{}

      timestamps(type: :utc_datetime_usec)
    end

    create unique_index(:outbound_requests, [:bot_instance_id, :idempotency_key])
    create index(:outbound_requests, [:operation])
    create index(:outbound_requests, [:status])
  end
end
