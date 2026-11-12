defmodule XamtBot.Repo.Migrations.FixEventInboxUniqueIndexAndAddTimestampIndexes do
  use Ecto.Migration

  def change do
    drop_if_exists unique_index(:event_inbox, [:external_event_id])

    create_if_not_exists unique_index(:event_inbox, [:bot_instance_id, :external_event_id])
    create_if_not_exists index(:event_inbox, [:received_at])
    create_if_not_exists index(:bot_execution_logs, [:started_at])
  end
end
