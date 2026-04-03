<#
.SYNOPSIS
    Deploys the EasyHoney modlet to a local 7 Days to Die dedicated server for testing.

.DESCRIPTION
    Copies the mod folder into the dedicated server's Mods directory. The script also
    supports an optional server restart and filtered log tailing for quick iteration.

    When started from PowerShell inside WSL, the script re-invokes itself through the
    Windows PowerShell host so the Windows game/server paths can be used without any
    manual path hunting.

.PARAMETER ServerPath
    Path to the 7 Days to Die dedicated server where the mod will be deployed.
    Defaults to the Steam default dedicated server path on Windows.

.PARAMETER Launch
    If specified, starts the dedicated server after a successful deployment.

.PARAMETER Restart
    If specified, stops any running 7DaysToDieServer.exe instances first and then starts
    the dedicated server after deployment.

.PARAMETER TailLog
    Follows the newest server log and prints only lines matching the log pattern.

.PARAMETER TailLogSeconds
    Number of seconds to follow the server log before returning. Defaults to 30.

.PARAMETER LogPattern
    Regex used when tailing logs. Defaults to 'EasyHoney'.

.EXAMPLE
    .\Deploy-Mod.ps1

    Deploy using the default Steam server path.

.EXAMPLE
    .\Deploy-Mod.ps1 -Restart

    Deploy and restart the local dedicated server.

.EXAMPLE
    .\Deploy-Mod.ps1 -Restart -TailLog

    Deploy, restart the local dedicated server, and then follow the mod log for a short
    functional test in-game.
#>

[CmdletBinding()]
param(
    [string]$ServerPath = "C:\Program Files (x86)\Steam\steamapps\common\7 Days To Die Dedicated Server",
    [switch]$Launch,
    [switch]$Restart,
    [switch]$TailLog,
    [ValidateRange(5, 600)]
    [int]$TailLogSeconds = 30,
    [string]$LogPattern = 'EasyHoney'
)

function Test-IsWslPowerShell {
    return $PSVersionTable.PSEdition -eq 'Core' -and
           [System.Environment]::GetEnvironmentVariable('WSL_DISTRO_NAME')
}

function Convert-ToWindowsPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    if ($Path -match '^[A-Za-z]:\\') {
        return $Path
    }

    $wslPath = Get-Command wslpath -ErrorAction SilentlyContinue
    if (-not $wslPath) {
        throw 'wslpath was not found. Install WSL path tools or pass Windows-style paths.'
    }

    return (& $wslPath.Source '-w' $Path).Trim()
}

function Invoke-WindowsSelf {
    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if (-not $windowsPowerShell) {
        throw 'powershell.exe was not found in WSL. Run this script from Windows PowerShell or install PowerShell bridging in WSL.'
    }

    $windowsScriptPath = Convert-ToWindowsPath -Path $PSCommandPath
    $relayArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $windowsScriptPath,
        '-ServerPath', (Convert-ToWindowsPath -Path $ServerPath),
        '-TailLogSeconds', $TailLogSeconds,
        '-LogPattern', $LogPattern
    )

    if ($Launch) {
        $relayArgs += '-Launch'
    }
    if ($Restart) {
        $relayArgs += '-Restart'
    }
    if ($TailLog) {
        $relayArgs += '-TailLog'
    }

    & $windowsPowerShell.Source @relayArgs
    exit $LASTEXITCODE
}

if (Test-IsWslPowerShell) {
    Invoke-WindowsSelf
}

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
function Write-Step  { param([string]$Msg) Write-Host "`n==> $Msg" -ForegroundColor Cyan }
function Write-Ok    { param([string]$Msg) Write-Host "    [OK]  $Msg" -ForegroundColor Green }
function Write-Fail  { param([string]$Msg) Write-Host "    [ERR] $Msg" -ForegroundColor Red }
function Write-Warn  { param([string]$Msg) Write-Host "    [WARN] $Msg" -ForegroundColor Yellow }

