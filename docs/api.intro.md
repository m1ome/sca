Strong Customer Authentication as a service. Your user approves a payment or a
sign-in on a device bound to them, and what you are left with is a signature
made by a key that never left that device.

This is the **merchant API**, `/api/merchant/v1`: it enrols devices and raises
approvals, and it is everything an integration needs. What happens between the
phone and us afterwards is ours to worry about.

Every example below is generated from the test suite: the requests were really
made and the responses are what the server really answered.

## How an integration goes

1. **Enrol the person once.** `POST /bindings`, carrying your own identifier for
   them, answers with an activation code and the exact string to put into a QR.
   They scan it with the app, the binding turns `active`, and a
   `binding.activated` webhook says so.
2. **Ask for an approval.** `POST /approvals` names the device and what is being
   approved. The card arrives on the phone as a push notification.
3. **Learn the answer.** A `request.confirmed` or `request.declined` webhook
   arrives; `GET /approvals/{id}` says the same thing to anyone who would rather
   poll.
4. **Keep the evidence.** A confirmed approval carries the signature, the exact
   bytes that were signed, and the hash of the parameters you sent.

## Addresses

The merchant API is at `/api/merchant/v1` on the API host of your deployment —
the console prints it under Settings. Everything in this document is relative to
that host.

There is one version, `v1`, and it is in the path. A new field may appear in a
response at any time; nothing that exists is renamed or removed without a new
version, so parse leniently and ignore what you do not know.

## Authentication

Every call carries an API key as a bearer token:

```
Authorization: Bearer sca_live_9WKUq...
```

Keys are issued in the merchant console under **Settings -> API keys**, shown
once at creation and never again, and can be revoked there. A key belongs to one
merchant, and every lookup it makes is narrowed to that merchant's data: another
merchant's binding is `404`, never `403`.

- `401 unauthorized` — no key, an unknown key, or one that has been revoked.
- `403 merchant_suspended` — the key is fine, the account is not being served.

Keys are secrets in the same sense as a password: they belong on your server,
never in a mobile app or a browser.

## Retrying safely

An HTTP call that times out leaves you unable to tell whether it happened, so
both creating calls are safe to repeat.

**Approvals** are keyed by `external_id` — your own reference for the thing being
approved, which you almost certainly already have. Repeat a `POST /approvals`
with the same `external_id` and the first card comes back with `200` instead of a
second one being raised on the phone. When you send no `external_id`, an
`Idempotency-Key` header fills it in.

**Bindings** are keyed by the `Idempotency-Key` header alone. Their `external_id`
names a *person*, not a call — enrolling the same person again is how a lost
phone is replaced, so it cannot double as the retry key. A repeated call answers
`200` with the same activation code, which matters: a fresh code would invalidate
the QR you may already be showing.

## Paging

Lists take `page` (from 1) and `page_size` (50 by default, 100 at most), and
answer with the rows in `data` and the position in `page`:

```json
{
  "data": [],
  "page": { "current": 1, "size": 50, "total_pages": 3, "total_count": 118 }
}
```

## Errors

Every refusal has the same shape, whichever API it came from:

```json
{
  "error": {
    "code": "invalid_request",
    "message": "Some fields were rejected.",
    "fields": { "currency": ["is required for a payment request"] }
  }
}
```

`code` is for your code, `message` is for a human reading a log, and `fields` is
present only when individual fields were rejected — keyed as you sent them.

| Status | `code` | What happened |
|---|---|---|
| 400 | `invalid_request` | A required field of the call itself is missing |
| 401 | `unauthorized` | The API key is missing, unknown or revoked |
| 403 | `merchant_suspended` | The account is not being served |
| 404 | `not_found` | No such binding or approval **for this merchant** |
| 409 | `binding_not_active` | That device is pending or revoked and cannot be asked |
| 409 | `not_pending` | The approval was already answered, cancelled or has expired |
| 422 | `invalid_request` | Fields were rejected; see `fields` |

## What a card may carry

`params` is what the phone shows the user and what the signature is computed
over, so it is deliberately narrow: a flat object of strings, numbers or
booleans — no nested objects, no arrays. Nothing else has a rendering that iOS
and Android can reproduce byte for byte.

