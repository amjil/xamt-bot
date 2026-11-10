defmodule XamtBot.EventsTest do
  use XamtBot.DataCase, async: true

  alias XamtBot.Events
  alias XamtBot.Fixtures

  setup do
    bot = Fixtures.bot_instance_fixture()
    %{bot: bot}
  end

  test "accept_delivery persists and queues a new event", %{bot: bot} do
    event_id = Ecto.UUID.generate()
    payload = Fixtures.message_created_payload(event_id: event_id)

    assert {:ok, :queued, event} =
             Events.accept_delivery(bot, %{
               external_event_id: event_id,
               event_type: "message.created",
               payload: payload
             })

    assert event.status == "queued"
    assert event.external_event_id == event_id

    assert [%Oban.Job{args: %{"event_inbox_id" => inbox_id}}] =
             all_enqueued(worker: XamtBot.Workers.EventProcessor)

    assert inbox_id == event.id
  end

  test "accept_delivery deduplicates by external event id", %{bot: bot} do
    event_id = Ecto.UUID.generate()

    attrs = %{
      external_event_id: event_id,
      event_type: "message.created",
      payload: Fixtures.message_created_payload(event_id: event_id)
    }

    assert {:ok, :queued, first} = Events.accept_delivery(bot, attrs)
    assert {:ok, :duplicate, second} = Events.accept_delivery(bot, attrs)
    assert first.id == second.id
    assert length(all_enqueued(worker: XamtBot.Workers.EventProcessor)) == 1
  end

  test "accept_delivery rejects disabled bots", %{bot: bot} do
    {:ok, bot} = XamtBot.Bots.update_instance(bot, %{"status" => "disabled"})
    event_id = Ecto.UUID.generate()

    assert {:error, :bot_disabled} =
             Events.accept_delivery(bot, %{
               external_event_id: event_id,
               event_type: "message.created",
               payload: Fixtures.message_created_payload(event_id: event_id)
             })
  end
end
