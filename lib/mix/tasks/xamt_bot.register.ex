defmodule Mix.Tasks.XamtBot.Register do
  @shortdoc "Register or update a local bot instance"

  @moduledoc """
  Upserts a local bot instance used by the runtime.

      mix xamt_bot.register \\
        --external-bot-id UUID \\
        --name "Echo Bot" \\
        --handler echo \\
        --signing-secret whsec_xxx \\
        --api-token xamt_bot_xxx

  Optional:

      --channel-id <XAMT_CHANNEL_UUID>
      --handler nomio_review

  When `--channel-id` is set, it is stored in `config["default_channel_id"]`
  (used by handlers such as `nomio_review` when the payload omits a channel).

  Secrets are stored for runtime use and must never be logged.
  """

  use Mix.Task

  @requirements ["app.start"]

  @impl Mix.Task
  def run(args) do
    {opts, _, _} =
      OptionParser.parse(args,
        strict: [
          external_bot_id: :string,
          name: :string,
          handler: :string,
          signing_secret: :string,
          api_token: :string,
          status: :string,
          channel_id: :string
        ]
      )

    required = [:external_bot_id, :name, :signing_secret, :api_token]

    missing =
      Enum.filter(required, fn key ->
        value = Keyword.get(opts, key)
        is_nil(value) or value == ""
      end)

    if missing != [] do
      Mix.raise("missing required options: #{Enum.map_join(missing, ", ", &"--#{dash(&1)}")}")
    end

    config =
      case Keyword.get(opts, :channel_id) do
        nil -> %{}
        "" -> %{}
        channel_id -> %{"default_channel_id" => channel_id}
      end

    attrs = %{
      "external_bot_id" => Keyword.fetch!(opts, :external_bot_id),
      "name" => Keyword.fetch!(opts, :name),
      "handler_key" => Keyword.get(opts, :handler, "echo"),
      "signing_secret" => Keyword.fetch!(opts, :signing_secret),
      "api_token" => Keyword.fetch!(opts, :api_token),
      "status" => Keyword.get(opts, :status, "active"),
      "config" => config
    }

    case XamtBot.Bots.upsert_instance(attrs) do
      {:ok, instance} ->
        Mix.shell().info("""
        Registered bot instance:
          id=#{instance.id}
          external_bot_id=#{instance.external_bot_id}
          handler=#{instance.handler_key}
          status=#{instance.status}
          default_channel_id=#{Map.get(instance.config || %{}, "default_channel_id") || "-"}
          webhook_path=/webhooks/xamt/#{instance.external_bot_id}
        """)

      {:error, changeset} ->
        Mix.raise("failed to register bot: #{inspect(changeset.errors)}")
    end
  end

  defp dash(atom), do: atom |> Atom.to_string() |> String.replace("_", "-")
end
