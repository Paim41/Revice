import { initializeTestEnvironment, assertSucceeds, assertFails } from '@firebase/rules-unit-testing';
import { readFile } from 'node:fs/promises';
import { test } from 'node:test';
const env = await initializeTestEnvironment({ projectId: 'demo-revice', database: { host: '127.0.0.1', port: 9000, rules: await readFile(new URL('database.rules.json', import.meta.url), 'utf8') } });
test('only verified owners read public records; credentials and all client writes stay denied', async () => {
  try {
    await env.withSecurityRulesDisabled(async c => {
      await c.database().ref().set({ directory: { alice: { phone: true } }, devices: { alice: { phone: { credentialHash: 'secret', public: { name: 'Phone' }, history: { one: { observedAt: '2026-10-16T00:00:00Z' } } } } } });
    });
    const alice = env.authenticatedContext('alice', { email_verified: true }).database();
    const bob = env.authenticatedContext('bob', { email_verified: true }).database();
    const unverified = env.authenticatedContext('alice', { email_verified: false }).database();
    await assertSucceeds(alice.ref('directory/alice').once('value'));
    await assertSucceeds(alice.ref('devices/alice/phone/public').once('value'));
    await assertSucceeds(alice.ref('devices/alice/phone/history').once('value'));
    await assertFails(alice.ref('devices/alice/phone').once('value'));
    await assertFails(alice.ref('devices/alice/phone/credentialHash').once('value'));
    await assertFails(bob.ref('devices/alice/phone/public').once('value'));
    await assertFails(unverified.ref('devices/alice/phone/public').once('value'));
    await assertFails(env.unauthenticatedContext().database().ref('directory/alice').once('value'));
    await assertFails(alice.ref('devices/alice/phone/public/name').set('changed'));
    await assertFails(alice.ref('private/pairing').once('value'));
  } finally { await env.cleanup(); }
});
