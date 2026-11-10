import Config

# Configure your database
#
# The MIX_TEST_PARTITION environment variable can be used
# to provide built-in test partitioning in CI environment.
# Run `mix help test` for more information.
config :xamt_bot, XamtBot.Repo,
  username: System.get_env("PGUSER", "amjil"),
  password: System.get_env("PGPASSWORD", ""),
  hostname: "localhost",
  database: "xamt_bot_test#{System.get_env("MIX_TEST_PARTITION")}",
  pool: Ecto.Adapters.SQL.Sandbox,
  pool_size: System.schedulers_online() * 2

# We don't run a server during test. If one is required,
# you can enable the server option below.
config :xamt_bot, XamtBotWeb.Endpoint,
  http: [ip: {127, 0, 0, 1}, port: 4002],
  secret_key_base: "4lfgXAKYsFwUFHr5zfJ3Ee1hOAXlLjRF0AvlLUL8NRBTn2nB5AEvYCa6wZcjsImz",
  server: false

# Print only warnings and errors during test
config :logger, level: :warning

config :xamt_bot, Oban, testing: :manual

config :xamt_bot, XamtBot.Clients.XamtClient,
  base_url: "http://xamt.test",
  receive_timeout: 1_000

config :xamt_bot, XamtBot.Events.Signature, timestamp_tolerance_seconds: 300

config :xamt_bot, ops_token: "test-ops-token"

# Initialize plugs at runtime for faster test compilation
config :phoenix, :plug_init_mode, :runtime

# Enable helpful, but potentially expensive runtime checks
config :phoenix_live_view,
  enable_expensive_runtime_checks: true

# Sort query params output of verified routes for robust url comparisons
config :phoenix,
  sort_verified_routes_query_params: true
