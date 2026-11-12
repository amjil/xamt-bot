defmodule XamtBot.Clients.XamtClient do
  @moduledoc """
  HTTP client for the Xamt Bot REST API (`/api/v1/bot`).

  Uses Req. Handler code should go through this module instead of issuing
  ad-hoc HTTP calls.
  """

  require Logger
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Audit

  @doc """
  GET /api/v1/bot/me
  """
  def me(%BotInstance{} = bot, opts \\ []) do
    request(bot, :get, "/api/v1/bot/me", opts)
  end

  @doc """
  POST /api/v1/bot/channels/:channel_id/messages

  Body fields accepted by Xamt: `body` (or `content`), optional `reply_to_id`,
  optional `nonce` for idempotency.
  """
  def create_message(%BotInstance{} = bot, channel_id, attrs, opts \\ [])
      when is_binary(channel_id) and is_map(attrs) do
    body =
      %{
        "body" =>
          Map.get(attrs, :body) || Map.get(attrs, "body") || Map.get(attrs, :content) ||
            Map.get(attrs, "content"),
        "reply_to_id" => Map.get(attrs, :reply_to_id) || Map.get(attrs, "reply_to_id"),
        "nonce" => Map.get(attrs, :nonce) || Map.get(attrs, "nonce")
      }
      |> Enum.reject(fn {_k, v} -> is_nil(v) end)
      |> Map.new()

    opts =
      opts
      |> Keyword.put_new(:operation, "messages.create")
      |> Keyword.put_new(:target_id, channel_id)
      |> maybe_put_idempotency(body["nonce"])

    encoded_channel_id = URI.encode(channel_id, &URI.char_unreserved?/1)

    request(
      bot,
      :post,
      "/api/v1/bot/channels/#{encoded_channel_id}/messages",
      Keyword.put(opts, :json, body)
    )
  end

  def request(%BotInstance{} = bot, method, path, opts \\ []) do
    base_url = Keyword.get_lazy(opts, :base_url, &configured_base_url/0)
    timeout = Keyword.get_lazy(opts, :receive_timeout, &configured_timeout/0)
    json = Keyword.get(opts, :json)
    operation = Keyword.get(opts, :operation, "#{method}:#{path}")
    target_id = Keyword.get(opts, :target_id)
    idempotency_key = Keyword.get(opts, :idempotency_key)

    req_options =
      opts
      |> Keyword.get(:req_options, [])
      |> then(&Keyword.merge(default_req_options(), &1))

    if idempotency_key do
      case Audit.claim_outbound(%{
             bot_instance_id: bot.id,
             idempotency_key: idempotency_key,
             operation: operation,
             target_id: target_id
           }) do
        {:ok, :claimed, _pending} ->
          do_request(
            bot,
            method,
            base_url,
            path,
            json,
            timeout,
            operation,
            target_id,
            idempotency_key,
            req_options
          )

        {:ok, :replayed, existing} ->
          {:ok, :replayed, existing}

        {:error, :in_flight} ->
          {:error, :in_flight}

        {:error, reason} ->
          {:error, reason}
      end
    else
      do_request(
        bot,
        method,
        base_url,
        path,
        json,
        timeout,
        operation,
        target_id,
        idempotency_key,
        req_options
      )
    end
  end

  defp do_request(
         bot,
         method,
         base_url,
         path,
         json,
         timeout,
         operation,
         target_id,
         idempotency_key,
         req_options
       ) do
    url = join_url(base_url, path)

    headers = [
      {"authorization", "Bearer #{bot.api_token}"},
      {"accept", "application/json"},
      {"user-agent", "XamtBot/0.1"}
    ]

    req =
      [
        method: method,
        url: url,
        headers: headers,
        receive_timeout: timeout,
        redirect: false,
        # Retry ownership belongs to Oban; avoid nested sleep/retry in-process.
        retry: false
      ]
      |> maybe_put(:json, json)
      |> Keyword.merge(req_options)

    start = System.monotonic_time(:millisecond)

    result =
      case Req.request(req) do
        {:ok, %Req.Response{status: status, body: body, headers: resp_headers}}
        when status in 200..299 ->
          duration = System.monotonic_time(:millisecond) - start
          request_id = header_value(resp_headers, "x-request-id")

          _ =
            maybe_track_outbound(
              bot,
              idempotency_key,
              operation,
              target_id,
              "succeeded",
              status,
              request_id,
              %{
                "duration_ms" => duration
              }
            )

          Logger.info("xamt api ok",
            bot_id: bot.external_bot_id,
            operation: operation,
            status: status,
            duration_ms: duration
          )

          {:ok, %{status: status, body: body, request_id: request_id}}

        {:ok, %Req.Response{status: status, body: body}} ->
          duration = System.monotonic_time(:millisecond) - start
          error = normalize_error(status, body)

          _ =
            maybe_track_outbound(
              bot,
              idempotency_key,
              operation,
              target_id,
              "failed",
              status,
              nil,
              %{
                "duration_ms" => duration,
                "error" => error_code(error)
              }
            )

          Logger.warning("xamt api error",
            bot_id: bot.external_bot_id,
            operation: operation,
            status: status,
            duration_ms: duration
          )

          {:error, error}

        {:error, reason} ->
          _ =
            maybe_track_outbound(
              bot,
              idempotency_key,
              operation,
              target_id,
              "failed",
              nil,
              nil,
              %{
                "error" => "transport_error"
              }
            )

          {:error, {:transport_error, reason}}
      end

    result
  end

  defp maybe_track_outbound(_bot, nil, _op, _target, _status, _code, _req_id, _meta), do: :ok

  defp maybe_track_outbound(bot, key, operation, target_id, status, code, request_id, metadata) do
    Audit.remember_outbound(%{
      bot_instance_id: bot.id,
      idempotency_key: key,
      operation: operation,
      target_id: target_id,
      status: status,
      response_code: code,
      request_id: request_id,
      metadata: metadata
    })
  end

  defp normalize_error(401, _body), do: {:unauthorized, "invalid_or_revoked_token"}
  defp normalize_error(403, body), do: {:forbidden, error_from_body(body)}
  defp normalize_error(404, body), do: {:not_found, error_from_body(body)}
  defp normalize_error(429, _body), do: {:rate_limited, "rate_limited"}
  defp normalize_error(status, body) when status >= 500, do: {:server_error, status, body}
  defp normalize_error(status, body), do: {:http_error, status, body}

  defp error_from_body(%{"error" => error}) when is_binary(error), do: error
  defp error_from_body(_), do: "unknown_error"

  defp error_code({:unauthorized, code}), do: code
  defp error_code({:forbidden, code}), do: code
  defp error_code({:not_found, code}), do: code
  defp error_code({:rate_limited, code}), do: code
  defp error_code({:server_error, status, _}), do: "server_error_#{status}"
  defp error_code({:http_error, status, _}), do: "http_error_#{status}"
  defp error_code(_), do: "unknown"

  defp maybe_put_idempotency(opts, nil), do: opts
  defp maybe_put_idempotency(opts, nonce), do: Keyword.put_new(opts, :idempotency_key, nonce)

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp join_url(base, path) do
    String.trim_trailing(base, "/") <> "/" <> String.trim_leading(path, "/")
  end

  defp header_value(headers, name) do
    headers
    |> Enum.find_value(fn
      {key, value} ->
        if String.downcase(to_string(key)) == name do
          case value do
            [first | _] -> first
            other when is_binary(other) -> other
            _ -> nil
          end
        end
    end)
  end

  defp configured_base_url do
    Application.get_env(:xamt_bot, __MODULE__, [])
    |> Keyword.get(:base_url, "http://127.0.0.1:4000")
  end

  defp configured_timeout do
    Application.get_env(:xamt_bot, __MODULE__, [])
    |> Keyword.get(:receive_timeout, 10_000)
  end

  defp default_req_options do
    Application.get_env(:xamt_bot, __MODULE__, [])
    |> Keyword.get(:req_options, [])
  end
end
