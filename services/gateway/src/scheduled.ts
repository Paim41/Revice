import type { Env, Store } from './store.js';
import { evaluateAlerts } from './alerts.js';
import type { Device } from './contracts.js';
import { deliverAlerts } from './telegram.js';

export async function scheduledMaintenance(store: Store, env: Env, now = Date.now()) {
  const directory = await store.get<Record<string, Record<string, boolean>>>('directory') ?? {};
  const items = Object.entries(directory).flatMap(([owner, devices]) => Object.keys(devices).map(device => ({ owner, device })));
  if (!items.length) return;
  const cursor = await store.update<{ next: number }>('private/maintenanceCursor', current => ({ next: ((current?.next ?? 0) + Math.min(4, items.length)) % items.length }));
  const start = (cursor.next - Math.min(4, items.length) + items.length) % items.length;
  for (let i = 0; i < Math.min(4, items.length); i++) {
    const { owner, device } = items[(start + i) % items.length];
    await store.update<Device>(`devices/${owner}/${device}`, current => {
      if (!current) throw new Error('Directory points to missing device');
      const history = Object.fromEntries(Object.entries(current.history ?? {}).filter(([, r]) => now - Date.parse(r.observedAt) < 7 * 86400000));
      return evaluateAlerts({ ...current, history }, now);
    });
    try { await deliverAlerts(store, env, owner, device, now); }
    catch { console.error(JSON.stringify({ error: 'ALERT_DELIVERY_FAILED' })); }
  }
}
