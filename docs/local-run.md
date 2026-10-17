# Revice local run and Firebase status

Verified 17 October 2026. Source: C:\dev\Revice. Existing features were preserved.

## Firebase configured

- Existing project: revice-e9d6b (Revice).
- Android package: app.revice.revice_android.
- Android Firebase app: 1:394433938810:android:6c425dc293435e655d42c3.
- Realtime Database: https://revice-e9d6b-default-rtdb.asia-southeast1.firebasedatabase.app
- Email/password enabled and verified through the management API.
- Existing owner-only database rules deployed; live rules match local rules exactly. Anonymous reads return HTTP 401.
- Cloud billing is disabled.
- Android public configuration is stored in apps/android/revice_android/config.json (git-ignored). Gateway Firebase variables are in services/gateway/wrangler.jsonc.

## Run Windows application

Open PowerShell:

```powershell
Set-Location C:\dev\Revice\apps\windows-agent\Revice.Agent
dotnet run -c Release
```

A running instance is reused; if no new window appears, look for Device Agent or its tray icon. The Windows application is native, not a browser page.

## Run local gateway

In a separate PowerShell window:

```powershell
Set-Location C:\dev\Revice\services\gateway
npm.cmd run dev -- --ip 127.0.0.1 --port 8787
```

Open http://127.0.0.1:8787/health in a browser. This is a JSON health endpoint, not the Revice dashboard. It was verified to return service revice-gateway, version 0.2.0. Stop the server with Ctrl+C before starting another instance on the same port.

## Run Android

Connect an Android phone with USB debugging enabled and approve the computer on the phone:

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat devices
& C:\dev\flutter\bin\flutter.bat run -d PHONE_ID --dart-define-from-file=config.json
```

Replace PHONE_ID with the identifier printed by devices. No Android phone or running emulator was available during this verification.

## Remaining cloud connection

CLOUDFLARE_GATEWAY_URL is intentionally empty until a real HTTPS gateway is deployed. The gateway also needs FIREBASE_SERVICE_ACCOUNT_JSON and AGENT_TOKEN_HASH_KEY as server-only secrets. Do not put them in Android config.json or source control. The Android cloud screen remains disabled until its required gateway configuration is complete; local monitoring remains available. A successful /health response does not verify cloud pairing or database writes. See docs/cloud-setup.md for gateway provisioning.

## Dependency verification

Flutter dependencies restored; analyze clean; all 7 tests pass. Gateway direct dependencies present; TypeScript check and all 13 tests pass. Firebase direct dependencies present; database security emulator test passes. .NET restore/build succeeds with zero warnings and errors. Newer incompatible Flutter releases were not forced into this project. One extraneous Firebase CLI dependency was left untouched because it does not block operation.
