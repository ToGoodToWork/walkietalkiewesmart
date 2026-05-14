# First Deploy — TrueNAS VM

End-to-end walkthrough for getting the stack running on the Debian VM
(`192.168.0.18`, user `walkiehost`) the very first time.

Assumes the infrastructure prerequisites from `claude-code-prompt.md` §0 are
already in place (VM up, Docker installed, ports forwarded, DuckDNS resolving).

---

## 1. On your Mac — generate migrations and push

Drizzle needs migration SQL to be checked into git. Do this once:

```bash
cd backend
npm install
npm run db:generate
cd ..
git add backend/drizzle
```

Then commit everything and push to GitHub (replace the URL with yours):

```bash
git remote add origin git@github.com:<you>/walkie-talkie.git
git branch -M main
git commit -m "Milestone 1: scaffolding"
git push -u origin main
```

## 2. Generate the five secrets

Run these on your Mac and paste each output into `secrets.txt` (kept on your
Mac only — already in `.gitignore`, never committed):

```bash
# JWT_ACCESS_SECRET
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# JWT_REFRESH_SECRET
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"

# POSTGRES_PASSWORD
node -e "console.log(require('crypto').randomBytes(16).toString('base64url'))"

# LIVEKIT_API_KEY  (must start with "API")
node -e "console.log('API' + require('crypto').randomBytes(8).toString('hex'))"

# LIVEKIT_API_SECRET
node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"
```

## 3. SSH to the VM and clone

```bash
ssh walkiehost@192.168.0.18

sudo mkdir -p /opt/walkie-talkie
sudo chown walkiehost:walkiehost /opt/walkie-talkie
cd /opt/walkie-talkie

git clone https://github.com/<you>/walkie-talkie.git .
```

If you use SSH keys with GitHub, use the `git@github.com:...` URL instead and
make sure your VM has access (private repo? add a deploy key).

## 4. Create `.env` on the VM

```bash
cp infra/.env.example .env
nano .env
```

Paste your secrets in for every `__from_secrets__` line. Double-check
`DUCKDNS_DOMAIN` and `ACME_EMAIL` look right.

Lock it down:

```bash
chmod 600 .env
```

## 5. Make sure the Postgres data path exists

```bash
sudo mkdir -p /opt/walkie-talkie/postgres-data
sudo chown -R 70:70 /opt/walkie-talkie/postgres-data
```

(UID/GID 70 is the alpine postgres user inside the container.)

If you want Postgres on a different path (e.g. a TrueNAS-mounted dataset), set
`POSTGRES_DATA_PATH=/your/path` in `.env` and `mkdir -p` + `chown 70:70` it.

## 6. First deploy

```bash
./deploy.sh
```

The script:

1. `docker compose pull` caddy, postgres, livekit
2. Builds the backend image from `/backend`
3. `docker compose up -d`
4. Waits for backend `/health`
5. Runs database migrations via `npm run migrate`
6. Curls `https://api.walkiehost.duckdns.org/health` from inside the VM

First-time Let's Encrypt cert provisioning can take 30–90 seconds. If the
external smoke-test prints `FAILED`, give Caddy a minute then retry:

```bash
curl https://api.walkiehost.duckdns.org/health
docker logs walkie-talkie-caddy-1 --tail=80
```

## 7. Seed the database (one-time)

```bash
docker compose --env-file ./.env -f infra/docker-compose.yml \
  exec -T backend npm run seed
```

This prints the admin email + password + invite code **once**. Save them to
`secrets.txt`. Re-running the seed is safe — it's a no-op once an org exists.

## 8. Verify

From your Mac:

```bash
curl https://api.walkiehost.duckdns.org/health
# {"status":"ok","timestamp":"2026-..."}
```

```bash
ssh walkiehost@192.168.0.18 'docker compose -f /opt/walkie-talkie/infra/docker-compose.yml ps'
# All four services should be Up (healthy)
```

---

## Common first-deploy failures

### Caddy can't get a TLS cert

```bash
docker logs walkie-talkie-caddy-1 --tail=100
```

Look for ACME errors. Most common causes:
- Port 80 not actually reachable from the public internet → re-check UDM Pro
  forwards and `185.91.166.28:80`.
- DuckDNS A record stale → run the updater script manually, then `dig` the
  hostname from a public DNS to confirm.
- ACME rate limit (5 cert failures in an hour) → wait 1h and retry.

### Postgres won't start ("permission denied")

The container's postgres user (UID/GID 70) must own the host data dir:

```bash
sudo chown -R 70:70 /opt/walkie-talkie/postgres-data
docker compose -f infra/docker-compose.yml restart postgres
```

### Backend exits immediately

```bash
docker compose -f infra/docker-compose.yml logs backend --tail=80
```

Usually a Zod env validation error — open `.env` and check every required var
is set.

### `./deploy.sh` fails on the migrate step

Migrations dir is empty. You forgot Step 1 — run `npm run db:generate` on your
Mac, commit `backend/drizzle/`, push, then `git pull && ./deploy.sh` on the VM.

### LiveKit logs say "no keys configured"

`.env` has placeholder values for `LIVEKIT_API_KEY` / `LIVEKIT_API_SECRET`. Fill
them in, then `docker compose -f infra/docker-compose.yml up -d livekit` to
recreate the container.
