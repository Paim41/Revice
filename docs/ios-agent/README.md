# Revice iOS Agent

Native SwiftUI agent for iPhone, minimum iOS 17.0, app version 0.1.0 (1). The owner dashboard remains Revice Android. Source is in `apps/ios-agent`; no Apple account secrets or Firebase SDK are included. Windows Agent is unchanged.

## Integration and implementation

The existing gateway uses temporary six-digit owner-created codes, agent join/status requests, explicit owner approval, HMAC-hashed credentials, stable IDs, monotonic sequence IDs and server receipt times. Existing Android/Windows pairing is preserved. iOS obtains a random enrollment-specific ID and 256-bit credential from `/v1/ios/identity`, stores it in Keychain before joining, then uses the same owner-approved pairing flow. Issuance alone grants no device access.

New authenticated agent endpoints `/v1/agent/status` and `/v1/agent/unpair` allow only the credential's own device metadata and revocation. They cannot rename devices or access another device. Owner naming stays in Android. Agent status retrieves the owner's latest alias during sync. No direct Firebase access is needed.

Registered `ios` devices are validated against a strict battery-only subtype on the server. Cloud requests carry `storage: null` solely to satisfy the existing v1 contract; raw/derived disk capacity, system metrics, extra battery fields and unknown properties are rejected. Ordinary telemetry cannot overwrite an owner alias. Existing battery/stale alerts apply; iOS battery-state changes add activity records. Stale means old observations, not powered off.

## Source map

- `App/`: SwiftUI entry point, lifecycle and BGAppRefreshTask registration.
- `Views/`: Volt AMOLED welcome, pairing, local Home, settings and credits.
- `Models/Telemetry.swift`: cloud-only typed battery payload, local-only non-Codable storage model, bounded queue and validation.
- `Services/`: public Apple battery/storage collectors, HTTPS client and protected atomic queue persistence.
- `Security/`: ThisDeviceOnly Keychain credential abstraction.
- `ViewModels/`: pairing/sync/recovery orchestration and status.
- `Resources/`: official existing Revice branding, Info.plist and privacy manifest.
- `Tests/`: battery/null serialization, privacy boundary, queue limits/persistence, pairing, timeout/retry/revocation/cancellation tests.
- `project.yml`, `generate.sh`: reproducible XcodeGen 2.46.0 project and icon packaging.
- `.github/workflows/ios-agent.yml`: macOS simulator compile/test pipeline and log artifacts.

Existing modified areas: gateway contracts/API/alerts/tests, generated shared telemetry schema, Android platform helpers/cards/notification payload and native notification label, Android regression tests and version 0.2.7+9. No data migration or Windows rebuild is needed.

## Operating behavior

Foreground activation reads battery and local storage and, if opted in, attempts battery sync. Battery events update local display and trigger throttled sync opportunities while active; no periodic foreground loop is added. Manual sync is available when paired. The queue is capped at 32 recent battery-only observations and expires observations older than six days. It never stores the agent credential. Each opportunity uploads one queued reading; subsequent opportunities retry transient errors. Success time changes only after an accepted gateway acknowledgement. Duplicate retries retain the same sequence/payload. Queue identity is bound to enrollment; Keychain survival after app-file loss is handled using the server sequence.

Background refresh is off by default. Enabling requests BGAppRefreshTask opportunities; the earliest eligibility is not an interval guarantee. Tasks reschedule, cancel network operations on expiration and report actual completion. iOS may delay or never execute a request, especially after force-quit. Background execution collects battery only, never disk space. Low Power Mode/background settings can limit opportunities. No audio, location, VoIP, foreground service or push entitlement is used.

Unpair normally revokes the credential server-side before local deletion. If offline, the app retains the credential and reports failure. Explicit Forget Local Pairing Only clears local data and warns that the owner must revoke on Android. Old server history is not deleted.

## Privacy and security

