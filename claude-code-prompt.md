# Walkie-Talkie App — Build Spec

You are building a native iOS walkie-talkie app for organizations. The entire backend is self-hosted on the user's TrueNAS server, deployed **manually** via a `deploy.sh` script. Read this whole spec before writing any code. Confirm the open questions at the end of Milestone 1's section, then proceed.

**After each milestone, stop and let me test before continuing.** Do not run ahead.

---

## 0. CURRENT STATE (already done — don't redo)

The user has already completed the following infrastructure setup. Build on top of this:

**TrueNAS host:**
- TrueNAS SCALE running
- Debian 12 VM created on TrueNAS named `walkie-talkie-host`
- VM has a static-ish IP `192.168.0.18` (DHCP reserved on UDM Pro)
- User account: `walkiehost` (with sudo)

**Software on the VM:**
- Docker Engine + Docker Compose plugin (verified working)
- git, curl, ufw, rsync installed
- Python 3 available
- The VM has internet access and SSH enabled

**Networking:**
- Public WAN IP: `185.91.166.28`
- ISP forwards all ports without restriction to UDM Pro
- UDM Pro port forwards active and verified working for:
  - 80/tcp, 443/tcp, 7881/tcp → `192.168.0.18`
  - 3478/udp, 50000-50200/udp → `192.168.0.18`
- DuckDNS subdomain: `walkiehost.duckdns.org` → resolves to public IP
- DuckDNS auto-updater running as cron on the VM at `/opt/duckdns/duck.sh`
- Inbound connectivity to the VM verified working via external port checker

**Secrets the user has or will generate:**
- `DUCKDNS_DOMAIN`, `DUCKDNS_TOKEN`
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`
- `POSTGRES_PASSWORD`
- `LIVEKIT_API_KEY`, `LIVEKIT_API_SECRET`

The user keeps these in a local `secrets.txt` on their Mac. When you need any of them, **ask the user** rather than try to generate or store them yourself. The exception: if the user hasn't generated some yet, give them the exact command to generate it (e.g. `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`).

**What is NOT yet done:**
- The GitHub repo is empty
- Nothing has been cloned to the VM at `/opt/walkie-talkie` yet
- No `.env` file exists on the VM yet
- iOS app does not exist yet
- Backend code does not exist yet
- Apple Developer account: free personal team only

---

## 1. Product Overview

A real-time voice + text app where members of an organization:

- Join multiple voice **channels** at once and hear all of them mixed together.
- Press a big **push-to-talk (PTT)** button or use **voice activation (VAD)** to transmit to a chosen channel.
- **Whisper** privately to any org member via a 1:1 audio overlay that automatically ducks (lowers) all other channels — does NOT disconnect them from anything else.
- Send and read **text messages** in each channel. A **Global Feed** aggregates messages from every channel the user can see, tagged by source channel; tapping a message jumps into that channel.
- **Admins** manage users, roles, channels, and invites from inside the app — Discord-style permission model.

Platform: **iOS only**, iPhone, iOS 17+. Must run with the screen locked / app backgrounded.

---

## 2. Tech Stack (pinned)

### Mobile app
- **Native iOS, SwiftUI, Swift 5.9+, iOS 17 minimum.**
- Async/await throughout. **SwiftData** for local cache.
- **LiveKit Swift SDK** (`livekit/client-sdk-swift`) for real-time audio.
- AVFoundation for audio session configuration.
- Keychain for token storage.
- `URLSessionWebSocketTask` for the realtime channel.

### Backend
- **Node.js 20 + Fastify + TypeScript** (strict mode).
- **In-memory state** for presence, rate limiting, and whisper room registry (no Redis — single backend instance).
- Single Dockerfile.
- All configuration via environment variables.

### Infrastructure (on the user's Debian VM)
- **Docker Compose** orchestrates everything in one stack.
- **Caddy** — reverse proxy + automatic Let's Encrypt TLS. Single Caddyfile.
- **Postgres 16** — in a container, data volume on the VM filesystem.
- **LiveKit Server** (self-hosted, `livekit/livekit-server` image) — WebRTC SFU.
- **Backend container** — manually rebuilt via `deploy.sh` on each deploy.

### Domain
- DuckDNS subdomain `walkiehost.duckdns.org` with subdomains routed by Caddy:
  - `api.walkiehost.duckdns.org` → backend
  - `livekit.walkiehost.duckdns.org` → LiveKit signaling

### Deployment model
**Manual deploy via shell script.** Workflow:
1. User develops on Mac
2. `git push` to GitHub from Mac
3. SSH to VM: `cd /opt/walkie-talkie && git pull && ./deploy.sh`
4. Test

No GitHub Actions, no auto-deploy, no self-hosted runner. Simple and explicit.

---

## 3. Repository Layout

```
/walkie-talkie/
  /backend/
    Dockerfile
    package.json
    tsconfig.json
    src/
    migrations/
    .env.example
  /ios/
    WalkieTalkie.xcodeproj
    WalkieTalkie/...
    Config/                    # xcconfig files: Debug vs Release
  /infra/
    docker-compose.yml         # the full production stack
    Caddyfile                  # reverse proxy + TLS
    livekit.yaml               # LiveKit server config
    .env.example               # production env vars template
  /docs/
    truenas-deploy.md          # one-time deploy steps
    operations.md              # logs, backups, common issues
    api.md
  deploy.sh                    # manual deploy script (run on VM)
  docker-compose.dev.yml       # local dev — just Postgres
  README.md
  .gitignore                   # MUST exclude .env, secrets.txt, *.p8, build artifacts
