# Android 0.2.4 — Insights subscription lifecycle repair

## Root cause

The shared Insights/Activity `DeviceHistory` built an `onValue` stream in its build method and passed it to a child `StreamBuilder` inside an `ExpansionTile`. By default, collapsing the tile removes/disposes its children. Re-expanding can mount a new StreamBuilder with the same stream object retained by the tile's child configuration. The installed Firebase Database method-channel `observe` implementation is an `async*` single-subscription stream. Listening again after cancellation therefore throws `Bad state: Stream has already been listened to`. Parent/cloud rebuilds could create another stream and temporarily mask the problem.

## Fix

Each `DeviceHistoryCard` owns one lazy subscription, started on first expansion. Collapsing retains the subscription and latest data for the life of the card on that page. Repeated expansion and cloud/local refresh rebuilds do not reconnect. Stable owner/device/feed keys prevent state from moving between cards or accounts. Disposal cancels the listener; returning to the page creates a fresh stream. Explicit Retry cancels the previous subscription before creating a replacement, with generation guards ignoring obsolete callbacks. No auto-refresh timer or blanket broadcast conversion was added.

Loading, empty, recoverable Firebase errors, malformed records and disconnected streams have compact themed feedback. Recoverable errors retain previously loaded readings; programming errors still reach Flutter diagnostics. Snapshot parsing validates dates and battery values, orders by actual timestamps and bounds rendered history. The existing battery chart was moved without changing its rendering. Storage history was not previously implemented and has not been invented. Pairing, monitoring, Firebase schema, gateway and Windows code are unchanged.

## Files

- `apps/android/revice_android/lib/features/history_screen.dart`: keyed card list.
- `lib/features/device_history_card.dart`: owned subscription, cached state, validation and retry.
- `lib/features/battery_chart.dart`: extracted existing chart.
- `test/history_subscription_test.dart`: single-subscription regression feeds and lifecycle checks.
- `pubspec.yaml`: Android version 0.2.4+6.

## Validation

All 18 Flutter tests passed; analyze reported no issues. Regression coverage includes repeated/rapid collapse and expansion, Android and Windows cards together, updates while open/collapsed, parent/manual-refresh rebuilds, reordering, page removal and return, account/feed isolation, empty history/activity, Firebase error and Retry, malformed records, ordering and cancellation/disposal. A read-only authenticated Firebase check fetched four history/activity feeds containing 45 records; no data was changed. Physical Android interaction and the native Firebase event-channel lifecycle have not been exercised on a connected phone in this run.

Configured debug APK build passed. Existing upstream Kotlin Gradle compatibility warnings remain. Output: `C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Android-0.2.4.apk`. Earlier APKs/Windows EXEs remain untouched. Install this APK over the previous development build, preserving its app data.
