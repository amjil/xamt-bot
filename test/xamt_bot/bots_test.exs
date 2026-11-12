defmodule XamtBot.BotsTest do
  use XamtBot.DataCase, async: true

  alias XamtBot.Bots
  alias XamtBot.Bots.BotInstance
  alias XamtBot.Fixtures

  test "inspect omits signing_secret and api_token" do
    bot = Fixtures.bot_instance_fixture()

    assert :signing_secret in BotInstance.__schema__(:redact_fields)
    assert :api_token in BotInstance.__schema__(:redact_fields)

    inspected = inspect(bot, limit: :infinity, printable_limit: :infinity)
    refute inspected =~ bot.signing_secret
    refute inspected =~ bot.api_token
    refute inspected =~ "signing_secret:"
    refute inspected =~ "api_token:"
  end

  test "upsert_instance creates then updates by external_bot_id" do
    external_bot_id = Ecto.UUID.generate()

    attrs = %{
      "external_bot_id" => external_bot_id,
      "name" => "Original",
      "handler_key" => "echo",
      "status" => "active",
      "signing_secret" => "whsec_original",
      "api_token" => "token_original",
      "config" => %{}
    }

    assert {:ok, %BotInstance{} = first} = Bots.upsert_instance(attrs)
    assert first.name == "Original"

    assert {:ok, %BotInstance{} = second} =
             Bots.upsert_instance(Map.put(attrs, "name", "Updated"))

    assert second.id == first.id
    assert second.name == "Updated"
    assert Bots.list_instances() |> Enum.count(&(&1.external_bot_id == external_bot_id)) == 1
  end
end
