# Operations

Day-to-day commands for running the stack. Everything assumes you are SSH'd
into the VM as `walkiehost` and in `/opt/walkie-talkie`.

`COMPOSE` shorthand below:

```bash
alias dc='docker compose --env-file ./.env -f infra/docker-compose.yml'
```

(Add to `~/.bashrc` if you want it persistent.)

---

## Tail logs

```bash
dc logs -f                 # everything
dc logs -f backend         # just the API
dc logs -f caddy           # TLS / proxy issues
dc logs -f postgres
dc logs -f livekit
```

## Restart one service

```bash
dc restart backend
dc restart caddy
```

## Rebuild after pulling new code

`./deploy.sh` does this. To do it manually:

```bash
git pull --ff-only
dc build backend
dc up -d
dc exec -T backend npm run migrate
```

## Roll back

```bash
git log --oneline -10           # find the previous good commit
git checkout <sha>
./deploy.sh
```

If a migration was applied that the older code can't tolerate, you'll need a
DB restore from backup (see below).

---

## Backups

The Postgres data lives at `/opt/walkie-talkie/postgres-data`. Two
complementary strategies:

### 1. TrueNAS snapshots (recommended)

Configure a periodic snapshot task in TrueNAS on the dataset that backs the
VM's `/opt/walkie-talkie/postgres-data`. Snapshots are crash-consistent for
Postgres because `postgresql.conf` defaults to fsync. Snapshot frequency:
hourly, retain 7 days; daily, retain 30 days.

### 2. Logical dumps (offsite)

```bash
dc exec -T postgres pg_dump -U walkietalk walkietalk \
  | gzip > /opt/walkie-talkie/backups/$(date +%Y%m%d-%H%M%S).sql.gz
```

Cron suggestion:

```cron
0 3 * * * cd /opt/walkie-talkie && docker compose --env-file ./.env -f infra/docker-compose.yml exec -T postgres pg_dump -U walkietalk walkietalk | gzip > /opt/walkie-talkie/backups/$(date +\%Y\%m\%d).sql.gz
```

Restore:

```bash
gunzip < backups/20260601.sql.gz \
  | dc exec -T postgres psql -U walkietalk -d walkietalk
```

---

## Rotating secrets

### JWT secrets

Edit `.env` with the new value, then `dc restart backend`. All existing
access/refresh tokens immediately become invalid — users must log in again.

### Postgres password

Trickier because the password is baked into the Postgres data dir at first
init. The safest sequence:

```bash
dc exec -T postgres psql -U walkietalk -d postgres \
  -c "ALTER USER walkietalk WITH PASSWORD '<new>';"
# Update .env with the new password
dc up -d --force-recreate backend
```

### LiveKit keys

Edit `.env`, then `dc up -d --force-recreate livekit backend`. Old LiveKit
tokens immediately stop working — users will be ejected from rooms and the iOS
app will reconnect with fresh tokens from the backend.

### `.env` hygiene

```bash
chmod 600 .env
sudo chown walkiehost:walkiehost .env
```

Never `git add .env`. The repo's `.gitignore` excludes it.

---

## Inspecting the stack

```bash
dc ps                          # all services + health status
dc top                         # processes inside each container
docker stats                   # live resource usage
dc exec backend node --version # poke into the backend
dc exec postgres psql -U walkietalk walkietalk
```

---

## Migrations

```bash
# Local on your Mac: generate after editing src/db/schema.ts
cd backend && npm run db:generate
git add drizzle && git commit -m "migration: ..."

# On the VM after `git pull`:
dc exec -T backend npm run migrate
```

`deploy.sh` runs `npm run migrate` automatically.

To inspect migration state:

```bash
dc exec -T postgres psql -U walkietalk -d walkietalk \
  -c "SELECT * FROM drizzle.__drizzle_migrations ORDER BY created_at;"
```

---

## When things look weird

```bash
dc ps                                # which container died?
dc logs --tail=120 backend           # last 2 minutes
dc events --since=10m                # docker daemon events
docker system df                     # are we out of disk?
df -h /opt/walkie-talkie             # is the data volume full?
```

If Caddy can't renew certs, check `dc logs caddy` for ACME errors and confirm
port 80 is still externally reachable.
