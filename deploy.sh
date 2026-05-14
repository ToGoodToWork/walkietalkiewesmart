#!/usr/bin/env bash
# Manual deploy script — runs ON THE VM, in /opt/walkie-talkie.
# After pushing changes from your Mac:  ssh in -> cd /opt/walkie-talkie -> ./deploy.sh
set -euo pipefail

cd "$(dirname "$0")"

if [[ ! -f .env ]]; then
  cat >&2 <<EOF
ERROR: .env not found at $(pwd)/.env

First-time setup:
  cp infra/.env.example .env
  nano .env          # fill in secrets
  chmod 600 .env
  ./deploy.sh

See docs/truenas-deploy.md for the full first-deploy walkthrough.
EOF
  exit 1
fi

# Make env vars (DUCKDNS_DOMAIN etc.) available in this shell for the smoke test.
set -a
# shellcheck disable=SC1091
source .env
set +a

COMPOSE=(docker compose --env-file ./.env -f infra/docker-compose.yml)

echo "==> Pulling latest code"
if [[ -d .git ]]; then
  git pull --ff-only
else
  echo "(not a git checkout — skipping git pull)"
fi

echo "==> Pulling base images (caddy, postgres, livekit)"
"${COMPOSE[@]}" pull caddy postgres livekit

echo "==> Building backend image"
"${COMPOSE[@]}" build backend

echo "==> Starting stack and waiting for healthy state"
# --wait blocks until every service with a healthcheck reports healthy,
# or fails after the container's retries are exhausted.
"${COMPOSE[@]}" up -d --wait --wait-timeout 120

echo "==> Running database migrations"
"${COMPOSE[@]}" exec -T backend npm run migrate

echo "==> External smoke test"
if curl -fsS --max-time 10 "https://api.${DUCKDNS_DOMAIN}/health" >/dev/null; then
  echo "    https://api.${DUCKDNS_DOMAIN}/health  OK"
else
  echo "    External smoke test FAILED — TLS may still be provisioning."
  echo "    First-run Let's Encrypt cert can take 30-90s. Watch:"
  echo "      ${COMPOSE[*]} logs -f caddy"
fi

echo "==> Done"
