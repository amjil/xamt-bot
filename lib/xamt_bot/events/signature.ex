defmodule XamtBot.Events.Signature do
  @moduledoc """
  Verifies Xamt webhook signatures.

  Contract (from Xamt.Bots.DeliveryWorker):

      signed_payload = "\#{timestamp}.\#{raw_body}"
      mac = HMAC-SHA256(signing_secret, signed_payload)
      header = "sha256=" <> Base.encode16(mac, case: :lower)

  Headers:

  - `x-xamt-timestamp`
  - `x-xamt-signature-256`
  - `x-xamt-delivery` (event id)
  - `x-xamt-event` (event type)
  """

  @doc """
  Verifies timestamp window and HMAC signature.
  """
  def verify(raw_body, timestamp, signature, signing_secret, opts \\ [])
      when is_binary(raw_body) and is_binary(timestamp) and is_binary(signature) and
             is_binary(signing_secret) do
    now = Keyword.get(opts, :now, System.system_time(:second))
    tolerance = Keyword.get_lazy(opts, :tolerance, &configured_tolerance/0)

    with :ok <- validate_timestamp(timestamp, now, tolerance),
         :ok <- validate_signature(raw_body, timestamp, signature, signing_secret) do
      :ok
    end
  end

  def sign(raw_body, timestamp, signing_secret)
      when is_binary(raw_body) and is_binary(timestamp) and is_binary(signing_secret) do
    mac =
      :crypto.mac(:hmac, :sha256, signing_secret, "#{timestamp}.#{raw_body}")
      |> Base.encode16(case: :lower)

    "sha256=" <> mac
  end

  defp validate_timestamp(timestamp, now, tolerance) do
    case Integer.parse(timestamp) do
      {ts, ""} ->
        if abs(now - ts) <= tolerance do
          :ok
        else
          {:error, :timestamp_out_of_range}
        end

      _ ->
        {:error, :invalid_timestamp}
    end
  end

  defp validate_signature(raw_body, timestamp, signature, signing_secret) do
    expected = sign(raw_body, timestamp, signing_secret)
    provided = normalize_signature(signature)

    if secure_compare(expected, provided) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  defp normalize_signature("sha256=" <> rest), do: "sha256=" <> String.downcase(rest)
  defp normalize_signature(other) when is_binary(other), do: String.downcase(other)

  defp secure_compare(a, b) when is_binary(a) and is_binary(b) do
    byte_size(a) == byte_size(b) and Plug.Crypto.secure_compare(a, b)
  end

  defp configured_tolerance do
    Application.get_env(:xamt_bot, __MODULE__, [])
    |> Keyword.get(:timestamp_tolerance_seconds, 300)
  end
end
