<#
.SYNOPSIS
    Preliminary deployment script for PC/GEOS Ensemble Alpha on Windows.

.DESCRIPTION
    Downloads the latest PC/GEOS Ensemble build alongside the Basebox DOSBox fork,
    refreshes the installation under $env:USERPROFILE\geospc while preserving the
    user configuration directory, patches Ensemble's GEOS.INI so that documents and
    overrides are redirected into the user tree, and installs launch helpers that
    expose a global `pcgeos-ensemble` command.

.NOTES
    Designed for PowerShell 5.1+ on Windows. Requires built-in tooling only
    (Invoke-WebRequest and Expand-Archive).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

$GeosReleaseUrl = 'https://github.com/bluewaysw/pcgeos/releases/download/CI-latest/pcgeos-ensemble_nc.zip'
$BaseboxReleaseUrl = 'https://github.com/bluewaysw/pcgeos-basebox/releases/download/CI-latest-issue-2/pcgeos-basebox.zip'

$HomeDir = [Environment]::GetFolderPath('UserProfile')
$InstallRoot = Join-Path -Path $HomeDir -ChildPath 'geospc'
$DriveCDir = Join-Path -Path $InstallRoot -ChildPath 'drivec'
$BaseboxDir = Join-Path -Path $InstallRoot -ChildPath 'basebox'
$UserDir = Join-Path -Path $DriveCDir -ChildPath 'user'
$UserDocumentDir = Join-Path -Path $UserDir -ChildPath 'document'
$UserGeosIni = Join-Path -Path $UserDir -ChildPath 'geos.ini'
$GeosInstallDir = Join-Path -Path $DriveCDir -ChildPath 'ensemble'
$GeosIniPath = Join-Path -Path $GeosInstallDir -ChildPath 'geos.ini'
$BaseboxConfigPath = Join-Path -Path $BaseboxDir -ChildPath 'basebox-geos.conf'
$LocalLauncherPath = Join-Path -Path $BaseboxDir -ChildPath 'run-ensemble.ps1'
$GlobalLauncherDir = Join-Path -Path ([Environment]::GetFolderPath('LocalApplicationData')) -ChildPath 'Microsoft\WindowsApps'
$GlobalLauncherCmd = Join-Path -Path $GlobalLauncherDir -ChildPath 'pcgeos-ensemble.cmd'
$GlobalLauncherPs1 = Join-Path -Path $GlobalLauncherDir -ChildPath 'pcgeos-ensemble.ps1'

$PathMappings = [ordered]@{
    document = 'C:\\USER\\DOCUMENT'
}

$AdditionalIniFiles = @(
    'C:\\USER\\GEOS.INI'
)

# -----------------------------------------------------------------------------
# Helpers
# -----------------------------------------------------------------------------

function Write-Log
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Message
    )

    Write-Host "[deploy] $Message"
}

function Ensure-Directory
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    if (-not (Test-Path -Path $Path))
    {
        [void](New-Item -Path $Path -ItemType Directory -Force)
    }
}

function Download-File
{
    param (
        [Parameter(Mandatory = $true)]
        [Uri] $Uri,

        [Parameter(Mandatory = $true)]
        [string] $Destination
    )

    Write-Log "Downloading $($Uri.AbsoluteUri)"
    Invoke-WebRequest -Uri $Uri -OutFile $Destination -UseBasicParsing
}

function New-TemporaryDirectory
{
    $tempRoot = [IO.Path]::GetTempPath()
    $name = [IO.Path]::GetRandomFileName()
    $path = Join-Path -Path $tempRoot -ChildPath $name
    [void](New-Item -Path $path -ItemType Directory -Force)
    return $path
}

function Get-AbsolutePath
{
    param (
        [Parameter(Mandatory = $true)]
        [string] $Path
    )

    return (Resolve-Path -LiteralPath $Path).ProviderPath
}

function Get-BaseboxExecutable
{
    $candidates = @(
        'binnt\\basebox.exe',
        'binl64\\basebox.exe',
        'binl\\basebox.exe',
        'binmac\\basebox'
    )

    foreach ($candidate in $candidates)
    {
        $fullPath = Join-Path -Path $BaseboxDir -ChildPath $candidate
        if (Test-Path -LiteralPath $fullPath)
        {
            return $fullPath
        }
    }

    return $null
}

