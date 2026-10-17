import { writeFile } from 'node:fs/promises';
import { z } from 'zod';
import { id, telemetry } from './src/contracts.js';
const schema = z.toJSONSchema(z.object({ ownerUid: id, deviceId: id, reading: telemetry }).strict());
await writeFile(new URL('../../packages/contracts/schemas/telemetry-v1.schema.json', import.meta.url), JSON.stringify({ ...schema, $comment: 'Agent ingestion envelope. Runtime additionally validates availableBytes <= totalBytes, time skew, credentials and sequence replay. receivedAt is server-generated.' }, null, 2) + '\n');
