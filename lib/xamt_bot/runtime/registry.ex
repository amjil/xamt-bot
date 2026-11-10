defmodule XamtBot.Runtime.Registry do
  @moduledoc """
  Explicit handler registry. First version uses a static map — no dynamic
  code loading or marketplace plugins.
  """

  @doc """
  Resolves a handler module for the given handler key.
  """
  def fetch(handler_key) when is_binary(handler_key) do
    handlers =
      Application.get_env(:xamt_bot, __MODULE__, [])
      |> Keyword.get(:handlers, %{})

    case Map.fetch(handlers, handler_key) do
      {:ok, module} -> {:ok, module}
      :error -> {:error, :unknown_handler}
    end
  end
end
