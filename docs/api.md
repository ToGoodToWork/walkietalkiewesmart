# API Reference

Milestone 1 ships only:

```
GET /health → { status: "ok", timestamp: ISO8601 }
```

The full endpoint surface (auth, channels, messages, whispers, admin) is added
incrementally in Milestones 2–8. See `claude-code-prompt.md` §9 for the
contract; this file will be filled in milestone by milestone.

A Bruno collection (`/api.bruno/`) will be committed alongside Milestone 2.
