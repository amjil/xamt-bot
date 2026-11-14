defmodule XamtBotWeb.WebhookController do
  use XamtBotWeb, :controller

  require Logger

  alias XamtBot.Bots
  alias XamtBot.Events
  alias XamtBot.Events.Signature
  alias XamtBot.Nomio

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
      error ->
        respond_webhook_error(conn, error, bot_id: external_bot_id)
    end
  end

  @doc """
  POST /webhooks/nomio/reviews

  Point Nomio's `XAMT_BOT_BASE_URL` at this service root. Nomio appends this
  path and signs with `XAMT_SERVICE_KEY_ID` / `XAMT_SERVICE_SECRET`.
  """
  def nomio_reviews(conn, _params) do
    raw_body = Map.get(conn.assigns, :raw_body) || ""
    key_id = first_header(conn, "x-nomio-key-id")
    timestamp = first_header(conn, "x-nomio-timestamp")
    signature = first_header(conn, "x-nomio-signature")
    event_id = first_header(conn, "x-nomio-event-id")

    with :ok <- require_nomio_headers(key_id, timestamp, signature, event_id),
         :ok <- Nomio.verify_request(raw_body, key_id, timestamp, signature),
         {:ok, payload} <- decode_payload(conn, raw_body) do
      if connectivity_test?(payload) do
        conn
        |> put_status(:accepted)
        |> json(%{ok: true, result: "connectivity_ok", event_id: event_id})
      else
        accept_nomio_delivery(conn, event_id, payload)
      end
    else
      error ->
        respond_webhook_error(conn, error, source: "nomio")
    end
  end

  defp accept_nomio_delivery(conn, event_id, payload) do
    event_type = resolve_nomio_event_type(payload)

    with {:ok, bot} <- Nomio.fetch_review_bot(),
         {:ok, result, event} <-
           Events.accept_delivery(bot, %{
             external_event_id: event_id,
             event_type: event_type,
             payload: payload
           }) do
      conn
      |> put_status(:accepted)
      |> json(%{
        ok: true,
        result: Atom.to_string(result),
        event_id: event.external_event_id
      })
    else
      {:error, :bot_disabled} ->
        conn
        |> put_status(:accepted)
        |> json(%{ok: true, result: "ignored", reason: "bot_disabled"})

      error ->
        respond_webhook_error(conn, error, source: "nomio")
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

  defp require_nomio_headers(key_id, timestamp, signature, event_id) do
    if present?(key_id) and present?(timestamp) and present?(signature) and present?(event_id) do
      :ok
    else
      {:error, :missing_headers}
    end
  end

  defp connectivity_test?(payload) when is_map(payload) do
    data = Map.get(payload, "data") || %{}
    Map.get(data, "operation") == "connectivity_test"
  end

  defp resolve_nomio_event_type(payload) when is_map(payload) do
    Map.get(payload, "event_type") ||
      Map.get(payload, "type") ||
      "review.updated"
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

  defp respond_webhook_error(conn, error, meta) do
    case error do
      {:error, :not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "bot_not_found"})

      {:error, :bot_not_found} ->
        conn |> put_status(:not_found) |> json(%{ok: false, error: "bot_not_found"})

      {:error, :bot_disabled} ->
        # Acknowledge so the sender does not keep retrying an intentionally disabled bot.
        conn |> put_status(:ok) |> json(%{ok: true, result: "ignored", reason: "bot_disabled"})

      {:error, :missing_headers} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: "missing_headers"})

      {:error, :missing_key_id} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: "missing_key_id"})

      {:error, :not_configured} ->
        conn |> put_status(:service_unavailable) |> json(%{ok: false, error: "not_configured"})

      {:error, :unknown_key_id} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "unknown_key_id"})

      {:error, :invalid_timestamp} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "invalid_timestamp"})

      {:error, :timestamp_out_of_range} ->
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "timestamp_out_of_range"})

      {:error, :invalid_signature} ->
        Logger.warning("webhook signature rejected", meta)
        conn |> put_status(:unauthorized) |> json(%{ok: false, error: "invalid_signature"})

      {:error, :invalid_json} ->
        conn |> put_status(:bad_request) |> json(%{ok: false, error: "invalid_json"})

      {:error, :enqueue_failed} ->
        conn |> put_status(:service_unavailable) |> json(%{ok: false, error: "enqueue_failed"})

      {:error, %Ecto.Changeset{}} ->
        conn |> put_status(:unprocessable_entity) |> json(%{ok: false, error: "invalid_event"})

      {:error, reason} ->
        Logger.error("webhook accept failed", Keyword.put(meta, :reason, inspect(reason)))
        conn |> put_status(:internal_server_error) |> json(%{ok: false, error: "internal_error"})
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