function Get-SteamRoots {
    $roots = New-Object System.Collections.Generic.List[string]

    foreach ($candidate in @(
        'C:\Program Files (x86)\Steam',
        'C:\Program Files\Steam'
    )) {
        if (Test-Path $candidate) {
            [void]$roots.Add($candidate)
        }
    }

    try {
        $registrySteamPath = (Get-ItemProperty -Path 'HKCU:\Software\Valve\Steam' -ErrorAction Stop).SteamPath
        if ($registrySteamPath) {
            $normalizedPath = $registrySteamPath -replace '/', '\\'
            if (Test-Path $normalizedPath) {
                [void]$roots.Add($normalizedPath)
            }
        }
    }
    catch {
    }

    return $roots | Select-Object -Unique
}

function Get-SteamLibraryRoots {
    $libraries = New-Object System.Collections.Generic.List[string]

    foreach ($steamRoot in Get-SteamRoots) {
        [void]$libraries.Add($steamRoot)

        $libraryFile = Join-Path $steamRoot 'steamapps\libraryfolders.vdf'
        if (-not (Test-Path $libraryFile)) {
            continue
        }

        foreach ($line in Get-Content -Path $libraryFile -ErrorAction SilentlyContinue) {
            if ($line -match '"path"\s+"([^"]+)"') {
                $libraryPath = $matches[1] -replace '\\\\', '\'
                if (Test-Path $libraryPath) {
                    [void]$libraries.Add($libraryPath)
                }
            }
        }
    }

    return $libraries | Select-Object -Unique
}

function Resolve-SteamAppInstallPath {
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$FallbackPath
    )

    foreach ($libraryRoot in Get-SteamLibraryRoots) {
        $manifestPath = Join-Path $libraryRoot "steamapps\appmanifest_$AppId.acf"
        if (-not (Test-Path $manifestPath)) {
            continue
        }

        $installDir = $null
        foreach ($line in Get-Content -Path $manifestPath -ErrorAction SilentlyContinue) {
            if ($line -match '"installdir"\s+"([^"]+)"') {
                $installDir = $matches[1]
                break
            }
        }

        if (-not $installDir) {
            continue
        }

        $candidate = Join-Path $libraryRoot (Join-Path 'steamapps\common' $installDir)
        if (Test-Path $candidate) {
            return $candidate
        }
    }

    return $FallbackPath
}

function Get-ServerProcesses {
    param([Parameter(Mandatory = $true)][string]$ServerExePath)

    $normalizedServerExePath = [System.IO.Path]::GetFullPath($ServerExePath)
    $processes = @(Get-CimInstance Win32_Process -Filter "Name='7DaysToDieServer.exe'" -ErrorAction SilentlyContinue)
    $exactMatches = @(
        $processes | Where-Object {
            $_.ExecutablePath -and
            [string]::Equals(
                [System.IO.Path]::GetFullPath($_.ExecutablePath),
                $normalizedServerExePath,
                [System.StringComparison]::OrdinalIgnoreCase)
        }
    )

    if ($exactMatches.Count -gt 0) {
        return $exactMatches
    }

    return @(
        Get-Process -Name '7DaysToDieServer' -ErrorAction SilentlyContinue |
            Where-Object {
                -not $_.Path -or
                [string]::Equals(
                    [System.IO.Path]::GetFullPath($_.Path),
                    $normalizedServerExePath,
                    [System.StringComparison]::OrdinalIgnoreCase)
            }
    )
}

function Stop-DedicatedServer {
    param([Parameter(Mandatory = $true)][string]$ServerExePath)

    $processes = @(Get-ServerProcesses -ServerExePath $ServerExePath)
    if ($processes.Count -eq 0) {
        Write-Ok 'No running dedicated server process found.'
        return
    }

    foreach ($process in $processes) {
        Write-Host "    Stopping PID $($process.ProcessId): $($process.ExecutablePath)"
        Stop-Process -Id $process.ProcessId -Force
    }

    Start-Sleep -Seconds 2
    Write-Ok 'Dedicated server stopped.'
}

