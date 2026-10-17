import { createApi } from './api.js';
import { FirebaseStore, type Env } from './store.js';
import { scheduledMaintenance } from './scheduled.js';
export default {
  fetch(request: Request, env: Env) { return createApi(env, { store: new FirebaseStore(env) })(request); },
  async scheduled(_event: unknown, env: Env) { await scheduledMaintenance(new FirebaseStore(env), env); },
};
