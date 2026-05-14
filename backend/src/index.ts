import Fastify from 'fastify';
import helmet from '@fastify/helmet';
import { env } from './env.js';
import { healthRoutes } from './routes/health.js';

const app = Fastify({
  logger: {
    level: env.NODE_ENV === 'production' ? 'info' : 'debug',
  },
  trustProxy: true,
});

await app.register(helmet, { contentSecurityPolicy: false });
await app.register(healthRoutes);

const shutdown = async (signal: string) => {
  app.log.info({ signal }, 'shutting down');
  try {
    await app.close();
    process.exit(0);
  } catch (err) {
    app.log.error(err, 'error during shutdown');
    process.exit(1);
  }
};

process.on('SIGINT', () => shutdown('SIGINT'));
process.on('SIGTERM', () => shutdown('SIGTERM'));

try {
  await app.listen({ port: env.PORT, host: '0.0.0.0' });
} catch (err) {
  app.log.error(err);
  process.exit(1);
}
