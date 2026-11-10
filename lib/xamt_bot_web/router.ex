defmodule XamtBotWeb.Router do
  use XamtBotWeb, :router

  pipeline :browser do
    plug :accepts, ["html"]
    plug :fetch_session
    plug :fetch_live_flash
    plug :put_root_layout, html: {XamtBotWeb.Layouts, :root}
    plug :protect_from_forgery
    plug :put_secure_browser_headers
  end

  pipeline :api do
    plug :accepts, ["json"]
  end

  pipeline :ops_auth do
    plug XamtBotWeb.Plugs.OpsAuth
  end

  scope "/", XamtBotWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", XamtBotWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/webhooks/xamt/:external_bot_id", WebhookController, :xamt
  end

  # Read-only ops surface. Requires OPS_TOKEN / :ops_token; otherwise 404.
  scope "/ops", XamtBotWeb do
    pipe_through [:api, :ops_auth]

    get "/bots", OpsController, :bots
    get "/bots/:id", OpsController, :show_bot
    get "/events", OpsController, :events
    get "/events/:id", OpsController, :show_event
    get "/executions", OpsController, :executions
  end
end