```

**Local dev:** developer runs Postgres locally via `docker-compose.dev.yml`, backend via `npm run dev` against it. iOS Debug config points at `http://localhost:3000`.

**Production:** the entire `/infra/` stack runs on the VM at `/opt/walkie-talkie/`. iOS Release config points at `https://api.walkiehost.duckdns.org`.

---

## 4. Domain Model

```
Organization
  id, name, created_at

User
  id, org_id, email, password_hash, display_name, avatar_url,
  status (online|busy|dnd|offline), last_seen_at, created_at

Role
  id, org_id, name, color, position (int for hierarchy), permissions JSONB:
    manage_org, manage_users, manage_roles, manage_channels,
    whisper_anyone, bypass_channel_perms

UserRole          (user_id, role_id)

Channel
  id, org_id, name, description, type (normal|broadcast|private),
  position, created_at

ChannelPermission   (channel_id, role_id, can_join, can_speak,
                     can_read_messages, can_post_messages, can_manage)
ChannelMember       (channel_id, user_id)   -- only for private channels

Message
  id, channel_id, user_id, content (text), reply_to_message_id (nullable),
  created_at, edited_at, deleted_at

MessageRead         (user_id, channel_id, last_read_message_id, last_read_at)

Invite
  id, org_id, code, created_by, expires_at, max_uses, used_count, created_at

Device
  id, user_id, apns_token, created_at        -- optional, only for push
```

Use **drizzle-kit** for migrations and schema.

Seed script creates: org, Admin role with all perms, Member role, "General" channel, one admin user, one invite code (prints to console on run).

---

## 5. Permissions Model

Discord-style overwrites:

1. Default Member role grants base perms.
2. Higher-position roles override lower for conflicts.
3. Per-channel `ChannelPermission` rows override role defaults for that channel.
4. `bypass_channel_perms` lets admins enter/speak anywhere.

**Server enforces everything.** Backend computes effective permissions per (user, channel) and bakes them into LiveKit token grants (`canPublish`, `canSubscribe`). Never trust the client.

---

## 6. Voice Architecture

### Listening to multiple channels
- One LiveKit room per channel.
- iOS app maintains multiple `Room` instances simultaneously via the Swift SDK.
- Per-channel volume slider adjusts gain on that room's remote tracks.
- Per-channel mute (stop listening) and self-mute (mic off) toggles.

