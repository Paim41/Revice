import { test } from 'node:test';
import assert from 'node:assert/strict';
import { evaluateAlerts, summarize } from '../src/alerts.js';
import type { Device } from '../src/contracts.js';

const now = Date.parse('2026-10-16T12:00:00Z');
function device(): Device { return { credentialHash: 'x', lastSequence: 1, public: { deviceId: 'phone', name: 'Phone', platform: 'android', pairedAt: now, revoked: false, latest: { schemaVersion: 1, sequenceId: 1, observedAt: new Date(now).toISOString(), receivedAt: now, agentVersion: 'test', battery: { percentage: 9, charging: false }, storage: null } } }; }
test('critical replaces low alert; repeated observations respect cooldown', () => {
  const first = evaluateAlerts(device(), now);
  assert.equal(Object.values(first.alerts!)[0].kind, 'criticalBattery');
  assert.equal(Object.keys(evaluateAlerts(first, now + 60000).alerts!).length, 1);
});
test('stale readings do not generate current battery warnings', () => {
  const result = evaluateAlerts(device(), now + 46 * 60000);
  assert.deepEqual(Object.values(result.alerts!).map(a => a.kind), ['stale']);
});
test('charging clears active critical alert', () => {
  const first = evaluateAlerts(device(), now);
  first.public.latest!.battery!.charging = true;
  assert.equal(Object.values(evaluateAlerts(first, now + 60000).alerts!)[0].active, false);
});
test('empty history has no fabricated analytics', () => assert.deepEqual(summarize([]), { count: 0, averageBattery: null, minimumBattery: null }));
