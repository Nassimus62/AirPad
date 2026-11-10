# Contributing

1. Open an issue for a bug or compatibility report before making large changes.
2. Keep the runtime PowerShell-native and compatible with Windows PowerShell 5.1 unless an issue explicitly changes that requirement.
3. Do not add a GUI, telemetry, cloud service, controller pairing to the TV, or silent driver installation.
4. Add or update Pester tests for behavior changes. Tests must not require a physical TV, controller, ADB server or HidHide driver.
5. Run `Invoke-Pester ./tests -Output Detailed` and parse-check PowerShell scripts before submitting.
6. Update `DEPENDENCIES.md` and review upstream hashes, signatures, license and release notes when changing pinned dependencies.
7. Do not include downloaded executables, archives, logs, recovery state, TV serials, IP addresses or ADB keys in pull requests.

Compatibility reports should include Windows version, TV/box model and Android version, controller model and whether it uses Bluetooth or a wireless receiver, ADB transport, and relevant redacted log output.