function Get-ServerLogFiles {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $files = New-Object System.Collections.Generic.List[object]

    $candidateDirectories = @(
        $ServerPath,
        (Join-Path $ServerPath '7DaysToDieServer_Data'),
        (Join-Path $env:APPDATA '7DaysToDie\logs')
    )

    foreach ($directory in $candidateDirectories) {
        if (-not [string]::IsNullOrWhiteSpace($directory) -and (Test-Path $directory)) {
            Get-ChildItem -Path $directory -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'output_log|Player|server|log' } |
                ForEach-Object {
                    $priority = 4
                    if ($_.Name -match '^output_log_dedi') {
                        $priority = 0
                    } elseif ($_.DirectoryName -eq $ServerPath) {
                        $priority = 1
                    } elseif ($_.DirectoryName -like '*7DaysToDieServer_Data*') {
                        $priority = 2
                    } elseif ($_.Name -match 'dedi|dedicated|server') {
                        $priority = 3
                    } elseif ($_.Name -match 'launcher') {
                        $priority = 5
                    } elseif ($_.Name -match 'client') {
                        $priority = 6
                    }

                    $isFresh = $_.LastWriteTime -ge $NotBefore
                    [void]$files.Add([pscustomobject]@{
                        FileInfo = $_
                        Priority = $priority
                        IsFresh  = $isFresh
                    })
                }
        }
    }

    $freshFiles = $files | Where-Object { $_.IsFresh }
    if ($freshFiles) {
        return $freshFiles |
            Sort-Object -Property Priority, @{ Expression = { $_.FileInfo.LastWriteTime }; Descending = $true }, @{ Expression = { $_.FileInfo.FullName }; Descending = $false } |
            ForEach-Object { $_.FileInfo }
    }

    return $files |
        Sort-Object -Property Priority, @{ Expression = { $_.FileInfo.LastWriteTime }; Descending = $true }, @{ Expression = { $_.FileInfo.FullName }; Descending = $false } |
        ForEach-Object { $_.FileInfo }
}

function Resolve-ServerLauncher {
    param([Parameter(Mandatory = $true)][string]$ServerPath)

    $launchers = @(
        (Join-Path $ServerPath 'StartDedicatedServer.bat'),
        (Join-Path $ServerPath 'startdedicated.bat'),
        (Join-Path $ServerPath '7DaysToDieServer.exe')
    )

    return $launchers | Where-Object { Test-Path $_ } | Select-Object -First 1
}

function Get-LatestServerLogFile {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    return Get-ServerLogFiles -ServerPath $ServerPath -NotBefore $NotBefore | Select-Object -First 1
}

function Follow-ServerLog {
    param(
        [Parameter(Mandatory = $true)][string]$ServerPath,
        [Parameter(Mandatory = $true)][string]$Pattern,
        [Parameter(Mandatory = $true)][int]$DurationSeconds,
        [datetime]$NotBefore = [datetime]::MinValue
    )

    $logFile = Get-LatestServerLogFile -ServerPath $ServerPath -NotBefore $NotBefore
    if (-not $logFile) {
        Write-Warn 'No server log file was found to follow.'
        return
    }

    Write-Step 'Following server log'
    Write-Host "    File: $($logFile.FullName)"
    Write-Host "    Filter: $Pattern"
    Write-Host "    Duration: $DurationSeconds seconds"

    foreach ($line in Get-Content -Path $logFile.FullName -Tail 20 -ErrorAction SilentlyContinue) {
        if ($line -match $Pattern) {
            Write-Host $line
        }
    }

    $deadline = (Get-Date).AddSeconds($DurationSeconds)
    $stream = [System.IO.File]::Open($logFile.FullName, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::ReadWrite)

    try {
        $reader = New-Object System.IO.StreamReader($stream)
        [void]$stream.Seek(0, [System.IO.SeekOrigin]::End)

        while ((Get-Date) -lt $deadline) {
            while (-not $reader.EndOfStream) {
                $line = $reader.ReadLine()
                if ($line -match $Pattern) {
                    Write-Host $line
                }
            }

            Start-Sleep -Milliseconds 500
        }
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }

    Write-Ok "Stopped log tail after $DurationSeconds seconds."
}

