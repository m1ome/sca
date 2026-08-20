# SCA

Strong Customer Authentication as a service. Merchants integrate over HTTP;
their users approve payments and logins with a cryptographic signature on a
bound device.

An Elixir/Phoenix umbrella: one domain, three HTTP entrypoints.

| Application | What it is | Dev port |
|---|---|---|
| `apps/sca` | Domain: models, repos, actions, Oban workers | — |
| `apps/sca_api` | JSON API for merchants and for devices | 4001 |
| `apps/sca_web` | Merchant console (LiveView) | 4000 |
| `apps/sca_admin` | Internal admin console (LiveView, Oban Web) | 4002 |
| `apps/sca_ui` | Design system shared by both consoles | — |

Only `apps/sca` talks to the database.

## Running it

```bash
docker compose up -d db     # Postgres 18 on localhost:55433
mix setup                   # deps, assets, ecto.create + migrate
mix ecto.reset              # development data; prints the login at the end
mix phx.server              # all three endpoints at once
```

- merchant console — <http://localhost:4000>
- API — <http://localhost:4001>
- admin console — <http://localhost:4002>, Oban at `/dev/oban`, LiveDashboard at
  `/dev/dashboard`

## Development

```bash
mix test          # every application
mix lint          # format --check-formatted + credo --strict
mix precommit     # compile --warnings-as-errors, format, credo, test
mix typecheck     # dialyzer; the first run builds a PLT and takes minutes
```

Tests run against `sca_test` on the same container, in the Ecto sandbox.
Factories are `Sca.Factory` (ExMachina). Oban is in `testing: :manual`, so jobs
are asserted with `Oban.Testing` rather than executed.

## The APIs

Both live in `apps/sca_api`; the routes are in `ScaApi.Router`.

- `/api/sca/v1` — the device API, also served under `/t/:tenant` (which is what
  the enrollment QR points a phone at, so the merchant is in every device call;
  `POST /bindings` answers with that address and the QR payload itself, so a
  merchant stores no address of ours).
  Its shape is fixed by the mobile client already in people's hands. Bearer
  token per binding, issued at enrollment.
- `/api/merchant/v1` — the merchant API: bindings and approvals. API key
  (`Authorization: Bearer sca_…`), issued in the merchant console under
  Settings → API keys and shown once. Resources are named by uuid, and a retried
  call answers with the first result instead of making a second entity: for an
  approval the key is its `external_id`, for a binding an `Idempotency-Key`
  header.

## Building and deploying

Everything ships as one release, `sca`: the domain, the API and both consoles in
a single image.

```bash
docker build -t sca .
docker run --rm -e DATABASE_URL=… -e SECRET_KEY_BASE=… sca /app/bin/migrate
docker run -e DATABASE_URL=… -e SECRET_KEY_BASE=… -e PHX_HOST=sca.example.com \
  -p 4000-4002:4000-4002 sca
```

Migrations are a deploy step of their own, not something the container does on
boot. `/app/bin/setup` runs them and then creates the first staff account from
`ADMIN_EMAIL` and `ADMIN_PASSWORD` — both halves do nothing when there is
nothing to do, so it is safe as a pre-deploy command on every deploy.
`/app/bin/migrate` is the schema alone. The release starts the endpoints itself.

| Variable | What it does |
|---|---|
| `SECRET_KEY_BASE` | required; signs cookies — `mix phx.gen.secret` |
| `DATABASE_URL` | required, `ecto://USER:PASS@HOST/DATABASE` |
| `POOL_SIZE`, `ECTO_IPV6`, `DATABASE_SSL` | database tuning; defaults are 10, off, off |
| `PHX_HOST` | domain for absolute links and LiveView's origin check |
| `WEB_HOST`, `API_HOST`, `ADMIN_HOST` | per-endpoint overrides of `PHX_HOST` |
| `WEB_PORT`, `API_PORT`, `ADMIN_PORT` | default 4000, 4001, 4002 |
| `FCM_CREDENTIALS` | Firebase service account JSON, base64; without it push is off |
| `FCM_PROJECT_ID` | when the project differs from the one in the key |
| `ADMIN_EMAIL`, `ADMIN_PASSWORD` | the first staff account, created once by `/app/bin/setup` |
| `SENTRY_DSN` | without it crash reporting is inert |

## Not done yet

Attestation (Android Key / Apple App Attest — the fields exist, the verification
does not), rate limiting on the API, CI.
