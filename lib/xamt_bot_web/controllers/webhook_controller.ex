defmodule XamtBotWeb.WebhookController do
  use XamtBotWeb, :controller

  require Logger

  alias XamtBot.Bots
  alias XamtBot.Events
  alias XamtBot.Events.Signature

  @doc """
  POST /webhooks/xamt/:external_bot_id

  Point the Xamt bot's `webhook_url` at this path. Verification uses the
  signing secret stored on the local bot instance.
  """
  def xamt(conn, %{"external_bot_id" => external_bot_id}) do
    raw_body = Map.get(conn.assigns, :raw_body) || ""
    timestamp = first_header(conn, "x-xamt-timestamp")
    signature = first_header(conn, "x-xamt-signature-256")
    delivery_id = first_header(conn, "x-xamt-delivery")
    event_type = first_header(conn, "x-xamt-event")

    with {:ok, bot} <- fetch_bot(external_bot_id),
         :ok <- require_headers(timestamp, signature, delivery_id, event_type),
         :ok <- Signature.verify(raw_body, timestamp, signature, bot.signing_secret),
         {:ok, payload} <- decode_payload(conn, raw_body),
         {:ok, result, event} <-
           Events.accept_delivery(bot, %{
             external_event_id: delivery_id,
             event_type: event_type,
             payload: payload
           }) do
      conn
      |> put_status(:ok)
      |> json(%{
        ok: true,
        result: Atom.to_string(result),
        event_id: event.external_event_id
      })
    else
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "bot_not_found"})

      {:error, :bot_disabled} ->
        # Acknowledge so Xamt does not keep retrying a intentionally disabled bot.
        conn |> put_status(:ok) |> json(%{ok: true, result: "ignored", reason: "bot_disabled"})

      {:error, :missing_headers} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: "missing_headers"})

      {:error, :invalid_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "invalid_timestamp"})

      {:error, :timestamp_out_of_range} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "timestamp_out_of_range"})

      {:error, :invalid_signature} ->
        Logger.warning("webhook signature rejected", bot_id: external_bot_id)
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "invalid_signature"})

      {:error, :invalid_json} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: "invalid_json"})

      {:error, :enqueue_failed} ->
        conn |> put_status(:service_unavailable) |> json(%{ok: false, error: "enqueue_failed"})

      {:error, %Ecto.Changeset{}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "invalid_event"})

      {:error, reason} ->
        Logger.error("webhook accept failed", reason: inspect(reason))
        conn |> put_status(:internal_server_error) |> json(%{ok: false, error: "internal_error"})
    end
  end

  defp fetch_bot(external_bot_id) do
    with {:ok, valid_uuid} <- Ecto.UUID.cast(external_bot_id),
         %Bots.BotInstance{} = bot <- Bots.get_instance_by_external_id(valid_uuid) do
      {:ok, bot}
    else
      _ -> {:error, :not_found}
    end
  end

  defp require_headers(timestamp, signature, delivery_id, event_type) do
    if present?(timestamp) and present?(signature) and present?(delivery_id) and
         present?(event_type) do
      :ok
    else
      {:error, :missing_headers}
    end
  end

  defp decode_payload(_conn, "") do
    {:ok, %{}}
  end

  defp decode_payload(_conn, raw_body) when is_binary(raw_body) do
    case Jason.decode(raw_body) do
      {:ok, map} when is_map(map) -> {:ok, map}
      _ -> {:error, :invalid_json}
    end
  end

  defp first_header(conn, name) do
    case get_req_header(conn, name) do
      [value | _] -> value
      _ -> nil
    end
  end

  defp present?(value) when is_binary(value), do: String.trim(value) != ""
  defp present?(_), do: false
end
