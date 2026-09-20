# Airtel Money proxy

A tiny Dart ([shelf](https://pub.dev/packages/shelf)) backend that holds your
Airtel API credentials, does the OAuth2 token dance, and exposes **one** endpoint
the Budget app syncs from. The app never sees the client secret or the Airtel
token — that's the whole point of this service.

```
Budget app ──►  this proxy  ──►  Airtel OpenAPI
                  │  client_id / client_secret (env)
                  │  POST /auth/oauth2/token   (cached ~1h)
                  └─ GET  /merchant/v1/transactions
```

## Endpoint

```
GET /transactions?from=<epochMillis>&to=<epochMillis>&limit=100&offset=0
Authorization: Bearer <PROXY_API_KEY>        # only if PROXY_API_KEY is set
```

Returns Airtel's `/merchant/v1/transactions` JSON body verbatim — the app's
`RemoteTxn.parseAirtelSummary` already understands it.

Plus `GET /health` → `ok`.

## Configure

Copy `.env.example` and fill it in (see comments there):

| Variable | What |
| --- | --- |
| `AIRTEL_BASE_URL` | `https://openapiuat.airtel.co.tz` (staging) → `https://openapi.airtel.co.tz` (prod) |
| `AIRTEL_CLIENT_ID` / `AIRTEL_CLIENT_SECRET` | from your Airtel developer app |
| `AIRTEL_COUNTRY` / `AIRTEL_CURRENCY` | `TZ` / `TZS` — sent as `x-country` / `x-currency` |
| `PROXY_API_KEY` | shared secret for the app↔backend call (long random string; empty = no auth) |
| `PORT` | listen port (default `8080`) |

## Run locally

```sh
dart pub get
set -a && source .env && set +a      # load env vars
dart run bin/server.dart
# → Airtel proxy listening on :8080

curl "http://localhost:8080/transactions?from=1772800000000&to=1773100000000&limit=100&offset=0" \
  -H "Authorization: Bearer $PROXY_API_KEY"
```

## Deploy (Cloud Run)

```sh
gcloud run deploy airtel-proxy --source . --region <region> --allow-unauthenticated \
  --set-env-vars AIRTEL_BASE_URL=https://openapi.airtel.co.tz,AIRTEL_COUNTRY=TZ,AIRTEL_CURRENCY=TZS
# set AIRTEL_CLIENT_ID / AIRTEL_CLIENT_SECRET / PROXY_API_KEY as secrets, not plain env vars
```

(The `Dockerfile` builds an AOT binary on a scratch image; any container host —
Fly.io, Render, a VPS — works the same way.)

## Point the app at it

In the Budget app, swap the demo source for the real one:

```dart
final source = HttpTransactionSource(
  endpoint: Uri.parse('https://<your-proxy-host>/transactions'),
  userMsisdn: '785000000',        // your wallet number, no country code
  authToken: '<PROXY_API_KEY>',   // matches the backend
);
// TransactionSync(state: state, source: source).run();
```

That's the only app change — parsing, mapping, dedup and the UI are already done.

## Note on scope

Transactions-Summary returns the **merchant account's** transactions
(`MERCHPAY` = payments received, `CASHIN` = cash-ins), so it's ideal for
auto-recording money **in**. Personal outgoing sends/cash-outs only appear when
your number is the payer on a `MERCHPAY`.
