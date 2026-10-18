<div align="center">
  
<img width="2172" height="724" alt="9d0b0057-9601-4f39-b951-69a9075f4ec6" src="https://github.com/user-attachments/assets/de18c5c2-c39c-4b13-86fd-3ecf4dfefffe" />

# Revice.

*Android and Windows device monitoring — local readings, approved pairing, and owner-scoped cloud synchronization.*

<img src="https://img.shields.io/badge/Flutter-3.47.7-B5F36D?style=for-the-badge&logo=flutter&logoColor=B5F36D&labelColor=18181B" alt="Flutter 3.47.7" />
<img src="https://img.shields.io/badge/Windows%20Agent-0.2.1-B5F36D?style=for-the-badge&labelColor=18181B" alt="Windows Agent 0.2.1" />
<img src="https://img.shields.io/badge/Firebase-Realtime%20Database-B5F36D?style=for-the-badge&logo=firebase&logoColor=B5F36D&labelColor=18181B" alt="Firebase Realtime Database" />
<img src="https://img.shields.io/badge/Cloudflare-Gateway-B5F36D?style=for-the-badge&logo=cloudflare&logoColor=B5F36D&labelColor=18181B" alt="Cloudflare Gateway" />
<img src="https://img.shields.io/badge/Status-Development-B5F36D?style=for-the-badge&labelColor=18181B" alt="Development status" />

<br /><br />

[Release notes](docs/release-0.2.1.md) · [Local run](docs/local-run.md) · [Cloud setup](docs/cloud-setup.md) · [Windows installation](docs/windows-installation.md)

</div>

---

## What is implemented

- **Android device readings** — local battery, storage, and device collectors through a Kotlin Flutter plugin supporting foreground and headless engines.
- **Account flows** — Firebase email/password sign-in, registration, email verification, and password reset, conditional on supplied public configuration.
- **Approved pairing** — a Cloudflare gateway with verified Firebase JWTs, owner-scoped registration, approved pairing, hashed agent credentials, revocation, bounded telemetry history, and replay checks.
- **Android dashboard** — realtime device list, revocation, battery history, and alert activity.
- **Offline uploads** — secure Android credential storage and a bounded SQLite upload queue.
- **Optional background collection** — WorkManager periodic collection, enabled by the user after pairing.
- **Windows tray agent** — CPU, RAM, battery, uptime, and drive readings, pairing, configurable synchronization, per-user startup, and DPAPI-protected state.
- **Alerts & backend commands** — threshold/cooldown alerts, scheduled stale checks, Telegram owner-approved linking, a test notification, and basic commands.

*Version 0.2.1 includes Windows Agent and Android UI refinements. Windows uses a text header in the refined Volt UI; Android raster branding remains removed.*

---

## Current status

| Area | Status |
|---|---|
| Firebase project | `revice-e9d6b` configured with an Android app and email/password authentication |
| Database access | Owner-only Realtime Database rules configured |
| Android configuration | Public build configuration saved locally and excluded from the repository |
| Gateway | The locally configured gateway was used successfully by the Windows agent during 0.2.1 verification |
| Telegram | UI removed; backend remains isolated |
| Earlier APK exports | Remain unconfigured |
| Production acceptance | Incomplete; no production release is claimed |

**Implementation does not establish full live-device acceptance.** See the [release notes](docs/release-0.2.1.md) and [local run guide](docs/local-run.md) for verification and limitations.

---

## Requirements

| Requirement | Detail |
|---|---|
| Flutter | Pinned 3.47.7 at `C:\dev\flutter` |
| Android device | USB debugging enabled; current instructions target the POCO F7 |
| Android toolchain | Flutter-compatible Android SDK and build tools |
| Firebase Emulator | Android Studio's Java 21 runtime if another Java is first on `PATH` |
| Windows | .NET SDK and Windows build environment for the Windows Forms agent |
| Gateway and rules checks | Node.js and npm compatible with the included dependency lockfiles |
| Cloud features | Configured Firebase project and Cloudflare gateway |

*Working repository: `C:\dev\Revice`. Dependency lockfiles are included.*

---

## Run Android