function Preserve-UserData
{
    Write-Log 'Preparing installation directories'

    Ensure-Directory -Path $InstallRoot
    Ensure-Directory -Path $DriveCDir
    Ensure-Directory -Path $UserDir
    Ensure-Directory -Path $UserDocumentDir

    # Remove everything under ~/geospc except the drivec folder.
    if (Test-Path -Path $InstallRoot)
    {
        $drivecAbsolute = Get-AbsolutePath -Path $DriveCDir
        Get-ChildItem -LiteralPath $InstallRoot -Force | Where-Object { $_.FullName -ne $drivecAbsolute } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }

    # Inside drivec, keep only the user directory and its contents.
    if (Test-Path -Path $DriveCDir)
    {
        $userAbsolute = Get-AbsolutePath -Path $UserDir
        Get-ChildItem -LiteralPath $DriveCDir -Force | Where-Object { $_.FullName -ne $userAbsolute } | ForEach-Object {
            Remove-Item -LiteralPath $_.FullName -Recurse -Force
        }
    }
}

function Extract-Packages
{
    $tempDir = New-TemporaryDirectory
    Write-Log "Using temporary workspace $tempDir"

    try
    {
        $geosZip = Join-Path -Path $tempDir -ChildPath 'pcgeos-ensemble.zip'
        $baseboxZip = Join-Path -Path $tempDir -ChildPath 'pcgeos-basebox.zip'

        Download-File -Uri $GeosReleaseUrl -Destination $geosZip
        Download-File -Uri $BaseboxReleaseUrl -Destination $baseboxZip

        $ensembleTemp = Join-Path -Path $tempDir -ChildPath 'ensemble'
        $baseboxTemp = Join-Path -Path $tempDir -ChildPath 'basebox'
        Ensure-Directory -Path $ensembleTemp
        Ensure-Directory -Path $baseboxTemp

        Write-Log 'Extracting Ensemble archive'
        Expand-Archive -Path $geosZip -DestinationPath $ensembleTemp -Force

        Write-Log 'Extracting Basebox archive'
        Expand-Archive -Path $baseboxZip -DestinationPath $baseboxTemp -Force

        Write-Log "Installing Ensemble into $GeosInstallDir"
        if (Test-Path -LiteralPath $GeosInstallDir)
        {
            Remove-Item -LiteralPath $GeosInstallDir -Recurse -Force
        }
        Ensure-Directory -Path $GeosInstallDir
        $ensembleSource = Join-Path -Path $ensembleTemp -ChildPath 'ensemble'
        Get-ChildItem -LiteralPath $ensembleSource -Force | ForEach-Object {
            $destination = Join-Path -Path $GeosInstallDir -ChildPath $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
        }

        Write-Log "Installing Basebox into $BaseboxDir"
        if (Test-Path -LiteralPath $BaseboxDir)
        {
            Remove-Item -LiteralPath $BaseboxDir -Recurse -Force
        }
        Ensure-Directory -Path $BaseboxDir
        $baseboxSource = Join-Path -Path $baseboxTemp -ChildPath 'pcgeos-basebox'
        Get-ChildItem -LiteralPath $baseboxSource -Force | ForEach-Object {
            $destination = Join-Path -Path $BaseboxDir -ChildPath $_.Name
            Copy-Item -LiteralPath $_.FullName -Destination $destination -Recurse -Force
        }

        $detected = Get-BaseboxExecutable
        if (-not $detected)
        {
            throw "Unable to locate the Basebox executable in $BaseboxDir"
        }

        Write-Log "Detected Basebox executable at $detected"
    }
    finally
    {
        if (Test-Path -LiteralPath $tempDir)
        {
            Remove-Item -LiteralPath $tempDir -Recurse -Force
        }
    }
}

