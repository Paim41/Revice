# iOS Agent 0.1.0 / Android compatibility 0.2.7

Implemented on 20 October 2026 in the existing Revice monorepo, branch `main`.

## Implementation

Native SwiftUI iPhone agent (iOS 17 minimum): official branding, Volt AMOLED welcome/pairing/Home/settings/credits, documented battery APIs, local storage display, owner-approved pairing, Keychain credentials, manual and foreground battery sync, bounded persistent queue, cancellation/retry/revocation handling, owner-name retrieval and optional best-effort background refresh.

No iPhone disk values are sent off-device. The local storage model is not serializable. Cloud readings contain `storage: null`; the gateway enforces a strict iOS battery-only schema. The privacy manifest declares Disk Space display reason 85F4.1. LAN storage sharing is deferred pending physical-device validation and separate consent.

The existing gateway now supports platform `ios`, enrollment identity issuance, credential-scoped status/unpair and charging activity. Android recognizes iOS in overview cards and notification summaries and explicitly labels storage as iPhone-only. Existing Android/Windows protocols, owner aliases, Firebase storage and pairing remain in place. No existing devices/history were reset.

## Files

New source: `apps/ios-agent/` (App, Views, ViewModels, Models, Services, Security, Resources, Tests, UITests and reproducible XcodeGen configuration).

New workflow: `.github/workflows/ios-agent.yml`. Installation/privacy guide: `docs/ios-agent/README.md`.

Existing modified areas: gateway `src/api.ts`, `src/contracts.ts`, `src/alerts.ts`, API tests; shared telemetry JSON schema; Android platform formatting, device overview, mini-dashboard serialization and tests; native mini-dashboard rendering/test; Android package version; root ignore rules.

## Verified local results

- Gateway: 16 tests passed; TypeScript check and Wrangler dry-run passed.
- Deployed gateway version: `dcddd126-60a1-44e8-b5a0-b5e996c135c7`. Live health endpoint responded successfully.
- Android: 28 Flutter tests, 5 native notification tests passed; analyzer reported no issues.
- Configured Android debug APK built; signature verification passed (v2).
- APK package: `app.revice.revice_android`, version `0.2.7`, version code `9`.
- Output: `C:\Users\fahim\Documents\Codex\2026-10-16\loca\outputs\Revice-Android-0.2.7.apk`.
- SHA256: `583ee147225dc799f5b4505f17ee9f9e89cfccec6b3115e372cae741f78435b9`.
- Prior APKs and Windows executables preserved. No Windows source changes required.

## Installation and remaining validation

There is no signed iPhone IPA or TestFlight release. Windows cannot run Xcode. Use the installation guide for temporary Mac + Xcode Personal Team provisioning, or Apple Developer Program signing and TestFlight. Signing credentials have not been supplied or committed.

On a Mac: clone, install XcodeGen 2.46.0, run `cd apps/ios-agent && bash generate.sh`, open `ReviceAgent.xcodeproj`, select your signing team and connected iPhone, then Run. Generate a code in Android Account & pairing, request pairing on iPhone, approve in Android, then Check Approval on iPhone.

Real battery/storage readings, lock/unlock Keychain behavior, Android/iPhone pairing over the live network, OS background execution, small-screen layout and energy impact still need physical-device testing. Background refresh has no guaranteed interval. Automated tests use injected test doubles, not production mock telemetry.

## macOS simulator evidence

Run [39355421627](https://github.com/Paim41/Revice/actions/runs/39355421627), source `d6d345852e6c1c989bb71b5f0699e37a3228d0b7`, succeeded with Xcode 16.4 on macos-15: 10 unit tests and 1 UI navigation test passed, zero failures. The simulator welcome screenshot was downloaded and visually inspected. Unavailable simulator battery correctly renders N/A/Unknown; displayed disk capacity belongs to the simulator environment, not a physical iPhone.

Visual review led to a follow-up primary-button contrast fix in commit `c323c5b` (dark text on lime). The final rerun also passed, as recorded below. Simulator results and screenshot from the earlier passing run are preserved in `outputs/ios-validation-39355421627`.

Final run [39381310888](https://github.com/Paim41/Revice/actions/runs/39381310888) on commit `c323c5b` succeeded: Xcode 16.4, 10 unit tests and 1 UI test, zero failures. The final simulator screenshot was visually checked and confirms dark, readable text on the lime primary button. Logs, xcresult and screenshot are saved in `outputs/ios-validation-39381310888`. Source and documentation are published on `main` at https://github.com/Paim41/Revice.
