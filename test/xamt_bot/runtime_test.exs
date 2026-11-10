defmodule XamtBot.RuntimeTest do
  use XamtBot.DataCase, async: false

  alias XamtBot.Events
  alias XamtBot.Fixtures
  alias XamtBot.Runtime
  alias XamtBot.Workers.EventProcessor

  setup do
    bot = Fixtures.bot_instance_fixture()
    previous = Application.get_env(:xamt_bot, XamtBot.Clients.XamtClient)

    on_exit(fn ->
      Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient, previous || [])
    end)

    %{bot: bot}
  end

  test "worker processes echo event idempotently", %{bot: bot} do
    Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient,
      base_url: "http://xamt.test",
      receive_timeout: 1_000,
      req_options: [plug: {Req.Test, XamtBot.Clients.XamtClient}]
    )

    Req.Test.stub(XamtBot.Clients.XamtClient, fn conn ->
      Req.Test.json(conn, %{ok: true, data: %{id: Ecto.UUID.generate()}})
    end)

    event_id = Ecto.UUID.generate()

    assert {:ok, :queued, event} =
             Events.accept_delivery(bot, %{
               external_event_id: event_id,
               event_type: "message.created",
               payload: Fixtures.message_created_payload(event_id: event_id, content: "Ping")
             })

    assert :ok = perform_job(EventProcessor, %{event_inbox_id: event.id})
    assert Events.get_event!(event.id).status == "processed"

    assert {:ok, :already_processed} = Runtime.process_event(Events.get_event!(event.id))
  end
end
