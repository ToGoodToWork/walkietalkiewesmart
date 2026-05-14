import type { FastifyPluginAsync } from 'fastify';
import { eq } from 'drizzle-orm';
import { db } from '../db/index.js';
import * as schema from '../db/schema.js';
import { unionPermissions } from '../auth/permissions.js';

export const meRoutes: FastifyPluginAsync = async (app) => {
  app.get('/me', { onRequest: [app.authenticate] }, async (req, reply) => {
    if (!req.user) return reply.code(401).send({ error: 'unauthenticated' });

    const user = await db
      .select()
      .from(schema.users)
      .where(eq(schema.users.id, req.user.id))
      .limit(1)
      .then((rows) => rows[0]);
    if (!user) return reply.code(404).send({ error: 'user_not_found' });

    const org = await db
      .select()
      .from(schema.organizations)
      .where(eq(schema.organizations.id, user.orgId))
      .limit(1)
      .then((rows) => rows[0]);
    if (!org) return reply.code(404).send({ error: 'org_not_found' });

    const userRolesRows = await db
      .select({
        id: schema.roles.id,
        name: schema.roles.name,
        color: schema.roles.color,
        position: schema.roles.position,
        permissions: schema.roles.permissions,
      })
      .from(schema.userRoles)
      .innerJoin(schema.roles, eq(schema.roles.id, schema.userRoles.roleId))
      .where(eq(schema.userRoles.userId, user.id));

    const permissions = unionPermissions(userRolesRows);

    return reply.send({
      user: {
        id: user.id,
        email: user.email,
        display_name: user.displayName,
        avatar_url: user.avatarUrl,
        status: user.status,
        created_at: user.createdAt,
      },
      org: { id: org.id, name: org.name },
      roles: userRolesRows,
      permissions,
    });
  });
};
