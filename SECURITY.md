# Security policy

## Supported versions

Security reports are accepted for the latest source revision on the default branch. This is an early MVP and does not yet publish signed releases.

## Reporting a vulnerability

Do not open a public issue containing exploit details, private network addresses, ADB keys or device identifiers. Use GitHub's private vulnerability reporting for this repository when enabled; otherwise contact the repository owner privately before disclosure.

## Security boundaries

This project runs ADB commands against devices on the local network and installs/configures the HidHide Windows input-filter driver only after explicit user consent. Dependency downloads are pinned and fetched over HTTPS; the app must not evaluate downloaded scripts or use `Invoke-Expression`. Never share `%LOCALAPPDATA%\AirPad\state` or logs without reviewing/redacting them.
