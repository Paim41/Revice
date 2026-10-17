import { z } from 'zod';
import { ApiError, type Env, type Store } from './store.js';
import { hash, sameHash } from './security.js';
import type { Device } from './contracts.js';

interface Link { tokenHash?: string; expiresAt?: number; pendingChat?: string; pendingName?: string; chatId?: string; lastUpdate?: number }
export async function sendTelegram(env: Env, chatId: string, text: string) {
  if (!env.TELEGRAM_BOT_TOKEN) throw new ApiError(503, 'TELEGRAM_NOT_CONFIGURED');
  const response = await fetch(`https://api.telegram.org/bot${env.TELEGRAM_BOT_TOKEN}/sendMessage`, { method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify({ chat_id: chatId, text: text.slice(0, 4000) }), signal: AbortSignal.timeout(15000) });
  const result = await response.json() as { ok: boolean };
  if (!response.ok || !result.ok) throw new ApiError(502, 'TELEGRAM_SEND_FAILED');
}
export async function telegramOwner(path: string, body: unknown, owner: string, store: Store, env: Env, now: number) {
  z.object({}).strict().parse(body);
  if (!env.TELEGRAM_BOT_TOKEN || !env.TELEGRAM_WEBHOOK_SECRET || !env.TELEGRAM_BOT_USERNAME) throw new ApiError(503, 'TELEGRAM_NOT_CONFIGURED');
  const linkPath = `private/telegram/${owner}`;
  if (path.endsWith('/link')) {
    const token = Array.from(crypto.getRandomValues(new Uint8Array(24)), b => b.toString(16).padStart(2, '0')).join('');
    const tokenHash = await hash(token, env.AGENT_TOKEN_HASH_KEY);
    await store.update<Link>(linkPath, current => ({ chatId: current?.chatId, tokenHash, expiresAt: now + 300000 }));
    await store.put(`private/telegramTokens/${tokenHash}`, { owner, expiresAt: now + 300000 });
    return { url: `https://t.me/${env.TELEGRAM_BOT_USERNAME}?start=${token}`, expiresAt: now + 300000 };
  }
  if (path.endsWith('/status')) {
    const link = await store.get<Link>(linkPath);
    return { linked: !!link?.chatId, pendingName: link?.expiresAt && link.expiresAt > now ? link.pendingName ?? null : null };
  }
  if (path.endsWith('/approve')) {
    const link = await store.update<Link>(linkPath, current => {
      if (!current?.pendingChat || !current.expiresAt || current.expiresAt <= now) throw new ApiError(409, 'NO_PENDING_TELEGRAM');
      return { chatId: current.pendingChat };
    });
    await store.put(`private/telegramChats/${link.chatId}`, { owner });
    return { linked: true };
  }
  if (path.endsWith('/unlink')) { await store.put(linkPath, null); return { linked: false }; }
  if (path.endsWith('/test')) {
    const link = await store.get<Link>(linkPath);
    if (!link?.chatId) throw new ApiError(409, 'TELEGRAM_NOT_LINKED');
    await sendTelegram(env, link.chatId, 'Device monitoring test notification. Your Telegram link is working.');
    return { sent: true };
  }
  throw new ApiError(404, 'NOT_FOUND');
}
export async function telegramWebhook(request: Request, body: unknown, store: Store, env: Env, now: number) {
  if (!env.TELEGRAM_WEBHOOK_SECRET || !env.TELEGRAM_BOT_TOKEN) throw new ApiError(503, 'TELEGRAM_NOT_CONFIGURED');
  const supplied = request.headers.get('X-Telegram-Bot-Api-Secret-Token') ?? '';
  if (!sameHash(await hash(supplied, env.AGENT_TOKEN_HASH_KEY), await hash(env.TELEGRAM_WEBHOOK_SECRET, env.AGENT_TOKEN_HASH_KEY))) throw new ApiError(401, 'WEBHOOK_UNAUTHORIZED');
  const update = z.object({ update_id: z.number().int(), message: z.object({ text: z.string().max(4096).optional(), chat: z.object({ id: z.number().int().safe(), type: z.string(), first_name: z.string().max(200).optional() }) }).optional() }).parse(body);
  const message = update.message;
  if (!message || message.chat.type !== 'private' || !message.text) return { ok: true };
  const chatId = String(message.chat.id);
  const start = message.text.match(/^\/start ([a-f0-9]{48})$/);
  if (start) {
    const tokenHash = await hash(start[1], env.AGENT_TOKEN_HASH_KEY);
    const token = await store.get<{ owner: string; expiresAt: number }>(`private/telegramTokens/${tokenHash}`);
    if (!token || token.expiresAt <= now) return { ok: true };
    await store.update<Link>(`private/telegram/${token.owner}`, current => {
      if (!current?.tokenHash || !sameHash(current.tokenHash, tokenHash) || !current.expiresAt || current.expiresAt <= now || (current.pendingChat && current.pendingChat !== chatId)) throw new ApiError(409, 'LINK_UNAVAILABLE');
      return { ...current, pendingChat: chatId, pendingName: message.chat.first_name ?? 'Telegram user' };
    });
    return { ok: true };
  }
  if (!['/status', '/devices', '/battery'].includes(message.text)) return { ok: true };
  const mapping = await store.get<{ owner: string }>(`private/telegramChats/${chatId}`);
  if (!mapping) return { ok: true };
  let duplicate = false;
  await store.update<Link>(`private/telegram/${mapping.owner}`, current => {
    if (!current || current.chatId !== chatId) throw new ApiError(401, 'TELEGRAM_NOT_LINKED');
    duplicate = current.lastUpdate != null && update.update_id <= current.lastUpdate;
    return duplicate ? current : { ...current, lastUpdate: update.update_id };
  });
  if (duplicate) return { ok: true };
  const directory = await store.get<Record<string, boolean>>(`directory/${mapping.owner}`) ?? {};
  const lines: string[] = [];
  for (const id of Object.keys(directory).slice(0, 20)) {
    const device = await store.get<Device>(`devices/${mapping.owner}/${id}`);
    if (!device || device.public.revoked) continue;
    const latest = device.public.latest;
    const age = latest ? Math.max(0, Math.floor((now - Date.parse(latest.observedAt)) / 60000)) : null;
    const battery = latest?.battery?.percentage;
    lines.push(`${device.public.name}: ${battery == null ? 'Battery unavailable' : `${battery}%`} • ${age == null ? 'No readings' : `${age} min old`}`);
  }
  await sendTelegram(env, chatId, lines.join('\n') || 'No reporting devices.');
  return { ok: true };
}

