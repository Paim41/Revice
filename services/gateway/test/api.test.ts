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
