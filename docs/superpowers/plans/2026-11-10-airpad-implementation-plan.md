# AirPad — Android TV Controller Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use `superpowers:subagent-driven-development` (recommended) or `superpowers:executing-plans` to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a PowerShell console tool that forwards Bluetooth- or wireless-dongle-connected PC gamepads to Android TVs over reachable ADB while hiding the selected controller from ordinary Windows apps for the session.

**Architecture:** PowerShell 5.1-compatible modules orchestrate pinned Android Platform Tools and scrcpy dependencies. ADB discovers already reachable devices; scrcpy forwards gamepad input via UHID; HidHide provides exclusive visibility with explicit elevated setup and recovery.

**Tech Stack:** Windows PowerShell 5.1, ADB Platform Tools, scrcpy, HidHide, Pester 3.4, GitHub Actions on Windows.

**Spec:** `docs/superpowers/specs/2026-11-10-airpad-design.md`

## Global Constraints

- Windows 10/11 with PowerShell available.
- Controller inputs are Bluetooth or wireless receiver/dongle connected to the PC; wired USB gamepads are out of scope.
- The TV and PC share the local network; ADB is already enabled, reachable and authorized when required.
- No automatic ADB enablement, wireless pairing, TV-side controller installation, or GUI.
- Scrcpy gamepad forwarding uses UHID; TV needs no Bluetooth or controller dongle.
- HidHide setup is explicit and requires administrator approval; do not silently install a kernel driver.
- Do not hide controller input until ADB, controller, scrcpy and HidHide prerequisites are validated.
- Always attempt scrcpy stop and controller visibility restoration on all normal/error exits; provide manual recovery for interrupted sessions.
- Dependency downloads use HTTPS, pinned versions, official upstream sources, and checksum/signature verification where upstream publishes it.
- LAN discovery is limited to ADB devices/services on the local network; never probe public internet ranges.
- No telemetry, cloud services, user accounts, or persistent controller data beyond recovery state.

---

## File Map