Enable USB debugging on the POCO F7, connect it by USB, and approve the authorization prompt.

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat devices
& C:\dev\flutter\bin\flutter.bat run -d PHONE_ID
```

Replace `PHONE_ID` with the Android identifier.

For a configured cloud run, follow [cloud-setup.md](docs/cloud-setup.md), then provide the local public configuration:

```powershell
& C:\dev\flutter\bin\flutter.bat run -d PHONE_ID --dart-define-from-file=config.json
```

Append `--dart-define-from-file=config.json` to Android build commands when producing a configured cloud build. **Never put server credentials in this file.**

---

## Local verification

These commands run checks and builds; they do not establish passed live acceptance tests.

### Android

```powershell
Set-Location C:\dev\Revice\apps\android\revice_android
& C:\dev\flutter\bin\flutter.bat analyze
& C:\dev\flutter\bin\flutter.bat test
& C:\dev\flutter\bin\flutter.bat build apk --debug

# With an Android device connected:
& C:\dev\flutter\bin\flutter.bat test integration_test -d PHONE_ID
```

*Android builds emit upstream plugin Kotlin migration warnings on this SDK. A warning alone is not a failed build.*

### Cloudflare gateway

```powershell
Set-Location C:\dev\Revice\services\gateway
npm.cmd ci
npm.cmd run check
npm.cmd test
npm.cmd run build
```

### Firebase rules

```powershell
Set-Location C:\dev\Revice\firebase
npm.cmd ci
npm.cmd test
```

### Windows Agent

```powershell
Set-Location C:\dev\Revice\apps\windows-agent\Revice.Agent
dotnet build -c Release
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o ..\publish
```

---

## Builds & installation

| Artifact | Availability |
|---|---|
| Windows self-contained executable | Available in the development workspace; see the [installation guide](docs/windows-installation.md) |
| Windows installer | Source in `apps/windows-agent/Installer`; not compiled or tested |
| Previously exported Android APKs | Unconfigured; rebuild with public configuration for cloud use |

The installer compiler installation was blocked by automatic approval review, so the installer has not been compiled or tested.

---

## Security & data handling

| Area | Implementation |
|---|---|
| Gateway authentication | Verified Firebase JWTs |
| Ownership | Owner-scoped registration and approved pairing |
| Agent credentials | Hashed credentials and revocation |
| Android credentials | Secure credential storage |
| Windows state | DPAPI protection |
| Telemetry | Replay checks, bounded history, and a bounded offline queue |
| Database access | Owner-only Realtime Database rules |
| Repository configuration | Secrets and public Android build configuration remain local and excluded |

---

## Remaining acceptance work

- Live owner sign-in, second-Android pairing, Windows pairing, Telegram delivery, device revocation, and offline recovery against configured infrastructure.
- Real-phone WorkManager operation, reboot recovery, Doze behavior, and power impact.
- Native emulator testing: the existing emulator did not finish booting during the prior attempt.
- Windows installer compilation and testing.

### Known limitations

| Area | Limitation |
|---|---|
| Offline readings | Old queued readings are coalesced |
| Raw history | Capped at 256 records / seven days |
| Analytics | Advanced analytics, aggregates, and full drive charts remain incomplete |
| Management | Threshold editing, account deletion/export, rotation, and some device-management controls remain incomplete |
| Private indexes | Cleanup of expired private indexes remains incomplete |
| Telegram delivery | Attempts are at-most-once and may be lost on network failure |

See [cloud-setup.md](docs/cloud-setup.md) for setup steps and limitations.

---

## Project structure

| Path | Contents |
|---|---|
| `apps/android/revice_android/` | Flutter Android application |
| `apps/windows-agent/Revice.Agent/` | Windows Forms tray agent |
| `apps/windows-agent/Installer/` | Windows installer source |
| `services/gateway/` | Cloudflare gateway |
| `firebase/` | Firebase rules and verification tooling |
| `docs/` | Setup, release, installation, and status documentation |
| `branding/` | Preserved source artwork |

---

## Documentation

| Guide | Contents |
|---|---|
| [Release 0.2.1](docs/release-0.2.1.md) | Current changes, verification, and limitations |
| [Local run](docs/local-run.md) | Current status and exact local run commands |
| [Cloud setup](docs/cloud-setup.md) | Infrastructure setup and limitations |
| [Windows installation](docs/windows-installation.md) | Executable usage and installer status |
| [Original brief](docs/project-brief.txt) | Preserved project requirements |

---

<div align="center">

*Device readings across Android and Windows — with approved pairing and owner-scoped access.*

**Revice · Windows Agent 0.2.1 · Development build**

</div>
