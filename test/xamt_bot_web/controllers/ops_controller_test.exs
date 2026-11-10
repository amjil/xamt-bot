defmodule XamtBotWeb.OpsControllerTest do
  use XamtBotWeb.ConnCase, async: true

  alias XamtBot.Events
  alias XamtBot.Fixtures

  setup do
    bot = Fixtures.bot_instance_fixture()
    event_id = Ecto.UUID.generate()

    {:ok, :queued, event} =
      Events.accept_delivery(bot, %{
        external_event_id: event_id,
        event_type: "message.created",
        payload: Fixtures.message_created_payload(event_id: event_id)
      })

    %{bot: bot, event: event}
  end

  test "lists bots with ops token", %{conn: conn, bot: bot} do
    conn =
      conn
      |> put_req_header("authorization", "Bearer test-ops-token")
      |> get(~p"/ops/bots")

    assert %{"ok" => true, "data" => data} = json_response(conn, 200)
    assert Enum.any?(data, &(&1["id"] == bot.id))
    refute Enum.any?(data, &Map.has_key?(&1, "api_token"))
    refute Enum.any?(data, &Map.has_key?(&1, "signing_secret"))
  end

  test "lists events and executions", %{conn: conn, bot: bot, event: event} do
    events_conn =
      conn
      |> put_req_header("authorization", "Bearer test-ops-token")
      |> get(~p"/ops/events?bot_instance_id=#{bot.id}")

    assert %{"ok" => true, "data" => [row | _]} = json_response(events_conn, 200)
    assert row["id"] == event.id
    assert row["status"] == "queued"

    exec_conn =
      build_conn()
      |> put_req_header("authorization", "Bearer test-ops-token")
      |> get(~p"/ops/executions")

    assert %{"ok" => true, "data" => _} = json_response(exec_conn, 200)
  end

  test "rejects missing ops token", %{conn: conn} do
    conn = get(conn, ~p"/ops/bots")
    assert %{"ok" => false, "error" => "unauthorized"} = json_response(conn, 401)
  end

  test "disables ops when token unset", %{conn: conn} do
    previous = Application.get_env(:xamt_bot, :ops_token)
    Application.put_env(:xamt_bot, :ops_token, nil)
    on_exit(fn -> Application.put_env(:xamt_bot, :ops_token, previous) end)

    conn =
      conn
      |> put_req_header("authorization", "Bearer anything")
      |> get(~p"/ops/bots")

    assert %{"ok" => false, "error" => "ops_disabled"} = json_response(conn, 404)
  end
end
