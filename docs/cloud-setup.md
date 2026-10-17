# Cloud setup and verification

The source implements cloud clients and a Worker; no live Firebase project or Worker has been configured or deployed from this chat.

## Firebase

1. Use your existing Firebase project. Keep billing on the intended free plan.
2. Enable Authentication → Email/password.
3. Create Realtime Database in locked mode. Copy its exact HTTPS database URL.
4. Register an Android app with package `app.revice.revice_android`.
5. Copy the public Firebase project ID, Android app ID, API key and messaging sender ID into a local copy of `apps/android/revice_android/config.example.json` named `config.json`.
6. Deploy the reviewed rules from `firebase/database.rules.json` using the Firebase console or `npx firebase deploy --only database --project YOUR_PROJECT_ID` from `firebase/`. This changes access to the selected database; use the intended Revice database.
7. Create a dedicated service account with only the database access it needs. Store its JSON in a Worker secret, never in Android configuration or Git.

Rules allow verified owners to read `directory/{uid}`, `devices/{uid}/{id}/public`, `/history` and `/alerts`. Parent device records, credentials, pairing and Telegram state remain unreadable by clients. Direct client writes are denied. The Worker uses Google OAuth service-account tokens to perform privileged REST operations.

## Cloudflare Worker

From `C:\dev\Revice\services\gateway`:

```powershell
npm.cmd ci
npm.cmd run check
npm.cmd test
npm.cmd run build
npx.cmd wrangler login
```

Set `FIREBASE_PROJECT_ID` and `FIREBASE_DATABASE_URL` in `wrangler.jsonc`. Use Wrangler secret prompts or the Cloudflare dashboard to set:

- `FIREBASE_SERVICE_ACCOUNT_JSON`: the dedicated service account JSON.
- `AGENT_TOKEN_HASH_KEY`: at least 32 cryptographically random characters; store a backup securely. Rotation currently invalidates all agent credentials and requires re-pairing.
- Optional `TELEGRAM_BOT_TOKEN` and `TELEGRAM_WEBHOOK_SECRET`.

Only after reviewing the target account and settings, deploy with `npx.cmd wrangler deploy`. No paid resource is required by this project configuration. Set `CLOUDFLARE_GATEWAY_URL` in Android `config.json` to the deployed HTTPS origin without trailing slash.

Build configured Android:

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=config.json
```

Unconfigured builds continue to support local metrics and explain that cloud settings are missing.

## Pairing

1. Owner signs in or creates an account and verifies email.
2. On the primary phone, open Account & pairing → Register this phone.
3. Create a pairing code for the secondary phone or Windows agent.
4. Enter the code on the other device. The agent generates a random 256-bit credential locally and submits it through HTTPS; only its keyed hash is persisted on the server.
5. On the owner phone, Check request, inspect the device name/platform, then Approve.
6. On the agent, Check approval. Sync now and verify the owner receives the device-specific reading.
7. Revoke the device in the owner dashboard and verify subsequent uploads fail.

Codes expire in five minutes and bind to a single requester. Repeated identical enrollment and approval requests are recoverable. Agent storage is Android secure storage or Windows DPAPI. Unpairing removes the local credential; revoke on the owner dashboard as well to invalidate the server record.

## Telegram

Create a bot with BotFather. Configure the token and a random webhook secret only on the Worker. Set the non-secret `TELEGRAM_BOT_USERNAME` variable to the bot's username without `@`. Register the webhook with Telegram `setWebhook`, using your Worker `/v1/telegram/webhook` endpoint and `secret_token` matching the Worker secret. Do not put the bot token in a browser URL or commit it to a script.

In Account & pairing → Telegram, create a link. Open the displayed link in Telegram and press Start. Back in the app, check the request and approve the displayed Telegram name. Sending `/start` alone never links an account. Use Send test to verify delivery. Commands `/status`, `/devices` and `/battery` return up to 20 current device summaries to the approved private chat.

The Worker evaluates low/critical battery, charging-target, storage and stale conditions. Scheduled checks process four devices every five minutes in round-robin order to bound subrequests; notification latency increases with device count. Cooldown defaults to one hour. Notification attempts are marked before sending (at-most-once attempts); a network failure may lose a notification rather than duplicate it. This limitation must be resolved before claiming reliable production delivery.

## Background monitoring

Paired Android phones can enable Background monitoring. WorkManager uses unique periodic work at a 15-minute minimum with exponential retry. It can be delayed by Doze, battery optimization, manufacturer restrictions or force-stop. Reopen after force-stop. On POCO/Xiaomi, review app battery settings and allow background activity if desired. No exact reporting interval is promised and battery impact has not been measured on the POCO F7.

Foreground and background paths share the same SQLite sequence counter and bounded queue. On successful upload, the current implementation coalesces older pending readings. It preserves current status but does not backfill every offline observation. Background enable/disable and foreground races still require real-device testing.

## Limits that remain

- Raw history is capped at 256 observations and seven days; no 30/90-day hourly/daily aggregates yet.
- Alert history is capped at 100 events and 90 days. Threshold editing UI is not implemented.
- Cleanup of expired pairing, Telegram token indexes and rate-limit identities is not yet implemented. Expiry is enforced on access, but unused entries can accumulate.
- Cron reads the directory index and processes four devices per tick. Free-tier capacity/load behavior is not benchmarked.
- Account deletion/export, credential rotation, full drive histories, advanced sorting/groups and Windows installer verification are incomplete.
- Firebase CLI dev dependencies report upstream npm audit findings; gateway production dependencies reported zero at installation. CLI dependencies are not included in the Worker or Android app.
- Live sign-in, pairing, upload, Telegram delivery and rules deployment remain unverified until account settings and credentials are configured.

Do not label this milestone production-ready.