function Ensure-UserState
{
    Ensure-Directory -Path $UserDocumentDir
    if (-not (Test-Path -LiteralPath $UserGeosIni))
    {
        Write-Log 'Creating user geos.ini placeholder'
        $header = @(
            '; User-specific GEOS settings are stored here. This file is merged via',
            '; the [paths] ini directive added by the deployment script. Feel free to',
            '; customize it without worrying about future deployments overwriting it.',
            ''
        )
        Set-Content -Path $UserGeosIni -Value $header -Encoding ASCII
    }
}

function Update-GeosIni
{
    if (-not (Test-Path -LiteralPath $GeosIniPath))
    {
        throw "Expected GEOS.INI at $GeosIniPath not found"
    }

    Write-Log 'Patching Ensemble geos.ini'

    $rawContent = Get-Content -LiteralPath $GeosIniPath -Raw -Encoding Byte
    $textContent = [System.Text.Encoding]::ASCII.GetString($rawContent)
    $newline = if ($textContent -match "`r`n") { "`r`n" } else { "`n" }

    $lines = $textContent -split "`r?`n"

    $processed = New-Object System.Collections.Generic.List[string]
    $pathsSectionSeen = $false
    $inPaths = $false
    $iniLineWritten = $false

    $mappingState = @{}
    foreach ($key in $PathMappings.Keys)
    {
        $mappingState[$key.ToLowerInvariant()] = [pscustomobject]@{
            Name    = $key
            Value   = $PathMappings[$key]
            Written = $false
        }
    }

    $addMissingPaths = {
        param (
            [System.Collections.Generic.List[string]] $Target
        )

        foreach ($entry in $mappingState.GetEnumerator())
        {
            if (-not $entry.Value.Written)
            {
                $Target.Add("{0} = {1}" -f $entry.Value.Name, $entry.Value.Value)
                $entry.Value.Written = $true
            }
        }
    }

    $writeIniLine = {
        param (
            [System.Collections.Generic.List[string]] $Target,
            [ref] $IniFlag
        )

        if ($IniFlag.Value -or $AdditionalIniFiles.Count -eq 0)
        {
            return
        }

        $unique = New-Object System.Collections.Generic.List[string]
        $seen = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($item in $AdditionalIniFiles)
        {
            if ($seen.Add($item))
            {
                $unique.Add($item)
            }
        }

        if ($unique.Count -gt 0)
        {
            $Target.Add('ini = ' + ($unique -join ' '))
            $IniFlag.Value = $true
        }
    }

    for ($i = 0; $i -lt $lines.Length; $i++)
    {
        $line = $lines[$i]

        if ($line -match '^[ \t]*\[[Pp][Aa][Tt][Hh][Ss]\][ \t]*$')
        {
            $pathsSectionSeen = $true
            $inPaths = $true
            $processed.Add($line)
            continue
        }

        if ($inPaths)
        {
            if ($line -match '^[ \t]*\[')
            {
                & $addMissingPaths $processed
                & $writeIniLine $processed ([ref]$iniLineWritten)
                $inPaths = $false
            }
            else
            {
                $assignmentPattern = '^[ \t]*([^=; \t]+)[ \t]*=[ \t]*(.*)$'
                if ($line -match $assignmentPattern)
                {
                    $keyRaw = $Matches[1]
                    $valuePart = $Matches[2]
                    $comment = ''
                    $commentIndex = $valuePart.IndexOf(';')
                    if ($commentIndex -ge 0)
                    {
                        $comment = $valuePart.Substring($commentIndex)
                        $valuePart = $valuePart.Substring(0, $commentIndex)
                    }

                    $valueTrim = $valuePart.Trim()
                    $keyLower = $keyRaw.ToLowerInvariant()

                    if ($keyLower -eq 'ini')
                    {
                        $tokens = @()
                        if ($valueTrim.Length -gt 0)
                        {
                            $tokens = $valueTrim -split '[ \t]+' | Where-Object { $_ }
                        }

                        $seenTokens = New-Object System.Collections.Generic.HashSet[string]([System.StringComparer]::OrdinalIgnoreCase)
                        $orderedTokens = New-Object System.Collections.Generic.List[string]
                        foreach ($token in $tokens)
                        {
                            if ($seenTokens.Add($token))
                            {
                                $orderedTokens.Add($token)
                            }
                        }

                        foreach ($extra in $AdditionalIniFiles)
                        {
                            if ($seenTokens.Add($extra))
                            {
                                $orderedTokens.Add($extra)
                            }
                        }

                        if ($orderedTokens.Count -gt 0)
                        {
                            $newlineValue = 'ini = ' + ($orderedTokens -join ' ')
                            if ($comment)
                            {
                                $newlineValue += ' ' + $comment.TrimStart()
                            }
                            $processed.Add($newlineValue)
                        }
                        elseif ($comment)
                        {
                            $processed.Add('ini = ' + $comment.TrimStart())
                        }

                        $iniLineWritten = $true
                        continue
                    }

                    if ($mappingState.ContainsKey($keyLower))
                    {
                        $entry = $mappingState[$keyLower]
                        $entry.Written = $true
                        $replacement = '{0} = {1}' -f $entry.Name, $entry.Value
                        if ($comment)
                        {
                            $replacement += ' ' + $comment.TrimStart()
                        }
                        $processed.Add($replacement)
                        continue
                    }
                }
            }
        }

        if (-not $inPaths)
        {
            $processed.Add($line)
        }
    }

    if ($inPaths)
    {
        & $addMissingPaths $processed
        & $writeIniLine $processed ([ref]$iniLineWritten)
    }
    elseif (-not $pathsSectionSeen)
    {
        if ($processed.Count -gt 0 -and $processed[$processed.Count - 1] -ne '')
        {
            $processed.Add('')
        }

        $processed.Add('[paths]')
        & $addMissingPaths $processed
        & $writeIniLine $processed ([ref]$iniLineWritten)
    }

    $output = ($processed -join $newline)
    if (-not $output.EndsWith($newline))
    {
        $output += $newline
    }

    $bytes = [System.Text.Encoding]::ASCII.GetBytes($output)
    [IO.File]::WriteAllBytes($GeosIniPath, $bytes)
}

