# Android 0.2.6 — device aliases and dashboard formatting

## Changes

Devices now has a pencil action opening a themed Rename Device dialog. It pre-fills the existing name, trims surrounding whitespace, preserves capitalization and Unicode, rejects empty/control-character names and limits aliases to 40 Unicode code points. Save waits for gateway success; network failures keep the dialog open with a retry message. Register This Phone and owner approval of a joining Android/Windows device also offer this naming dialog.

The existing registered `public.name` remains authoritative. The owner-authenticated gateway updates that metadata atomically under the authenticated UID. No migration, new identity, credential change or history reset occurs. Telemetry already preserves metadata; repeated enrollment and approval do not overwrite later aliases. Windows Agent's local name remains its pairing suggestion and does not overwrite the dashboard alias after approval. Windows source code is unchanged.

Existing Firebase listeners update Home, Devices, Insights, Activity, favorites and notifications. Local cards use the registered alias while retaining the hardware Model separately in details. Open detail sheets also listen for updates. Background notification refresh retains the same owner's cached local alias; sign-out clears owner-only names from the notification.

Home/shared device cards and Mini Dashboard use Windows/Android capitalization, selective Title Case, ` | ` metadata separators and local observation dates. Battery percentages round to whole numbers; storage percentages use at most one decimal with no trailing zero. Unavailable/invalid metrics show N/A. These are display-only changes; raw telemetry is unchanged. Other detailed metric displays keep their existing precision.

Notifications retain the stable ID, channel, permissions, privacy, favorites, dismissal and safe navigation actions. Observation time has its own expanded line and cached-readings wording remains. No new timers, network polling or background services were added.

## Validation

- Flutter analysis reported no issues. Configured APK build and APK signature verification passed (version 0.2.6, build 8).
- 26 Flutter tests passed, including name validation, trimming, Unicode/case preservation, network failure/retry, local alias payloads, compact formatting and existing Insights/navigation regressions.
- 15 gateway tests passed. Tests cover Android/Windows aliases surviving telemetry/enrollment, stable credentials/IDs/history, cross-owner rejection and naming during owner approval without retry overwrite.
- Four native Android notification tests passed under Robolectric, including revised formatting, permissions/privacy, stable notification updates, navigation and dismissal/account isolation.
- Gateway TypeScript check and deployment dry run passed. Deployed worker version: `233467fd-9d42-4b99-a511-d3d34617cd4d`; live health endpoint responded successfully.
- No physical device was attached. Real POCO F7/HyperOS wrapping, permission dialogs, physical restart and live end-to-end renaming were not exercised. No real user's devices were renamed or reset for testing. Native notification line limits remain OEM-controlled.

## Files

- Android `lib/core/formatters.dart`: compact percentages, platform labels, local times and name validation.
- `lib/features/device_name_dialog.dart`, `cloud_screen.dart`: rename, registration and approval UI.
- `lib/features/app_shell.dart`, `device_overview.dart`: local/remote aliases, metadata and live details.
- `lib/services/cloud_service.dart`, `mini_dashboard.dart`: secure update request and alias propagation.
- Native `packages/native_monitoring/android/src/main/kotlin/app/revice/native_monitoring/MiniDashboard.kt`: notification text and cached local alias preservation.
- Gateway `src/contracts.ts`, `src/api.ts`: validated aliases and optional approval name.
- Gateway API tests, Android formatting/dialog/overview/notification tests, and `pubspec.yaml` version 0.2.6+8.

## Install

APK: `C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Android-0.2.6.apk`.

Install over the existing development build without uninstalling to retain pairing and settings. This follows the existing debug-signed APK workflow. Earlier APKs and Windows executables remain untouched.

Rename: Devices → pencil beside a registered device → edit → Save. New phones: Account & pairing → Register this phone → choose name → Save. New remote devices: create pairing code and review request as before, then Approve this device → choose name → Save.

Build from `C:\dev\Revice\apps\android\revice_android`:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& C:\dev\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=config.json
```

The existing ignored `config.json` supplies public cloud configuration. Upstream Kotlin/Gradle deprecation warnings remain; no unrelated toolchain upgrade was made.
