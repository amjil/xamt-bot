defmodule XamtBotWeb.NomioWebhookControllerTest do
  use XamtBotWeb.ConnCase, async: true

  alias XamtBot.Events.Signature
  alias XamtBot.Fixtures

  @key_id "nomio-v1"
  @secret "dev-nomio-xamt-secret"

  setup do
    bot =
      Fixtures.bot_instance_fixture(%{
        "handler_key" => "nomio_review",
        "config" => %{"default_channel_id" => Ecto.UUID.generate()}
      })

    %{bot: bot}
  end

  test "accepts a signed Nomio review event and queues it", %{conn: conn} do
    event_id = "evt_" <> Ecto.UUID.generate()
    payload = review_created_payload(event_id)
    body = Jason.encode!(payload)
    {ts, sig} = sign(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-nomio-key-id", @key_id)
      |> put_req_header("x-nomio-timestamp", ts)
      |> put_req_header("x-nomio-signature", sig)
      |> put_req_header("x-nomio-event-id", event_id)
      |> post(~p"/webhooks/nomio/reviews", body)

    assert %{"ok" => true, "result" => "queued", "event_id" => ^event_id} =
             json_response(conn, 202)

    assert length(all_enqueued(worker: XamtBot.Workers.EventProcessor)) == 1
  end

  test "acks connectivity tests without enqueueing", %{conn: conn} do
    event_id = "evt_test_" <> Ecto.UUID.generate()

    payload = %{
      "event_id" => event_id,
      "event_type" => "review.updated",
      "schema_version" => 1,
      "source" => "nomio",
      "data" => %{
        "operation" => "connectivity_test",
        "status" => "pending",
        "destination" => %{"channel_id" => Ecto.UUID.generate()}
      }
    }

    body = Jason.encode!(payload)
    {ts, sig} = sign(body)

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-nomio-key-id", @key_id)
      |> put_req_header("x-nomio-timestamp", ts)
      |> put_req_header("x-nomio-signature", sig)
      |> put_req_header("x-nomio-event-id", event_id)
      |> post(~p"/webhooks/nomio/reviews", body)

    assert %{"ok" => true, "result" => "connectivity_ok", "event_id" => ^event_id} =
             json_response(conn, 202)

    assert all_enqueued(worker: XamtBot.Workers.EventProcessor) == []
  end

  test "rejects invalid signatures", %{conn: conn} do
    event_id = Ecto.UUID.generate()
    body = Jason.encode!(review_created_payload(event_id))
    ts = Integer.to_string(System.system_time(:second))

    conn =
      conn
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-nomio-key-id", @key_id)
      |> put_req_header("x-nomio-timestamp", ts)
      |> put_req_header("x-nomio-signature", "sha256=00")
      |> put_req_header("x-nomio-event-id", event_id)
      |> post(~p"/webhooks/nomio/reviews", body)

    assert %{"ok" => false, "error" => "invalid_signature"} = json_response(conn, 401)
  end

  test "deduplicates repeated Nomio deliveries" do
    event_id = "evt_" <> Ecto.UUID.generate()
    body = Jason.encode!(review_created_payload(event_id))
    {ts, sig} = sign(body)

    build = fn ->
      build_conn()
      |> put_req_header("content-type", "application/json")
      |> put_req_header("x-nomio-key-id", @key_id)
      |> put_req_header("x-nomio-timestamp", ts)
      |> put_req_header("x-nomio-signature", sig)
      |> put_req_header("x-nomio-event-id", event_id)
      |> post(~p"/webhooks/nomio/reviews", body)
    end

    assert %{"result" => "queued"} = json_response(build.(), 202)
    assert %{"result" => "duplicate"} = json_response(build.(), 202)
    assert length(all_enqueued(worker: XamtBot.Workers.EventProcessor)) == 1
  end

  defp sign(body) do
    ts = Integer.to_string(System.system_time(:second))
    {ts, Signature.sign(body, ts, @secret)}
  end

  defp review_created_payload(event_id) do
    %{
      "event_id" => event_id,
      "event_type" => "review.created",
      "schema_version" => 1,
      "occurred_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "source" => "nomio",
      "data" => %{
        "review_task_id" => Ecto.UUID.generate(),
        "review_round" => 1,
        "status" => "pending",
        "content" => %{
          "content_type" => "article",
          "title" => "费用报销",
          "summary" => "差旅报销 1200",
          "author_display_name" => "alice",
          "review_url" => "https://nomio.example/admin/reviews/1"
        },
        "destination" => %{
          "server_id" => Ecto.UUID.generate(),
          "channel_id" => Ecto.UUID.generate()
        }
      }
    }
  end
end
