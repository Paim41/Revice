import { test } from 'node:test';
import assert from 'node:assert/strict';
import { telegramOwner, telegramWebhook } from '../src/telegram.js';
import type { Store, Env } from '../src/store.js';
const env: Env = { FIREBASE_PROJECT_ID: 'test', FIREBASE_DATABASE_URL: '', FIREBASE_SERVICE_ACCOUNT_JSON: '', AGENT_TOKEN_HASH_KEY: 'x'.repeat(32), TELEGRAM_BOT_TOKEN: 'test-token', TELEGRAM_WEBHOOK_SECRET: 'webhook-secret', TELEGRAM_BOT_USERNAME: 'test_bot' };
function memory(): Store {
  const data = new Map<string, unknown>();
  return { async get<T>(path: string) { return structuredClone(data.get(path) ?? null) as T | null; }, async put(path, value) { data.set(path, structuredClone(value)); }, async update<T>(path: string, change: (value: T | null) => T) { const value = change(structuredClone(data.get(path) ?? null) as T | null); data.set(path, value); return value; } };
}
test('webhook requires secret header before processing any message', async () => {
  await assert.rejects(() => telegramWebhook(new Request('https://test'), {}, memory(), env, 0));
});
test('Telegram link requires owner approval; expires and never auto-links', async () => {
  const store = memory();
  const start = await telegramOwner('/v1/telegram/link', {}, 'alice', store, env, 1000) as { url: string };
  const token = new URL(start.url).searchParams.get('start');
  const request = new Request('https://test', { headers: { 'X-Telegram-Bot-Api-Secret-Token': env.TELEGRAM_WEBHOOK_SECRET! } });
  await telegramWebhook(request, { update_id: 1, message: { text: `/start ${token}`, chat: { id: 123, type: 'private', first_name: 'Test user' } } }, store, env, 2000);
  assert.deepEqual(await telegramOwner('/v1/telegram/status', {}, 'alice', store, env, 2000), { linked: false, pendingName: 'Test user' });
  await telegramOwner('/v1/telegram/approve', {}, 'alice', store, env, 3000);
  assert.equal((await telegramOwner('/v1/telegram/status', {}, 'alice', store, env, 3000) as { linked: boolean }).linked, true);
  await telegramOwner('/v1/telegram/unlink', {}, 'alice', store, env, 4000);
  assert.equal((await telegramOwner('/v1/telegram/status', {}, 'alice', store, env, 4000) as { linked: boolean }).linked, false);
});
