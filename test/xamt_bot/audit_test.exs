defmodule XamtBot.AuditTest do
  use XamtBot.DataCase, async: true

  alias XamtBot.Audit
  alias XamtBot.Fixtures

  setup do
    bot = Fixtures.bot_instance_fixture()
    %{bot: bot}
  end

  test "claim_outbound grants pending then blocks in-flight peers", %{bot: bot} do
    key = "nonce-#{System.unique_integer([:positive])}"

    attrs = %{
      bot_instance_id: bot.id,
      idempotency_key: key,
      operation: "messages.create",
      target_id: Ecto.UUID.generate()
    }

    assert {:ok, :claimed, pending} = Audit.claim_outbound(attrs)
    assert pending.status == "pending"
    assert {:error, :in_flight} = Audit.claim_outbound(attrs)
  end

  test "claim_outbound replays succeeded and reclaims failed", %{bot: bot} do
    key = "nonce-#{System.unique_integer([:positive])}"

    attrs = %{
      bot_instance_id: bot.id,
      idempotency_key: key,
      operation: "messages.create",
      target_id: Ecto.UUID.generate()
    }

    assert {:ok, :claimed, _} = Audit.claim_outbound(attrs)

    assert {:ok, _} =
             Audit.remember_outbound(Map.merge(attrs, %{status: "succeeded", response_code: 200}))

    assert {:ok, :replayed, succeeded} = Audit.claim_outbound(attrs)
    assert succeeded.status == "succeeded"

    failed_key = "nonce-failed-#{System.unique_integer([:positive])}"
    failed_attrs = Map.put(attrs, :idempotency_key, failed_key)

    assert {:ok, :claimed, _} = Audit.claim_outbound(failed_attrs)

    assert {:ok, _} =
             Audit.remember_outbound(
               Map.merge(failed_attrs, %{status: "failed", response_code: 500})
             )

    assert {:ok, :claimed, reclaimed} = Audit.claim_outbound(failed_attrs)
    assert reclaimed.status == "pending"
  end
end
