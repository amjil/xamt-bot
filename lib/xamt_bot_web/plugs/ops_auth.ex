defmodule XamtBotWeb.Plugs.OpsAuth do
  @moduledoc """
  Simple bearer-token gate for read-only ops endpoints.

  When `OPS_TOKEN` / `:ops_token` is unset, ops routes are disabled (404),
  so the service does not accidentally expose inbox data.
  """

  import Plug.Conn
  import Phoenix.Controller, only: [json: 2]

  def init(opts), do: opts

  def call(conn, _opts) do
    case configured_token() do
      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{ok: false, error: "ops_disabled"})
        |> halt()

      expected ->
        case bearer_token(conn) do
          ^expected ->
            conn

          _ ->
            conn
            |> put_status(:unauthorized)
            |> json(%{ok: false, error: "unauthorized"})
            |> halt()
        end
    end
  end

  defp configured_token do
    case Application.get_env(:xamt_bot, :ops_token) do
      token when is_binary(token) and token != "" -> token
      _ -> nil
    end
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      ["Bearer " <> token] -> String.trim(token)
      _ -> nil
    end
  end
end
