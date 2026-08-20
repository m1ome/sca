defmodule Sca.Webhooks.EncryptionTest do
  use ExUnit.Case, async: true

  alias Sca.Webhooks.Encryption

  @fixtures Path.expand("../../support/fixtures", __DIR__)

  setup_all do
    %{
      certificate: File.read!(Path.join(@fixtures, "webhook_cert.pem")),
      private_key: File.read!(Path.join(@fixtures, "webhook_key.pem"))
    }
  end

  test "what we encrypt for a certificate is what its owner decrypts", ctx do
    plaintext = Jason.encode!(%{"event" => "request.confirmed", "amount" => "149.90"})

    assert {:ok, jwe} = Encryption.encrypt(plaintext, ctx.certificate)

    assert %{"alg" => "RSA-OAEP-256", "enc" => "A256GCM"} = jwe_header(jwe)
    assert decrypt(jwe, ctx.private_key) == plaintext
  end

  test "each call is a fresh encryption", ctx do
    {:ok, one} = Encryption.encrypt("same plaintext", ctx.certificate)
    {:ok, two} = Encryption.encrypt("same plaintext", ctx.certificate)

    refute one == two
    assert decrypt(one, ctx.private_key) == decrypt(two, ctx.private_key)
  end

  test "a tampered ciphertext does not decrypt", ctx do
    {:ok, jwe} = Encryption.encrypt("original", ctx.certificate)
    [header, key, iv, _ciphertext, tag] = String.split(jwe, ".")
    tampered = Enum.join([header, key, iv, Base.url_encode64("nope", padding: false), tag], ".")

    assert decrypt(tampered, ctx.private_key) == :error
  end

  test "a bare public key works as well as a certificate" do
    private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    assert {:ok, jwe} = Encryption.encrypt("hello", public_key_pem(private_key))
    assert {"hello", _jwe} = JOSE.JWE.block_decrypt(JOSE.JWK.from_key(private_key), jwe)
  end

  test "refuses something that is not a usable key" do
    assert Encryption.encrypt("hello", "not a pem at all") == {:error, :invalid_pem}

    assert Encryption.public_key_from_pem("-----BEGIN CERTIFICATE-----\nnope\n") ==
             {:error, :invalid_pem}
  end

  # What a merchant would write: one call, any JOSE library.
  defp decrypt(jwe, private_key_pem) do
    case JOSE.JWE.block_decrypt(JOSE.JWK.from_pem(private_key_pem), jwe) do
      {plaintext, _jwe} when is_binary(plaintext) -> plaintext
      _other -> :error
    end
  end

  defp jwe_header(jwe) do
    jwe |> String.split(".") |> hd() |> Base.url_decode64!(padding: false) |> Jason.decode!()
  end

  defp public_key_pem(private_key) do
    public_key = {:RSAPublicKey, elem(private_key, 2), elem(private_key, 3)}

    :public_key.pem_encode([:public_key.pem_entry_encode(:SubjectPublicKeyInfo, public_key)])
  end
end
