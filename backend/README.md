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
curl localhost:${HOST_PORT:-8090}/health   # → ok
```

The stack is namespaced (`spenda-api`, `spenda-db`, `spenda_pgdata`) and the
API binds to `127.0.0.1:${HOST_PORT}` (default **8090**), so it won't collide
with the other projects on the box. Postgres isn't published at all — it's only
reachable inside the compose network.

### Route the API subdomain through the box's existing reverse proxy

`api.spenda.flow-hq.com` → `127.0.0.1:8090`. (We use `api.spenda.flow-hq.com`,
not `api.flow-hq.com`, which another project owns.) Add one vhost to whatever
proxy already fronts the other sites:

**nginx** — `/etc/nginx/sites-available/api.spenda.flow-hq.com`, then symlink
into `sites-enabled/`, `nginx -t`, `systemctl reload nginx`:
```nginx
server {
  listen 80;
  listen [::]:80;
  server_name api.spenda.flow-hq.com;

  location / {
    proxy_pass http://127.0.0.1:8090;
    proxy_http_version 1.1;
    proxy_set_header Host $host;
    proxy_set_header X-Real-IP $remote_addr;
    proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    proxy_set_header X-Forwarded-Proto $scheme;
  }
}
```
Then `sudo certbot --nginx -d api.spenda.flow-hq.com` adds the `443` block,
the cert and the http→https redirect. (If the Cloudflare record is proxied,
certbot's HTTP-01 challenge still works over port 80; if it ever fails, flip the
record to DNS-only, issue, then re-enable the proxy and set SSL mode
Full (strict).)

Point an `A` record for `api.spenda.flow-hq.com` at the VPS IP. The app then
talks to `https://api.spenda.flow-hq.com`.

(Caddy: `api.spenda.flow-hq.com { reverse_proxy 127.0.0.1:8090 }`. Traefik: a
router on `Host(\`api.spenda.flow-hq.com\`)` → `127.0.0.1:8090`.)

## Google OAuth setup

In the [Google Cloud Console](https://console.cloud.google.com/apis/credentials):

1. Create an **OAuth client ID** → **Web application**.
2. Under *Authorised JavaScript origins*, add the frontend origin(s):
   `https://spenda.flow-hq.com` (and `http://localhost:8732` for local dev).
3. Copy the client ID into `GOOGLE_CLIENT_ID` here **and** into the Flutter web
   build (`--dart-define=GOOGLE_CLIENT_ID=…`). No client *secret* is needed —
   the app uses Google Identity Services and the server only verifies the token.

## Frontend on Cloudflare Pages (spenda.flow-hq.com)

Use the deploy script — it bakes the config in and refuses to ship a build that
lost it:

```sh
cd ..                                  # repo root
./scripts/deploy_web.sh
```

> ⚠️ The `--dart-define` flags are not optional. A plain `flutter build web`
> (or a Pages "connect the repo" build that can't run Flutter) ships a
> **local-only** site: it loads fine but has no sign-in and no sync, so each
> device keeps its own data. Symptom: "I signed in on another laptop and my
> data isn't there." Always build via the script, or by hand with the flags:

```sh
flutter build web --release \
  --dart-define=API_BASE=https://api.spenda.flow-hq.com \
  --dart-define=GOOGLE_CLIENT_ID=xxxx.apps.googleusercontent.com
npx wrangler pages deploy build/web --project-name spenda   # Direct Upload only
```

Add `spenda.flow-hq.com` as the Pages project's custom domain. `CORS_ORIGIN` in
`.env` is already that origin; re-run `docker compose up -d` after any change.

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
