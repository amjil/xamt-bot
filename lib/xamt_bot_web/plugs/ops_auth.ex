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
        with token when is_binary(token) <- bearer_token(conn),
             true <- secure_compare(token, expected) do
          conn
        else
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

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    byte_size(a) == byte_size(b) and Plug.Crypto.secure_compare(a, b)
  end

  defp bearer_token(conn) do
    case get_req_header(conn, "authorization") do
      [header | _] ->
        case String.split(header, " ", parts: 2) do
          [scheme, token] ->
            if String.downcase(scheme) == "bearer", do: String.trim(token), else: nil

          _ ->
            nil
        end

      _ ->
        nil
    end
  end
end
