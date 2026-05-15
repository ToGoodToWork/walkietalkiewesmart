import type { FastifyPluginAsync } from 'fastify';
import { eq, and, inArray, asc } from 'drizzle-orm';
import { db } from '../db/index.js';
import * as schema from '../db/schema.js';
import { computeChannelGrants, type ChannelGrants } from '../auth/permissions.js';
import { issueChannelToken } from '../livekit/token.js';
import { env } from '../env.js';

export const channelsRoutes: FastifyPluginAsync = async (app) => {
  app.get('/channels', { onRequest: [app.authenticate] }, async (req, reply) => {
    if (!req.user) return reply.code(401).send({ error: 'unauthenticated' });

    const user = await db
      .select()
      .from(schema.users)
      .where(eq(schema.users.id, req.user.id))
      .limit(1)
      .then((rows) => rows[0]);
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    const userRoles = await db
      .select({
        id: schema.roles.id,
        permissions: schema.roles.permissions,
      })
      .from(schema.userRoles)
      .innerJoin(schema.roles, eq(schema.roles.id, schema.userRoles.roleId))
      .where(eq(schema.userRoles.userId, user.id));

    const channels = await db
      .select()
      .from(schema.channels)
      .where(eq(schema.channels.orgId, user.orgId))
      .orderBy(asc(schema.channels.position), asc(schema.channels.name));

    if (channels.length === 0) return reply.send([]);

    const channelIds = channels.map((c) => c.id);
    const permRows = await db
      .select()
      .from(schema.channelPermissions)
      .where(inArray(schema.channelPermissions.channelId, channelIds));

    const memberRows = await db
      .select()
      .from(schema.channelMembers)
      .where(
        and(
          eq(schema.channelMembers.userId, user.id),
          inArray(schema.channelMembers.channelId, channelIds),
        ),
      );
    const memberChannelIds = new Set(memberRows.map((m) => m.channelId));

    const visible = channels
      .map((c) => {
        const rowsForChannel = permRows.filter((p) => p.channelId === c.id);
        const grants = computeChannelGrants({
          userRoles,
          channelType: c.type,
          channelPermRows: rowsForChannel,
          isChannelMember: memberChannelIds.has(c.id),
        });
        return { channel: c, grants };
      })
      .filter(({ grants }) => grants.canJoin || grants.canRead)
      .map(({ channel: c, grants }) => ({
        id: c.id,
        name: c.name,
        description: c.description,
        type: c.type,
        position: c.position,
        can_join: grants.canJoin,
        can_speak: grants.canSpeak,
        can_read: grants.canRead,
        can_post: grants.canPost,
        can_manage: grants.canManage,
      }));

    return reply.send(visible);
  });

  app.post(
    '/channels/:id/join-token',
    { onRequest: [app.authenticate] },
    async (req, reply) => {
      if (!req.user) return reply.code(401).send({ error: 'unauthenticated' });
      const { id: channelId } = req.params as { id: string };

      const user = await db
        .select()
        .from(schema.users)
        .where(eq(schema.users.id, req.user.id))
        .limit(1)
        .then((rows) => rows[0]);
      if (!user) return reply.code(404).send({ error: 'user_not_found' });

      const channel = await db
        .select()
        .from(schema.channels)
        .where(and(eq(schema.channels.id, channelId), eq(schema.channels.orgId, user.orgId)))
        .limit(1)
        .then((rows) => rows[0]);
      if (!channel) return reply.code(404).send({ error: 'channel_not_found' });

      const userRoles = await db
        .select({ id: schema.roles.id, permissions: schema.roles.permissions })
        .from(schema.userRoles)
        .innerJoin(schema.roles, eq(schema.roles.id, schema.userRoles.roleId))
        .where(eq(schema.userRoles.userId, user.id));

      const permRows = await db
        .select()
        .from(schema.channelPermissions)
        .where(eq(schema.channelPermissions.channelId, channel.id));

      const isMember = await db
        .select()
        .from(schema.channelMembers)
        .where(
          and(
            eq(schema.channelMembers.channelId, channel.id),
            eq(schema.channelMembers.userId, user.id),
          ),
        )
        .limit(1)
        .then((rows) => rows.length > 0);

      const grants: ChannelGrants = computeChannelGrants({
        userRoles,
        channelType: channel.type,
        channelPermRows: permRows,
        isChannelMember: isMember,
      });

      if (!grants.canJoin) {
        return reply.code(403).send({ error: 'cannot_join_channel' });
      }

      const token = await issueChannelToken({
        userId: user.id,
        displayName: user.displayName,
        channelId: channel.id,
        grants: { canJoin: grants.canJoin, canSpeak: grants.canSpeak },
      });

      return reply.send({
        livekit_url: env.LIVEKIT_URL,
        token,
      });
    },
  );
};
