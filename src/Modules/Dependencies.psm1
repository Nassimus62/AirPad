Set-StrictMode -Version Latest

function Invoke-BridgeTool {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$FilePath,
        [string[]]$Arguments = @(),
        [int]$TimeoutSeconds = 30
    )

    if (-not (Test-Path -LiteralPath $FilePath -PathType Leaf)) {
        throw "Required executable was not found: $FilePath"
    }

    $start = New-Object System.Diagnostics.ProcessStartInfo
    $start.FileName = $FilePath
    $start.UseShellExecute = $false
    $start.CreateNoWindow = $true
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $quotedArguments = foreach ($argument in $Arguments) {
        if ($argument -match '[\s"]') { '"' + ($argument -replace '([\\]*)"', '$1$1\"' -replace '(\\+)$', '$1$1') + '"' }
        else { $argument }
    }
    $start.Arguments = $quotedArguments -join ' '

    $process = New-Object System.Diagnostics.Process
    $process.StartInfo = $start
    if (-not $process.Start()) { throw "Could not start $FilePath" }
    $stdoutTask = $process.StandardOutput.ReadToEndAsync()
    $stderrTask = $process.StandardError.ReadToEndAsync()
    if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
        try { $process.Kill() } catch { }
        throw "Timed out after $TimeoutSeconds seconds: $FilePath"
    }
    $stdout = $stdoutTask.Result
    $stderr = $stderrTask.Result
    [pscustomobject]@{ ExitCode = $process.ExitCode; StdOut = $stdout; StdErr = $stderr; FilePath = $FilePath }
}

function Test-BridgeDependencies {
    [CmdletBinding()]
    param([Parameter(Mandatory)]$Config)

    $adb = Get-Command adb.exe -ErrorAction SilentlyContinue
    $scrcpy = Get-Command scrcpy.exe -ErrorAction SilentlyContinue
    $adbPath = if ($adb) { $adb.Source } else { Get-ChildItem -LiteralPath $Config.DependencyRoot -Filter adb.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    $scrcpyPath = if ($scrcpy) { $scrcpy.Source } else { Get-ChildItem -LiteralPath $Config.DependencyRoot -Filter scrcpy.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName }
    $driverPath = Get-ChildItem -LiteralPath (Join-Path $env:ProgramFiles 'Nefarius Software Solutions') -Filter HidHideCLI.exe -Recurse -ErrorAction SilentlyContinue | Select-Object -First 1 -ExpandProperty FullName

    @(
        [pscustomobject]@{ Name = 'ADB'; Path = $adbPath; Available = [bool]$adbPath },
        [pscustomobject]@{ Name = 'scrcpy'; Path = $scrcpyPath; Available = [bool]$scrcpyPath },
        [pscustomobject]@{ Name = 'HidHide CLI'; Path = $driverPath; Available = [bool]$driverPath }
    )
}

function Test-ZipArchiveSafe {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Path)

    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($Path)
    try {
        foreach ($entry in $archive.Entries) {
            $normalized = $entry.FullName.Replace('\', '/')
            if ($normalized.StartsWith('/') -or $normalized -match '(^|/)\.\.(/|$)' -or $normalized -match '^[A-Za-z]:') {
                throw "Unsafe path in downloaded archive: $($entry.FullName)"
            }
        }
    } finally { $archive.Dispose() }
}

function Install-BridgeDependencies {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]$Config,
        [switch]$IncludeDriver
    )

    foreach ($path in @($Config.DependencyRoot, $Config.StateRoot, $Config.LogRoot)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }

    foreach ($dependencyName in @('platformTools', 'scrcpy')) {
        $dependency = $Config.Manifest.$dependencyName
        $targetDirectory = Join-Path $Config.DependencyRoot $(if ($dependencyName -eq 'platformTools') { 'platform-tools' } else { 'scrcpy' })
        if (Test-Path -LiteralPath $targetDirectory) { continue }
        $archivePath = Join-Path $Config.DependencyRoot "$dependencyName-$($dependency.version).zip"
        Write-Host "Downloading $dependencyName $($dependency.version) from its official release source..."
        Invoke-WebRequest -Uri $dependency.url -OutFile $archivePath -UseBasicParsing
        if ($dependency.sha256) {
            $actualHash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
            if ($actualHash -ne $dependency.sha256.ToLowerInvariant()) {
                Remove-Item -LiteralPath $archivePath -Force
                throw "SHA-256 validation failed for $dependencyName; archive was deleted."
            }
        } else {
            Write-Warning "Upstream does not publish a pinned checksum for $dependencyName; HTTPS is used, but integrity cannot be independently confirmed."
        }
        Test-ZipArchiveSafe -Path $archivePath
        Expand-Archive -LiteralPath $archivePath -DestinationPath $targetDirectory -Force
        Remove-Item -LiteralPath $archivePath -Force
    }

    if ($IncludeDriver) {
        $driver = $Config.Manifest.hidHide
        $driverDirectory = Join-Path $Config.DependencyRoot 'hidhide'
        New-Item -ItemType Directory -Path $driverDirectory -Force | Out-Null
        $installer = Join-Path $driverDirectory "HidHide-$($driver.version)-x64.exe"
        if (-not (Test-Path -LiteralPath $installer)) {
            Write-Host "Downloading HidHide $($driver.version) from its official release source..."
            Invoke-WebRequest -Uri $driver.url -OutFile $installer -UseBasicParsing
        }
        $signature = Get-AuthenticodeSignature -FilePath $installer
        if ($driver.requiresValidAuthenticodeSignature -and ($signature.Status -ne 'Valid' -or $signature.SignerCertificate.Subject -notmatch '(?i)Nefarius Software Solutions')) {
            Remove-Item -LiteralPath $installer -Force
            throw "HidHide installer signature is invalid or is not from Nefarius Software Solutions ($($signature.Status)); installer was deleted."
        }
        Write-Host 'HidHide is a Windows input-filter driver. It requires administrator approval and may require a reboot.'
        $answer = Read-Host 'Run the signed HidHide installer now? (y/N)'
        if ($answer -match '^(y|yes)$') {
            $result = Start-Process -FilePath $installer -Verb RunAs -Wait -PassThru
            if ($result.ExitCode -ne 0) { throw "HidHide installer returned exit code $($result.ExitCode)." }
        } else {
            Write-Host "Driver setup skipped. You can run the installer manually: $installer"
        }
    }

    Write-Host 'Dependency setup finished. Run .\run.ps1 to scan for a TV.'
}

Export-ModuleMember -Function Invoke-BridgeTool, Test-BridgeDependencies, Install-BridgeDependencies, Test-ZipArchiveSafe