if ($Restart) {
    $Launch = $true
}

$ServerLaunchTime = [datetime]::MinValue

# ---------------------------------------------------------------------------
# Step 1 – Validate prerequisites
# ---------------------------------------------------------------------------
Write-Step 'Checking prerequisites'

$ResolvedServerPath = Resolve-SteamAppInstallPath -AppId '294420' -FallbackPath $ServerPath
if (-not [string]::Equals($ResolvedServerPath, $ServerPath, [System.StringComparison]::OrdinalIgnoreCase)) {
    Write-Ok "Auto-detected server path: $ResolvedServerPath"
    $ServerPath = $ResolvedServerPath
}

if (-not (Test-Path $ServerPath)) {
    Write-Fail "Dedicated server path not found: $ServerPath"
    Write-Fail 'Set -ServerPath to your 7 Days to Die dedicated server installation.'
    exit 1
}
Write-Ok "Server path: $ServerPath"

$ServerExe = Join-Path $ServerPath '7DaysToDieServer.exe'
$ServerLauncher = Resolve-ServerLauncher -ServerPath $ServerPath
if (($Launch -or $Restart) -and -not $ServerLauncher) {
    Write-Fail "No dedicated server launcher found in: $ServerPath"
    exit 1
}

if (($Launch -or $Restart) -and -not (Test-Path $ServerExe)) {
    Write-Fail "Server executable not found: $ServerExe"
    exit 1
}

# ---------------------------------------------------------------------------
# Step 2 – Deploy to dedicated server
# ---------------------------------------------------------------------------
Write-Step 'Deploying mod to dedicated server'

$ModName   = 'EasyHoney'
$SourceDir = $PSScriptRoot
$DestDir   = Join-Path $ServerPath "Mods\$ModName"

if (Test-Path $DestDir) {
    Write-Host "    Removing existing mod folder: $DestDir"
    Remove-Item $DestDir -Recurse -Force
}
New-Item -ItemType Directory -Path $DestDir | Out-Null

$ItemsToCopy = @(
    'ModInfo.xml',
    'Config'
)

foreach ($item in $ItemsToCopy) {
    $source = Join-Path $SourceDir $item
    if (-not (Test-Path $source)) {
        Write-Fail "Expected file/folder not found: $source"
        exit 1
    }

    Copy-Item -Path $source -Destination $DestDir -Recurse -Force
    Write-Ok "Copied: $item"
}

Write-Ok "Mod deployed to: $DestDir"

# ---------------------------------------------------------------------------
# Step 3 – (Optional) Restart or launch dedicated server
# ---------------------------------------------------------------------------
if ($Restart) {
    Write-Step 'Restarting dedicated server'
    Stop-DedicatedServer -ServerExePath $ServerExe
}

if ($Launch) {
    Write-Step 'Launching dedicated server'
    Write-Host "    Starting: $ServerLauncher"
    $ServerLaunchTime = Get-Date
    if ($ServerLauncher.EndsWith('.bat', [System.StringComparison]::OrdinalIgnoreCase)) {
        $startedProcess = Start-Process -FilePath 'cmd.exe' -ArgumentList @('/k', $ServerLauncher) -WorkingDirectory $ServerPath -PassThru
    } else {
        $startedProcess = Start-Process -FilePath $ServerLauncher -WorkingDirectory $ServerPath -PassThru
    }

    if ($startedProcess) {
        Write-Ok "Dedicated server launcher started (PID $($startedProcess.Id))."
    } else {
        Write-Ok 'Dedicated server started.'
    }
} else {
    Write-Host "`n    To start the server manually, run:" -ForegroundColor Yellow
    Write-Host "    & `"$ServerLauncher`"" -ForegroundColor Yellow
}

# ---------------------------------------------------------------------------
# Step 4 – (Optional) Log follow
# ---------------------------------------------------------------------------
if ($TailLog) {
    Follow-ServerLog -ServerPath $ServerPath -Pattern $LogPattern -DurationSeconds $TailLogSeconds -NotBefore $ServerLaunchTime
}

Write-Host "`nDone." -ForegroundColor Green
