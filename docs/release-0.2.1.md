# Revice 0.2.1 UI refinement and Windows lifecycle update

## Android

- Shared 12 logical-pixel spacing separates registered-device cards and expandable Activity/Insights cards.
- Lime selected navigation icons and labels contrast with a dark green active pill.
- Home retains local battery, charging, storage, observation time and details, then lists other registered Android and Windows devices from the existing realtime subscriptions.
- Remote cards include platform, battery/charging when supported, storage usage/capacity, observation time and Recent/Stale state. Missing readings remain unavailable. Tap a card for details.
- All percentage labels use two decimal places; raw readings and uploaded values are unchanged.
- Removed the visible Telegram panel and its unused Dart widget. Isolated gateway Telegram support is retained.
- Account & pairing separates phone monitoring from account actions. Already registered phones cannot accidentally repeat enrollment from the registration button.

## Windows

The existing .NET WinForms agent now uses reusable Volt cards and metric controls, a two-column layout, real progress indicators, bounded/filterable event log, readable system-font fallback and accessible explicit Exit button. No raster header logo was reintroduced, preserving the earlier request to remove black-background branding images.

Exit stops the timer, cancels pending HTTP work, waits for the active operation to finish, disposes the tray/service and releases the named mutex. A second launch signals the running instance to show its window; an abandoned mutex is handled.

Windows login startup uses the current user's Run entry, with a quoted executable path and --startup argument. Startup defaults on for this requested behavior; an explicit toggle choice is persisted separately under HKCU\Software\Revice. Each launch refreshes the path when startup is enabled. Startup launches into the tray while monitoring continues. Keep the final EXE in its output location. No elevation or terminal is required to launch it.

The DPAPI agent.dat schema, credential location, pairing endpoints, collectors and queue logic are preserved. Only cancellation support was added to AgentService. Collector version metadata is 0.2.1.

## Outputs

- C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Agent-0.2.1.exe
- C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Android-UI-refinement.apk

The Windows EXE is a fresh self-contained Windows x64 publish, file version 0.2.1.0. Earlier executables remain untouched. Android APK is a configured debug build, using local git-ignored Firebase/gateway configuration.

## Verification

- Windows build and self-contained publish: passed, no compilation warnings/errors.
- Final EXE launch, explicit Exit, process termination, relaunch with --startup, hidden startup window, second launch reopening the same process: passed.
- Existing saved credential, owner UID, device ID, gateway, device name and interval: compared via an in-memory fingerprint before and after testing; unchanged. No secrets were printed or committed.
- Existing live pairing loaded and live gateway synchronization succeeded. A later request timed out and correctly retained the queued reading; network delivery is not guaranteed.
- Windows isolated self-test: actual RAM/drive collection and DPAPI save/reload passed.
- Android analysis, existing eight tests, and three new overview/navigation tests: passed. Configured debug APK build passed.
- Gateway TypeScript check and 13 tests: passed; backend integration code was preserved.
- Windows UI inspected on this desktop; nested card scrollbars/clipping found in the first implementation were corrected before publishing.

## Limits

A full Windows reboot/login was not performed; startup registry and --startup execution were verified. 125%/150% display scaling and all narrow-window layouts still need manual acceptance testing. Android changes were verified by widget tests/build, not installed on a physical phone in this run. Windows is unsigned; Android uses the development signing key. Full new-device pairing and unpairing were not exercised against the live account because that would alter the existing pairing.

## Principal changed files

Android: lib/core/theme.dart, lib/core/formatters.dart, lib/models/local_snapshot.dart, lib/features/app_shell.dart, cloud_screen.dart, history_screen.dart, new device_overview.dart, removed telegram_panel.dart, and formatting/overview/widget tests.

Windows: Program.cs, SingleInstance.cs, UI/AgentForm.cs, UI/Volt.cs, Services/StartupSettings.cs, Services/AgentService.cs, Collectors/SystemCollector.cs, and Revice.Agent.csproj.

## Build again

```powershell
Set-Location C:\dev\Revice\apps\windows-agent\Revice.Agent
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish-021

Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=config.json
```
