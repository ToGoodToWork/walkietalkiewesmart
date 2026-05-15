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

export interface ChannelGrants {
  canJoin: boolean;
  canSpeak: boolean;
  canRead: boolean;
  canPost: boolean;
  canManage: boolean;
}

export const emptyChannelGrants = (): ChannelGrants => ({
  canJoin: false,
  canSpeak: false,
  canRead: false,
  canPost: false,
  canManage: false,
});

const allChannelGrants = (): ChannelGrants => ({
  canJoin: true,
  canSpeak: true,
  canRead: true,
  canPost: true,
  canManage: true,
});

/**
 * Compute the user's effective permissions on one channel:
 *   1. bypass_channel_perms → everything true
 *   2. Else OR together channel_permissions rows matching the user's roles
 *      (no row for a role means that role contributes no grants)
 *   3. private channels additionally require a channel_members row
 */
export function computeChannelGrants(args: {
  userRoles: { id: string; permissions: RolePermissions }[];
  channelType: 'normal' | 'broadcast' | 'private';
  channelPermRows: {
    roleId: string;
    canJoin: boolean;
    canSpeak: boolean;
    canReadMessages: boolean;
    canPostMessages: boolean;
    canManage: boolean;
  }[];
  isChannelMember: boolean;
}): ChannelGrants {
  const { userRoles, channelType, channelPermRows, isChannelMember } = args;

  if (userRoles.some((r) => r.permissions.bypass_channel_perms)) {
    return allChannelGrants();
  }

  const userRoleIds = new Set(userRoles.map((r) => r.id));
  const grants = emptyChannelGrants();
  for (const row of channelPermRows) {
    if (!userRoleIds.has(row.roleId)) continue;
    grants.canJoin ||= row.canJoin;
    grants.canSpeak ||= row.canSpeak;
    grants.canRead ||= row.canReadMessages;
    grants.canPost ||= row.canPostMessages;
    grants.canManage ||= row.canManage;
  }

  if (channelType === 'private' && !isChannelMember) {
    return emptyChannelGrants();
  }

  return grants;
}
