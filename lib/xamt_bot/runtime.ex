defmodule XamtBot.Runtime do
  @moduledoc """
  Dispatches inbox events to the registered handler for a bot instance.
  """

  require Logger

  alias XamtBot.Audit
  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events
  alias XamtBot.Events.EventInbox
  alias XamtBot.Runtime.Registry

  @doc """
  Processes a single inbox event end-to-end.
  """
  def process_event(%EventInbox{} = event) do
    event = XamtBot.Repo.preload(event, :bot_instance)
    bot = event.bot_instance

    cond do
      is_nil(bot) ->
        {:cancel, :bot_missing}

      not Bots.active?(bot) ->
        _ = Events.mark_ignored(event, "bot_disabled")
        {:ok, :ignored}

      event.status == "processed" ->
        {:ok, :already_processed}

      event.status == "ignored" ->
        {:ok, :already_ignored}

      true ->
        dispatch(bot, event)
    end
  end

  defp dispatch(%BotInstance{} = bot, %EventInbox{} = event) do
    with {:ok, handler} <- Registry.fetch(bot.handler_key),
         {:ok, log} <-
           Audit.start_execution(%{
             bot_instance_id: bot.id,
             event_inbox_id: event.id,
             handler_key: bot.handler_key,
             metadata: %{"event_type" => event.event_type}
           }),
         {:ok, _} <- Events.mark_processing(event) do
      started = System.monotonic_time(:millisecond)

      try do
        case handler.handle_event(bot, event) do
          :ok ->
            finish_ok(bot, event, log, started, %{})

          {:ok, meta} when is_map(meta) ->
            finish_ok(bot, event, log, started, meta)

          :ignored ->
            finish_ignored(bot, event, log, started, "ignored")

          {:ignored, reason} ->
            finish_ignored(bot, event, log, started, to_string(reason))

          {:error, :retry, reason} ->
            finish_retry(bot, event, log, started, reason)

          {:error, reason} ->
            finish_failed(bot, event, log, started, reason)
        end
      rescue
        exception ->
          finish_retry(bot, event, log, started, Exception.message(exception))
      end
    else
      {:error, :unknown_handler} ->
        _ = Events.mark_failed(event, "unknown_handler:#{bot.handler_key}")
        {:cancel, :unknown_handler}

      {:error, reason} ->
        {:error, reason}
    end
  end

  defp finish_ok(bot, event, log, started, metadata) do
    duration = System.monotonic_time(:millisecond) - started
    _ = Events.mark_processed(event)

    _ =
      Audit.finish_execution(log, %{
        status: "succeeded",
        metadata: Map.merge(log.metadata || %{}, metadata)
      })

    Logger.info("bot handler succeeded",
      bot_id: bot.external_bot_id,
      event_id: event.external_event_id,
      handler_key: bot.handler_key,
      duration_ms: duration
    )

    {:ok, :processed}
  end

  defp finish_ignored(bot, event, log, started, reason) do
    duration = System.monotonic_time(:millisecond) - started
    _ = Events.mark_ignored(event, reason)

    _ =
      Audit.finish_execution(log, %{
        status: "ignored",
        metadata: Map.put(log.metadata || %{}, "reason", reason)
      })

    Logger.info("bot handler ignored event",
      bot_id: bot.external_bot_id,
      event_id: event.external_event_id,
      handler_key: bot.handler_key,
      reason: reason,
      duration_ms: duration
    )

    {:ok, :ignored}
  end

  defp finish_failed(bot, event, log, started, reason) do
    duration = System.monotonic_time(:millisecond) - started
    message = format_reason(reason)
    _ = Events.mark_failed(event, message)

    _ =
      Audit.finish_execution(log, %{
        status: "failed",
        error_code: error_code(reason),
        error_message: String.slice(message, 0, 1000)
      })

    Logger.warning("bot handler failed permanently",
      bot_id: bot.external_bot_id,
      event_id: event.external_event_id,
      handler_key: bot.handler_key,
      duration_ms: duration
    )

    {:cancel, reason}
  end

  defp finish_retry(bot, event, log, started, reason) do
    duration = System.monotonic_time(:millisecond) - started
    message = format_reason(reason)
    _ = Events.mark_failed(event, message)

    _ =
      Audit.finish_execution(log, %{
        status: "failed",
        error_code: error_code(reason),
        error_message: String.slice(message, 0, 1000)
      })

    Logger.warning("bot handler failed; will retry",
      bot_id: bot.external_bot_id,
      event_id: event.external_event_id,
      handler_key: bot.handler_key,
      duration_ms: duration
    )

    {:error, reason}
  end

  defp format_reason(reason) when is_binary(reason), do: reason
  defp format_reason(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp format_reason(reason), do: inspect(reason)

  defp error_code({:unauthorized, _}), do: "unauthorized"
  defp error_code({:forbidden, _}), do: "forbidden"
  defp error_code({:rate_limited, _}), do: "rate_limited"
  defp error_code({:server_error, _, _}), do: "server_error"
  defp error_code({:transport_error, _}), do: "transport_error"
  defp error_code(reason) when is_atom(reason), do: Atom.to_string(reason)
  defp error_code(_), do: "handler_error"
end
