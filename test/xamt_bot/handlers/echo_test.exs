defmodule XamtBot.Handlers.EchoTest do
  use XamtBot.DataCase, async: false

  alias XamtBot.Events
  alias XamtBot.Events.EventInbox
  alias XamtBot.Fixtures
  alias XamtBot.Handlers.Echo
  alias XamtBot.Repo

  setup do
    bot = Fixtures.bot_instance_fixture()
    previous = Application.get_env(:xamt_bot, XamtBot.Clients.XamtClient)

    on_exit(fn ->
      Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient, previous || [])
    end)

    %{bot: bot}
  end

  test "echoes human message.created events via Xamt API", %{bot: bot} do
    test_pid = self()

    Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient,
      base_url: "http://xamt.test",
      receive_timeout: 1_000,
      req_options: [plug: {Req.Test, XamtBot.Clients.XamtClient}]
    )

    Req.Test.stub(XamtBot.Clients.XamtClient, fn conn ->
      {:ok, body, conn} = Plug.Conn.read_body(conn)
      send(test_pid, {:xamt_api, conn.method, conn.request_path, Jason.decode!(body)})
      Req.Test.json(conn, %{ok: true, data: %{id: Ecto.UUID.generate()}})
    end)

    event = insert_event(bot, Fixtures.message_created_payload(content: "Hello"))

    assert {:ok, meta} = Echo.handle_event(bot, event)
    assert meta["channel_id"]
    assert_received {:xamt_api, "POST", path, body}
    assert path =~ "/api/v1/bot/channels/"
    assert body["body"] == "Echo: Hello"
    assert body["nonce"] == "echo:#{event.external_event_id}"
  end

  test "ignores bot-authored messages to prevent loops", %{bot: bot} do
    event = insert_event(bot, Fixtures.message_created_payload(author_type: "bot"))
    assert {:ignored, :bot_author} = Echo.handle_event(bot, event)
  end

  test "ignores unsupported event types", %{bot: bot} do
    event = insert_event(bot, %{}, "channel.created")
    assert {:ignored, :unsupported_event} = Echo.handle_event(bot, event)
  end

  test "treats revoked tokens as permanent failures", %{bot: bot} do
    Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient,
      base_url: "http://xamt.test",
      receive_timeout: 1_000,
      req_options: [plug: {Req.Test, XamtBot.Clients.XamtClient}]
    )

    Req.Test.stub(XamtBot.Clients.XamtClient, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(401, Jason.encode!(%{ok: false, error: "invalid_or_revoked_token"}))
    end)

    event = insert_event(bot, Fixtures.message_created_payload())
    assert {:error, {:unauthorized, "invalid_or_revoked_token"}} = Echo.handle_event(bot, event)
  end

  defp insert_event(bot, payload, type \\ "message.created") do
    event_id = Map.get(payload, "id") || Ecto.UUID.generate()

    {:ok, :queued, event} =
      Events.accept_delivery(bot, %{
        external_event_id: event_id,
        event_type: type,
        payload: payload
      })

    Repo.get!(EventInbox, event.id)
  end
end
