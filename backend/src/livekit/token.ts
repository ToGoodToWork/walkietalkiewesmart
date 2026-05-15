import { AccessToken } from 'livekit-server-sdk';
import { env } from '../env.js';

export interface ChannelGrants {
  canJoin: boolean;
  canSpeak: boolean;
}

/**
 * Issue a LiveKit access token for a user joining a channel-backed room.
 * Room name is `channel-<channelId>` (deterministic so every member of an
 * org joins the same room for the same channel).
 */
export async function issueChannelToken(args: {
  userId: string;
  displayName: string;
  channelId: string;
  grants: ChannelGrants;
}): Promise<string> {
  const { userId, displayName, channelId, grants } = args;

  const at = new AccessToken(env.LIVEKIT_API_KEY, env.LIVEKIT_API_SECRET, {
    identity: userId,
    name: displayName,
    ttl: 60 * 60, // 1 hour, per spec §13
  });

  at.addGrant({
    room: `channel-${channelId}`,
    roomJoin: grants.canJoin,
    canPublish: grants.canSpeak,
    canSubscribe: grants.canJoin,
    canPublishData: false,
  });

  return at.toJwt();
}
