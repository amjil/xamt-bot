defmodule XamtBot.Application do
  # See https://hexdocs.pm/elixir/Application.html
  # for more information on OTP Applications
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      XamtBotWeb.Telemetry,
      XamtBot.Repo,
      {DNSCluster, query: Application.get_env(:xamt_bot, :dns_cluster_query) || :ignore},
      {Phoenix.PubSub, name: XamtBot.PubSub},
      {Oban, Application.fetch_env!(:xamt_bot, Oban)},
      # Start to serve requests, typically the last entry
      XamtBotWeb.Endpoint
    ]

    # See https://hexdocs.pm/elixir/Supervisor.html
    # for other strategies and supported options
    opts = [strategy: :one_for_one, name: XamtBot.Supervisor]
    Supervisor.start_link(children, opts)
  end

  # Tell Phoenix to update the endpoint configuration
  # whenever the application is updated.
  @impl true
  def config_change(changed, _new, removed) do
    XamtBotWeb.Endpoint.config_change(changed, removed)
    :ok
  end
end