### Push-to-talk
- Default mode. Big circular button at bottom of main screen, ≥80pt diameter.
- A chip just above the button shows the PTT target channel. Tap to switch among joined channels.
- Hold the button → unmute publish track in target room only. Release → mute.
- Haptic feedback on press and release. Animated ring while transmitting.
- Stretch (Milestone 9): volume-down hardware key as PTT trigger.

### Voice activation
- Global toggle in settings (one mode at a time per user).
- Use LiveKit's audio level detection with a sensitivity slider.
- Transmits only to the currently selected channel.

### Whisper (1:1 private audio)
- `POST /whispers/start { target_user_id }`:
  - Backend creates or reuses ephemeral LiveKit room `whisper-<min(uid1,uid2)>-<max(uid1,uid2)>`.
  - Issues short-lived tokens to both users.
  - Pushes `whisper.incoming { from, room, token, livekit_url }` over WebSocket to target.
- Whisper is a **parallel room**. User stays connected to all their other channels.
- Receiver sees prominent banner + haptic + "Hold to reply" button.
- **Audio ducking:** lower volume of all other rooms ~60% while whisper is active.
- Auto-end whisper room 30s after both sides go silent.

### Audio session
- `AVAudioSession.Category.playAndRecord`, mode `.voiceChat`, options `[.allowBluetooth, .allowBluetoothA2DP, .defaultToSpeaker]`.
- Background mode `audio` enabled in `Info.plist`.
- Handle `AVAudioSession.interruptionNotification` (incoming phone calls).
- Route picker UI for speaker / earpiece / Bluetooth.
- Don't activate audio session until first channel join.

---

## 7. Messaging Architecture

### Behavior
- Each channel has scrollable message history.
- `POST /channels/:id/messages { content, reply_to_message_id? }` → persist, broadcast `message.new` over WebSocket.
- `PATCH /messages/:id { content }` (author only, ≤15 min) → broadcast `message.updated`.
- `DELETE /messages/:id` (author or moderator) → soft delete, broadcast `message.deleted`.
- Pagination: cursor-based, descending by `created_at`. `GET /channels/:id/messages?before=<message_id>&limit=50`.

### Global Feed
- Pseudo-channel "Global" pinned at top of channel list.
- Aggregates most recent messages from every channel the user can read.
- Each row clearly shows: channel name + channel color tag, sender, content, timestamp.
- **Tapping a message navigates into that channel, scrolled to that message.**
- Backend: `GET /feed/global?before&limit` returns a union across permitted channels. WebSocket fans out `feed.message` events.

### Unread counts
- Each channel row shows unread badge.
- Opening a channel + scrolling to bottom updates `MessageRead.last_read_message_id`.
- App icon badge = sum of unread counts.

### Permissions on messaging
- `can_read_messages` and `can_post_messages` per role-per-channel.
- A user who can't read a channel doesn't see it in Global Feed.
- Whisper is voice-only in MVP.

### Out of scope for MVP
Attachments, @mentions, reactions, message search.

---

## 8. Screens (SwiftUI)

Big-button, glove-friendly. Primary actions ≥ 64pt tap targets.

1. **AuthView** — login + signup (signup requires invite code).
2. **MainTabView**
   - **Channels** — Global Feed pinned on top; rows: name, color dot, unread badge, speaking indicator.
   - **Members** — searchable, online status; tap → profile + Whisper button.
   - **Settings** — profile, audio (input device, VAD sensitivity, PTT vs VAD), notifications, admin entry, sign out.
3. **GlobalFeedView** — scrolling list of recent messages from permitted channels with colored channel chips. Tap → ChannelView at that message.
4. **ChannelView** — split: text thread on top, voice control strip on bottom (join/leave, volume, mute, speakers, PTT target).
5. **MultiChannelDashboard** — list of joined voice channels with sliders + mute toggles, big PTT button, PTT-target chip.
6. **WhisperOverlay** — modal: sender info, big "Hold to reply", end button.
7. **Admin screens** (visible with relevant perms): Users, Roles (drag hierarchy), Channels, Invites, Org settings.

