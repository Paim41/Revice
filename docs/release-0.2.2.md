# Revice 0.2.2 — compact desktop, credits and floating navigation

## Changes

Windows uses a fixed 1100×740 logical-pixel client area, centered and clamped to the working screen. Content-sized cards, compact metric rows and a bounded internally scrolling log replace the oversized layout. Column scrolling remains available when the working area cannot fit the content. About & Credits is a separate dialog with the official icon, actual assembly version and external GitHub profile link. Two-decimal percentages, raw collectors, startup preference, tray, single-instance signaling and explicit Exit remain intact.

Android adds Settings → Developer Credits with the official icon, Paim41 profile, installed version/build metadata and external URL launching with failure feedback. A reusable ReviceFloatingNavigationBar retains all five destinations, with 16dp side margins, a 14dp gap above the safe area, 26dp corners, lime selection and 220ms transitions. It respects reduced motion and hides for the keyboard. Scaffold reserves its space, keeping page content reachable. Existing Home device overview, card spacing and simplified Account & pairing remain intact; Telegram UI remains removed, with isolated backend support retained.

No Firebase/Cloudflare APIs or monitoring calculations were changed. No new dependencies were introduced.

## Artifacts

- `C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Agent-0.2.2.exe` — self-contained Windows x64 WinExe, file version 0.2.2.0; double-click to launch.
- `C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Android-0.2.2.apk` — configured development APK, version 0.2.2+4.

Earlier release executables remain untouched; the 0.2.1 SHA-256 still matches its previous release fingerprint.

SHA-256:

```text
Windows: 0A0BF2573CB6CE26CEE1B0B8B4E56A53162FFB153A9B6AE63D583E99417F6F2E
Android: B0E3EAA03ABE737D2332F3C3264CC3EAADEAC06098BE2BE858EE5E304EB4B097
```

## Verification and limits

- Windows release publish passed. Actual RAM/drive collection and DPAPI persistence self-test passed; raw battery floating-point values remain unchanged while display rounds to two decimals.
- Real Windows UI inspected on this desktop: all main sections visible without scrolling, real metric updates, About dialog opens/closes and GitHub opens in the browser. Launch, explicit Exit, termination and relaunch verified. `--startup` produced a hidden window; launching again reopened the same process. Startup registry targets the final output EXE.
- Flutter tests cover percentages, local readings, remote Android/Windows overview, all five tabs, credits navigation/back, installed metadata and browser fallback, safe areas, small-screen large-text layout, keyboard and reduced motion.
- Configured Android APK build passed. Upstream Kotlin Gradle/SDK XML compatibility warnings remain.
- Physical POCO F7, actual Android gesture/three-button navigation and Windows 125%/150% scaling were not tested. Full Windows reboot/login was not performed. Windows is unsigned; Android uses development signing.
- Fresh cloud pairing/sync was deliberately not performed after the requested reset; reconnect with the account to resume uploads.

## User-requested device reset

After explicit confirmation to delete all devices and history/activity, removed 3 device records, 129 history readings, 18 alerts and 6 pairing sessions. Verified devices, directory and pairing requests empty. Firebase Authentication accounts and service configuration were retained. Windows local pairing/queued readings were cleared, preserving gateway, device name and interval. On Android, use Unpair this phone to clear the old local credential, then register again. The workstation cannot clear phone-local data without a connected device.

## Main source files

- Windows: `UI/AgentForm.cs`, `UI/Volt.cs`, `UI/AboutDialog.cs`, `Collectors/SystemCollector.cs`, `Revice.Agent.csproj`.
- Android: `lib/features/app_shell.dart`, `developer_credits.dart`, `floating_navigation_bar.dart`, `pubspec.yaml`, credits/navigation/widget tests.
- Native Android: `packages/native_monitoring/android/src/main/kotlin/app/revice/native_monitoring/NativeMonitoringPlugin.kt` (metadata and external profile opening only).

## Build again

```powershell
Set-Location C:\dev\Revice\apps\windows-agent\Revice.Agent
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish-022

Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat test
& C:\dev\flutter\bin\flutter.bat analyze
& C:\dev\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=config.json
```
