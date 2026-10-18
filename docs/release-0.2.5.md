# Android 0.2.5 — Mini Dashboard

Revice now offers an optional, silent notification with local Android and authorized remote Android/Windows device readings. Enable it under Settings → Notifications → Mini Dashboard. It is disabled by default; enabling requests notification permission on Android 13+. Denial leaves monitoring functional and provides an Android settings shortcut.

## Behavior

- One stable notification, low-importance silent channel, monochrome Revice-style icon and lime accent. Standard collapsed/expanded Android templates preserve system accessibility and OEM styling.
- Up to four eligible devices, plus an overflow count. Favorites select remote devices; no favorites means all eligible devices. Local/remote, battery, storage, observation time, privacy and ongoing options are persisted locally.
- Battery and used-storage percentages display two decimals. Unsupported/missing values show N/A. Absolute observation times and the cached-readings label avoid falsely presenting old data as live.
- Tap opens Home; View Devices opens Devices, where existing details navigation remains available. Standard BigText rows are not individual links. No extra Refresh action was added.
- Lock-screen privacy defaults on, using a generic public notification. Android lock-screen settings ultimately control presentation.
- Dismissal stays respected across updates and process restart. Show again or re-enabling restores the notification. Disabling removes it and clears its telemetry cache.
- Foreground updates reuse monitoring/controller and Firebase listeners. The existing paired-phone background job can update local readings at its existing interval; cached remote readings are retained only for the same authenticated owner. Sign-out/account changes and observed revocation remove ineligible remote entries.
- No new network requests, polling timer, background job or foreground service. Raw telemetry, pairing, Firebase/Cloudflare protocols and Windows Agent are unchanged.

## Limitations and device checks

Remote telemetry is cached while the app is not receiving existing Firebase events. Revocation is reflected when the existing device feed receives it; the notification is not an independently live feed. Android can delay existing background work, and a force-stopped app cannot refresh until reopened. Reboot restoration occurs on the next existing monitor/app update, not through a new boot receiver.

No physical Android phone was connected for this work. POCO F7 / HyperOS rendering, the actual permission dialog, shade expansion, lock-screen appearance and physical notification taps still need device verification. OEMs may truncate expanded content or alter accent colors and ongoing-notification dismissal behavior. No battery-life measurement is claimed.

## Changed files

- `apps/android/revice_android/lib/services/mini_dashboard.dart`: safe metric payloads, preferences, permission handling, lifecycle and notification navigation.
- `lib/features/mini_dashboard_settings.dart`: Volt-themed settings and favorites.
- `lib/features/app_shell.dart`: settings entry and lifecycle/navigation wiring.
- `lib/services/background_monitoring.dart`: notification update using the existing observation.
- `lib/services/cloud_service.dart`: explicit ownership for the public device cache.
- `packages/native_monitoring/android/src/main/kotlin/app/revice/native_monitoring/MiniDashboard.kt`: notification rendering, persistence, permission bridge, intents and dismissal receiver.
- `NativeMonitoringPlugin.kt`, plugin manifest, vector icon and Gradle dependency: native registration and AndroidX notification support.
- App Gradle/test setup, `test/mini_dashboard_test.dart`, native `MiniDashboardTest.kt`, onboarding widget test and `pubspec.yaml`.

## Validation

- All 22 Flutter tests passed; `flutter analyze` reported no issues.
- All four Robolectric Android 13 native tests passed with zero failures/errors. They verify default opt-out, permission denial, one stable silent notification, percentage rendering, unsupported battery, observation times, private/public content, immutable navigation intents, favorite filtering, overflow, dismissal/restart and background owner isolation.
- Dart tests additionally cover local/remote payload validation, secret exclusion, permission/settings interaction, preference restoration, revocation/sign-out/account transitions, update deduplication and the existing background bridge. Existing Insights lifecycle and navigation regressions remain passing.
- Configured debug APK built successfully. Existing upstream Gradle/Kotlin deprecation warnings remain; no unrelated toolchain upgrade was made.

## Installation

Install `Revice-Android-0.2.5.apk` over the existing development build to retain app data and pairing. Do not uninstall first. Open Revice, go to Settings → Notifications → Mini Dashboard, enable it and allow notifications. Select device favorites and display/privacy preferences there.

Build again from `C:\dev\Revice\apps\android\revice_android` with:

```powershell
$env:JAVA_HOME = 'C:\Program Files\Android\Android Studio\jbr'
& C:\dev\flutter\bin\flutter.bat build apk --debug --dart-define-from-file=config.json
```

This remains a debug-signed development APK. Public cloud configuration is supplied by the existing ignored `config.json`; credentials are not committed.
