import { importPKCS8, SignJWT } from 'jose';

export class ApiError extends Error {
  constructor(public status: number, public code: string) { super(code); }
}
export interface Store {
  get<T>(path: string): Promise<T | null>;
  put(path: string, value: unknown): Promise<void>;
  update<T>(path: string, change: (value: T | null) => T): Promise<T>;
}
export interface Env {
  FIREBASE_PROJECT_ID: string;
  FIREBASE_DATABASE_URL: string;
  FIREBASE_SERVICE_ACCOUNT_JSON: string;
  AGENT_TOKEN_HASH_KEY: string;
  TELEGRAM_BOT_TOKEN?: string;
  TELEGRAM_WEBHOOK_SECRET?: string;
  TELEGRAM_BOT_USERNAME?: string;
}
let cached: { identity: string; token: string; until: number } | undefined;
async function accessToken(env: Env): Promise<string> {
  const account = JSON.parse(env.FIREBASE_SERVICE_ACCOUNT_JSON);
  if (account.project_id !== env.FIREBASE_PROJECT_ID) throw new ApiError(503, 'CONFIGURATION');
  if (cached && cached.identity === account.private_key_id && cached.until > Date.now()) return cached.token;
  const key = await importPKCS8(account.private_key, 'RS256');
  const assertion = await new SignJWT({ scope: 'https://www.googleapis.com/auth/firebase.database https://www.googleapis.com/auth/userinfo.email' })
    .setProtectedHeader({ alg: 'RS256' }).setIssuer(account.client_email)
    .setAudience('https://oauth2.googleapis.com/token').setIssuedAt().setExpirationTime('1h').sign(key);
  const response = await fetch('https://oauth2.googleapis.com/token', {
    method: 'POST', body: new URLSearchParams({ grant_type: 'urn:ietf:params:oauth:grant-type:jwt-bearer', assertion }),
    signal: AbortSignal.timeout(15000),
  });
  if (!response.ok) throw new ApiError(503, 'DATABASE_AUTH');
  const data = await response.json() as { access_token: string; expires_in: number };
  cached = { identity: account.private_key_id, token: data.access_token, until: Date.now() + (data.expires_in - 120) * 1000 };
  return cached.token;
}

export class FirebaseStore implements Store {
  constructor(private env: Env) {}
  private async request(path: string, init: RequestInit = {}) {
    const base = new URL(this.env.FIREBASE_DATABASE_URL);
    if (base.protocol !== 'https:' || !/\.(firebaseio\.com|firebasedatabase\.app)$/.test(base.hostname)) throw new ApiError(503, 'CONFIGURATION');
    const response = await fetch(`${base.origin}/${path}.json`, {
      ...init, headers: { Authorization: `Bearer ${await accessToken(this.env)}`, 'Content-Type': 'application/json', ...init.headers },
      signal: AbortSignal.timeout(15000),
    });
    if (!response.ok && response.status !== 412) throw new ApiError(503, 'DATABASE_UNAVAILABLE');
    return response;
  }
  async get<T>(path: string): Promise<T | null> { return await (await this.request(path)).json() as T | null; }
  async put(path: string, value: unknown) { await this.request(path, { method: 'PUT', body: JSON.stringify(value) }); }
  async update<T>(path: string, change: (value: T | null) => T): Promise<T> {
    for (let attempt = 0; attempt < 8; attempt++) {
      const read = await this.request(path, { headers: { 'X-Firebase-ETag': 'true' } });
      const etag = read.headers.get('etag');
      if (!etag) throw new ApiError(503, 'DATABASE_CONCURRENCY');
      const next = change(await read.json() as T | null);
      const write = await this.request(path, { method: 'PUT', headers: { 'if-match': etag }, body: JSON.stringify(next) });
      if (write.status !== 412) return next;
    }
    throw new ApiError(409, 'RETRY_CONFLICT');
  }
}
