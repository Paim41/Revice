import { test } from 'node:test';
import assert from 'node:assert/strict';
import { createApi } from '../src/api.js';
import { ApiError, type Store, type Env } from '../src/store.js';

class MemoryStore implements Store {
  records = new Map<string, unknown>();
  async get<T>(path: string): Promise<T | null> { return structuredClone(this.records.get(path) ?? null) as T | null; }
  async put(path: string, value: unknown) { this.records.set(path, structuredClone(value)); }
  async update<T>(path: string, change: (value: T | null) => T): Promise<T> {
    const value = change(structuredClone(this.records.get(path) ?? null) as T | null);
    this.records.set(path, structuredClone(value)); return value;
  }
}
const credential = 'a'.repeat(64);
function setup() {
  let now = Date.parse('2026-10-16T12:00:00Z');
  const store = new MemoryStore();
  const env: Env = { FIREBASE_PROJECT_ID: 'test', FIREBASE_DATABASE_URL: 'https://test.firebaseio.com', FIREBASE_SERVICE_ACCOUNT_JSON: '', AGENT_TOKEN_HASH_KEY: 'x'.repeat(32) };
  const handler = createApi(env, { store, now: () => now, verifyOwner: async token => {
    if (!['alice', 'bob'].includes(token)) throw new ApiError(401, 'OWNER_AUTH_REQUIRED');
    return token;
  } });
  const request = async (path: string, data: unknown, token?: string) => {
    const response = await handler(new Request(`https://test${path}`, { method: 'POST', headers: { 'Content-Type': 'application/json', ...(token ? { Authorization: `Bearer ${token}` } : {}) }, body: JSON.stringify(data) }));
    return { status: response.status, data: await response.json() as Record<string, any> };
  };
  return { request, store, advance: (ms: number) => { now += ms; } };
}
const device = { deviceId: 'phone1', name: 'Phone', platform: 'android', credential };
test('iOS issued identity pairs, aliases sync, battery-only telemetry rejects disk data, and agent unpairs', async () => {
  const { request, store, advance } = setup();
  const issued = await request('/v1/ios/identity', {});
  assert.equal(issued.status, 200);
  assert.match(issued.data.deviceId, /^[a-f0-9]{32}$/); assert.match(issued.data.credential, /^[a-f0-9]{64}$/);
  const { code } = (await request('/v1/pairing/create', {}, 'alice')).data;
  await request('/v1/pairing/join', { ...issued.data, code, name: 'iPhone', platform: 'ios' });
  assert.equal((await request('/v1/pairing/status', { code, credential: issued.data.credential })).data.state, 'requested');
  await request('/v1/pairing/approve', { code, name: 'paIM iPhone' }, 'alice');
  const ref = { ownerUid: 'alice', deviceId: issued.data.deviceId };
  assert.equal((await request('/v1/agent/status', ref, issued.data.credential)).data.name, 'paIM iPhone');
  assert.equal((await request('/v1/agent/status', { ...ref, ownerUid: 'bob' }, issued.data.credential)).status, 401);
  const ios = { ...reading, storage: null, battery: { percentage: 10, charging: false, state: 'unplugged' } };
  for (const value of [ { ...ios, storage: { totalBytes: 100, availableBytes: 20 } }, { ...ios, system: { ramTotalBytes: 100 } }, { ...ios, battery: { ...ios.battery, voltageMv: 100 } }, { ...ios, disk: 55 } ]) {
    assert.equal((await request('/v1/telemetry', { ...ref, reading: value }, issued.data.credential)).status, 400);
  }
  assert.equal((await request('/v1/telemetry', { ...ref, reading: ios }, issued.data.credential)).status, 200);
  assert.equal((await request('/v1/telemetry', { ...ref, reading: ios }, issued.data.credential)).status, 200);
  advance(16000);
  assert.equal((await request('/v1/telemetry', { ...ref, reading: { ...ios, sequenceId: 2, battery: { percentage: 11, charging: true, state: 'charging' } } }, issued.data.credential)).status, 200);
  const record = await store.get<any>(`devices/alice/${issued.data.deviceId}`);
  assert.equal(record.public.platform, 'ios'); assert.equal(record.public.latest.storage, null);
  assert.ok(Object.values(record.alerts).some((a: any) => a.kind === 'chargingState'));
  assert.ok(!JSON.stringify(record).includes('totalBytes'));
  assert.equal((await request('/v1/agent/unpair', ref, issued.data.credential)).status, 200);
  assert.equal((await request('/v1/telemetry', { ...ref, reading: { ...ios, sequenceId: 3 } }, issued.data.credential)).status, 401);
});
test('aliases persist across telemetry and enrollment with owner isolation', async () => {
  for (const platform of ['android', 'windows']) {
    const { request, store, advance } = setup();
    await request('/v1/devices/enroll-self', { ...device, platform }, 'alice');
    await request('/v1/telemetry', { ownerUid: 'alice', deviceId: 'phone1', reading }, credential);
    const before = await store.get<any>('devices/alice/phone1');
    assert.equal((await request('/v1/devices/update', { deviceId: 'phone1', name: '  paIM 家 📱  ' }, 'alice')).status, 200);
    assert.equal((await request('/v1/devices/update', { deviceId: 'phone1', name: 'Hacked' }, 'bob')).status, 404);
    assert.equal((await request('/v1/devices/update', { deviceId: 'phone1', name: 'Hacked' })).status, 401);
    for (const name of ['', '   ', 'x'.repeat(41), 'a\nb', 'a\u0000b']) {
      assert.equal((await request('/v1/devices/update', { deviceId: 'phone1', name }, 'alice')).status, 400);
    }
    await request('/v1/devices/enroll-self', { ...device, platform }, 'alice');
    advance(16000);
    assert.equal((await request('/v1/telemetry', { ownerUid: 'alice', deviceId: 'phone1', reading: { ...reading, sequenceId: 2 } }, credential)).status, 200);
    const after = await store.get<any>('devices/alice/phone1');
    assert.equal(after.public.name, 'paIM 家 📱');
    assert.equal(after.credentialHash, before.credentialHash);
    assert.equal(after.public.deviceId, before.public.deviceId);
    assert.equal(Object.keys(after.history).length, 2);
    assert.equal([...store.records.keys()].filter(k => k.startsWith('devices/')).length, 1);
  }
});

