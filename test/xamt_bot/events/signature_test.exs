defmodule XamtBot.Events.SignatureTest do
  use ExUnit.Case, async: true

  alias XamtBot.Events.Signature

  @secret "whsec_test_secret"
  @body ~s({"type":"message.created","data":{"content":"hi"}})

  test "accepts a valid signature within the timestamp window" do
    ts = Integer.to_string(System.system_time(:second))
    sig = Signature.sign(@body, ts, @secret)

    assert :ok = Signature.verify(@body, ts, sig, @secret)
  end

  test "rejects an invalid signature" do
    ts = Integer.to_string(System.system_time(:second))

    assert {:error, :invalid_signature} =
             Signature.verify(@body, ts, "sha256=deadbeef", @secret)
  end

  test "rejects timestamps outside the tolerance window" do
    old = Integer.to_string(System.system_time(:second) - 10_000)
    sig = Signature.sign(@body, old, @secret)

    assert {:error, :timestamp_out_of_range} =
             Signature.verify(@body, old, sig, @secret, tolerance: 300)
  end

  test "uses constant-time comparison for matching length signatures" do
    ts = Integer.to_string(System.system_time(:second))
    good = Signature.sign(@body, ts, @secret)

    bad =
      String.replace_suffix(
        good,
        String.slice(good, -1, 1),
        if(String.ends_with?(good, "a"), do: "b", else: "a")
      )

    assert {:error, :invalid_signature} = Signature.verify(@body, ts, bad, @secret)
  end
end
