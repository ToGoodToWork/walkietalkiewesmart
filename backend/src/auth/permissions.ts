import type { RolePermissions } from '../db/schema.js';

export const emptyPermissions = (): RolePermissions => ({
  manage_org: false,
  manage_users: false,
  manage_roles: false,
  manage_channels: false,
  whisper_anyone: false,
  bypass_channel_perms: false,
});

/**
 * Combine permissions from multiple roles by OR'ing every flag together.
 * Per-channel overrides land in Milestone 8 (§5 of the spec).
 */
export function unionPermissions(roles: { permissions: RolePermissions }[]): RolePermissions {
  const out = emptyPermissions();
  for (const r of roles) {
    for (const key of Object.keys(out) as (keyof RolePermissions)[]) {
      out[key] = out[key] || r.permissions[key];
    }
  }
  return out;
}