- at most 20 fields; names up to 40 characters, values up to 200
- `title` up to 140 characters, `description` up to 500
- unknown keys are welcome and are shown to the user as extra rows

Three types, differing only in what they insist on:

| `type` | Required `params` |
|---|---|
| `payment` | `amount`, `currency`, `beneficiary` |
| `login` | `ip` |
| `freeform` | none |

`amount` is a plain decimal with at most two fraction digits (`"149.90"`), kept
as the string you sent — the phone hashes that exact text. `currency` is an
ISO 4217 code and is upper-cased. `ip` must parse as an IPv4 or IPv6 address.

## Deadlines

An approval expires on its own. Send `expires_at` (RFC 3339) to say when, or
leave it out and the merchant default applies — 5 minutes, adjustable between 30
seconds and an hour in the console. An expired card cannot be answered by the
device any more and turns `expired`, with a webhook to match.

An activation code lives for 15 minutes. Once the device is bound it stays
bound: a user who opens the app now and then never scans a QR again, and one who
does not is asked for a new code only after a month of silence.

## Statuses

A binding: `pending` (enrolled, nobody has scanned it yet) -> `active` -> `revoked`.
Revoking is final; the person enrols again to get a new device.

An approval: `pending` -> `confirmed` | `declined` (the user answered),
`expired` (the clock), `cancelled` (you took it back).

## Webhooks

The URL, the signing secret and an optional encryption certificate live in the
console under **Settings -> Webhooks**, where you can also fire any event at your
endpoint as a test — the same envelope, the same signature, with `"test": true`
added so a receiver can take it apart without acting on it.

Events: `binding.activated`, `binding.revoked`, `request.created`,
`request.confirmed`, `request.declined`, `request.expired`, `request.cancelled`.

The envelope keeps its routing metadata in the clear:

```json
{
  "id": "0f1c...",
  "event": "request.confirmed",
  "created_at": "2026-08-20T10:11:12Z",
  "data": {
    "request": { "id": "...", "external_id": "order-4471", "status": "confirmed" },
    "binding": { "id": "...", "external_id": "customer-4471", "status": "active" }
  }
}
```

The identifiers are the same UUIDs the API answered you with, so a webhook can be
matched against the call that caused it. With a certificate configured, `data` is
replaced by `encrypted`: a compact JWE (`RSA-OAEP-256` + `A256GCM`) of the same
object, so what a log or a queue keeps afterwards is unreadable without your
private key.

Each delivery carries:

```
X-SCA-Event: request.confirmed
X-SCA-Delivery: 0f1c...
X-SCA-Signature: t=1755500000,v1=<hex>
```

The signature is `HMAC-SHA256(secret, "<t>.<raw body>")`, hex, lower case. The
timestamp is inside the signed string, so a captured call cannot be replayed
later; reject anything older than a few minutes, and compare digests in constant
time.

Answer `2xx` and be quick about it: connect times out after 5 seconds, the
response after 10. Anything else is retried up to 8 times with jittered
exponential backoff, from half a minute to an hour. Redirects are not followed.
Deliveries and their attempts are visible in the console, and can be resent from
there.

## The evidence you keep

A confirmed or declined approval carries three fields worth storing:

- `payload_hash` — SHA-256, lower-case hex, of the canonical rendering of
  `params`: keys sorted, one `key=value` line each, joined with `\n`.
- `signed_payload` — the exact string the device signed:
  `sca-service:v1:{approval id}:{nonce}:{confirm|deny}:{payload_hash}`
- `signature` — base64 of an ASN.1 DER ECDSA signature over SHA-256 of that
  string, made with the device key (`signature_algorithm: "ecdsa-p256"`).

The check worth making is that the card the user signed is the card you asked
for: recompute `payload_hash` from the `params` you sent and confirm it is the
one inside `signed_payload`. The device's public key stays with us on purpose —
it is what makes a signature ours to verify and not something a merchant can
forge — so verifying the signature itself is our side of the bargain, done
before an approval is ever reported as confirmed.
