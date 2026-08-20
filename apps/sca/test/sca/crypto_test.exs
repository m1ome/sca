defmodule Sca.CryptoTest do
  use ExUnit.Case, async: true

  alias Sca.Crypto

  # The vector the mobile client pins too. If this test starts failing, devices
  # stop signing: the implementations have drifted.
  @payload %{"merchant" => "ACME Store", "amount" => "149.90", "currency" => "EUR"}
  @canonical "amount=149.90\ncurrency=EUR\nmerchant=ACME Store"

  describe "canonical_payload/1" do
    test "matches the locked cross-language vector" do
      assert Crypto.canonical_payload(@payload) == @canonical
    end

    test "does not depend on key order" do
      reordered = %{"amount" => "149.90", "currency" => "EUR", "merchant" => "ACME Store"}

      assert Crypto.canonical_payload(reordered) == @canonical
      assert Crypto.payload_hash(reordered) == Crypto.payload_hash(@payload)
    end

    test "renders an empty payload as an empty string" do
      assert Crypto.canonical_payload(%{}) == ""
    end
  end

  test "payload_hash/1 is a lowercase hex sha256 of the canonical form" do
    expected = :sha256 |> :crypto.hash(@canonical) |> Base.encode16(case: :lower)

    assert Crypto.payload_hash(@payload) == expected
    assert Crypto.payload_hash(@payload) =~ ~r/\A[0-9a-f]{64}\z/
  end

  test "signing strings have the shape the client reproduces" do
    assert Crypto.signing_string("req-id", "nonce", "confirm", "hash") ==
             "sca-service:v1:req-id:nonce:confirm:hash"

    assert Crypto.refresh_signing_string("bin-id", "nonce") ==
             "sca-service:refresh:v1:bin-id:nonce"
  end

  describe "verify/4" do
    setup do
      {public, private} = :crypto.generate_key(:ecdh, :secp256r1)

      %{public: Base.encode64(public), private: private}
    end

    test "accepts a signature from the matching key", %{public: public, private: private} do
      message = Crypto.signing_string("req", "nonce", "confirm", "hash")
      signature = sign(message, private)

      assert Crypto.verify("ecdsa-p256", public, message, signature) == :ok
      assert Crypto.verify(nil, public, message, signature) == :ok
    end

    test "rejects a signature over a different message", %{public: public, private: private} do
      signature = sign("one message", private)

      assert Crypto.verify("ecdsa-p256", public, "another message", signature) ==
               {:error, :signature_mismatch}
    end

    test "rejects a signature from another key", %{public: public} do
      {_other_public, other_private} = :crypto.generate_key(:ecdh, :secp256r1)

      assert Crypto.verify("ecdsa-p256", public, "message", sign("message", other_private)) ==
               {:error, :signature_mismatch}
    end

    test "rejects garbage instead of crashing", %{public: public, private: private} do
      assert Crypto.verify("ecdsa-p256", public, "message", "not base64!") ==
               {:error, :invalid_signature_encoding}

      assert Crypto.verify("ecdsa-p256", public, "message", Base.encode64("not a der signature")) ==
               {:error, :signature_mismatch}

      assert Crypto.verify("ecdsa-p256", "not base64!", "message", sign("message", private)) ==
               {:error, :invalid_public_key_encoding}
    end

    test "refuses an algorithm it does not implement", %{public: public} do
      assert Crypto.verify("ed25519", public, "message", Base.encode64("sig")) ==
               {:error, {:unsupported_algorithm, "ed25519"}}
    end
  end

  describe "validate_public_key/2" do
    test "accepts a real P-256 point" do
      {public, _private} = :crypto.generate_key(:ecdh, :secp256r1)

      assert Crypto.validate_public_key("ecdsa-p256", Base.encode64(public)) == :ok
    end

    test "rejects a point that is not on the curve" do
      <<0x04, x::binary-size(32), _y::binary-size(32)>> =
        elem(:crypto.generate_key(:ecdh, :secp256r1), 0)

      forged = Base.encode64(<<0x04>> <> x <> :binary.copy(<<0>>, 32))

      assert Crypto.validate_public_key("ecdsa-p256", forged) == {:error, :invalid_public_key}
    end

    test "rejects a key of the wrong shape" do
      assert Crypto.validate_public_key("ecdsa-p256", Base.encode64("short")) ==
               {:error, :invalid_public_key_encoding}

      assert Crypto.validate_public_key("ecdsa-p256", "not base64!") ==
               {:error, :invalid_public_key_encoding}
    end
  end

  test "random_token/1 is url-safe and unique" do
    tokens = for _ <- 1..100, do: Crypto.random_token(16)

    assert length(Enum.uniq(tokens)) == 100
    assert Enum.all?(tokens, &(&1 =~ ~r/\A[A-Za-z0-9_-]+\z/))
  end

  test "token_digest/1 is stable and hides the token" do
    token = Crypto.random_token()

    assert Crypto.token_digest(token) == Crypto.token_digest(token)
    refute Crypto.token_digest(token) =~ token
  end

  defp sign(message, private_key) do
    :ecdsa
    |> :crypto.sign(:sha256, message, [private_key, :secp256r1])
    |> Base.encode64()
  end
end
