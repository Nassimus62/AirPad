Import-Module (Join-Path $PSScriptRoot '../src/Modules/Dependencies.psm1') -Force

Describe 'Pinned dependency download sources' {
    It 'uses the published Google Platform-Tools Windows archive' {
        $manifestPath = Join-Path $PSScriptRoot '../config/dependencies.json'
        $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
        $manifest.platformTools.version | Should Be '37.0.3'
        $manifest.platformTools.url | Should Be 'https://dl.google.com/android/repository/platform-tools_r37.0.3-win.zip'
    }
}

Describe 'Downloaded archive validation' {
    It 'rejects a zip entry that escapes the extraction directory' {
        $archivePath = Join-Path $TestDrive 'unsafe.zip'
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        try { $null = $archive.CreateEntry('../escape.txt') } finally { $archive.Dispose() }
        { Test-ZipArchiveSafe -Path $archivePath } | Should Throw
    }

    It 'accepts a regular relative archive entry' {
        $archivePath = Join-Path $TestDrive 'safe.zip'
        Add-Type -AssemblyName System.IO.Compression
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $archive = [System.IO.Compression.ZipFile]::Open($archivePath, [System.IO.Compression.ZipArchiveMode]::Create)
        try { $null = $archive.CreateEntry('folder/file.txt') } finally { $archive.Dispose() }
        { Test-ZipArchiveSafe -Path $archivePath } | Should Not Throw
    }
}
