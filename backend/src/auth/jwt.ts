import { randomUUID } from 'node:crypto';
import { SignJWT, jwtVerify, type JWTPayload } from 'jose';
import { env } from '../env.js';

const accessKey = new TextEncoder().encode(env.JWT_ACCESS_SECRET);
const refreshKey = new TextEncoder().encode(env.JWT_REFRESH_SECRET);

const ACCESS_TTL_SECONDS = 15 * 60; // 15 min
const REFRESH_TTL_SECONDS = 30 * 24 * 60 * 60; // 30 days

const ISSUER = 'walkie-talkie';

export interface AccessClaims extends JWTPayload {
  sub: string; // user id
  org: string; // org id
  typ: 'access';
}

export interface RefreshClaims extends JWTPayload {
  sub: string;
  jti: string;
  typ: 'refresh';
}

export async function signAccessToken(userId: string, orgId: string): Promise<string> {
  return new SignJWT({ org: orgId, typ: 'access' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setIssuedAt()
    .setIssuer(ISSUER)
    .setExpirationTime(`${ACCESS_TTL_SECONDS}s`)
    .sign(accessKey);
}

export interface SignedRefresh {
  token: string;
  jti: string;
  expiresAt: Date;
}

export async function signRefreshToken(userId: string): Promise<SignedRefresh> {
  const jti = randomUUID();
  const expiresAt = new Date(Date.now() + REFRESH_TTL_SECONDS * 1000);
  const token = await new SignJWT({ typ: 'refresh' })
    .setProtectedHeader({ alg: 'HS256' })
    .setSubject(userId)
    .setJti(jti)
    .setIssuedAt()
    .setIssuer(ISSUER)
    .setExpirationTime(expiresAt)
    .sign(refreshKey);
  return { token, jti, expiresAt };
}

export async function verifyAccessToken(token: string): Promise<AccessClaims> {
  const { payload } = await jwtVerify<AccessClaims>(token, accessKey, { issuer: ISSUER });
  if (payload.typ !== 'access') throw new Error('Wrong token type');
  if (!payload.sub || !payload.org) throw new Error('Malformed access token');
  return payload;
}

export async function verifyRefreshToken(token: string): Promise<RefreshClaims> {
  const { payload } = await jwtVerify<RefreshClaims>(token, refreshKey, { issuer: ISSUER });
  if (payload.typ !== 'refresh') throw new Error('Wrong token type');
  if (!payload.sub || !payload.jti) throw new Error('Malformed refresh token');
  return payload;
}

export const tokenTTL = {
  access: ACCESS_TTL_SECONDS,
  refresh: REFRESH_TTL_SECONDS,
};
