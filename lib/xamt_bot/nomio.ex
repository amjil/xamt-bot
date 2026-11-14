defmodule XamtBot.Nomio do
  @moduledoc """
  Nomio → xamt-bot service authentication and bot lookup.

  Contract (from Nomio.Reviews.Webhook):

      signed_payload = "\#{timestamp}.\#{raw_body}"
      header = "sha256=" <> Base.encode16(HMAC-SHA256(secret, signed_payload), case: :lower)

  Headers:

  - `x-nomio-key-id`
  - `x-nomio-timestamp`
  - `x-nomio-signature`
  - `x-nomio-event-id`
  """

  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events.Signature

  @handler_key "nomio_review"

  def handler_key, do: @handler_key

  def config do
    Application.get_env(:xamt_bot, __MODULE__, [])
  end

  def service_key_id do
    Keyword.get(config(), :service_key_id)
  end

  def service_secret do
    Keyword.get(config(), :service_secret)
  end

  def service_keys do
    Keyword.get(config(), :service_keys, %{})
  end

  @doc """
  Verifies Nomio webhook headers against the configured service secret(s).
  """
  def verify_request(raw_body, key_id, timestamp, signature, opts \\ [])
      when is_binary(raw_body) do
    with :ok <- require_present(key_id, :missing_key_id),
         :ok <- require_present(timestamp, :missing_headers),
         :ok <- require_present(signature, :missing_headers),
         {:ok, secret} <- fetch_secret(key_id),
         :ok <- Signature.verify(raw_body, timestamp, signature, secret, opts) do
      :ok
    end
  end

  @doc """
  Returns the active bot instance registered for `nomio_review`.
  """
  def fetch_review_bot do
    case Bots.get_active_by_handler_key(@handler_key) do
      %BotInstance{} = bot -> {:ok, bot}
      nil -> {:error, :bot_not_found}
    end
  end

  defp fetch_secret(key_id) do
    secret =
      Map.get(service_keys(), key_id) ||
        if(key_id == service_key_id(), do: service_secret(), else: nil)

    if is_binary(secret) and String.trim(secret) != "" do
      {:ok, secret}
    else
      if is_nil(service_secret()) or service_secret() == "" do
        {:error, :not_configured}
      else
        {:error, :unknown_key_id}
      end
    end
  end

  defp require_present(value, _reason) when is_binary(value) do
    if String.trim(value) != "", do: :ok, else: {:error, :missing_headers}
  end

  defp require_present(_, reason), do: {:error, reason}
end
