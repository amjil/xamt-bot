defmodule XamtBot.Handlers.NomioReviewTest do
  use XamtBot.DataCase, async: false

  alias XamtBot.Events
  alias XamtBot.Events.EventInbox
  alias XamtBot.Fixtures
  alias XamtBot.Handlers.NomioReview
  alias XamtBot.Repo

  setup do
    bot =
      Fixtures.bot_instance_fixture(%{
        "handler_key" => "nomio_review",
        "config" => %{"default_channel_id" => Ecto.UUID.generate()}
      })

    previous = Application.get_env(:xamt_bot, XamtBot.Clients.XamtClient)

    on_exit(fn ->
      Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient, previous || [])
    end)

    %{bot: bot}
  end

  test "forwards nomio.review.created to Xamt channel", %{bot: bot} do
    test_pid = self()
    channel_id = bot.config["default_channel_id"]

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

    event =
      insert_event(bot, %{
        "data" => %{
          "title" => "费用报销",
          "submitter" => "alice",
          "status" => "待审核",
          "summary" => "差旅报销 1200",
          "review_url" => "https://nomio.example/reviews/1"
        }
      })

    assert {:ok, meta} = NomioReview.handle_event(bot, event)
    assert meta["channel_id"] == channel_id
    assert meta["message_id"]

    assert_received {:xamt_api, "POST", path, body}
    assert path =~ "/api/v1/bot/channels/#{channel_id}/messages"
    assert body["nonce"] == "nomio_review:#{event.external_event_id}"
    assert body["body"] =~ "费用报销"
    assert body["body"] =~ "alice"
    assert body["body"] =~ "差旅报销 1200"
    assert body["body"] =~ "https://nomio.example/reviews/1"
  end

  test "prefers payload channel_id over bot default", %{bot: bot} do
    test_pid = self()
    payload_channel_id = Ecto.UUID.generate()

    Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient,
      base_url: "http://xamt.test",
      receive_timeout: 1_000,
      req_options: [plug: {Req.Test, XamtBot.Clients.XamtClient}]
    )

    Req.Test.stub(XamtBot.Clients.XamtClient, fn conn ->
      send(test_pid, {:xamt_api, conn.request_path})
      Req.Test.json(conn, %{ok: true, data: %{id: Ecto.UUID.generate()}})
    end)

    event =
      insert_event(bot, %{
        "data" => %{
          "channel_id" => payload_channel_id,
          "title" => "合同审核"
        }
      })

    assert {:ok, meta} = NomioReview.handle_event(bot, event)
    assert meta["channel_id"] == payload_channel_id
    assert_received {:xamt_api, path}
    assert path =~ payload_channel_id
  end

  test "returns missing_channel_id when neither payload nor config provides one" do
    bot = Fixtures.bot_instance_fixture(%{"handler_key" => "nomio_review", "config" => %{}})
    event = insert_event(bot, %{"data" => %{"title" => "无频道"}})
    assert {:error, :missing_channel_id} = NomioReview.handle_event(bot, event)
  end

  test "ignores unsupported event types", %{bot: bot} do
    event = insert_event(bot, %{}, "message.created")
    assert {:ignored, :unsupported_event} = NomioReview.handle_event(bot, event)
  end

  test "retries on rate limited responses", %{bot: bot} do
    Application.put_env(:xamt_bot, XamtBot.Clients.XamtClient,
      base_url: "http://xamt.test",
      receive_timeout: 1_000,
      req_options: [plug: {Req.Test, XamtBot.Clients.XamtClient}]
    )

    Req.Test.stub(XamtBot.Clients.XamtClient, fn conn ->
      conn
      |> Plug.Conn.put_resp_content_type("application/json")
      |> Plug.Conn.send_resp(429, Jason.encode!(%{ok: false, error: "rate_limited"}))
    end)

    event = insert_event(bot, %{"data" => %{"title" => "限流"}})

    assert {:error, :retry, {:rate_limited, "rate_limited"}} =
             NomioReview.handle_event(bot, event)
  end

  defp insert_event(bot, payload, type \\ "nomio.review.created") do
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
