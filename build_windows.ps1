#Requires -Version 7.4
<# Cross-builds a native LHA MSI on Linux, using generated Autotools inputs. #>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture,
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$BuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
& (Join-Path $PSScriptRoot 'powershell/all/build_windows.ps1') @PSBoundParameters
