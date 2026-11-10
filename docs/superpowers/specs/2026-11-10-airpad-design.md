# AirPad — AirPad — Android TV controller bridge Design

**Date:** 2026-11-10  
**Status:** Approved architecture; implementation underway

## Goal

Provide a PowerShell-native Windows console app that forwards a controller already connected to the PC over Bluetooth or its wireless USB receiver to an Android TV / TV box over the local network. The controller and its receiver stay at the PC; the TV does not need Bluetooth, and the controller is not a wired USB gamepad.

While forwarding is active, ordinary Windows apps must not receive input from the selected controller. When the session stops, restore normal controller visibility on the PC.

## Non-goals

- A graphical Windows application or a permanent background service.
- Pairing a controller to the TV or requiring a TV-side controller receiver.
- Automatically enabling or pairing ADB on a TV.
- Wired USB gamepad support in v1.
- Guaranteeing support for every proprietary/unknown controller. The compatibility target is devices Windows recognizes as game controllers; unusual layouts may need mappings.
- Supporting every Android TV vendor/firmware combination without an ADB and UHID compatibility check.

## User and device prerequisites

- Windows 10/11 with PowerShell available.
- A Bluetooth controller paired with Windows or a wireless controller receiver connected to the PC.
- ADB debugging enabled on the TV and ADB reachable over the same LAN. The PC must already be authorized by the TV when the ADB implementation requires authorization.
- The TV and PC are on the same local network; client isolation/firewall rules may prevent discovery.
- The first-time setup may download Android Platform Tools, scrcpy and the HidHide controller-filter driver from their official upstream release sources. Installing/configuring HidHide requires administrator approval.

“USB debugging” on the TV does not guarantee that the TV exposes ADB over Wi-Fi. The app must not claim it can enable ADB remotely. If it cannot find a reachable/authorized ADB endpoint, it gives concise TV-side setup instructions and remains safe (no input is hidden).

## Recommended architecture

A PowerShell 5.1-compatible console program orchestrates maintained third-party tools rather than implementing Android input injection itself:

1. **PowerShell CLI:** interactive menu/status, local dependency bootstrap, ADB discovery, selection, confirmation, session lifetime and cleanup.
2. **ADB Platform Tools:** list already connected devices and discover/connect reachable network ADB endpoints. Restrict discovery to the local subnet and ADB-advertised services; never scan the public internet.
3. **scrcpy:** use its gamepad UHID forwarding mode over ADB (no screen mirroring required in the normal session). Android receives a virtual HID gamepad, not a Bluetooth pairing.
4. **HidHide:** hide selected physical controller device(s) from ordinary Windows applications while allowing the scrcpy process to read them. Restore the prior visibility state on normal stop. Setup must be explicit and elevated; do not silently install a kernel driver.

A custom Android companion app is rejected for v1 because non-privileged Android apps cannot reliably inject gamepad input into arbitrary games. A custom Windows HID driver/protocol is also rejected because it is a substantially larger signing and maintenance burden.

## User flow

1. User launches the downloaded/cloned project from PowerShell.
2. The app checks prerequisites and offers to download pinned dependency versions from upstream sources. Driver installation/configuration is called out and separately approved through Windows elevation.
3. The app displays a short reminder to enable ADB / wireless ADB on the TV, then scans for ADB-reachable Android devices on the LAN. It does not attempt wireless pairing or enable TV settings.
4. The user selects a discovered device and confirms the connection.
5. Before hiding input, the app validates the ADB target, scrcpy UHID support and controller presence. It records the original controller visibility/configuration for recovery.
6. The app enables HidHide isolation before launching scrcpy, so no controller input reaches Windows apps during the forwarding startup window. After scrcpy starts successfully, it prints a clear “connected / controller captured” status and keeps the console interactive.
7. On the user’s stop command, scrcpy is stopped and the original controller visibility is restored. On errors, the same cleanup path runs.

## Error handling and recovery

- No ADB TV found: display actionable TV steps (enable Developer Options/ADB or Wireless debugging as supported by that TV, authorize the PC if prompted, ensure same Wi-Fi, avoid guest/client-isolated networks) and offer rescan.
- ADB device is unauthorized/offline: show the exact state and do not hide any controller.
- No compatible controller: explain that Windows does not currently expose a supported controller and do not start the session.
- HidHide missing/not configured: offer setup and elevation instructions; never begin exclusive mode without confirming the isolation driver is active.
- scrcpy/UHID start failure: restore visibility immediately and show captured diagnostics.
- Stop/cleanup: always attempt to stop scrcpy and restore controller visibility in a `finally` path. Persist enough recovery state and provide a manual `-Recover` command for interrupted sessions. Document that forced termination or power loss can bypass PowerShell cleanup; recovery must be simple and clearly explained.
- Downloads: pin versions, use HTTPS and official upstream release URLs, verify available checksums/signatures where upstream publishes them, and fail closed if validation fails. Never execute downloaded content without first saving and validating it.

## Security and privacy

- No user accounts, telemetry, cloud services, or outbound network use except dependency downloads and local ADB discovery/connection.
- Never elevate the whole launcher silently. Elevate only the explicit driver setup/configuration action.
- Keep ADB targets and controller IDs local; do not persist them unless needed for recovery.
- Treat dependency archives as untrusted until checksummed and extracted to an app-owned directory.

## Compatibility and acceptance criteria

- Project is PowerShell-first and has no GUI; all interaction and status are visible in the terminal.
- A single documented launch command starts the local launcher/bootstrap flow without requiring the user to manually install a full Android SDK.
- The app can discover already reachable ADB devices, let the user choose one, and connect only after confirmation.
- If ADB is unavailable, the app explains what to enable on the TV and never claims to pair or enable it automatically.
- With an attached supported Bluetooth/wireless-dongle controller, the app forwards its gamepad input through scrcpy UHID and hides that physical controller from ordinary Windows apps for the active session.
- Stopping the session restores controller visibility; errors before/after capture take the cleanup path.
- The repository includes README, license, contribution/security guidance, dependency notices, launch/setup scripts and tests for discovery/session/cleanup logic.
- Tests can validate orchestration with mocked external tools; actual TV/controller compatibility requires hardware testing and must be documented as such.

## Open implementation constraint

ADB discovery differs across Android versions and TV vendors. The implementation should prefer ADB’s own connected-device and mDNS/service discovery, with bounded local-subnet probing only where it is safe and practical. It must not promise that a generic scan can reveal a TV whose ADB network endpoint is disabled or not advertised.
