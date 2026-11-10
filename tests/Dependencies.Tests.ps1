Import-Module (Join-Path $PSScriptRoot '../src/Modules/Dependencies.psm1') -Force

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
