#Requires -Version 7.4
<# Installs/removes packages: run only in a disposable Debian test container. #>
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Package)
$ErrorActionPreference = 'Stop'
function Invoke-Native(
    [string]$File,
    [string[]]$Arguments
) {
    & $File @Arguments
    if ($LASTEXITCODE -ne 0) {
        throw "Package test command failed: $File"
    }
}
Invoke-Native apt-get @('update', '--error-on=any')
Invoke-Native apt-get @('install', '-y', '--no-install-recommends', 'lhasa')
$original = (& readlink -f /usr/bin/lha).Trim()
Invoke-Native update-alternatives @('--set', 'lha', $original)
Invoke-Native apt-get @('install', '-y', '--no-install-recommends', $Package)
if ((& readlink -f /usr/bin/lha).Trim() -ne $original) {
    throw 'Installing the compressor replaced a manually chosen alternative.'
}
& (Join-Path $PSScriptRoot 'test_roundtrip.ps1') -Executable /usr/bin/lha.unix
Invoke-Native update-alternatives @('--auto', 'lha')
if ((& readlink -f /usr/bin/lha).Trim() -ne '/usr/bin/lha.unix') {
    throw 'Automatic alternatives did not select the full compressor.'
}
Invoke-Native apt-get @('remove', '-y', 'lha-unix')
if ((& readlink -f /usr/bin/lha).Trim() -ne $original) {
    throw 'Removing the compressor did not restore the remaining alternative.'
}
Invoke-Native dpkg-query @('-W', 'lhasa')
'PASS coinstallation with Lhasa, retained manual choice, automatic selection and uninstall fallback'