test('owner names Windows at approval; retries do not overwrite later alias', async () => {
  const { request, store } = setup();
  const { code } = (await request('/v1/pairing/create', {}, 'alice')).data;
  await request('/v1/pairing/join', { ...device, platform: 'windows', code });
  assert.equal((await request('/v1/pairing/approve', { code, name: 'Paim Windows' }, 'alice')).status, 200);
  assert.equal((await store.get<any>('devices/alice/phone1')).public.name, 'Paim Windows');
  await request('/v1/devices/update', { deviceId: 'phone1', name: 'Office' }, 'alice');
  await request('/v1/pairing/approve', { code, name: 'Paim Windows' }, 'alice');
  assert.equal((await store.get<any>('devices/alice/phone1')).public.name, 'Office');
});
const reading = { schemaVersion: 1, sequenceId: 1, observedAt: '2026-10-16T12:00:00Z', agentVersion: '0.2.0', battery: { percentage: 50, charging: false }, storage: { totalBytes: 100, availableBytes: 30 } };

test('owner authentication is required', async () => {
  const { request } = setup();
  assert.equal((await request('/v1/devices/enroll-self', device)).status, 401);
});
test('enrollment is idempotent, isolated by owner and rejects credential replacement', async () => {
  const { request } = setup();
  assert.equal((await request('/v1/devices/enroll-self', device, 'alice')).status, 200);
  assert.equal((await request('/v1/devices/enroll-self', device, 'alice')).status, 200);
  assert.equal((await request('/v1/devices/enroll-self', { ...device, credential: 'b'.repeat(64) }, 'alice')).status, 409);
  assert.equal((await request('/v1/devices/revoke', { deviceId: 'phone1' }, 'bob')).status, 404);
});
test('pairing requires approval and binds one requester', async () => {
  const { request } = setup();
  const { code } = (await request('/v1/pairing/create', {}, 'alice')).data;
  assert.equal((await request('/v1/pairing/join', { ...device, code })).status, 200);
  assert.equal((await request('/v1/pairing/join', { ...device, code, credential: 'b'.repeat(64) })).status, 409);
  assert.equal((await request('/v1/pairing/status', { code, credential })).data.state, 'requested');
  assert.equal((await request('/v1/pairing/approve', { code }, 'bob')).status, 404);
  assert.equal((await request('/v1/pairing/approve', { code }, 'alice')).status, 200);
  assert.equal((await request('/v1/pairing/status', { code, credential })).data.ownerUid, 'alice');
  assert.equal((await request('/v1/pairing/join', { ...device, code })).status, 400);
});
test('expired pairing and rejected requests cannot be approved', async () => {
  const { request, advance } = setup();
  const { code } = (await request('/v1/pairing/create', {}, 'alice')).data;
  await request('/v1/pairing/reject', { code }, 'alice');
  assert.equal((await request('/v1/pairing/approve', { code }, 'alice')).status, 409);
  advance(300001);
  assert.equal((await request('/v1/pairing/join', { ...device, code })).status, 400);
});
test('telemetry rejects replay, invalid metrics, cross-owner access and revoked credentials', async () => {
  const { request, advance } = setup();
  await request('/v1/devices/enroll-self', device, 'alice');
  const payload = { ownerUid: 'alice', deviceId: 'phone1', reading };
  assert.equal((await request('/v1/telemetry', payload, credential)).status, 200);
  assert.equal((await request('/v1/telemetry', payload, credential)).status, 200);
  assert.equal((await request('/v1/telemetry', { ...payload, reading: { ...reading, battery: null } }, credential)).status, 409);
  assert.equal((await request('/v1/telemetry', { ...payload, ownerUid: 'bob' }, credential)).status, 401);
  assert.equal((await request('/v1/telemetry', { ...payload, reading: { ...reading, storage: { totalBytes: 1, availableBytes: 2 } } }, credential)).status, 400);
  advance(16000);
  await request('/v1/devices/revoke', { deviceId: 'phone1' }, 'alice');
  assert.equal((await request('/v1/telemetry', { ...payload, reading: { ...reading, sequenceId: 2 } }, credential)).status, 401);
});
test('public pairing attempts are persistently rate limited', async () => {
  const { request } = setup();
  for (let i = 0; i < 10; i++) await request('/v1/pairing/status', { code: '123456', credential });
  assert.equal((await request('/v1/pairing/status', { code: '123456', credential })).status, 429);
});
