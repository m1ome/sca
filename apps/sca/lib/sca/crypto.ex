defmodule Sca.Crypto do
  @moduledoc """
  The signing conventions shared with the mobile client.

  Byte-for-byte identical to what the mobile client computes: the device hashes
  what it displays and signs that, so any difference here stops signing
  altogether. Both implementations pin the vector in `test/sca/crypto_test.exs`.

  `ecdsa-p256`: public key is an X9.63 uncompressed point (`0x04 || X || Y`),
  signature is ASN.1 DER over SHA-256 — what the Secure Enclave and the Android
  Keystore produce. Everything on the wire is base64.
  """

  @algorithm_ecdsa_p256 "ecdsa-p256"
  @curve :secp256r1

  # Valid DER, meaningless signature (r=1, s=1): verifying with it exercises
  # OpenSSL's key parsing without anyone caring about the answer.
  @probe_signature <<0x30, 0x06, 0x02, 0x01, 0x01, 0x02, 0x01, 0x01>>

  @doc "The only signature algorithm supported today."
  def algorithm_ecdsa_p256, do: @algorithm_ecdsa_p256

  @doc """
  Deterministic rendering of a request's params: keys sorted, one `key=value`
  per line. Params are flat and scalar so iOS and Android can do the same.
  """
  def canonical_payload(payload) when is_map(payload) do
    payload
    |> Enum.map(fn {key, value} -> {to_string(key), render(value)} end)
    |> Enum.sort_by(fn {key, _value} -> key end)
    |> Enum.map_join("\n", fn {key, value} -> "#{key}=#{value}" end)
  end

  @doc "Lowercase hex SHA-256 of the canonical payload."
  def payload_hash(payload) when is_map(payload) do
    payload
    |> canonical_payload()
    |> then(&:crypto.hash(:sha256, &1))
    |> Base.encode16(case: :lower)
  end

  @doc """
  The string a device signs to decide a request.

      sca-service:v1:{request_id}:{nonce}:{decision}:{payload_hash}

  `decision` is the client's wire word, not our status. `nonce` is the server's
  per-request challenge.
  """
  def signing_string(request_id, nonce, decision, payload_hash)
      when decision in ["confirm", "deny"] do
    "sca-service:v1:#{request_id}:#{nonce}:#{decision}:#{payload_hash}"
  end

  @doc """
  The challenge a device signs with its hardware key to refresh its token.

  Keeps a stolen bearer from renewing itself: the bearer names the binding, the
  signature authorises.
  """
  def refresh_signing_string(binding_id, nonce) do
    "sca-service:refresh:v1:#{binding_id}:#{nonce}"
  end

  @doc """
  Verifies a signature made by a bound device. Never raises: this is wire input.
  """
  def verify(algorithm, public_key_b64, message, signature_b64)

  def verify(algorithm, public_key_b64, message, signature_b64)
      when algorithm in [nil, "", @algorithm_ecdsa_p256] do
    with {:ok, point} <- decode_public_key(public_key_b64),
         {:ok, signature} <- decode_base64(signature_b64, :invalid_signature_encoding) do
      if :crypto.verify(:ecdsa, :sha256, message, signature, [point, @curve]) do
        :ok
      else
        {:error, :signature_mismatch}
      end
    end
  rescue
    # A malformed DER signature makes the NIF raise rather than return false.
    _error -> {:error, :signature_mismatch}
  end

  def verify(algorithm, _public_key, _message, _signature) do
    {:error, {:unsupported_algorithm, algorithm}}
  end

  @doc """
  Checks that OpenSSL accepts the key, at bind time rather than at the first
  payment. Loading the point is the validation; an invalid one raises.
  """
  def validate_public_key(algorithm, public_key_b64)

  def validate_public_key(algorithm, public_key_b64)
      when algorithm in [nil, "", @algorithm_ecdsa_p256] do
    with {:ok, point} <- decode_public_key(public_key_b64) do
      :crypto.verify(:ecdsa, :sha256, "sca-key-probe", @probe_signature, [point, @curve])
      :ok
    end
  rescue
    _error -> {:error, :invalid_public_key}
  end

  def validate_public_key(algorithm, _public_key) do
    {:error, {:unsupported_algorithm, algorithm}}
  end

  @doc "URL-safe random token: enrollment, access tokens, challenges."
  def random_token(bytes \\ 32) when is_integer(bytes) and bytes > 0 do
    bytes |> :crypto.strong_rand_bytes() |> Base.url_encode64(padding: false)
  end

  @doc """
  SHA-256 of a bearer token: stored instead of the token, like a password.
  """
  def token_digest(token) when is_binary(token) do
    :sha256 |> :crypto.hash(token) |> Base.encode16(case: :lower)
  end

  defp decode_public_key(public_key_b64) do
    with {:ok, raw} <- decode_base64(public_key_b64, :invalid_public_key_encoding) do
      case raw do
        <<0x04, _rest::binary-size(64)>> -> {:ok, raw}
        _other -> {:error, :invalid_public_key_encoding}
      end
    end
  end

  defp decode_base64(nil, error), do: {:error, error}

  defp decode_base64(value, error) when is_binary(value) do
    case Base.decode64(value) do
      {:ok, decoded} -> {:ok, decoded}
      :error -> {:error, error}
    end
  end

  defp decode_base64(_value, error), do: {:error, error}

  # Params are strings by the time they arrive; the rest is a safety net.
  defp render(value) when is_binary(value), do: value
  defp render(value) when is_boolean(value), do: to_string(value)
  defp render(value) when is_integer(value), do: Integer.to_string(value)
  defp render(value) when is_float(value), do: Float.to_string(value)
  defp render(nil), do: ""
  defp render(value), do: to_string(value)
end
