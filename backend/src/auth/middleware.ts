import type { FastifyPluginAsync, FastifyRequest, FastifyReply } from 'fastify';
import fp from 'fastify-plugin';
import { verifyAccessToken } from './jwt.js';

export interface AuthedUser {
  id: string;
  orgId: string;
}

declare module 'fastify' {
  interface FastifyRequest {
    user?: AuthedUser;
  }
  interface FastifyInstance {
    authenticate: (req: FastifyRequest, reply: FastifyReply) => Promise<void>;
  }
}

const authPlugin: FastifyPluginAsync = async (app) => {
  app.decorate('authenticate', async (req: FastifyRequest, reply: FastifyReply) => {
    const header = req.headers.authorization;
    if (!header || !header.startsWith('Bearer ')) {
      return reply.code(401).send({ error: 'missing_token' });
    }
    const token = header.slice('Bearer '.length).trim();
    try {
      const claims = await verifyAccessToken(token);
      req.user = { id: claims.sub, orgId: claims.org };
    } catch {
      return reply.code(401).send({ error: 'invalid_token' });
    }
  });
};

export default fp(authPlugin, { name: 'auth' });
