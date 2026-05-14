import { randomBytes } from 'node:crypto';
import argon2 from 'argon2';
import postgres from 'postgres';
import { drizzle } from 'drizzle-orm/postgres-js';
import { env } from './env.js';
import * as schema from './db/schema.js';

const sql = postgres(env.DATABASE_URL, { max: 1 });
const db = drizzle(sql, { schema });

const log = (msg: string) => console.log(`[seed] ${msg}`);

async function run() {
  const existing = await db.select().from(schema.organizations).limit(1);
  if (existing.length > 0) {
    log('Database already seeded — skipping.');
    return;
  }

  log('Seeding initial org, roles, admin user, default channel, invite...');

  const [org] = await db
    .insert(schema.organizations)
    .values({ name: 'My Organization' })
    .returning();
  if (!org) throw new Error('Failed to insert organization');

  const [adminRole] = await db
    .insert(schema.roles)
    .values({
      orgId: org.id,
      name: 'Admin',
      color: '#e91e63',
      position: 100,
      permissions: {
        manage_org: true,
        manage_users: true,
        manage_roles: true,
        manage_channels: true,
        whisper_anyone: true,
        bypass_channel_perms: true,
      },
    })
    .returning();
  if (!adminRole) throw new Error('Failed to insert Admin role');

  const [memberRole] = await db
    .insert(schema.roles)
    .values({
      orgId: org.id,
      name: 'Member',
      color: '#9aa0a6',
      position: 0,
      permissions: {
        manage_org: false,
        manage_users: false,
        manage_roles: false,
        manage_channels: false,
        whisper_anyone: true,
        bypass_channel_perms: false,
      },
    })
    .returning();
  if (!memberRole) throw new Error('Failed to insert Member role');

  const adminEmail = 'admin@walkietalk.local';
  const adminPassword = randomBytes(12).toString('base64url');
  const passwordHash = await argon2.hash(adminPassword, { type: argon2.argon2id });

  const [admin] = await db
    .insert(schema.users)
    .values({
      orgId: org.id,
      email: adminEmail,
      passwordHash,
      displayName: 'Admin',
      status: 'offline',
    })
    .returning();
  if (!admin) throw new Error('Failed to insert admin user');

  await db.insert(schema.userRoles).values({
    userId: admin.id,
    roleId: adminRole.id,
  });

  const [channel] = await db
    .insert(schema.channels)
    .values({
      orgId: org.id,
      name: 'General',
      description: 'Default channel',
      type: 'normal',
      position: 0,
    })
    .returning();
  if (!channel) throw new Error('Failed to insert General channel');

  await db.insert(schema.channelPermissions).values([
    {
      channelId: channel.id,
      roleId: adminRole.id,
      canJoin: true,
      canSpeak: true,
      canReadMessages: true,
      canPostMessages: true,
      canManage: true,
    },
    {
      channelId: channel.id,
      roleId: memberRole.id,
      canJoin: true,
      canSpeak: true,
      canReadMessages: true,
      canPostMessages: true,
      canManage: false,
    },
  ]);

  const inviteCode = randomBytes(6).toString('base64url');
  await db.insert(schema.invites).values({
    orgId: org.id,
    code: inviteCode,
    createdBy: admin.id,
    maxUses: 100,
  });

  console.log('');
  console.log('========== SEED COMPLETE ==========');
  console.log(`Org name:        ${org.name}`);
  console.log(`Org id:          ${org.id}`);
  console.log(`Admin email:     ${adminEmail}`);
  console.log(`Admin password:  ${adminPassword}`);
  console.log(`Default channel: ${channel.name}`);
  console.log(`Invite code:     ${inviteCode}`);
  console.log('');
  console.log('Save the admin password — it is NOT recoverable. Re-running');
  console.log('the seed script is a no-op once an org exists.');
  console.log('===================================');
}

try {
  await run();
} catch (err) {
  console.error('[seed] Failed:', err);
  process.exitCode = 1;
} finally {
  await sql.end();
}