function Write-BaseboxConfig
{
    $drivecAbsolute = Get-AbsolutePath -Path $DriveCDir
    $basebox = Get-BaseboxExecutable
    if (-not $basebox)
    {
        throw 'Unable to locate the Basebox executable for configuration generation.'
    }

    Write-Log "Generating Basebox configuration using $basebox"

    $tempConfig = [IO.Path]::GetTempFileName()
    try
    {
        $previousDriver = $env:SDL_VIDEODRIVER
        try
        {
            $env:SDL_VIDEODRIVER = 'dummy'
            & $basebox '-writeconf' $tempConfig | Out-Null
            if ($LASTEXITCODE -ne 0)
            {
                throw "Basebox exited with $LASTEXITCODE while writing configuration"
            }
        }
        catch
        {
            if ($null -eq $previousDriver)
            {
                Remove-Item Env:SDL_VIDEODRIVER -ErrorAction SilentlyContinue
            }
            else
            {
                $env:SDL_VIDEODRIVER = $previousDriver
            }

            & $basebox '-writeconf' $tempConfig | Out-Null
            if ($LASTEXITCODE -ne 0)
            {
                throw "Basebox exited with $LASTEXITCODE while writing configuration"
            }
        }
        finally
        {
            if ($null -eq $previousDriver)
            {
                Remove-Item Env:SDL_VIDEODRIVER -ErrorAction SilentlyContinue
            }
            else
            {
                $env:SDL_VIDEODRIVER = $previousDriver
            }
        }

        $raw = Get-Content -LiteralPath $tempConfig -Raw -Encoding Byte
        $text = [System.Text.Encoding]::ASCII.GetString($raw)
        $newline = if ($text -match "`r`n") { "`r`n" } else { "`n" }
        $lines = $text -split "`r?`n"

        $autoexecLines = @(
            '@echo off',
            "mount c \"$drivecAbsolute\" -t dir",
            'c:',
            'cd ensemble',
            'loader'
        )

        $output = New-Object System.Collections.Generic.List[string]
        $inAutoexec = $false

        foreach ($line in $lines)
        {
            if ([Text.RegularExpressions.Regex]::IsMatch($line, '^\s*\[autoexec\]\s*$', [Text.RegularExpressions.RegexOptions]::IgnoreCase))
            {
                $output.Add($line)
                foreach ($entry in $autoexecLines)
                {
                    $output.Add($entry)
                }
                $inAutoexec = $true
                continue
            }

            if ($inAutoexec)
            {
                if ([Text.RegularExpressions.Regex]::IsMatch($line, '^\s*\[', [Text.RegularExpressions.RegexOptions]::IgnoreCase))
                {
                    $inAutoexec = $false
                    $output.Add($line)
                }
                continue
            }

            $output.Add($line)
        }

        $final = ($output -join $newline)
        if (-not $final.EndsWith($newline))
        {
            $final += $newline
        }

        [IO.File]::WriteAllText($BaseboxConfigPath, $final, [System.Text.Encoding]::ASCII)
    }
    finally
    {
        if (Test-Path -LiteralPath $tempConfig)
        {
            Remove-Item -LiteralPath $tempConfig -Force
        }
    }
}

