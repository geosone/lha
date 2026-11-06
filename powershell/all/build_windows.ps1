#Requires -Version 7.4
<#
.SYNOPSIS
Cross-compiles LHA with MinGW and packages the binary plus complete source in MSI.
.DESCRIPTION
Requires Linux, make, MinGW, wixl and an Autotools-prepared clean source tree.
Build/output directories must be new. Failed builds retain their logs.
This creates packages only. Installing the MSI appends its directory to system PATH;
uninstall removes that entry. Existing shells/services must be restarted.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][ValidateSet('x86', 'x64')][string]$Architecture,
    [Parameter(Mandatory)][string]$SourceDirectory,
    [Parameter(Mandatory)][string]$SourceArchive,
    [Parameter(Mandatory)][string]$BuildDirectory,
    [Parameter(Mandatory)][string]$OutputDirectory
)
$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest
if (!$IsLinux) {
    throw 'This entry is the Linux MinGW cross-builder.'
}
$source = (Resolve-Path -LiteralPath $SourceDirectory).Path
$sourceTar = (Resolve-Path -LiteralPath $SourceArchive).Path
if (!(Test-Path -LiteralPath (Join-Path $source 'configure')) -or (Test-Path -LiteralPath (Join-Path $source 'config.status'))) {
    throw 'Use autoreconf-prepared, unconfigured source; distclean a previously configured tree.'
}

