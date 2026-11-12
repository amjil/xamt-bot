defmodule XamtBotWeb.Plugs.CacheBodyReader do
  @moduledoc """
  Stores the raw request body on `conn.assigns.raw_body` so webhook signature
  verification can hash the exact bytes Xamt signed.
  """

  def read_body(conn, opts) do
    case Plug.Conn.read_body(conn, opts) do
      {:ok, body, conn} ->
        conn = append_raw_body(conn, body)
        {:ok, body, conn}

      {:more, body, conn} ->
        conn = append_raw_body(conn, body)
        {:more, body, conn}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp append_raw_body(conn, chunk) do
    existing = Map.get(conn.assigns, :raw_body, "")
    Plug.Conn.assign(conn, :raw_body, existing <> chunk)
  end
end
