import { z } from 'zod';
import { ApiError, type Env, type Store } from './store.js';
import { deviceInput, id, secret, telemetry, type Device, type Pairing } from './contracts.js';
import { hash, ownerIdentity, randomCode, rateLimit, sameHash } from './security.js';
import { evaluateAlerts } from './alerts.js';
import { telegramOwner, telegramWebhook } from './telegram.js';

type Dependencies = { store: Store; verifyOwner?: (token: string) => Promise<string>; now?: () => number };
const pairingInput = z.object({ code: z.string().regex(/^\d{6}$/) }).strict();
async function body(request: Request) {
  if (!request.headers.get('content-type')?.startsWith('application/json')) throw new ApiError(415, 'JSON_REQUIRED');
  const reader = request.body?.getReader();
  if (!reader) throw new ApiError(400, 'BODY_REQUIRED');
  const chunks: Uint8Array[] = []; let length = 0;
  for (;;) {
    const { done, value } = await reader.read(); if (done) break;
    length += value.length;
    if (length > 16384) { await reader.cancel(); throw new ApiError(413, 'PAYLOAD_TOO_LARGE'); }
    chunks.push(value);
  }
  const all = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { all.set(chunk, offset); offset += chunk.length; }
  try { return JSON.parse(new TextDecoder().decode(all)); } catch { throw new ApiError(400, 'INVALID_JSON'); }
}
export function createApi(env: Env, dependencies: Dependencies) {
  const { store } = dependencies;
  return async (request: Request): Promise<Response> => {
    const requestId = crypto.randomUUID();
    const reply = (value: unknown, status = 200) => Response.json(value, { status, headers: { 'Cache-Control': 'no-store', 'X-Request-Id': requestId } });
    try {
      const path = new URL(request.url).pathname;
      if (path === '/health' && request.method === 'GET') return reply({ service: 'revice-gateway', version: '0.2.0' });
      if (request.method !== 'POST') throw new ApiError(405, 'METHOD_NOT_ALLOWED');
      if (!env.FIREBASE_PROJECT_ID || !env.FIREBASE_DATABASE_URL || env.AGENT_TOKEN_HASH_KEY?.length < 32) throw new ApiError(503, 'CONFIGURATION');
      const now = dependencies.now?.() ?? Date.now();
      const data = await body(request);
      if (path === '/v1/telegram/webhook') return reply(await telegramWebhook(request, data, store, env, now));
      const bearer = request.headers.get('authorization')?.match(/^Bearer (\S+)$/)?.[1];
      const publicPairing = path === '/v1/pairing/join' || path === '/v1/pairing/status';
      if (publicPairing) {
        const ip = request.headers.get('CF-Connecting-IP') ?? 'local';
        await rateLimit(store, await hash(`ip:${ip}`, env.AGENT_TOKEN_HASH_KEY), 10, now);
      }
      let owner = '';
      if (!publicPairing && path !== '/v1/telemetry') {
        if (!bearer) throw new ApiError(401, 'OWNER_AUTH_REQUIRED');
        owner = await (dependencies.verifyOwner ?? ((t: string) => ownerIdentity(t, env.FIREBASE_PROJECT_ID)))(bearer);
        await rateLimit(store, await hash(`owner:${owner}`, env.AGENT_TOKEN_HASH_KEY), 60, now);
      }
      if (path === '/v1/devices/enroll-self') {
        const input = deviceInput.parse(data);
        const credentialHash = await hash(input.credential, env.AGENT_TOKEN_HASH_KEY);
        const record = await store.update<Device>(`devices/${owner}/${input.deviceId}`, current => {
          if (current) {
            if (!sameHash(current.credentialHash, credentialHash) || current.public.revoked) throw new ApiError(409, 'DEVICE_EXISTS');
            return current;
          }
          return { credentialHash, lastSequence: -1, public: { deviceId: input.deviceId, name: input.name, platform: input.platform, pairedAt: now, revoked: false } };
        });
        await store.put(`directory/${owner}/${input.deviceId}`, true);
        return reply({ ownerUid: owner, device: record.public });
      }
      if (path.startsWith('/v1/telegram/')) return reply(await telegramOwner(path, data, owner, store, env, now));
      if (path === '/v1/pairing/create') {
        z.object({}).strict().parse(data);
        for (let attempt = 0; attempt < 5; attempt++) {
          const code = randomCode();
          try {
            await store.update<Pairing>(`private/pairing/${code}`, current => {
              if (current && current.expiresAt > now) throw new ApiError(409, 'CODE_COLLISION');
              return { ownerUid: owner, expiresAt: now + 300000, state: 'waiting' };
            });
            return reply({ code, expiresAt: now + 300000 });
          } catch (error) { if (!(error instanceof ApiError) || error.code !== 'CODE_COLLISION') throw error; }
        }
        throw new ApiError(503, 'PAIRING_BUSY');
      }
      if (path === '/v1/pairing/join') {
        const input = deviceInput.extend({ code: z.string().regex(/^\d{6}$/) }).parse(data);
        const credentialHash = await hash(input.credential, env.AGENT_TOKEN_HASH_KEY);
        await store.update<Pairing>(`private/pairing/${input.code}`, current => {
          if (!current || current.expiresAt <= now || current.state === 'rejected' || current.state === 'approved') throw new ApiError(400, 'PAIRING_UNAVAILABLE');
          if (current.request && (current.request.deviceId !== input.deviceId || !sameHash(current.request.credentialHash, credentialHash))) throw new ApiError(409, 'PAIRING_IN_USE');
          return { ...current, state: 'requested', request: { deviceId: input.deviceId, name: input.name, platform: input.platform, credentialHash } };
        });
        return reply({ state: 'requested' });
      }
      if (path === '/v1/pairing/status') {
        const input = pairingInput.extend({ credential: secret }).parse(data);
        const session = await store.get<Pairing>(`private/pairing/${input.code}`);
        const credentialHash = await hash(input.credential, env.AGENT_TOKEN_HASH_KEY);
        if (!session || session.expiresAt <= now || !session.request || !sameHash(session.request.credentialHash, credentialHash)) throw new ApiError(404, 'PAIRING_UNAVAILABLE');
        if (session.state !== 'approved') return reply({ state: session.state });
        const device = await store.get<Device>(`devices/${session.ownerUid}/${session.request.deviceId}`);
        if (!device || device.public.revoked) return reply({ state: 'requested' });
        return reply({ state: 'approved', ownerUid: session.ownerUid, deviceId: session.request.deviceId });
      }
      if (['/v1/pairing/inspect', '/v1/pairing/approve', '/v1/pairing/reject'].includes(path)) {
        const { code } = pairingInput.parse(data);
        const session = await store.update<Pairing>(`private/pairing/${code}`, current => {
          if (!current || current.ownerUid !== owner || current.expiresAt <= now) throw new ApiError(404, 'PAIRING_UNAVAILABLE');
          if (path.endsWith('inspect')) return current;
          if (current.state === 'rejected') throw new ApiError(409, 'PAIRING_REJECTED');
          if (path.endsWith('reject')) {
            if (current.state === 'approved') throw new ApiError(409, 'PAIRING_ALREADY_APPROVED');
            return { ...current, state: 'rejected' };
          }
          if (!current.request) throw new ApiError(409, 'NO_REQUEST');
          return { ...current, state: 'approved' };
        });
        if (path.endsWith('approve') && session.request) {
          const r = session.request;
          await store.update<Device>(`devices/${owner}/${r.deviceId}`, existing => {
            if (existing) {
              if (!sameHash(existing.credentialHash, r.credentialHash) || existing.public.revoked) throw new ApiError(409, 'DEVICE_EXISTS');
              return existing;
            }
            return { credentialHash: r.credentialHash, lastSequence: -1, public: { deviceId: r.deviceId, name: r.name, platform: r.platform, pairedAt: now, revoked: false } };
          });
          await store.put(`directory/${owner}/${r.deviceId}`, true);
        }
        return reply({ state: session.state, expiresAt: session.expiresAt, request: session.request ? { deviceId: session.request.deviceId, name: session.request.name, platform: session.request.platform } : null });
      }
      if (path === '/v1/devices/revoke' || path === '/v1/devices/update') {
        const input = z.object({ deviceId: id, name: z.string().trim().min(1).max(80).optional(), group: z.string().max(80).optional() }).strict().parse(data);
        await store.update<Device>(`devices/${owner}/${input.deviceId}`, current => {
          if (!current) throw new ApiError(404, 'DEVICE_NOT_FOUND');
          return { ...current, public: { ...current.public, ...(input.name ? { name: input.name } : {}), ...(input.group !== undefined ? { group: input.group } : {}), revoked: path.endsWith('revoke') || current.public.revoked } };
        });
        return reply({ ok: true });
      }
      if (path === '/v1/telemetry') {
        const input = z.object({ ownerUid: id, deviceId: id, reading: telemetry }).strict().parse(data);
        if (!bearer || !secret.safeParse(bearer).success) throw new ApiError(401, 'AGENT_AUTH_REQUIRED');
        const credentialHash = await hash(bearer, env.AGENT_TOKEN_HASH_KEY);
        const observed = Date.parse(input.reading.observedAt);
        if (observed > now + 120000 || observed < now - 7 * 86400000) throw new ApiError(400, 'TIMESTAMP_OUT_OF_RANGE');
        const digest = await hash(JSON.stringify(input.reading), env.AGENT_TOKEN_HASH_KEY);
        await store.update<Device>(`devices/${input.ownerUid}/${input.deviceId}`, current => {
          if (!current || current.public.revoked || !sameHash(current.credentialHash, credentialHash)) throw new ApiError(401, 'AGENT_REVOKED_OR_INVALID');
          if (input.reading.sequenceId === current.lastSequence && current.lastDigest === digest) return current;
          if (input.reading.sequenceId <= current.lastSequence) throw new ApiError(409, 'SEQUENCE_REPLAY');
          if (current.public.latest && now - current.public.latest.receivedAt < 15000) throw new ApiError(429, 'REPORT_TOO_FREQUENT');
          const reading = { ...input.reading, receivedAt: now };
          const history = Object.fromEntries(Object.entries(current.history ?? {}).filter(([, value]) => now - Date.parse(value.observedAt) < 7 * 86400000).sort((a, b) => a[1].receivedAt - b[1].receivedAt).slice(-255));
          history[`s_${input.reading.sequenceId}`] = reading;
          const latest = !current.public.latest || observed >= Date.parse(current.public.latest.observedAt) ? reading : current.public.latest;
          return evaluateAlerts({ ...current, lastSequence: input.reading.sequenceId, lastDigest: digest, history, public: { ...current.public, latest } }, now);
        });
        return reply({ accepted: true });
      }
      throw new ApiError(404, 'NOT_FOUND');
    } catch (error) {
      if (error instanceof z.ZodError) return reply({ error: 'INVALID_INPUT', requestId }, 400);
      if (error instanceof ApiError) return reply({ error: error.code, requestId }, error.status);
      // Never log request bodies, authorization headers or upstream secret-bearing errors.
      console.error(JSON.stringify({ requestId, error: 'INTERNAL' }));
      return reply({ error: 'INTERNAL', requestId }, 500);
    }
  };
}
