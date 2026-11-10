[CmdletBinding()]
param(
    [switch]$Help,
    [switch]$Recover,
    [switch]$InstallDependencies
)

$ErrorActionPreference = 'Stop'
$entry = Join-Path $PSScriptRoot 'src/AirPad.ps1'
if (-not (Test-Path -LiteralPath $entry)) {
    throw "AirPad entry point not found: $entry"
}

& $entry -Help:$Help -Recover:$Recover -InstallDependencies:$InstallDependencies