- `run.ps1` — simple local entry point that invokes the CLI without policy-bypass tricks.
- `src/AirPad.ps1` — menu loop and top-level command dispatch (`Start`, `Recover`, `InstallDependencies`).
- `src/Modules/Config.psm1` — app paths and pinned tool version/configuration.
- `src/Modules/Dependencies.psm1` — dependency checks/downloads/extraction and validation.
- `src/Modules/AdbDiscovery.psm1` — ADB process invocation, device/service parsing and LAN discovery.
- `src/Modules/ControllerIsolation.psm1` — controller inventory and HidHide state/configuration wrappers.
- `src/Modules/BridgeSession.psm1` — validation, scrcpy launch, session loop, stop/finally cleanup and recovery-state persistence.
- `src/Modules/ConsoleUi.psm1` — user-facing prompts, status and setup guidance.
- `config/dependencies.json` — pinned dependency versions and official asset metadata.
- `tests/*..Tests.ps1` — Pester tests with external executable calls mocked.
- `README.md`, `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `DEPENDENCIES.md` — GitHub onboarding, boundaries, support and notices.
- `.gitignore` — exclude downloaded binaries, logs and local recovery state.
- `.github/workflows/test.yml` — run Pester 3.4 under Windows PowerShell 5.1, matching the runtime compatibility target.

## Task 1: Create repository scaffold and configuration

**Files:** `run.ps1`, `src/AirPad.ps1`, `src/Modules/Config.psm1`, `config/dependencies.json`, `.gitignore`, `tests/Config.Tests.ps1`

**Interfaces:** `Get-BridgeConfig` returns a config object with app data path, dependency paths, pinned versions and official download metadata. Entry point accepts `-Recover` and `-InstallDependencies` switches.

- [ ] **Step 1: Add Pester tests for config defaults and CLI switches.** Assert app data paths are under `$env:LOCALAPPDATA`, versions are non-empty and pinned, and both switches are recognized.
- [ ] **Step 2: Run `Invoke-Pester ./tests/Config.Tests.ps1 -Output Detailed` and verify the tests fail because the entry point/config do not exist.**
- [ ] **Step 3: Implement the minimal config, dependency JSON, entry point and `run.ps1`.** Keep all paths rooted from the script location; do not rely on the caller’s working directory.
- [ ] **Step 4: Run `Invoke-Pester ./tests/Config.Tests.ps1 -Output Detailed` and verify it passes.**
- [ ] **Step 5: Run `powershell -NoProfile -File ./run.ps1 -Help` and verify usage is printed without downloading or elevating.**

## Task 2: Implement dependency bootstrap and safe external-tool invocation

**Files:** `src/Modules/Dependencies.psm1`, `config/dependencies.json`, `tests/Dependencies.Tests.ps1`, `DEPENDENCIES.md`

**Interfaces:** `Test-BridgeDependencies` returns named dependency status records. `Install-BridgeDependencies` downloads only pinned official assets into the app-owned data directory, validates published hashes/signatures before extraction, and never runs an installer silently. `Invoke-BridgeTool` invokes a resolved executable with an argument array and captures exit code/stdout/stderr.

- [ ] **Step 1: Add tests using a temporary directory and mocked `Invoke-WebRequest` for missing assets, valid checksum, checksum mismatch, and extraction path.** Ensure mismatch throws before extraction.
- [ ] **Step 2: Run `Invoke-Pester ./tests/Dependencies.Tests.ps1 -Output Detailed` and verify the tests fail for the missing functions.**
- [ ] **Step 3: Implement pinned dependency metadata and bootstrap logic.** Save archives before extracting; validate SHA-256 when provided; reject paths escaping the app dependency directory; do not invoke downloaded binaries during installation.
- [ ] **Step 4: Add a test proving an invalid checksum leaves no extracted files; run the dependency tests.**
- [ ] **Step 5: Document upstream names, versions, licenses, URLs and update procedure in `DEPENDENCIES.md`.**

## Task 3: Discover reachable Android TV devices through ADB

**Files:** `src/Modules/AdbDiscovery.psm1`, `tests/AdbDiscovery.Tests.ps1`, `src/Modules/ConsoleUi.psm1`

**Interfaces:** `Get-AdbDeviceInventory` returns objects with `Serial`, `State`, `Model` and `Transport`. `Find-AdbNetworkDevices` returns only successfully connected/authorized local ADB targets. `Get-AdbSetupGuidance` returns concise TV-side instructions when discovery is empty or unauthorized.

- [ ] **Step 1: Add parsing tests for `adb devices -l` output covering device, unauthorized, offline, empty, USB-transport and network-serial examples.**
- [ ] **Step 2: Run `Invoke-Pester ./tests/AdbDiscovery.Tests.ps1 -Output Detailed` and verify the tests fail before implementation.**
- [ ] **Step 3: Implement `adb devices -l` parsing and prefer ADB mDNS service discovery for network devices.** Keep ADB invocation isolated behind `Invoke-BridgeTool` so tests can mock it.
- [ ] **Step 4: Add tests showing unauthorized/offline devices are never offered as connectable; run the discovery tests.**
- [ ] **Step 5: Implement only bounded local-network probing if the chosen ADB discovery API needs it; validate private/local address ranges and never scan public ranges.** If no safe automatic range is available, request a TV IP from the user rather than guess a subnet.
- [ ] **Step 6: Verify an empty scan emits the exact state and setup guidance without changing TV settings or hiding controllers.**

## Task 4: Inventory wireless controllers and isolate input with HidHide

**Files:** `src/Modules/ControllerIsolation.psm1`, `tests/ControllerIsolation.Tests.ps1`, `src/Modules/ConsoleUi.psm1`

**Interfaces:** `Get-BridgeControllerInventory` returns controller device records containing stable PnP instance IDs and friendly names for Windows-recognized game controllers. `Enable-BridgeControllerIsolation` records previous HidHide state, configures the selected controller(s) as hidden and allowlists the scrcpy executable. `Restore-BridgeControllerVisibility` restores recorded state. `Test-HidHideReady` confirms the driver is installed and operational.

- [ ] **Step 1: Add tests for controller inventory normalization, selecting one/multiple devices, and preserving the pre-session HidHide state.** Mock all Windows device and HidHide CLI calls.
- [ ] **Step 2: Run `Invoke-Pester ./tests/ControllerIsolation.Tests.ps1 -Output Detailed` and verify the tests fail before implementation.**
- [ ] **Step 3: Implement Windows controller enumeration and HidHide CLI wrappers behind injectable command functions.** Accept Bluetooth and wireless-receiver game controllers recognized by Windows; do not claim support for unknown/non-gamepad devices.
- [ ] **Step 4: Implement reversible isolation state: persist only the minimum recovery data, allowlist scrcpy, hide only the selected controller, and roll back partial configuration on failure.**
- [ ] **Step 5: Add tests that failure during allowlisting/hiding restores prior settings and does not leave the controller hidden.** Run the isolation tests.
- [ ] **Step 6: Verify driver-missing/unavailable errors are actionable and setup/elevation remains explicit; do not elevate the whole launcher.**

## Task 5: Build the ADB + scrcpy forwarding session lifecycle

**Files:** `src/Modules/BridgeSession.psm1`, `tests/BridgeSession.Tests.ps1`, `src/AirPad.ps1`

**Interfaces:** `Start-BridgeSession -DeviceSerial <string> -ControllerInstanceIds <string[]>` validates prerequisites, enables HidHide for every HID path belonging to the selected controller, then launches scrcpy with `--gamepad=uhid --no-video --no-audio` for the selected ADB serial and blocks until stop. `Restore-InterruptedBridgeSession` consumes persisted recovery state and invokes restoration.

- [ ] **Step 1: Add tests for validation ordering: ADB state, UHID option availability, controller inventory and HidHide readiness are checked before any isolation change.**
- [ ] **Step 2: Run `Invoke-Pester ./tests/BridgeSession.Tests.ps1 -Output Detailed` and verify the tests fail before implementation.**
- [ ] **Step 3: Implement scrcpy launch with explicit argument arrays and selected serial; capture process ID and log path.** Do not use a shell command string or `Invoke-Expression`.
- [ ] **Step 4: After all prerequisites pass, persist recovery state and enable HidHide before launching scrcpy; use `try/finally` to stop the process and restore controller visibility.**
- [ ] **Step 5: Implement an interactive stop loop and `-Recover` command that restores persisted prior state after forced termination.**
- [ ] **Step 6: Add failure-injection tests for scrcpy launch failure, user stop and restoration failure; run all session tests.**

## Task 6: Complete PowerShell terminal UX and setup flow

**Files:** `src/Modules/ConsoleUi.psm1`, `src/AirPad.ps1`, `run.ps1`, `tests/ConsoleUi.Tests.ps1`

**Interfaces:** `Show-BridgeMenu`, `Show-AdbSetupInstructions`, `Read-BridgeSelection` and `Show-BridgeStatus` contain presentation/input only; connection/session modules own actions.

- [ ] **Step 1: Add tests for menu choices, empty discovery, unauthorized device status and stop confirmation using mocked `Read-Host`/`Write-Host`.**
- [ ] **Step 2: Implement a terminal-only menu: Scan, Connect, Stop/Recover, Install dependencies, Exit.**
- [ ] **Step 3: Ensure the connect path requires explicit selection and confirmation before controller isolation begins.**
- [ ] **Step 4: Run all UI tests and manually run `./run.ps1 -Help` in Windows PowerShell.**

## Task 7: Publish-ready docs, tests and CI

**Files:** `README.md`, `LICENSE`, `SECURITY.md`, `CONTRIBUTING.md`, `DEPENDENCIES.md`, `.github/workflows/test.yml`, all `tests/*.Tests.ps1`

- [ ] **Step 1: Write README requirements, limitations, first-run steps, ADB-on-TV guidance, controller support, install/launch/recover commands and troubleshooting.** Include a clearly marked launch example and explain that reachable network ADB is required.
- [ ] **Step 2: Add a permissive OSS license and security/contribution guidance; ensure dependency notices are present.**
- [ ] **Step 3: Configure GitHub Actions on `windows-latest` to install Pester 3.4 and run the complete test suite under Windows PowerShell 5.1.**
- [ ] **Step 4: Run `Invoke-Pester ./tests` and the static parse check `Get-ChildItem ./src,./tests -Recurse -Filter *.ps1,*.psm1 | ForEach-Object { $tokens=$null; $errors=$null; [System.Management.Automation.Language.Parser]::ParseFile($_.FullName,[ref]$tokens,[ref]$errors) > $null; if($errors){ throw ($errors | Out-String) } }`.**
- [ ] **Step 5: Verify `.gitignore` excludes downloaded dependencies, logs and recovery state, then review the complete repository for claims that overstate hardware compatibility or guarantee cleanup after power loss.**

## Verification boundaries

- Automated tests mock ADB, scrcpy, HidHide and Windows device enumeration; they verify orchestration and cleanup ordering, not real hardware behavior.
- A real acceptance test requires a Windows 10/11 PC, a Bluetooth or wireless-receiver controller, an Android TV with reachable authorized network ADB, and a TV firmware/scrcpy combination that supports UHID gamepad input.
- Do not claim all Android TVs or all third-party controllers work until an explicit device compatibility matrix has been tested.
- No commits or pushes are part of this plan unless the user asks; the final folder should be GitHub-ready and initializeable.
