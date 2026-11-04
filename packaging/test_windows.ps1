#Requires -Version 7.4
<# Installs and removes the MSI; use a disposable Windows qualification host. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Package,
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture
)
$ErrorActionPreference = 'Stop'
if (!$IsWindows) {
    throw 'This qualification requires Windows.'
}
$programs = if ($Architecture -eq 'x86' -and [Environment]::Is64BitOperatingSystem) {
    [Environment]::GetFolderPath('ProgramFilesX86')
} else {
    [Environment]::GetFolderPath('ProgramFiles')
}
$directory = Join-Path $programs 'LHa for UNIX'
if (Test-Path -LiteralPath $directory) {
    throw 'An existing LHA installation was preserved; use a clean qualification host.'
}
$packagePath = (Resolve-Path -LiteralPath $Package).Path
$installed = $false
try {
    $process = Start-Process msiexec.exe -ArgumentList ('/i "' + $packagePath + '" /qn /norestart') -Wait -PassThru
    if ($process.ExitCode -notin 0, 3010) {
        throw "MSI installation failed: $($process.ExitCode)"
    }
    $installed = $true
    & (Join-Path $PSScriptRoot 'test_roundtrip.ps1') -Executable (Join-Path $directory 'lha.exe')
    foreach ($name in @('COPYRIGHT.txt', 'MINGW-NOTICES.txt', 'GCC-NOTICES.txt', 'source.tar.gz')) {
        if (!(Test-Path -LiteralPath (Join-Path $directory $name))) {
            throw 'The package omitted source or required licence notices.'
        }
    }
    $file = [IO.File]::OpenRead((Join-Path $directory 'source.tar.gz'))
    $gzip = [IO.Compression.GZipStream]::new($file, [IO.Compression.CompressionMode]::Decompress)
    $reader = [System.Formats.Tar.TarReader]::new($gzip)
    try {
        $members = [Collections.Generic.HashSet[string]]::new()
        while ($null -ne ($entry = $reader.GetNextEntry())) {
            $null = $members.Add(($entry.Name -replace '^\./', ''))
        }
        foreach ($required in @('src/lhext.c', 'man/lha.n', 'debian/copyright', 'debian/patches/mingw-symlink-helper.patch')) {
            if (!$members.Contains($required)) {
                throw 'The MSI source archive is incomplete.'
            }
        }
    } finally {
        $reader.Dispose()
        $gzip.Dispose()
        $file.Dispose()
    }
} finally {
    if ($installed) {
        $process = Start-Process msiexec.exe -ArgumentList ('/x "' + $packagePath + '" /qn /norestart') -Wait -PassThru
        if ($process.ExitCode -notin 0, 3010 -or (Test-Path -LiteralPath (Join-Path $directory 'lha.exe'))) {
            throw 'MSI uninstall did not remove its installed executable.'
        }
    }
}
'PASS native Windows MSI installation, LHA/LZH round trips, included matching source/notices and uninstall'
