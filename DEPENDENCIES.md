# Third-party dependencies

The bridge downloads these tools from their official upstream sources into `%LOCALAPPDATA%\AirPad\dependencies`:

| Component | Pinned version | Source | Purpose | License / notes |
|---|---:|---|---|---|
| Android SDK Platform-Tools | 37.0.3 | [Google download](https://dl.google.com/android/repository/platform-tools_r37.0.3-win.zip) | ADB discovery and connection | Google Android SDK Platform-Tools license; upstream page does not publish a pinned SHA-256 archive checksum. |
| scrcpy | 5.0.1 | [Genymobile release](https://github.com/Genymobile/scrcpy/releases/tag/v5.0.1) | Controller forwarding through ADB UHID | Apache-2.0; Windows x64 archive SHA-256 is pinned in `config/dependencies.json`. |
| HidHide | 1.5.230.0 | [Nefarius release](https://github.com/nefarius/HidHide/releases/tag/v1.5.230.0) | Hide selected gamepad from other Windows applications | GPL-3.0; signed driver installer, administrator approval required and reboot may be needed. |

Dependency versions are intentionally pinned. Review upstream release notes, license changes and published hashes before updating `config/dependencies.json`. The app checks the scrcpy archive hash and rejects unsafe ZIP paths. Platform-Tools has no published SHA-256 checksum in the maintained source used here, so the app warns and relies on HTTPS. HidHide is installed only after the user explicitly confirms and Windows shows an elevation prompt; a valid Authenticode signature is required.

The project does not bundle or redistribute these binaries. The downloaded files remain outside the repository.