function Write-Launchers
{
    Write-Log "Creating Basebox launcher at $LocalLauncherPath"

    $launcherContent = @(
        'param(',
        '    [Parameter(ValueFromRemainingArguments = $true)]',
        '    [string[]] $Arguments',
        ')',
        '',
        'Set-StrictMode -Version Latest',
        '$ErrorActionPreference = ''Stop''',
        '',
        '$scriptDir = Split-Path -Parent -LiteralPath $MyInvocation.MyCommand.Path',
        '$configPath = Join-Path -Path $scriptDir -ChildPath ''basebox-geos.conf''',
        'function Get-Basebox',
        '{',
        '    $candidates = @(',
        "        'binnt\\basebox.exe',",
        "        'binl64\\basebox.exe',",
        "        'binl\\basebox.exe',",
        "        'binmac\\basebox'",
        '    )',
        '    foreach ($candidate in $candidates)',
        '    {',
        '        $path = Join-Path -Path $scriptDir -ChildPath $candidate',
        '        if (Test-Path -LiteralPath $path)',
        '        {',
        '            return $path',
        '        }',
        '    }',
        '    throw ''Unable to locate the Basebox executable.''',
        '}',
        '$basebox = Get-Basebox',
        'if (-not (Test-Path -LiteralPath $configPath))',
        '{',
        '    throw ''Missing Basebox configuration file.''',
        '}',
        '& $basebox -conf $configPath @Arguments'
    )

    Set-Content -Path $LocalLauncherPath -Value $launcherContent -Encoding ASCII

    Write-Log "Linking global launcher into $GlobalLauncherDir"
    Ensure-Directory -Path $GlobalLauncherDir

    $shimCmd = @(
        '@echo off',
        'setlocal',
        'set "launcher=%~dp0pcgeos-ensemble.ps1"',
        'powershell -NoLogo -NoProfile -ExecutionPolicy Bypass -File "%launcher%" %*'
    )

    $shimPs1 = @(
        'param(',
        '    [Parameter(ValueFromRemainingArguments = $true)]',
        '    [string[]] $Arguments',
        ')',
        ("`$launcher = Join-Path -Path '{0}' -ChildPath 'run-ensemble.ps1'" -f $BaseboxDir),
        '& $launcher @Arguments'
    )

    Set-Content -Path $GlobalLauncherCmd -Value $shimCmd -Encoding ASCII
    Set-Content -Path $GlobalLauncherPs1 -Value $shimPs1 -Encoding ASCII
}

function Invoke-Main
{
    Preserve-UserData
    Extract-Packages
    Ensure-UserState
    Update-GeosIni
    Write-BaseboxConfig
    Write-Launchers

    Write-Log "Deployment complete. Run 'pcgeos-ensemble' from any PowerShell or CMD window."
    $windowsApps = Get-AbsolutePath -Path $GlobalLauncherDir
    $pathEntries = ($env:PATH -split ';')
    if (-not ($pathEntries | Where-Object { $_ -eq $windowsApps }))
    {
        Write-Log "Note: $windowsApps is not currently on your PATH. Add it to call the launcher globally."
    }
}

Invoke-Main