---

## 9. Backend API

REST endpoints (Bearer auth except `/auth/*` and `/health`):

```
POST   /auth/signup                 { email, password, invite_code, display_name }
POST   /auth/login                  { email, password } → { access, refresh }
POST   /auth/refresh                { refresh_token }
GET    /me                          → user + org + roles + computed perms
GET    /health                      → 200 OK

GET    /orgs/me/members             → users with status
GET    /channels                    → channels visible to me + unread counts
POST   /channels                    (manage_channels)
PATCH  /channels/:id                (manage_channels)
DELETE /channels/:id                (manage_channels)
POST   /channels/:id/join-token     → { livekit_url, token }

GET    /channels/:id/messages?before&limit
POST   /channels/:id/messages       { content, reply_to_message_id? }
PATCH  /messages/:id                { content }
DELETE /messages/:id
POST   /channels/:id/read           { last_read_message_id }
GET    /feed/global?before&limit

POST   /whispers/start              { target_user_id } → { livekit_url, token, room }
POST   /whispers/:room/end

GET    /roles
POST   /roles                       (manage_roles)
PATCH  /roles/:id                   (manage_roles)
DELETE /roles/:id                   (manage_roles)
POST   /users/:id/roles             (manage_users)
DELETE /users/:id/roles/:role_id    (manage_users)

GET    /invites                     (manage_users)
POST   /invites                     (manage_users)
DELETE /invites/:id                 (manage_users)

POST   /devices/apns                { token }        -- optional, push only
```

