import 'dotenv/config';
import { z } from 'zod';

const schema = z.object({
  NODE_ENV: z.enum(['development', 'production', 'test']).default('development'),
  PORT: z.coerce.number().int().positive().default(3000),
  DATABASE_URL: z.string().url(),

  // Optional in Milestone 1; tightened in later milestones.
  JWT_ACCESS_SECRET: z.string().min(32).optional(),
  JWT_REFRESH_SECRET: z.string().min(32).optional(),
  LIVEKIT_URL: z.string().url().optional(),
  LIVEKIT_API_KEY: z.string().optional(),
  LIVEKIT_API_SECRET: z.string().optional(),
});

const parsed = schema.safeParse(process.env);

if (!parsed.success) {
  console.error('Invalid environment variables:', parsed.error.flatten().fieldErrors);
  process.exit(1);
}

export const env = parsed.data;
