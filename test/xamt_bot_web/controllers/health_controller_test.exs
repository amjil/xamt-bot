defmodule XamtBotWeb.HealthControllerTest do
  use XamtBotWeb.ConnCase, async: true

  test "GET /health", %{conn: conn} do
    conn = get(conn, ~p"/health")
    assert %{"ok" => true, "service" => "xamt-bot", "status" => "up"} = json_response(conn, 200)
  end
end
