# AirPad

A PowerShell console tool for sending a PC-connected Bluetooth or wireless-dongle controller to an Android TV / TV box over Wi-Fi. The controller and its wireless receiver stay at the PC; the TV does not need Bluetooth or an open USB port.

AirPad uses ADB and scrcpy to forward the PC gamepad as a virtual HID device, and HidHide to keep ordinary Windows apps from receiving the selected controller while the bridge is active.

> **Early MVP:** real TV and controller testing is still required. Compatibility depends on the TV firmware, ADB configuration, controller mapping and Android UHID support. This does not promise every third-party gamepad or Android TV works.

## Requirements

- Windows 10/11 and PowerShell 5.1 or newer.
- A Bluetooth controller paired with Windows, or a wireless controller receiver/dongle plugged into the PC. Wired USB gamepads are outside the v1 scope.
- Android TV and PC on the same non-guest Wi-Fi/LAN.
- ADB debugging already enabled on the TV and reachable over the network. Some TVs require Wireless debugging or ADB-over-network to be enabled separately and may require approving the PC.
- HidHide driver installed and running for exclusive input. Driver setup requires administrator approval and may require a reboot.
- Android firmware that accepts scrcpy's UHID gamepad. This varies by manufacturer and Android version.

USB debugging enabled on a TV does not necessarily mean ADB is reachable over Wi-Fi. AirPad cannot enable ADB or pair the PC with the TV remotely. It discovers already reachable ADB devices and gives setup guidance if none are found.

## Quick start

Download or clone this repository, open PowerShell in the project folder, then run:

```powershell
.\run.ps1
```

Choose **Install/download dependencies** on first run. AirPad downloads pinned ADB and scrcpy packages from their official release sources, verifies the scrcpy SHA-256 and asks before launching the signed HidHide installer. Review the installer prompt and approve Windows elevation only if you want exclusive controller capture.

After setup, run `.\run.ps1` again, choose **Scan and connect**, select the TV and controller, and confirm. Press **Q** in the PowerShell console to stop the forwarding session. AirPad stops its scrcpy process and restores the controller's prior HidHide visibility.

### Recovery after forced exit

If PowerShell is force-closed or the PC loses power during a session, HidHide settings can remain active. Reopen PowerShell in the project folder and run:

```powershell
.\run.ps1 -Recover
```

The recovery command stops the recorded scrcpy process if it still matches the saved executable path and restores the prior controller-visibility settings. AirPad also checks the previous `AndroidTvControllerBridge` recovery location so an interrupted session from an older build can still be recovered. If Windows refuses an elevation prompt, run recovery again and approve it.

## TV setup guidance

On the TV, enable Developer Options and ADB debugging. If the TV has a Wireless debugging or ADB-over-network setting, enable it. Accept any on-TV authorization prompt for this PC. Keep both devices on the same private LAN; guest Wi-Fi, client isolation, firewalls and some mesh/router settings can block discovery.

AirPad scans ADB mDNS services and probes TCP 5555 only on directly connected private IPv4 subnets up to /24 in size. If the TV exposes a different ADB port, enter its private `IP:port` when prompted. It never scans public internet addresses and never attempts wireless pairing.

## Controller behavior and limitations

- Controllers must already work in Windows over Bluetooth or a wireless receiver/dongle. AirPad does not pair them to the TV.
- HidHide hides the selected controller device from ordinary applications while allowing scrcpy. It cannot prevent kernel-level input monitors or guarantee exclusivity against every specialized driver/software stack.
- Windows-recognized game controllers are the compatibility target. Cheap/generic devices with unusual HID descriptors or unknown button/axis layouts may not be recognized or may need scrcpy/SDL mappings.
- AirPad only hides the selected device. If a receiver exposes several gamepads as one device, they may be isolated together.
- Some Android TV firmware rejects virtual UHID devices or gamepad input in particular games. This cannot be confirmed without testing the target TV/game.
- Do not run multiple copies of AirPad at the same time.

## Command-line switches

```powershell
.\run.ps1 -Help
.\run.ps1 -InstallDependencies
.\run.ps1 -Recover
```

## Testing

Windows PowerShell 5.1 includes a compatible Pester 3.4 test environment on many systems. Run:

```powershell
Invoke-Pester ./tests
```

The automated tests cover parsing, local-address safety, archive validation and orchestration boundaries using mocks. A real acceptance test needs a Windows PC, a supported wireless controller, reachable authorized ADB and a compatible Android TV.

## Security

- No telemetry, account, cloud connection or data upload.
- Network discovery stays on the local network; only dependency bootstrap accesses the internet.
- Downloads use HTTPS; scrcpy is checked against a pinned SHA-256. Platform-Tools upstream does not publish a checksum in the configured source and is accompanied by a warning.
- HidHide installation is explicit and requires a valid Authenticode signature and Windows elevation.
- See [SECURITY.md](SECURITY.md) before reporting a security concern.

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) and [DEPENDENCIES.md](DEPENDENCIES.md). Please include Windows version, TV/box model and Android version, controller model/connection type, ADB transport, and scrcpy logs when reporting compatibility issues. Redact device IDs and IPs before sharing logs.

## License

MIT for this repository. Third-party tools retain their own licenses; see [DEPENDENCIES.md](DEPENDENCIES.md).
