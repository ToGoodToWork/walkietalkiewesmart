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

echo "==> Starting stack"
"${COMPOSE[@]}" up -d

echo "==> Waiting for backend health"
for i in {1..30}; do
  if "${COMPOSE[@]}" exec -T backend wget -qO- http://localhost:3000/health >/dev/null 2>&1 \
     || curl -fsS http://localhost:3000/health >/dev/null 2>&1; then
    echo "    backend healthy"
    break
  fi
  if [[ $i -eq 30 ]]; then
    echo "ERROR: backend did not become healthy in 60s"
    "${COMPOSE[@]}" logs --tail=120 backend
    exit 1
  fi
  sleep 2
done

echo "==> Running database migrations"
"${COMPOSE[@]}" exec -T backend npm run migrate

echo "==> External smoke test"
if curl -fsS "https://api.${DUCKDNS_DOMAIN}/health" >/dev/null; then
  echo "    https://api.${DUCKDNS_DOMAIN}/health  OK"
else
  echo "    External smoke test FAILED — TLS may still be provisioning."
  echo "    First-run Let's Encrypt cert can take 30-90s. Watch:"
  echo "      docker logs -f walkie-talkie-caddy-1"
fi

echo "==> Done"
