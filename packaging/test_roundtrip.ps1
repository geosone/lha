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

        # Mystic may pass the absolute path of the file to pack. With -i the
        # archive must hold the bare name: extracting it without -i must not
        # create any directory.
        $absolute = Join-Path $work ('absolute.' + $extension)
        & $Executable -a -i $absolute $inputFile
        if ($LASTEXITCODE -ne 0) {
            throw 'Native LHA creation from an absolute path failed.'
        }
        $flat = Join-Path $work 'flat output'
        $null = New-Item -ItemType Directory $flat
        & $Executable ("-efw=$flat") $absolute
        $entries = @(Get-ChildItem -LiteralPath $flat -Recurse)
        if ($LASTEXITCODE -ne 0 -or $entries.Count -ne 1 -or $entries[0].Name -ne 'file_id.diz' -or
            ![Linq.Enumerable]::SequenceEqual[byte]($payload, [IO.File]::ReadAllBytes($entries[0].FullName))) {
            throw 'LHA -a -i stored a directory path.'
        }
        Remove-Item -LiteralPath $flat -Recurse

        # Mystic packs QWK packets with a quoted "dir/*" that no shell
        # expands; lha must expand it and store both bare names.
        $wildcard = Join-Path $work ('wildcard.' + $extension)
        $pattern = Join-Path $inputDirectory '*'
        & $Executable -a -i $wildcard $pattern
        if ($LASTEXITCODE -ne 0) {
            throw 'Native LHA creation from a wildcard failed.'
        }
        $null = New-Item -ItemType Directory $flat
        & $Executable ("-efw=$flat") $wildcard
        $names = @(Get-ChildItem -LiteralPath $flat -Recurse | ForEach-Object { $_.Name } | Sort-Object)
        if ($LASTEXITCODE -ne 0 -or ($names -join '|') -ne 'file_id.diz|release notes.txt') {
            throw "LHA did not expand the wildcard into bare names: $($names -join '|')"
        }
        Remove-Item -LiteralPath $flat -Recurse
    }
    'PASS LHA and LZH creation/extraction with Mystic flags, spaced paths, bare -i member names, wildcard arguments and exact content checks'
} finally {
    Remove-Item -LiteralPath $work -Recurse -Force
}
