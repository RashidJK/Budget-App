# Budget / Spaces API

A small Dart ([shelf](https://pub.dev/packages/shelf)) backend for the product:

- **Google sign-in** — the app sends a Google ID token; the server verifies it
  and returns its own session token.
- **Sync** — a per-user document store with last-write-wins. One `POST /sync`
  pushes the records a device changed and pulls back everything else.
- **Airtel Money proxy** — the original `/transactions` endpoint, unchanged and
  optional.

Nothing secret (Google client secret, Airtel credentials, the session signing
key) ever reaches the app.

```
Flutter web (Cloudflare Pages)  ──►  this API (Contabo VPS, Docker)  ──►  Postgres
        Google ID token                 verifies, mints a session           JSONB docs
```

## Endpoints

| Method + path | Auth | Body → result |
| --- | --- | --- |
| `POST /auth/google` | — | `{idToken}` → `{token, email, name}` |
| `POST /sync` | `Bearer <token>` | `{since, changes}` → `{cursor, changes}` |
| `GET /transactions` | `Bearer <PROXY_API_KEY>` | Airtel summary JSON (optional) |
| `GET /health` | — | `ok` |

`changes` is `{ "expenses": [ {record}, … ], "brain": [ … ], … }`; each record
is a model's JSON, already carrying `id` / `updatedAt` / `deletedAt`. `since` /
`cursor` are integers — send back the `cursor` you last received.

## Configure

Copy `.env.example` → `.env` and fill it in. Generate the secrets with
`openssl rand -hex 32`. `GOOGLE_CLIENT_ID` and `CORS_ORIGIN` are the two that
must match the frontend.

## Run it on Contabo (Docker)

On a fresh Ubuntu VPS:

```sh
# 1. Install Docker (get.docker.com) and the compose plugin.
curl -fsSL https://get.docker.com | sh

# 2. Get the code and configure.
git clone <your repo> && cd Budget/backend
cp .env.example .env && nano .env      # fill in secrets + CORS_ORIGIN

# 3. Build and start the API + Postgres.
docker compose up -d --build
curl localhost:8080/health             # → ok
```

The API listens on `127.0.0.1:8080`. Put TLS in front of it — easiest is
**Cloudflare Tunnel** (no open ports, no manual certs):

```sh
# Install cloudflared, then:
cloudflared tunnel login
cloudflared tunnel create budget-api
cloudflared tunnel route dns budget-api api.yourdomain.com
cloudflared tunnel run --url http://localhost:8080 budget-api
```

(Or a reverse proxy like Caddy with `api.yourdomain.com { reverse_proxy
localhost:8080 }` for automatic Let's Encrypt certs.) Either way the app talks
to `https://api.yourdomain.com`.

## Google OAuth setup

In the [Google Cloud Console](https://console.cloud.google.com/apis/credentials):

1. Create an **OAuth client ID** → **Web application**.
2. Under *Authorised JavaScript origins*, add the frontend origin(s):
   `https://your-app.pages.dev` (and `http://localhost:8732` for local dev).
3. Copy the client ID into `GOOGLE_CLIENT_ID` here **and** into the Flutter web
   build (`--dart-define=GOOGLE_CLIENT_ID=…`). No client *secret* is needed —
   the app uses Google Identity Services and the server only verifies the token.

## Frontend on Cloudflare Pages

```sh
cd ..                                  # repo root
flutter build web --release \
  --dart-define=API_BASE=https://api.yourdomain.com \
  --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
# Deploy build/web — via the Pages dashboard (connect the repo, build command
# above, output dir build/web) or Wrangler:
npx wrangler pages deploy build/web --project-name spaces
```

Set `CORS_ORIGIN` in `.env` to the resulting Pages URL (or your custom domain),
then `docker compose up -d` again.

## Local development

```sh
cd backend
dart pub get
set -a && source .env && set +a
dart run bin/server.dart            # needs a reachable Postgres in DATABASE_URL
```

## Note on the Airtel scope

Transactions-Summary returns the **merchant account's** transactions
(`MERCHPAY` received, `CASHIN`), so it's ideal for auto-recording money **in**.
Leave the `AIRTEL_*` vars blank to disable the endpoint entirely.
