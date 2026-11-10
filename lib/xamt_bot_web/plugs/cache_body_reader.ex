defmodule XamtBotWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Stores the raw request body on `conn.assigns.raw_body` so webhook signature
  verification can hash the exact bytes Xamt signed.
  """

  def read_body(conn, opts) do
    {:ok, body, conn} = Plug.Conn.read_body(conn, opts)
    existing = Map.get(conn.assigns, :raw_body, "")
    conn = Plug.Conn.assign(conn, :raw_body, existing <> body)
    {:ok, body, conn}
  end
end