# dpkg-buildpackage unapplies the quilt series after the Debian build. The
# Windows executable must contain the same patches as the DEB, so refuse a
# tree whose applied patches (quilt's .pc/applied-patches) differ from the
# series; `dpkg-source --before-build` applies them.
$series = @(
    Get-Content -LiteralPath (Join-Path $source 'debian/patches/series') |
        ForEach-Object { $_.Trim() } |
        Where-Object { $_ -and !$_.StartsWith('#') }
)
$appliedList = Join-Path $source '.pc/applied-patches'
$applied = if (Test-Path -LiteralPath $appliedList) {
    @(Get-Content -LiteralPath $appliedList | Where-Object { $_.Trim() })
} else {
    @()
}
if (($series -join "`n") -cne ($applied -join "`n")) {
    throw 'Apply the Debian patch series to the source first (dpkg-source --before-build).'
}
foreach ($path in @($BuildDirectory, $OutputDirectory)) {
    if (![IO.Path]::IsPathFullyQualified($path) -or (Test-Path -LiteralPath $path)) {
        throw 'Build and output directories must be new absolute paths.'
    }
}
$profiles = @{
    x86 = @{
        Triplet   = 'i686-w64-mingw32'
        Folder    = 'ProgramFilesFolder'
        Win64     = 'no'
        Upgrade   = 'ab010a4e-06d9-58a1-9656-3245aba42334'
        Component = '42d9e174-e0a6-5311-bedd-91293f7abc83'
    }
    x64 = @{
        Triplet   = 'x86_64-w64-mingw32'
        Folder    = 'ProgramFiles64Folder'
        Win64     = 'yes'
        Upgrade   = '142adf0a-bcc5-5f9a-ba46-df3b8a3c1e9e'
        Component = 'a1aa69e2-e1dd-5cbe-b0a5-c571ccb1f957'
    }
}
$profile = $profiles[$Architecture]
foreach ($tool in @('sh', 'make', 'wixl', ($profile.Triplet + '-gcc'), ($profile.Triplet + '-strip'))) {
    $null = Get-Command $tool -CommandType Application -ErrorAction Stop
}
$null = New-Item -ItemType Directory $BuildDirectory, $OutputDirectory
$build = (Resolve-Path -LiteralPath $BuildDirectory).Path
$payload = Join-Path $build 'payload'
$null = New-Item -ItemType Directory $payload
function Invoke-BuildStep(
    [string]$Name,
    [string]$File,
    [string[]]$Arguments
) {
    $start = [Diagnostics.ProcessStartInfo]::new($File)
    $start.WorkingDirectory = $build
    $start.UseShellExecute = $false
    $start.RedirectStandardOutput = $true
    $start.RedirectStandardError = $true
    $start.Environment['CC'] = $profile.Triplet + '-gcc'
    $start.Environment['CFLAGS'] = '-O2'
    $start.Environment['LDFLAGS'] = '-static-libgcc'
    foreach ($argument in $Arguments) {
        $start.ArgumentList.Add($argument)
    }
    $process = [Diagnostics.Process]::Start($start)
    try {
        $stdout = $process.StandardOutput.ReadToEndAsync()
        $stderr = $process.StandardError.ReadToEndAsync()
        if (!$process.WaitForExit(300000)) {
            $process.Kill($true)
            throw "Build step timed out: $Name"
        }
        [IO.File]::WriteAllText((Join-Path $build ($Name + '.stdout.log')), $stdout.GetAwaiter().GetResult())
        [IO.File]::WriteAllText((Join-Path $build ($Name + '.stderr.log')), $stderr.GetAwaiter().GetResult())
        if ($process.ExitCode) {
            throw "Build step failed: $Name; inspect logs in $build"
        }
    } finally {
        $process.Dispose()
    }
}
$buildTriplet = (& sh (Join-Path $source 'config.guess')).Trim()
if ($LASTEXITCODE -ne 0) {
    throw 'Cannot determine the Linux build triplet.'
}
# Upstream documents with-tmp-file=no for the MinGW port. Disable iconv so
# the executable needs no separately installed iconv DLL. Unicode filenames
# remain a separate qualification concern, not an implied supported feature.
Invoke-BuildStep configure sh @((Join-Path $source 'configure'), ('--build=' + $buildTriplet), ('--host=' + $profile.Triplet), '--disable-iconv', '--with-tmp-file=no', '--with-default-method=5')
Invoke-BuildStep make make @('-j2')
$exe = Join-Path $payload 'lha.exe'
Copy-Item -LiteralPath (Join-Path $build 'src/lha.exe') -Destination $exe
Invoke-BuildStep strip ($profile.Triplet + '-strip') @($exe)
Copy-Item -LiteralPath $sourceTar -Destination (Join-Path $payload 'source.tar.gz')
Copy-Item -LiteralPath (Join-Path $source 'debian/copyright') -Destination (Join-Path $payload 'COPYRIGHT.txt')
Copy-Item -LiteralPath '/usr/share/doc/mingw-w64-common/copyright' -Destination (Join-Path $payload 'MINGW-NOTICES.txt')
Copy-Item -LiteralPath '/usr/share/doc/gcc-mingw-w64-base/copyright' -Destination (Join-Path $payload 'GCC-NOTICES.txt')
$payloadXml = [Security.SecurityElement]::Escape($payload)
# MSI's third version field is bounded to 65535. Days since 2000 gives this
# upstream date (2026-07-23) a base of 9700; revision 1 adds the PATH change,
# revision 2 the bare file names of the i option when archiving, revision 3
# the wildcard expansion of file arguments when archiving.
$xml = @"
<Wix xmlns="http://schemas.microsoft.com/wix/2006/wi">
  <Product Id="*" Name="LHa for UNIX $Architecture" Language="1033" Version="1.14.9703" Manufacturer="Disconnected by Peer AT" UpgradeCode="$($profile.Upgrade)">
    <Package InstallerVersion="500" Compressed="yes" InstallScope="perMachine" />
    <Media Id="1" Cabinet="lha.cab" EmbedCab="yes" />
    <MajorUpgrade DowngradeErrorMessage="A newer LHA package is already installed." />
    <Directory Id="TARGETDIR" Name="SourceDir">
      <Directory Id="$($profile.Folder)">
        <Directory Id="INSTALLFOLDER" Name="LHa for UNIX">
          <Component Id="Runtime" Guid="$($profile.Component)" Win64="$($profile.Win64)">

            <File Id="LhaExe" Source="$payloadXml/lha.exe" KeyPath="yes" />
            <File Id="SourceCode" Source="$payloadXml/source.tar.gz" />
            <File Id="Copyright" Source="$payloadXml/COPYRIGHT.txt" />
            <File Id="MingwNotice" Source="$payloadXml/MINGW-NOTICES.txt" />
            <File Id="GccNotice" Source="$payloadXml/GCC-NOTICES.txt" />
          </Component>
        </Directory>
      </Directory>
    </Directory>
    <Feature Id="Main" Title="LHA compressor, decompressor and complete matching source" Level="1">
      <ComponentRef Id="Runtime" />
    </Feature>
  </Product>
</Wix>
"@
$definition = Join-Path $build 'lha.wxs'
[IO.File]::WriteAllText($definition, $xml)
$msi = Join-Path $OutputDirectory ('lha-unix-1.14i-ac20260723-4-windows-' + $Architecture + '.msi')
Invoke-BuildStep msi wixl @('-a', $Architecture, '-o', $msi, $definition)
& (Join-Path $PSScriptRoot '../../packaging/finalize_msi_path.ps1') -Package $msi -Component Runtime
[pscustomobject]@{
    Package    = $msi
    Executable = $exe
    SHA256     = (Get-FileHash $msi).Hash
}
