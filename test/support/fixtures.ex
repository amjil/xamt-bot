defmodule XamtBot.Fixtures do
  @moduledoc false

  alias XamtBot.Bots

  def bot_instance_fixture(attrs \\ %{}) do
    unique = System.unique_integer([:positive])

    attrs =
      Map.merge(
        %{
          "external_bot_id" => Ecto.UUID.generate(),
          "name" => "Echo #{unique}",
          "handler_key" => "echo",
          "status" => "active",
          "signing_secret" => "whsec_test_#{unique}",
          "api_token" => "xamt_bot_test_#{unique}",
          "config" => %{}
        },
        stringify(attrs)
      )

    {:ok, bot} = Bots.create_instance(attrs)
    bot
  end

  def message_created_payload(opts \\ []) do
    channel_id = Keyword.get(opts, :channel_id, Ecto.UUID.generate())
    message_id = Keyword.get(opts, :message_id, Ecto.UUID.generate())
    author_type = Keyword.get(opts, :author_type, "user")
    content = Keyword.get(opts, :content, "Hello")
    event_id = Keyword.get(opts, :event_id, Ecto.UUID.generate())

    %{
      "id" => event_id,
      "type" => "message.created",
      "event_id" => event_id,
      "event_type" => "message.created",
      "version" => 1,
      "channel_id" => channel_id,
      "created_at" => DateTime.utc_now() |> DateTime.to_iso8601(),
      "data" => %{
        "message_id" => message_id,
        "channel_id" => channel_id,
        "author" => %{"type" => author_type, "id" => Ecto.UUID.generate(), "username" => "alice"},
        "content" => content
      },
      "message" => %{
        "id" => message_id,
        "body" => content,
        "author" => %{"type" => author_type, "id" => Ecto.UUID.generate(), "username" => "alice"}
      }
    }
  end

  defp stringify(attrs) do
    Map.new(attrs, fn
      {k, v} when is_atom(k) -> {Atom.to_string(k), v}
      {k, v} -> {k, v}
    end)
  end
end
