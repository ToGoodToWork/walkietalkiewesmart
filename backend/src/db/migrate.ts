import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import { migrate } from 'drizzle-orm/postgres-js/migrator';
import { env } from '../env.js';

const migrationsFolder = process.env.DRIZZLE_MIGRATIONS_FOLDER ?? './drizzle';

const sql = postgres(env.DATABASE_URL, { max: 1 });
const db = drizzle(sql);

try {
  console.log(`[migrate] Running migrations from ${migrationsFolder}`);
  await migrate(db, { migrationsFolder });
  console.log('[migrate] Done');
} catch (err) {
  console.error('[migrate] Failed:', err);
  process.exitCode = 1;
} finally {
  await sql.end();
}