### WebSocket
Single endpoint `wss://api.walkiehost.duckdns.org/ws`. Auth via access token sent in first frame. Server → client events:
- `presence.update { user_id, status }`
- `message.new`, `message.updated`, `message.deleted`
- `feed.message` (filtered to user's permitted channels)
- `channel.created`, `channel.updated`, `channel.deleted`
- `role.updated`, `permissions.changed` (client should refetch `/me`)
- `whisper.incoming { from_user_id, room, token, livekit_url }`
- `whisper.ended { room }`

Client → server: `subscribe`/`unsubscribe` to topics, heartbeat ping every 30s.

iOS WebSocket client must reconnect with exponential backoff (1s, 2s, 4s, 8s, capped 30s). On reconnect re-fetch `/me`, `/channels`, and any open channel's recent messages.

---

## 10. In-Memory State Management

Backend maintains some state in process memory:

- **Presence map** — `Map<userId, { status, lastSeen, wsConnections: Set<ws> }>`. Cleared on restart; clients re-report on reconnect.
- **Whisper room registry** — `Map<roomName, { participants, createdAt, lastActivity }>`. Ephemeral.
- **Rate limiter** — sliding window counters per user.
- **WebSocket pub/sub** — single `EventEmitter` in process.

**Constraint:** single backend instance. Don't write code that assumes multiple instances. Leave `TODO(scale): replace with Redis pub/sub` comments at each in-memory location.

---

## 11. Infrastructure Files

### `/infra/docker-compose.yml`

Services:

1. **caddy** — `caddy:2-alpine`. Ports 80:80, 443:443 published. Volumes: Caddyfile, caddy_data (certs), caddy_config. Depends on backend + livekit.
2. **backend** — built from `/backend/Dockerfile`. Loads env from `/opt/walkie-talkie/.env`. Internal port 3000.
3. **postgres** — `postgres:16-alpine`. Volume `/opt/walkie-talkie/postgres-data:/var/lib/postgresql/data` (or another path on the VM — confirm with user during Milestone 1).
4. **livekit** — `livekit/livekit-server:latest`. Ports 7881:7881/tcp, 3478:3478/udp, 50000-50200:50000-50200/udp published. Config from `/infra/livekit.yaml`. Set `use_external_ip: true` so it advertises the public IP.

All services on a single bridge network. Caddy and LiveKit publish ports; backend and postgres are internal-only.

### `/infra/Caddyfile`

```
{
  email {$ACME_EMAIL}
}

api.{$DUCKDNS_DOMAIN} {
  reverse_proxy backend:3000
}

livekit.{$DUCKDNS_DOMAIN} {
  reverse_proxy livekit:7880
}
```

Caddy automatically obtains and renews Let's Encrypt certs via HTTP-01 challenge on port 80.

### `/infra/livekit.yaml`

```yaml
port: 7880
bind_addresses:
  - ""
rtc:
  tcp_port: 7881
  port_range_start: 50000
  port_range_end: 50200
  use_external_ip: true
turn:
  enabled: true
  udp_port: 3478
keys:
  ${LIVEKIT_API_KEY}: ${LIVEKIT_API_SECRET}
log_level: info
```

The `keys` line needs to be populated from env at deploy time. Use an entrypoint script in the LiveKit container, or use `envsubst` to render the final config. Pick the cleanest approach and document it.

### `/infra/.env.example`

```
# Domain
DUCKDNS_DOMAIN=walkiehost.duckdns.org
ACME_EMAIL=__set_to_user_email__

# Postgres
POSTGRES_DB=walkietalk
POSTGRES_USER=walkietalk
POSTGRES_PASSWORD=__from_secrets__

# Backend
NODE_ENV=production
PORT=3000
DATABASE_URL=postgres://walkietalk:__pwd__@postgres:5432/walkietalk
JWT_ACCESS_SECRET=__from_secrets__
JWT_REFRESH_SECRET=__from_secrets__

# LiveKit
LIVEKIT_URL=wss://livekit.walkiehost.duckdns.org
LIVEKIT_API_KEY=__from_secrets__
LIVEKIT_API_SECRET=__from_secrets__

# Optional push
APNS_KEY_ID=
APNS_TEAM_ID=
APNS_KEY=
```

The real `.env` lives at `/opt/walkie-talkie/.env` on the VM (NOT in the repo). The user creates it during the first deploy by copying `.env.example` and filling in values from `secrets.txt`.

---

## 12. `deploy.sh` (Manual Deploy Script)

This script runs ON THE VM, in `/opt/walkie-talkie/`. The user pulls the repo and runs it after each change.

```bash
#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")"

echo "==> Pulling latest code"
git pull --ff-only

echo "==> Building backend image"
docker compose --env-file ./.env -f infra/docker-compose.yml build backend

echo "==> Pulling other images"
docker compose --env-file ./.env -f infra/docker-compose.yml pull caddy postgres livekit

echo "==> Starting stack"
docker compose --env-file ./.env -f infra/docker-compose.yml up -d

echo "==> Waiting for backend health"
for i in {1..30}; do
  if curl -fsS http://localhost:3000/health >/dev/null 2>&1; then
    echo "Backend healthy"
    break
  fi
  sleep 2
done

echo "==> Running migrations"
docker compose --env-file ./.env -f infra/docker-compose.yml exec -T backend npm run migrate

echo "==> Smoke test"
curl -fsS https://api.${DUCKDNS_DOMAIN}/health && echo "OK"

echo "==> Done"
```

Make it executable (`chmod +x deploy.sh`). Document any one-time setup in `docs/truenas-deploy.md`:
- How the user clones the repo to `/opt/walkie-talkie` on the VM
- How they create `.env` from `.env.example` filling in values from `secrets.txt`
- The first-deploy command sequence

---

## 13. Security

- Argon2id for password hashing.
- Access tokens 15-min TTL, refresh tokens 30-day TTL, rotate on use.
- LiveKit tokens issued per room with grants matching computed perms, 1-hour TTL.
- Rate limit token issuance and message sending per user (in-memory sliding window).
- Whisper rooms: tokens only for the two participants. Reject any third subscriber.
- No audio recording. State this in onboarding.
- `zod` validation on every endpoint.
- Security headers via `@fastify/helmet`.
- Postgres only on the Docker internal network — no published port.
- `.env` permissions: `chmod 600` on the VM.

---

## 14. iOS Implementation Notes

- Bundle ID and app name come from clarification responses.
- Code signing with personal team in Xcode (free, 7-day provisioning fine for dev).
- Backend URL is a build-config setting — `Config/Debug.xcconfig` has `http://localhost:3000`, `Config/Release.xcconfig` has `https://api.walkiehost.duckdns.org`. App reads from `Info.plist`.
- Keychain wrapper for tokens. Auto-refresh on 401.
- WebSocket reconnect: exponential backoff (1s, 2s, 4s, 8s, 16s, cap 30s).
- LiveKit URL + tokens come from backend responses — never hardcoded.
- **Test on real iPhone**, not just Simulator (Simulator audio session is unreliable).

---

## 15. Build Milestones — DO THESE IN ORDER

**Stop after each milestone and let the user test before continuing.** Show exactly what to test and how.

### Milestone 1: Repo scaffolding + first deploy

Before writing code, ask the user:
- (a) Bundle ID for the iOS app (e.g. `com.username.walkietalkie`)
- (b) App display name (e.g. "WalkieTalk")
- (c) Their email (for Let's Encrypt registration in Caddy)
- (d) Confirm Postgres data path on the VM (`/opt/walkie-talkie/postgres-data` unless they want different)
- (e) Drizzle vs node-pg-migrate — recommend Drizzle, confirm

Also tell the user up front which secrets you'll need and the exact commands they can run on their Mac to generate any they don't have:
- `JWT_ACCESS_SECRET`, `JWT_REFRESH_SECRET`, `LIVEKIT_API_SECRET` — each: `node -e "console.log(require('crypto').randomBytes(32).toString('hex'))"`
- `LIVEKIT_API_KEY` — `node -e "console.log('API' + require('crypto').randomBytes(8).toString('hex'))"`
- `POSTGRES_PASSWORD` — `node -e "console.log(require('crypto').randomBytes(16).toString('base64url'))"`

Then build:
- Repo structure per Section 3.
- Backend: Fastify + TypeScript + Drizzle scaffolding. `/health` endpoint (no DB hit).
- Backend `Dockerfile` (multi-stage, slim final image).
- Migrations + seed script (creates org, admin user, General channel, prints invite code).
- `docker-compose.dev.yml` for local Postgres only.
- `/infra/docker-compose.yml` for production stack (Section 11).
- `/infra/Caddyfile`.
- `/infra/livekit.yaml`.
- `/infra/.env.example`.
- `deploy.sh` (Section 12) at repo root.
- `docs/truenas-deploy.md`: step-by-step initial deploy — how to clone repo to `/opt/walkie-talkie`, populate `.env`, run `./deploy.sh` for the first time, troubleshoot common issues.
- `docs/operations.md`: tailing logs, restarting services, backup strategy (TrueNAS snapshots on postgres-data), rotating secrets.
- Commit, instruct user to push to GitHub.

**Tell the user:** the exact commands to run on the VM for the first deploy:
```bash
ssh walkiehost@192.168.0.18
sudo mkdir -p /opt/walkie-talkie && sudo chown walkiehost:walkiehost /opt/walkie-talkie
cd /opt/walkie-talkie
git clone <repo-url> .
cp infra/.env.example .env
nano .env       # fill in values from secrets.txt
chmod 600 .env
./deploy.sh
```

**Verification:** `curl https://api.walkiehost.duckdns.org/health` returns 200 from anywhere on the internet.

### Milestone 2: Auth + iOS shell
- `/auth/signup`, `/auth/login`, `/auth/refresh`, `/me`.
- Argon2id, JWT signing, refresh rotation.
- SwiftUI Xcode project, iOS 17+, Bundle ID set, personal-team signing.
- xcconfig files: Debug → `http://localhost:3000`, Release → `https://api.walkiehost.duckdns.org`.
- AuthView (login + signup with invite). Keychain token storage. Auto-refresh on 401.
- HomeView shows `/me` data. Sign out clears Keychain.

### Milestone 3: Channels + single-channel voice
- Channels endpoints + ChannelsTab.
- Backend issues LiveKit tokens with per-channel grants.
- iOS joins one channel via LiveKit Swift SDK, hears others, PTT transmits.
- AVAudioSession configured. Background audio works with screen locked (verify on real iPhone, including phone locked 5+ minutes).
- Route picker for speaker/earpiece/Bluetooth.
- **UDP port verification:** confirm WebRTC media flows. If blocked, fall back to TCP via port 7881 — verify that fallback too.

### Milestone 4: Multi-channel voice
- Join multiple channels simultaneously. Per-channel volume + mute.
- MultiChannelDashboard with PTT target chip + big PTT button.
- Voice activation mode toggle in settings.

### Milestone 5: Text messaging
- Send / fetch / paginate messages in a channel.
- WebSocket with reconnect logic (Section 9).
- Realtime `message.new`/`updated`/`deleted` delivery.
- Unread counts in channel list.
- ChannelView combined text + voice layout.

### Milestone 6: Global Feed
- `GET /feed/global` + WebSocket `feed.message` fanout filtered by permissions.
- GlobalFeedView at top of Channels tab.
- Tap message → navigates to source channel, scrolls to that message.

### Milestone 7: Whisper
- Ephemeral whisper rooms, sender + receiver flows.
- Audio ducking on receiver. "Hold to reply" overlay.
- Auto-end after silence.

### Milestone 8: Roles, permissions, admin UI
- Permission enforcement everywhere.
- Admin screens: Users, Roles (drag hierarchy), Channels, Invites.
- Confirm `bypass_channel_perms` and broadcast/private channel types work.

### Milestone 9 (optional): Polish + push
- APNs push for whispers when backgrounded (requires Apple Developer account).
- Hardware volume-key PTT (research iOS-legal approach first).
- Bluetooth route handling refined.
- Onboarding flow + empty states.

---

## 16. Out of Scope (MVP)

Android. E2E encryption (transport TLS only). Message attachments / images. @mentions / reactions / search. Video. Voice message recording / playback. Cross-org communication. Web client. GitHub Actions auto-deploy (manual only for now).

---

## 17. Quality Bar

- TypeScript strict on backend, no `any` without comment.
- Swift with explicit access modifiers, no force-unwraps in production paths.
- Server enforces all permissions.
- User-readable error messages.
- Every in-memory state location has `TODO(scale): replace with Redis pub/sub` comment.
- `docs/truenas-deploy.md` lets a fresh sysadmin reproduce the deploy.
- `docs/operations.md` answers: logs? rollback? backup? secret rotation?
- Bruno collection committed for the full API.

---

## 18. If Milestone 1 doesn't work

Likely failure modes and fixes:

- **Caddy can't get a TLS cert:** port 80 must be reachable (already verified), DuckDNS must resolve correctly (already verified), email in Caddyfile must be valid. Check `docker logs caddy`.
- **LiveKit clients can't connect:** verify TCP 7881 from outside, UDP range advertising. If UDP truly blocked, clients should fall back to TCP on 7881 automatically.
- **Postgres won't start:** volume permissions issue. Container's postgres user (UID 999) needs to own the host data path. Document fix command.
- **`./deploy.sh` exits with error:** show user the line, common issues are missing env vars or wrong paths.

Document all of these in `docs/operations.md` with concrete commands.

---

**Start with Milestone 1. Ask the user the five clarification questions before writing any code. Tell them which secrets you'll need and how to generate any they're missing. Then proceed.**
