#Requires -Version 7.4
[CmdletBinding()]
param([Parameter(Mandatory)][string]$Executable)
$ErrorActionPreference = 'Stop'
$work = Join-Path ([IO.Path]::GetTempPath()) ('lha-test-' + [guid]::NewGuid().ToString('N'))
$inputDirectory = Join-Path $work 'input files'
$outputDirectory = Join-Path $work 'output files'
$null = New-Item -ItemType Directory $inputDirectory, $outputDirectory
try {
    $inputFile = Join-Path $inputDirectory 'file_id.diz'
    $payload = [Text.Encoding]::ASCII.GetBytes("LHA/LZH compression fixture`r`n" * 200)
    [IO.File]::WriteAllBytes($inputFile, $payload)
    $second = Join-Path $inputDirectory 'release notes.txt'
    [IO.File]::WriteAllText($second, 'A second file with spaces in its name.')
    foreach ($extension in @('lha', 'lzh')) {
        $archive = Join-Path $work ('round trip.' + $extension)
        # The flags match Mystic A49's original LHA command templates.
        # Mystic packs files from a node's working directory. Relative stored
        # names allow a later FILE_ID.DIZ basename selection.
        Push-Location $inputDirectory
        try {
            & $Executable -a -i $archive 'file_id.diz' 'release notes.txt'
        } finally {
            Pop-Location
        }
        if ($LASTEXITCODE -ne 0 -or !(Test-Path $archive)) {
            throw 'Native LHA creation failed.'
        }
        & $Executable ("-efiw=$outputDirectory") $archive 'file_id.diz'
        $output = Join-Path $outputDirectory 'file_id.diz'
        if ($LASTEXITCODE -ne 0 -or !(Test-Path $output) -or ![Linq.Enumerable]::SequenceEqual[byte]($payload, [IO.File]::ReadAllBytes($output))) {
            throw 'Native LHA extraction failed to restore exact contents.'
        }
        Remove-Item -LiteralPath $output
    }
    'PASS LHA and LZH creation/extraction with Mystic flags, spaced paths and exact content checks'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
