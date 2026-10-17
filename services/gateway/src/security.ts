import { createRemoteJWKSet, jwtVerify, type JWTVerifyGetKey } from 'jose';
import { ApiError, type Store } from './store.js';

const keys = createRemoteJWKSet(new URL('https://www.googleapis.com/service_accounts/v1/jwk/securetoken@system.gserviceaccount.com'));
export async function ownerIdentity(token: string, project: string, keySet: JWTVerifyGetKey = keys) {
  try {
    const { payload } = await jwtVerify(token, keySet, {
      algorithms: ['RS256'], issuer: `https://securetoken.google.com/${project}`, audience: project,
      requiredClaims: ['sub', 'exp', 'iat', 'auth_time'],
    });
    if (!payload.sub || !/^[A-Za-z0-9_-]{1,128}$/.test(payload.sub) || typeof payload.iat !== 'number' || payload.iat > Date.now() / 1000 || typeof payload.auth_time !== 'number' || payload.auth_time > Date.now() / 1000 || payload.email_verified !== true) throw new Error();
    return payload.sub;
  } catch { throw new ApiError(401, 'OWNER_AUTH_REQUIRED'); }
}
export async function hash(value: string, secret: string) {
  if (secret.length < 32) throw new ApiError(503, 'CONFIGURATION');
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(secret), { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  return Array.from(new Uint8Array(await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(value))), b => b.toString(16).padStart(2, '0')).join('');
}
export function sameHash(a: string, b: string) {
  if (a.length !== 64 || b.length !== 64) return false;
  let difference = 0;
  for (let i = 0; i < 64; i++) difference |= a.charCodeAt(i) ^ b.charCodeAt(i);
  return difference === 0;
}
export function randomCode() {
  const limit = Math.floor(2 ** 32 / 1000000) * 1000000;
  let value: number;
  do { value = crypto.getRandomValues(new Uint32Array(1))[0]; } while (value >= limit);
  return (value % 1000000).toString().padStart(6, '0');
}
export async function rateLimit(store: Store, identity: string, max: number, now: number) {
  await store.update<{ start: number; count: number }>(`private/limits/${identity}`, current => {
    const state = current && now - current.start < 60000 ? current : { start: now, count: 0 };
    if (state.count >= max) throw new ApiError(429, 'RATE_LIMITED');
    return { start: state.start, count: state.count + 1 };
  });
}