export async function deliverAlerts(store: Store, env: Env, owner: string, deviceId: string, now: number) {
  const link = await store.get<Link>(`private/telegram/${owner}`);
  if (!link?.chatId || !env.TELEGRAM_BOT_TOKEN) return;
  const pending: string[] = [];
  const ids: string[] = [];
  await store.update<Device>(`devices/${owner}/${deviceId}`, current => {
    if (!current) throw new ApiError(404, 'DEVICE_NOT_FOUND');
    pending.length = 0;
    ids.length = 0;
    if (current.public.revoked) return current;
    for (const alert of Object.values(current.alerts ?? {})) {
      if (alert.active && !alert.deliveryAttemptedAt) { pending.push(alert.message); ids.push(alert.id); alert.deliveryAttemptedAt = now; }
    }
    return current;
  });
  // Mark before sending for at-most-once notification attempts. Telegram has no
  // idempotency key; failures remain visible in activity but are not auto-replayed.
  if (pending.length) {
    await sendTelegram(env, link.chatId, pending.join('\n'));
    await store.update<Device>(`devices/${owner}/${deviceId}`, current => {
      if (!current) throw new ApiError(404, 'DEVICE_NOT_FOUND');
      for (const id of ids) if (current.alerts?.[id]) current.alerts[id].deliveredAt = now;
      return current;
    });
  }
}
