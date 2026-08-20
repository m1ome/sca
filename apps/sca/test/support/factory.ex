defmodule Sca.Factory do
  @moduledoc """
  ExMachina factories for the domain.

  Factories live here rather than next to each schema so tests in every app
  have one place to look.
  """

  use ExMachina.Ecto, repo: Sca.Repo

  alias Sca.Models.Admin
  alias Sca.Models.Binding
  alias Sca.Models.Embed.TenantSettings
  alias Sca.Models.Request
  alias Sca.Models.Tenant
  alias Sca.Models.User

  @password "correct horse battery"

  @doc "Password baked into `:user` factories, for tests that sign in."
  def valid_password, do: @password

  def tenant_factory do
    %Tenant{
      name: sequence(:tenant_name, &"Merchant #{&1}"),
      status: :active,
      settings: build(:settings)
    }
  end

  def settings_factory do
    %TenantSettings{
      webhook_url: "https://merchant.example.com/sca/webhook",
      logo_url: "https://merchant.example.com/logo.png",
      webhook_secret: Sca.Crypto.random_token(32),
      default_request_timeout_seconds: 300
    }
  end

  def user_factory do
    %User{
      tenant: build(:tenant),
      email: sequence(:user_email, &"member#{&1}@merchant.example.com"),
      name: "Team member",
      role: :admin,
      status: :active,
      password_hash: Bcrypt.hash_pwd_salt(@password)
    }
  end

  def binding_factory do
    %Binding{
      tenant: build(:tenant),
      external_id: sequence(:binding_external_id, &"customer-#{&1}"),
      name: "iPhone",
      status: :pending,
      enroll_token: sequence(:enroll_token, &"enroll-token-#{&1}"),
      enroll_expires_at: Timex.shift(Timex.now(), seconds: 900)
    }
  end

  @doc "A binding that already finished enrollment."
  def active_binding_factory do
    struct!(
      binding_factory(),
      status: :active,
      enroll_token: nil,
      enroll_expires_at: nil,
      public_key: Base.encode64(elem(:crypto.generate_key(:ecdh, :secp256r1), 0)),
      algorithm: "ecdsa-p256",
      activated_at: Timex.now(),
      push_token: sequence(:push_token, &"push-#{&1}"),
      push_platform: :ios
    )
  end

  def request_factory do
    %Request{
      tenant: build(:tenant),
      binding: build(:active_binding),
      type: :payment,
      title: "Payment confirmation",
      description: "Transfer to ACME Ltd",
      payload: %{"amount" => "10.00", "currency" => "EUR", "beneficiary" => "ACME Ltd"},
      payload_hash: Base.encode16(:crypto.hash(:sha256, "payload"), case: :lower),
      nonce: sequence(:request_nonce, &"nonce-#{&1}"),
      status: :pending,
      expires_at: Timex.shift(Timex.now(), seconds: 300)
    }
  end

  def admin_factory do
    %Admin{
      email: sequence(:admin_email, &"admin#{&1}@sca.example.com"),
      name: "Staff member",
      role: :support,
      status: :active,
      password_hash: Bcrypt.hash_pwd_salt(@password)
    }
  end
end
