# Local foundation

Flutter widgets -> MonitoringController (ChangeNotifier) -> MethodChannel -> Kotlin DeviceCollector -> Android public APIs.

The controller handles loading and failure state independently of widgets. The typed model validates battery bounds and storage consistency. Native collection reads ACTION_BATTERY_CHANGED and StatFs for the data filesystem. Missing fields remain null; a storage-source failure does not invent capacity. Existing readings remain visible on refresh failure with a visible error.

The controller is owned by the app. Foreground refresh scheduling is owned by the shell and suspended outside resumed lifecycle state. It is not a background sync scheduler. Preferences are two nonsensitive booleans in private SharedPreferences. Credentials must use Keystore-backed storage when authentication is introduced.

No unnecessary third-party runtime dependency is needed for this slice. ChangeNotifier is the state management boundary; Firebase repositories and durable SQLite storage will be added when there is actual cloud/history behavior to persist. System fonts are the current fallback; bundled licensed Space Grotesk/Inter typography remains a refinement.

Official references:
- https://docs.flutter.dev/install/manual
- https://docs.flutter.dev/platform-integration/android/setup
- https://developer.android.com/reference/android/os/BatteryManager
- https://developer.android.com/reference/android/os/StatFs
