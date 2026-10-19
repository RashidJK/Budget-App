#!/usr/bin/env bash
#
# Build and deploy the Spenda web app to Cloudflare Pages WITH its config
# compiled in. Use this instead of a bare `flutter build web`.
#
# WHY THIS EXISTS: a `flutter build web` run WITHOUT the --dart-define flags
# below produces a perfectly valid-looking site that is silently LOCAL-ONLY —
# no sign-in, no server sync, every device keeps its own data. The symptom is
# "I signed in on another laptop and my data isn't there." This script bakes the
# config in and refuses to deploy a bundle that lost it.
#
# Both values are PUBLIC (the Google client id is not a secret), so they live
# here as defaults; override via env vars if the hosts ever change.
set -euo pipefail

cd "$(dirname "$0")/.."

API_BASE="${API_BASE:-https://api.spenda.flow-hq.com}"
GOOGLE_CLIENT_ID="${GOOGLE_CLIENT_ID:-51882869696-1g7d9dco3hbundfeahsadkvs35fmqp1a.apps.googleusercontent.com}"
PROJECT="${CF_PAGES_PROJECT:-spenda}"

echo "▸ Building web (API_BASE=$API_BASE)"
flutter build web --release \
  --dart-define=API_BASE="$API_BASE" \
  --dart-define=GOOGLE_CLIENT_ID="$GOOGLE_CLIENT_ID"

# Guard: the config must have made it into the compiled bundle. If it didn't,
# this is a local-only build and deploying it would break cross-device sync.
if ! grep -q "$API_BASE" build/web/main.dart.js; then
  echo "✗ build/web/main.dart.js has no API base compiled in — this is a" >&2
  echo "  local-only build (no sign-in / no sync). Refusing to deploy." >&2
  exit 1
fi
echo "✓ Config verified in bundle"

echo "▸ Deploying to Cloudflare Pages project '$PROJECT'"
echo "  (needs a wrangler login or CLOUDFLARE_API_TOKEN)"
npx wrangler pages deploy build/web --project-name "$PROJECT"
