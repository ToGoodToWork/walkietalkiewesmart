# API Reference

Base URL: `https://api.walkiehost.duckdns.org` (production) or
`http://localhost:3000` (local dev).

All requests/responses are JSON. Auth is via `Authorization: Bearer <access>`
unless noted.

## Public

### `GET /health`

```json
{ "status": "ok", "timestamp": "2026-05-14T12:11:25Z" }
```

### `POST /auth/signup`

```json
{
  "email": "alice@example.com",
  "password": "at-least-8-chars",
  "invite_code": "vYt7Jbtf",
  "display_name": "Alice"
}
```

201 → `{ "access": "...", "refresh": "..." }`.
Errors: 400 `invalid_input` / `invalid_invite` / `invite_expired` /
`invite_used_up`, 409 `email_taken`.

### `POST /auth/login`

```json
{ "email": "alice@example.com", "password": "..." }
```

200 → `{ access, refresh }`. 401 `invalid_credentials`.

### `POST /auth/refresh`

```json
{ "refresh_token": "..." }
```

200 → new `{ access, refresh }`. Old refresh token is revoked (rotation).
401 `invalid_refresh` / `expired_refresh`.

## Authenticated

### `GET /me`

```json
{
  "user": {
    "id": "uuid",
    "email": "alice@example.com",
    "display_name": "Alice",
    "avatar_url": null,
    "status": "offline",
    "created_at": "..."
  },
  "org": { "id": "uuid", "name": "My Organization" },
  "roles": [
    { "id": "uuid", "name": "Admin", "color": "#e91e63", "position": 100,
      "permissions": { "manage_org": true, "manage_users": true, ... } }
  ],
  "permissions": {
    "manage_org": true,
    "manage_users": true,
    "manage_roles": true,
    "manage_channels": true,
    "whisper_anyone": true,
    "bypass_channel_perms": true
  }
}
```

`permissions` is the union (logical OR) across all of the user's roles.

### `GET /channels`

Returns channels visible to the caller (`can_join || can_read`), with
per-channel computed grants:

```json
[
  {
    "id": "uuid",
    "name": "General",
    "description": "Default channel",
    "type": "normal",
    "position": 0,
    "can_join": true,
    "can_speak": true,
    "can_read": true,
    "can_post": true,
    "can_manage": false
  }
]
```

Grant rules:
- A role with `bypass_channel_perms = true` grants everything.
- Otherwise grants are the OR of `channel_permissions` rows for the user's roles.
- `private` channels also require a `channel_members` row.

### `POST /channels/:id/join-token`

No body. Returns a short-lived LiveKit token:

```json
{
  "livekit_url": "wss://livekit.walkiehost.duckdns.org",
  "token": "eyJ..."
}
```

Token TTL: 1 hour. Token grants reflect channel permissions
(`canPublish = can_speak`, `canSubscribe = can_join`). Room name is
`channel-<channel_id>`.

Errors: 403 `cannot_join_channel`, 404 `channel_not_found`.

## Token lifetimes

- Access JWT: 15 minutes
- Refresh JWT: 30 days, rotated on every use
- LiveKit JWT: 1 hour

## Coming in later milestones

Multi-channel voice management (M4), messages + WS (M5), Global Feed (M6),
whispers (M7), admin endpoints (M8).
