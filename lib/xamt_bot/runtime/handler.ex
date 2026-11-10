defmodule XamtBot.Runtime.Handler do
  @moduledoc """
  Behaviour for bot event handlers.
  """

  alias XamtBot.Bots.BotInstance
  alias XamtBot.Events.EventInbox

  @type result ::
          :ok
          | :ignored
          | {:ok, term()}
          | {:ignored, reason :: atom() | String.t()}
          | {:error, reason :: term()}
          | {:error, :retry, reason :: term()}

  @callback handle_event(BotInstance.t(), EventInbox.t()) :: result
end
