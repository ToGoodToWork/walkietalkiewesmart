import type { FastifyPluginAsync } from 'fastify';
import { z } from 'zod';
import { eq, and, isNull } from 'drizzle-orm';
import { db } from '../db/index.js';
import * as schema from '../db/schema.js';
import { hashPassword, verifyPassword } from '../auth/password.js';
import {
  signAccessToken,
  signRefreshToken,
  verifyRefreshToken,
} from '../auth/jwt.js';

const signupSchema = z.object({
  email: z.string().email().max(254).transform((s) => s.toLowerCase()),
  password: z.string().min(8).max(256),
  invite_code: z.string().min(1).max(64),
  display_name: z.string().min(1).max(60).trim(),
});

const loginSchema = z.object({
  email: z.string().email().transform((s) => s.toLowerCase()),
  password: z.string().min(1).max(256),
});

const refreshSchema = z.object({
  refresh_token: z.string().min(1),
});

async function issueTokens(userId: string, orgId: string) {
  const access = await signAccessToken(userId, orgId);
  const refresh = await signRefreshToken(userId);
  await db.insert(schema.refreshTokens).values({
    userId,
    jti: refresh.jti,
    expiresAt: refresh.expiresAt,
  });
  return { access, refresh: refresh.token };
}

export const authRoutes: FastifyPluginAsync = async (app) => {
  app.post('/auth/signup', async (req, reply) => {
    const body = signupSchema.safeParse(req.body);
    if (!body.success) {
      return reply.code(400).send({ error: 'invalid_input', details: body.error.flatten() });
    }
    const { email, password, invite_code, display_name } = body.data;

    const invite = await db
      .select()
      .from(schema.invites)
      .where(eq(schema.invites.code, invite_code))
      .limit(1)
      .then((rows) => rows[0]);

    if (!invite) return reply.code(400).send({ error: 'invalid_invite' });
    if (invite.expiresAt && invite.expiresAt < new Date()) {
      return reply.code(400).send({ error: 'invite_expired' });
    }
    if (invite.maxUses !== null && invite.usedCount >= invite.maxUses) {
      return reply.code(400).send({ error: 'invite_used_up' });
    }

    const existing = await db
      .select({ id: schema.users.id })
      .from(schema.users)
      .where(and(eq(schema.users.orgId, invite.orgId), eq(schema.users.email, email)))
      .limit(1);
    if (existing.length > 0) {
      return reply.code(409).send({ error: 'email_taken' });
    }

    const passwordHash = await hashPassword(password);
    const memberRole = await db
      .select()
      .from(schema.roles)
      .where(and(eq(schema.roles.orgId, invite.orgId), eq(schema.roles.name, 'Member')))
      .limit(1)
      .then((rows) => rows[0]);

    const inserted = await db.transaction(async (tx) => {
      const [user] = await tx
        .insert(schema.users)
        .values({
          orgId: invite.orgId,
          email,
          passwordHash,
          displayName: display_name,
          status: 'offline',
        })
        .returning();
      if (!user) throw new Error('Failed to insert user');

      if (memberRole) {
        await tx.insert(schema.userRoles).values({ userId: user.id, roleId: memberRole.id });
      }

      await tx
        .update(schema.invites)
        .set({ usedCount: invite.usedCount + 1 })
        .where(eq(schema.invites.id, invite.id));

      return user;
    });

    const tokens = await issueTokens(inserted.id, inserted.orgId);
    return reply.code(201).send(tokens);
  });

  app.post('/auth/login', async (req, reply) => {
    const body = loginSchema.safeParse(req.body);
    if (!body.success) return reply.code(400).send({ error: 'invalid_input' });

    const { email, password } = body.data;
    const user = await db
      .select()
      .from(schema.users)
      .where(eq(schema.users.email, email))
      .limit(1)
      .then((rows) => rows[0]);

    if (!user) {
      // Constant-time-ish: still hash a dummy to avoid leaking which emails exist.
      await hashPassword('not-a-real-password-just-burning-cycles');
      return reply.code(401).send({ error: 'invalid_credentials' });
    }

    const ok = await verifyPassword(user.passwordHash, password);
    if (!ok) return reply.code(401).send({ error: 'invalid_credentials' });

    const tokens = await issueTokens(user.id, user.orgId);
    return reply.send(tokens);
  });

  app.post('/auth/refresh', async (req, reply) => {
    const body = refreshSchema.safeParse(req.body);
    if (!body.success) return reply.code(400).send({ error: 'invalid_input' });

    let claims;
    try {
      claims = await verifyRefreshToken(body.data.refresh_token);
    } catch {
      return reply.code(401).send({ error: 'invalid_refresh' });
    }

    const stored = await db
      .select()
      .from(schema.refreshTokens)
      .where(eq(schema.refreshTokens.jti, claims.jti))
      .limit(1)
      .then((rows) => rows[0]);

    if (!stored || stored.revokedAt) {
      return reply.code(401).send({ error: 'invalid_refresh' });
    }
    if (stored.expiresAt < new Date()) {
      return reply.code(401).send({ error: 'expired_refresh' });
    }

    const user = await db
      .select({ id: schema.users.id, orgId: schema.users.orgId })
      .from(schema.users)
      .where(eq(schema.users.id, stored.userId))
      .limit(1)
      .then((rows) => rows[0]);
    if (!user) return reply.code(401).send({ error: 'invalid_refresh' });

    // Rotate: revoke the consumed refresh, issue a fresh pair.
    const result = await db.transaction(async (tx) => {
      await tx
        .update(schema.refreshTokens)
        .set({ revokedAt: new Date() })
        .where(
          and(eq(schema.refreshTokens.jti, claims.jti), isNull(schema.refreshTokens.revokedAt)),
        );
      return issueTokens(user.id, user.orgId);
    });
    return reply.send(result);
  });
};
