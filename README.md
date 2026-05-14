# Walkie-Talkie

Native iOS walkie-talkie app for organizations, with a self-hosted backend
(Node.js + Postgres + LiveKit + Caddy) running on a TrueNAS VM.

This repository is built milestone-by-milestone — see
[`claude-code-prompt.md`](./claude-code-prompt.md) for the full spec.

## Layout

```
/backend/                 Node.js + Fastify + Drizzle backend
/infra/                   docker-compose, Caddy, LiveKit, .env.example
/ios/                     iOS SwiftUI app (added in Milestone 2)
/docs/                    Deploy and operations docs
deploy.sh                 Manual deploy script (runs on the VM)
docker-compose.dev.yml    Local Postgres for development on your Mac
```

## Quick start

**On your Mac (one-time, before first push to GitHub):**

```bash
cd backend
npm install
npm run db:generate     # generates the initial Drizzle migration files
```

Commit the generated `backend/drizzle/` folder, then push.

**On the TrueNAS VM (first deploy):** see [`docs/truenas-deploy.md`](./docs/truenas-deploy.md).

**Subsequent deploys** (after pushing changes to GitHub):

```bash
ssh walkiehost@192.168.0.18
cd /opt/walkie-talkie
./deploy.sh
```

## Status

- ✅ Milestone 1: Repo scaffolding + first deploy
- ⏳ Milestone 2: Auth + iOS shell
- ⏳ Milestone 3+: see spec

## Operations

- Logs, backups, rotation: [`docs/operations.md`](./docs/operations.md)
- API reference: [`docs/api.md`](./docs/api.md)
