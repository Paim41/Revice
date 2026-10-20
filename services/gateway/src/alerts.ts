import type { Device, Reading } from './contracts.js';

export type AlertKind = 'criticalBattery' | 'lowBattery' | 'chargingTarget' | 'storage' | 'stale' | 'chargingState';
export interface Alert { id: string; kind: AlertKind; at: number; message: string; active: boolean; deliveryAttemptedAt?: number; deliveredAt?: number }
export const defaults = { criticalBattery: 10, lowBattery: 20, chargingTarget: 80, storage: 90, staleMinutes: 45, cooldownMinutes: 60 };
export function evaluateAlerts(device: Device, now: number): Device {
  const settings = { ...defaults, ...device.alertSettings };
  const latest = device.public.latest;
  if (!latest || device.public.revoked) return device;
  const percent = latest.battery?.percentage;
  const stale = now - Date.parse(latest.observedAt) >= settings.staleMinutes * 60000;
  const conditions: Record<AlertKind, boolean> = {
    criticalBattery: !stale && percent != null && !latest.battery?.charging && percent <= settings.criticalBattery,
    lowBattery: !stale && percent != null && !latest.battery?.charging && percent <= settings.lowBattery && percent > settings.criticalBattery,
    chargingTarget: !stale && percent != null && latest.battery?.charging === true && percent >= settings.chargingTarget,
    storage: !stale && latest.storage != null && 100 * (1 - latest.storage.availableBytes / latest.storage.totalBytes) >= settings.storage,
    stale,
    chargingState: false,
  };
  const descriptions: Record<AlertKind, string> = {
    criticalBattery: `Critical battery: ${percent}%`, lowBattery: `Low battery: ${percent}%`, chargingTarget: `Charging target reached: ${percent}%`, storage: 'Storage usage exceeds your threshold', stale: 'Device readings are stale', chargingState: 'Charging state changed',
  };
  const state = { ...device.alertState };
  const alerts = Object.fromEntries(Object.entries(device.alerts ?? {}).filter(([, alert]) => now - alert.at < 90 * 86400000).sort((a, b) => a[1].at - b[1].at).slice(-99));
  for (const kind of Object.keys(conditions) as AlertKind[]) {
    const previous = state[kind];
    if (conditions[kind] && (!previous || now - previous.lastSent >= settings.cooldownMinutes * 60000)) {
      const id = `${kind}_${now}`;
      alerts[id] = { id, kind, at: now, message: `${device.public.name}: ${descriptions[kind]}`, active: true };
      state[kind] = { active: true, lastSent: now };
    } else {
      state[kind] = { active: conditions[kind], lastSent: previous?.lastSent ?? 0 };
    }
    if (!conditions[kind]) for (const alert of Object.values(alerts)) if (alert.kind === kind) alert.active = false;
  }
  return { ...device, alerts, alertState: state };
}

export function summarize(readings: Reading[]) {
  const values = readings.map(r => r.battery?.percentage).filter((v): v is number => v != null);
  return { count: readings.length, averageBattery: values.length ? values.reduce((a, b) => a + b, 0) / values.length : null, minimumBattery: values.length ? Math.min(...values) : null };
}
