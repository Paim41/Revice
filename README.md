# Revice — Android and Windows device monitoring

Windows Agent 0.2.1 and Android UI refinement. See [release notes](docs/release-0.2.1.md) for current changes, verification and limitations. Working repository: `C:\dev\Revice`. Android raster branding remains removed; Windows uses a text header in the refined Volt UI.

## Implemented

- Android local battery, storage and device collectors through a Kotlin Flutter plugin that can attach to foreground and headless engines.
- Firebase email/password sign-in, registration, email verification and reset flows, conditional on supplied public configuration.
- Cloudflare gateway with verified Firebase JWTs, owner-scoped registration, approved pairing, hashed agent credentials, revocation, bounded telemetry history and replay checks.
- Android realtime device list, revocation, battery history and alert activity.
- Secure Android credential storage and a bounded SQLite upload queue. Optional WorkManager periodic collection, enabled by the user after pairing.
- Windows Forms tray agent with CPU, RAM, battery, uptime and drive readings, pairing, configurable synchronization, per-user startup option and DPAPI state.
- Threshold/cooldown alerts, scheduled stale checks, Telegram owner-approved linking, test notification and basic commands.

Firebase project revice-e9d6b is now configured with an Android app, email/password authentication, and owner-only Realtime Database rules. Public Android configuration is saved locally. The locally configured gateway was used successfully by the Windows agent during 0.2.1 verification. Secrets and public Android build configuration remain local and are not included in the repository. Telegram UI has been removed; its backend remains isolated. Previously exported APKs remain unconfigured. See docs/local-run.md for current status and exact local run commands.

## Run Android

Enable USB debugging on the POCO F7, connect it by USB and approve the authorization prompt.

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat devices
& C:\dev\flutter\bin\flutter.bat run -d PHONE_ID
```

Replace PHONE_ID with the Android identifier. For a configured cloud build, follow `docs/cloud-setup.md`, then append `--dart-define-from-file=config.json` to run/build commands. Never put server credentials in that file.

## Local verification

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat analyze
& C:\dev\flutter\bin\flutter.bat test
& C:\dev\flutter\bin\flutter.bat build apk --debug
# With an Android device connected:
& C:\dev\flutter\bin\flutter.bat test integration_test -d PHONE_ID

Set-Location C:\dev\Revice\services\gateway
npm.cmd ci
npm.cmd run check
npm.cmd test
npm.cmd run build

Set-Location C:\dev\Revice\firebase
npm.cmd ci
npm.cmd test

Set-Location C:\dev\Revice\apps\windows-agent\Revice.Agent
dotnet build -c Release
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish
```

Use Android Studio's Java 21 runtime for Firebase Emulator if another Java is first on PATH. Flutter is pinned to 3.47.7 under `C:\dev\flutter`; dependency lockfiles are included. Android builds emit upstream plugin Kotlin migration warnings on this SDK, but a warning alone is not a failed build.

## Remaining acceptance work

Live owner sign-in, second-Android pairing, Windows pairing, Telegram delivery, device revocation and offline recovery must be tested against configured infrastructure. Real-phone WorkManager, reboot, Doze behavior and power impact are not verified. The existing emulator did not finish booting during the prior native test attempt. No production release is claimed.

The current history/queue implementation coalesces old offline readings and caps raw history at 256 records/seven days. Advanced analytics/aggregates, full drive charts, threshold editing, account deletion/export, rotation, cleanup of expired private indexes and some device-management controls remain incomplete. Telegram attempts are at-most-once and may be lost on network failure. See `docs/cloud-setup.md` for these limitations and setup steps.

Windows self-contained executable is available; installer source is in `apps/windows-agent/Installer`. The installer compiler installation was blocked by automatic approval review, so the installer has not been compiled or tested. See `docs/windows-installation.md`.

Original brief and source artwork remain preserved under `docs/project-brief.txt` and `branding/`.


