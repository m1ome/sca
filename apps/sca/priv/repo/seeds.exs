# Development data: one merchant with a bound device and a handful of approvals
# in every state a screen has to render.
#
#     mix ecto.reset   # drops, migrates and runs this

alias Sca.Actions
alias Sca.Repos.RequestRepo
alias Sca.Repos.TenantRepo

email = "ops@northstar.example.com"
password = "northstar-dev-password"

{:ok, %{tenant: tenant}} =
  case TenantRepo.get_by_public_id("TNT-1") do
    {:ok, tenant} ->
      {:ok, %{tenant: tenant}}

    {:error, :not_found} ->
      Actions.Tenant.create(%{
        name: "Northstar Payments",
        owner_email: email,
        owner_name: "Dana Ops",
        settings: %{webhook_url: "https://northstar.example.com/hooks/sca"}
      })
  end

{:ok, user} = Sca.Repos.UserRepo.get_by_email(tenant, email)
{:ok, _user} = Actions.Tenant.change_user_password(user, password)

# A device that can actually sign: the key shape the phone produces.
{public_key, private_key} = :crypto.generate_key(:ecdh, :secp256r1)

binding =
  case Sca.Repos.BindingRepo.get_by_external_id(tenant, "customer-4471") do
    {:ok, binding} ->
      binding

    {:error, :not_found} ->
      {:ok, pending} = Actions.Binding.enroll(tenant, %{external_id: "customer-4471"})

      {:ok, session} =
        Actions.Binding.bind(pending.enroll_token, %{
          public_key: Base.encode64(public_key),
          name: "Dana's iPhone",
          device_info: %{"model" => "iPhone 15", "os" => "iOS 18.2"},
          push_token: "seed-push-token",
          push_platform: :ios
        })

      session.binding
  end

payment = fn amount ->
  %{
    type: :payment,
    title: "Payment confirmation",
    description: "Transfer to ACME Ltd",
    payload: %{"amount" => amount, "currency" => "EUR", "beneficiary" => "ACME Ltd"}
  }
end

sign = fn request, decision ->
  request.id
  |> Sca.Crypto.signing_string(request.nonce, decision, request.payload_hash)
  |> then(&:crypto.sign(:ecdsa, :sha256, &1, [private_key, :secp256r1]))
  |> Base.encode64()
end

if RequestRepo.list_by_tenant(tenant) == [] do
  {:ok, _pending} = Actions.Request.create(binding, payment.("149.90"))

  {:ok, confirmed} = Actions.Request.create(binding, payment.("24.00"))

  {:ok, _confirmed} =
    Actions.Request.decide(confirmed, binding, "confirm", sign.(confirmed, "confirm"))

  {:ok, declined} = Actions.Request.create(binding, payment.("980.00"))
  {:ok, _declined} = Actions.Request.decide(declined, binding, "deny", sign.(declined, "deny"))

  {:ok, _overdue} =
    Actions.Request.create(
      binding,
      Map.put(payment.("12.50"), :expires_at, Timex.shift(Timex.now(), seconds: -30))
    )

  Actions.Request.expire_overdue()

  {:ok, _login} =
    Actions.Request.create(binding, %{
      type: :login,
      title: "Sign-in confirmation",
      description: "Someone is signing in to your account",
      payload: %{
        "ip" => "203.0.113.42",
        "location" => "Yerevan, AM",
        "device" => "Chrome on macOS"
      }
    })
end

{:ok, %{token: api_token}} =
  case Sca.Repos.ApiTokenRepo.list_by_tenant(tenant) do
    [] -> Actions.ApiToken.issue(tenant, %{name: "Development"})
    [existing | _rest] -> {:ok, %{token: "#{existing.preview} (issued earlier, not recoverable)"}}
  end

staff_email = "admin@enum8.example.com"
staff_password = "enum8-dev-password"

case Sca.Repos.AdminRepo.get_by_email(staff_email) do
  {:ok, admin} ->
    {:ok, _admin} = Actions.Admin.change_password(admin, staff_password)

  {:error, :not_found} ->
    {:ok, %{admin: admin}} =
      Actions.Admin.create(%{email: staff_email, name: "Sam Support", role: :superadmin})

    {:ok, _admin} = Actions.Admin.change_password(admin, staff_password)
end

IO.puts("""

  Seeded #{tenant.name} (#{tenant.public_id})
  Sign in at http://localhost:4000/log-in
    merchant  #{tenant.public_id}
    email     #{email}
    password  #{password}

  Merchant API key (Authorization: Bearer …)
    #{api_token}

  Admin console at http://localhost:4002/log-in
    email     #{staff_email}
    password  #{staff_password}
""")