Disk capacity uses Foundation `volumeTotalCapacityKey` and `volumeAvailableCapacityKey` for local display only, under reason **85F4.1**. Estimated used capacity is total minus free capacity on the app volume; it can differ from iPhone Settings. The storage model is not serializable, is not queued, and is never passed to the gateway. Android and notification cards show iPhone-only storage instead of fabricated values, even if a malformed cached record contains disk fields.

The manifest declares no tracking and app-functionality collection of an enrollment device identifier, owner identifier and battery/related device data. App Store privacy answers must be reviewed against the deployed backend and retention policies before distribution. This is not a guarantee of App Review approval. No UserDefaults, file timestamp, uptime, private battery-health or fingerprinting APIs are used. Queue files are excluded from backup and use protected atomic writes; secrets use `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`. Logs contain fixed operational messages, not tokens, payloads or names. HTTPS only; URL redirects are refused to avoid forwarding credentials.

LAN storage sharing is deliberately **not implemented** in this release. It requires a separately tested same-owner, explicitly consented, encrypted local session with no Internet relay. No LAN permissions or listening sockets are declared. It must not be enabled until the core agent is tested on real devices.

Apple references checked during implementation:
- [Required-reason API categories and 85F4.1](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype)
- [Background task execution and expiration](https://developer.apple.com/documentation/backgroundtasks/refreshing-and-maintaining-your-app-using-background-tasks)
- [Personal Team provisioning](https://developer.apple.com/help/account/basics/about-your-developer-account)
- [TestFlight](https://developer.apple.com/testflight/)

## Build and installation

Windows can edit the source and run gateway/Android tests but cannot build Apple frameworks. GitHub Actions uses `macos-15`, the runner's stable `/Applications/Xcode.app`, and XcodeGen pinned to 2.46.0. It records the actual Xcode version, selects an available iPhone simulator, builds/tests without signing, and uploads logs/results. The generated project has no Swift package dependencies; XcodeGen's build dependencies are only generation tools. An unsigned simulator build is **not an installable iPhone IPA**.

### Temporary Mac / Personal Team

1. Clone the repository on a Mac with stable Xcode and its iOS platform installed.
2. Install/build XcodeGen **2.46.0**. Run `cd apps/ios-agent && bash generate.sh`.
3. Open `ReviceAgent.xcodeproj`, choose ReviceAgent, and set your Apple development team and a unique bundle identifier under Signing & Capabilities. Keep the background task identifier consistent with Info.plist/source.
4. Connect the iPhone, trust the Mac, and enable Developer Mode if required.
5. Select the phone destination and run from Xcode. A free Personal Team may support personal device testing, but provisioning expires and requires periodic rebuild/reinstallation; do not treat it as permanent distribution.
6. On Android generate a pairing code in Account & pairing, enter it on iPhone, approve with the desired name on Android, then Check Approval on iPhone.
7. Confirm real battery, local disk display, cloud battery-only history, rename retrieval, offline recovery and revocation. Test small-screen layout, lock/unlock, force-quit and background behavior separately.

### TestFlight

Requires Apple Developer Program membership and authorized App Store Connect/signing access. On macOS configure distribution signing and the app record, select an iOS device/archive destination, Product → Archive, validate and upload through Organizer. Complete export compliance/privacy details and TestFlight beta information, invite testers, and install through TestFlight. External testing may require beta review. Builds have limited availability and need replacement (Apple currently documents up to 90 days). Do not commit certificates, provisioning profiles or private keys; use protected CI secrets if a signed pipeline is later added.

Without suitable signing/build access, iPhone installation remains blocked. No signed IPA or TestFlight deployment is produced by this unsigned workflow. The Android APK cannot run on iPhone.

## Physical-device acceptance still required

Actual iPhone collectors, secure lock/unlock behavior, OS background scheduling, power impact, UI on small screens, Android-to-iPhone owner approval and real network recovery require device verification. Simulator unit tests use explicit injected test doubles and are not evidence of real hardware monitoring. Source contains no production mock telemetry. LAN sharing and signed distribution remain follow-up stages.
