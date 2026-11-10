defmodule XamtBotWeb.HealthController do
  use XamtBotWeb, :controller

  def show(conn, _params) do
    json(conn, %{ok: true, service: "xamt-bot", status: "up"})
  end
end
