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

  scope "/", XamtBotWeb do
    pipe_through :browser

    get "/", PageController, :home
  end

  scope "/", XamtBotWeb do
    pipe_through :api

    get "/health", HealthController, :show
    post "/webhooks/xamt/:external_bot_id", WebhookController, :xamt
  end
end
