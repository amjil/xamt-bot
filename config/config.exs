# This file is responsible for configuring your application
# and its dependencies with the aid of the Config module.
#
# This configuration file is loaded before any dependency and
# is restricted to this project.

# General application configuration
import Config

config :xamt_bot,
  ecto_repos: [XamtBot.Repo],
  generators: [timestamp_type: :utc_datetime_usec, binary_id: true],
  ops_token: nil

config :xamt_bot, Oban,
  repo: XamtBot.Repo,
  queues: [bot_events: 10],
  plugins: [
    {Oban.Plugins.Pruner, max_age: 60 * 60 * 24 * 7}
  ]

config :xamt_bot, XamtBot.Clients.XamtClient,
  base_url: "http://127.0.0.1:4000",
  receive_timeout: 10_000

config :xamt_bot, XamtBot.Events.Signature, timestamp_tolerance_seconds: 300

config :xamt_bot, XamtBot.Runtime.Registry,
  handlers: %{
    "echo" => XamtBot.Handlers.Echo,
    "nomio_review" => XamtBot.Handlers.NomioReview
  }

# Configure the endpoint
config :xamt_bot, XamtBotWeb.Endpoint,
  url: [host: "localhost"],
  adapter: Bandit.PhoenixAdapter,
  render_errors: [
    formats: [html: XamtBotWeb.ErrorHTML, json: XamtBotWeb.ErrorJSON],
    layout: false
  ],
  pubsub_server: XamtBot.PubSub,
  live_view: [signing_salt: "CXPx03pH"]

# Configure esbuild (the version is required)
config :esbuild,
  version: "0.25.4",
  xamt_bot: [
    args:
      ~w(js/app.js --bundle --target=es2022 --outdir=../priv/static/assets/js --external:/fonts/* --external:/images/* --alias:@=.),
    cd: Path.expand("../assets", __DIR__),
    env: %{"NODE_PATH" => [Path.expand("../deps", __DIR__), Mix.Project.build_path()]}
  ]

# Configure tailwind (the version is required)
config :tailwind,
  version: "4.1.12",
  xamt_bot: [
    args: ~w(
      --input=assets/css/app.css
      --output=priv/static/assets/css/app.css
    ),
    cd: Path.expand("..", __DIR__)
  ]

# Configure Elixir's Logger
config :logger, :default_formatter,
  format: "$time $metadata[$level] $message\n",
  metadata: [
    :request_id,
    :bot_id,
    :event_id,
    :handler_key,
    :operation,
    :status,
    :duration_ms,
    :reason
  ]

# Use Jason for JSON parsing in Phoenix
config :phoenix, :json_library, Jason

# Import environment specific config. This must remain at the bottom
# of this file so it overrides the configuration defined above.
import_config "#{config_env()}.exs"
