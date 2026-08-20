defmodule Sca.Webhooks.Encryption do
  @moduledoc """
  Encrypts a webhook body for the tenant's certificate as a JWE (RFC 7516).

  TLS covers the hop; this covers everything that stores or forwards the payload
  afterwards. Compact JWE, `alg: RSA-OAEP-256`, `enc: A256GCM` — one call to any
  JOSE library, not a scheme of ours.
  """

  require Record

  Record.defrecordp(
    :otp_certificate,
    :OTPCertificate,
    Record.extract(:OTPCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_tbs_certificate,
    :OTPTBSCertificate,
    Record.extract(:OTPTBSCertificate, from_lib: "public_key/include/public_key.hrl")
  )

  Record.defrecordp(
    :otp_subject_public_key_info,
    :OTPSubjectPublicKeyInfo,
    Record.extract(:OTPSubjectPublicKeyInfo, from_lib: "public_key/include/public_key.hrl")
  )

  @algorithm "RSA-OAEP-256"
  @encryption "A256GCM"

  @doc "The JWE algorithms we encrypt with, as they appear in the JOSE header."
  def algorithms, do: %{"alg" => @algorithm, "enc" => @encryption}

  @doc """
  Encrypts `plaintext` for the given PEM and returns the JWE compact string.

  Accepts a certificate, a `PUBLIC KEY` (SubjectPublicKeyInfo) or an
  `RSA PUBLIC KEY`.
  """
  def encrypt(plaintext, pem) when is_binary(plaintext) and is_binary(pem) do
    with {:ok, jwk} <- public_key_from_pem(pem) do
      {_meta, compact} =
        jwk
        |> JOSE.JWE.block_encrypt(plaintext, algorithms())
        |> JOSE.JWE.compact()

      {:ok, compact}
    end
  rescue
    error -> {:error, {:encryption_failed, Exception.message(error)}}
  end

  @doc """
  Reads the tenant's PEM into a JWK.

  Also the check behind the settings form: a certificate we cannot encrypt for
  is worth refusing where someone pastes it, not at the first webhook.
  """
  def public_key_from_pem(pem) when is_binary(pem) do
    case :public_key.pem_decode(pem) do
      [] -> {:error, :invalid_pem}
      entries -> entries |> Enum.find_value(&jwk_from_entry/1) |> wrap_key()
    end
  rescue
    _error -> {:error, :invalid_pem}
  end

  defp jwk_from_entry({:Certificate, der, _cipher}) do
    der
    |> :public_key.pkix_decode_cert(:otp)
    |> otp_certificate(:tbsCertificate)
    |> otp_tbs_certificate(:subjectPublicKeyInfo)
    |> otp_subject_public_key_info(:subjectPublicKey)
    |> rsa_jwk()
  rescue
    _error -> nil
  end

  defp jwk_from_entry({type, _der, _cipher} = entry)
       when type in [:SubjectPublicKeyInfo, :RSAPublicKey] do
    entry |> :public_key.pem_entry_decode() |> rsa_jwk()
  rescue
    _error -> nil
  end

  defp jwk_from_entry(_entry), do: nil

  # RSA-OAEP-256 has nothing to do with an EC key; saying so here beats a JOSE
  # crash at delivery time.
  defp rsa_jwk(key) do
    case JOSE.JWK.from_key(key) do
      %JOSE.JWK{kty: {:jose_jwk_kty_rsa, _key}} = jwk -> jwk
      _other -> nil
    end
  end

  defp wrap_key(nil), do: {:error, :unsupported_certificate}
  defp wrap_key(jwk), do: {:ok, jwk}
end
