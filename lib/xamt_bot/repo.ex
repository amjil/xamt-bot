defmodule XamtBot.Repo do
  use Ecto.Repo,
    otp_app: :xamt_bot,
    adapter: Ecto.Adapters.Postgres
end
