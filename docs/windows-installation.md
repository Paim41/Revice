# Windows preview

`Revice.Agent.exe` is a self-contained Windows x64 .NET 10 application. It does not require an extra .NET runtime installation. Copy it to a permanent user-owned folder and run it.

It reads CPU (after two samples), RAM, battery if present, uptime and fixed-drive capacities. The system-drive summary is synchronized; all drive capacities are shown locally. No administrator privileges are needed.

Enter the deployed HTTPS gateway origin and device name, save settings, then request pairing using the six-digit owner code. Approve on Android and click Check approval on Windows. Default sync interval is 60 seconds. Check Start with Windows only if desired; it adds an HKCU Run entry pointing to this executable's current location.

When paired, closing the window hides it in the tray. Use tray Exit to stop monitoring. A sleeping computer does not report; the next scheduled timer after resume reads fresh metrics. State and queued readings live in `%LOCALAPPDATA%\Revice\agent.dat`, protected with DPAPI for the current Windows user. Moving the state to another Windows account will not decrypt it.

The local smoke test verified real RAM/drive reads and DPAPI save/restore. Live pairing, offline retry and sleep/resume behavior need further integration testing. The executable is unsigned.

An Inno Setup script is provided in `apps/windows-agent/Installer/Revice.iss`. The compiler installation was blocked by automatic approval review, so no compiled installer or installer validation is claimed. After installing Inno Setup yourself, compile the script with its ISCC tool. The installer is per-user, offers uninstall, and does not enable startup automatically.
