import { test } from 'node:test';
import assert from 'node:assert/strict';
import { generateKeyPair, exportJWK, SignJWT, createLocalJWKSet } from 'jose';
import { ownerIdentity } from '../src/security.js';

test('Firebase owner JWT enforces signature, issuer, audience, expiry and verified email', async () => {
  const keys = await generateKeyPair('RS256');
  const publicKey = await exportJWK(keys.publicKey);
  publicKey.kid = 'test-key';
  const localKeys = createLocalJWKSet({ keys: [publicKey] });
  const sign = (overrides: Record<string, unknown> = {}) => new SignJWT({ sub: 'owner1', auth_time: Math.floor(Date.now() / 1000) - 1, email_verified: true, ...overrides }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer('https://securetoken.google.com/demo-revice').setAudience('demo-revice').setIssuedAt().setExpirationTime('5m').sign(keys.privateKey);
  const valid = await sign();
  assert.equal(await ownerIdentity(valid, 'demo-revice', localKeys), 'owner1');
  await assert.rejects(() => ownerIdentity(valid, 'different-project', localKeys));
  await assert.rejects(() => ownerIdentity(valid.slice(0, -12) + 'xxxxxxxxxxxx', 'demo-revice', localKeys));
  await assert.rejects(async () => ownerIdentity(await sign({ email_verified: false }), 'demo-revice', localKeys));
  const expired = await new SignJWT({ sub: 'owner1', auth_time: 0, email_verified: true }).setProtectedHeader({ alg: 'RS256', kid: 'test-key' }).setIssuer('https://securetoken.google.com/demo-revice').setAudience('demo-revice').setIssuedAt(1).setExpirationTime(2).sign(keys.privateKey);
  await assert.rejects(() => ownerIdentity(expired, 'demo-revice', localKeys));
});
