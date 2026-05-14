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

Request:

```json
{
  "email": "alice@example.com",
  "password": "at-least-8-chars",
  "invite_code": "vYt7Jbtf",
  "display_name": "Alice"
}
```

201 Response:

```json
{ "access": "eyJ...", "refresh": "eyJ..." }
```

Errors: 400 `invalid_input`/`invalid_invite`/`invite_expired`/`invite_used_up`,
409 `email_taken`.

### `POST /auth/login`

```json
{ "email": "alice@example.com", "password": "..." }
```

200 → same shape as signup. 401 `invalid_credentials`.

### `POST /auth/refresh`

```json
{ "refresh_token": "eyJ..." }
```

200 → new `{ access, refresh }`. The old refresh token is revoked.
401 `invalid_refresh` or `expired_refresh`.

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
    "created_at": "2026-05-14T..."
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

## Token lifetimes

- Access: 15 minutes
- Refresh: 30 days, rotated on every use

## Coming in later milestones

Channels, voice join-tokens, messages, whispers, admin endpoints — see
`claude-code-prompt.md` §9.
