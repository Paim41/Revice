import { z } from 'zod';
import type { Alert, AlertKind } from './alerts.js';
export const id = z.string().regex(/^[A-Za-z0-9_-]{1,128}$/);
export const secret = z.string().regex(/^[a-f0-9]{64}$/);
export const displayName = z.string().refine(s => !/[\p{Cc}\p{Cf}]/u.test(s), 'Control characters are not allowed').transform(s => s.trim()).refine(s => [...s].length >= 1 && [...s].length <= 40, 'Use 1–40 characters');
export const deviceInput = z.object({ deviceId: id, name: z.string().trim().min(1).max(80), platform: z.enum(['android', 'windows', 'ios']), credential: secret }).strict();
export const battery = z.object({
  percentage: z.number().min(0).max(100).nullable(), charging: z.boolean().nullable(),
  state: z.enum(['charging', 'unplugged', 'full', 'unknown']).optional(),
  temperatureC: z.number().min(-50).max(150).nullable().optional(),
  voltageMv: z.number().int().positive().nullable().optional(), health: z.string().max(40).nullable().optional(),
  cycleCount: z.number().int().nonnegative().nullable().optional(),
}).strict().nullable();
export const storage = z.object({ totalBytes: z.number().int().positive().max(Number.MAX_SAFE_INTEGER), availableBytes: z.number().int().nonnegative() }).strict().refine(s => s.availableBytes <= s.totalBytes).nullable();
export const telemetry = z.object({
  schemaVersion: z.literal(1), sequenceId: z.number().int().nonnegative().max(Number.MAX_SAFE_INTEGER),
  observedAt: z.iso.datetime(), agentVersion: z.string().min(1).max(32), battery, storage,
  system: z.object({ cpuPercent: z.number().min(0).max(100).nullable().optional(), ramTotalBytes: z.number().nonnegative().optional(), ramUsedBytes: z.number().nonnegative().optional(), uptimeSeconds: z.number().nonnegative().optional() }).strict().optional(),
}).strict();
// Enforced against the registered platform, never a client-supplied platform flag.
export const iosTelemetry = telemetry.extend({
  storage: z.null(), system: z.never().optional(),
  battery: z.object({ percentage: z.number().min(0).max(100).nullable(), charging: z.boolean().nullable(), state: z.enum(['charging', 'unplugged', 'full', 'unknown']) }).strict(),
});
export type Reading = z.infer<typeof telemetry> & { receivedAt: number };
export interface Device {
  credentialHash: string;
  public: { deviceId: string; name: string; platform: 'android' | 'windows' | 'ios'; pairedAt: number; revoked: boolean; latest?: Reading; group?: string };
  lastSequence: number;
  lastDigest?: string;
  history?: Record<string, Reading>;
  alerts?: Record<string, Alert>;
  alertState?: Partial<Record<AlertKind, { active: boolean; lastSent: number }>>;
  alertSettings?: { criticalBattery: number; lowBattery: number; chargingTarget: number; storage: number; staleMinutes: number; cooldownMinutes: number };
}
export interface Pairing {
  ownerUid: string; expiresAt: number; state: 'waiting' | 'requested' | 'approved' | 'rejected';
  request?: { deviceId: string; name: string; platform: 'android' | 'windows' | 'ios'; credentialHash: string };
}
