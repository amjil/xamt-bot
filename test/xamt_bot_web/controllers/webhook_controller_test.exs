defmodule XamtBotWeb.WebhookControllerTest do
  use XamtBotWeb.ConnCase, async: true

  alias XamtBot.Events.Signature
  alias XamtBot.Fixtures

  setup do
    bot = Fixtures.bot_instance_fixture()
    %{bot: bot}
  end

  test "accepts a signed webhook and queues the event", %{conn: conn, bot: bot} do
    event_id = Ecto.UUID.generate()
    payload = Fixtures.message_created_payload(event_id: event_id)
    body = Jason.encode!(payload)
    ts = Integer.to_string(System.system_time(:second))
    sig = Signature.sign(body, ts, bot.signing_secret)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-xamt-timestamp", ts)
      |> put_req_header("x-xamt-signature-256", sig)
      |> put_req_header("x-xamt-delivery", event_id)
      |> put_req_header("x-xamt-event", "message.created")
      |> post(~p"/webhooks/xamt/#{bot.external_bot_id}", body)

    assert %{"ok" => true, "result" => "queued", "event_id" => ^event_id} =
             json_response(conn, 200)

    assert length(all_enqueued(worker: XamtBot.Workers.EventProcessor)) == 1
  end

  test "returns 404 for non-uuid external bot ids", %{conn: conn} do
    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-xamt-timestamp", "1")
      |> put_req_header("x-xamt-signature-256", "sha256=00")
      |> put_req_header("x-xamt-delivery", Ecto.UUID.generate())
      |> put_req_header("x-xamt-event", "message.created")
      |> post(~p"/webhooks/xamt/not-a-uuid", "{}")

    assert %{"ok" => false, "error" => "bot_not_found"} = json_response(conn, 404)
  end

  test "rejects invalid signatures", %{conn: conn, bot: bot} do
    event_id = Ecto.UUID.generate()
    body = Jason.encode!(Fixtures.message_created_payload(event_id: event_id))
    ts = Integer.to_string(System.system_time(:second))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-xamt-timestamp", ts)
      |> put_req_header("x-xamt-signature-256", "sha256=00")
      |> put_req_header("x-xamt-delivery", event_id)
      |> put_req_header("x-xamt-event", "message.created")
      |> post(~p"/webhooks/xamt/#{bot.external_bot_id}", body)

    assert %{"ok" => false, "error" => "invalid_signature"} = json_response(conn, 401)
  end

  test "deduplicates repeated deliveries", %{bot: bot} do
    event_id = Ecto.UUID.generate()
    payload = Fixtures.message_created_payload(event_id: event_id)
    body = Jason.encode!(payload)
    ts = Integer.to_string(System.system_time(:second))
    sig = Signature.sign(body, ts, bot.signing_secret)

    build = fn ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-xamt-timestamp", ts)
      |> put_req_header("x-xamt-signature-256", sig)
      |> put_req_header("x-xamt-delivery", event_id)
      |> put_req_header("x-xamt-event", "message.created")
      |> post(~p"/webhooks/xamt/#{bot.external_bot_id}", body)
    end

    assert %{"result" => "queued"} = json_response(build.(), 200)
    assert %{"result" => "duplicate"} = json_response(build.(), 200)
    assert length(all_enqueued(worker: XamtBot.Workers.EventProcessor)) == 1
  end
end
