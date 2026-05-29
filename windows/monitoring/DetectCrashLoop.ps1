<#
.SYNOPSIS
    Detects crash loops for any Windows application by querying the Application event log.
.DESCRIPTION
    Prompts for a process name, look-back window in minutes, and a crash-count threshold.
    Queries Application event log IDs 1000 (application error) and 1026 (.NET runtime error)
    for events matching the process name within the window.
    Outputs OK (no crashes), WARN (below threshold), or CRASH LOOP (at or above threshold)
    with rate and timing detail. Read-only; no changes are made to the system.
    Runs as LocalSystem or elevated admin without non-default module dependencies.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-NonEmptyInput {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    do {
        $value = Read-Host -Prompt $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-PositiveInt {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [int]$Default
    )

    while ($true) {
        $raw = Read-Host -Prompt "$Prompt [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }
        $parsed = 0
        if ([int]::TryParse($raw.Trim(), [ref]$parsed) -and $parsed -gt 0) {
            return $parsed
        }
        Write-Host '  Enter a positive whole number.' -ForegroundColor Yellow
    }
}

function Get-AppCrashEvent {
    param(
        [Parameter(Mandatory)]
        [string]$ProcessName,
        [Parameter(Mandatory)]
        [datetime]$Cutoff
    )

    $raw = Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        Id        = @(1000, 1026)
        StartTime = $Cutoff
    } -ErrorAction SilentlyContinue

    return @($raw | Where-Object { $_.Message -match [regex]::Escape($ProcessName) })
}

function Invoke-Main {
    $processName   = Read-NonEmptyInput -Prompt 'Process name to check (e.g. MyApp.exe)'
    $windowMinutes = Read-PositiveInt   -Prompt 'Look-back window in minutes'            -Default 10
    $threshold     = Read-PositiveInt   -Prompt 'Crash count threshold for CRASH LOOP'   -Default 5

    $cutoff      = (Get-Date).AddMinutes(-$windowMinutes)
    $events      = Get-AppCrashEvent -ProcessName $processName -Cutoff $cutoff
    $crashEvents = @($events | Where-Object { $_.Id -eq 1000 })
    $crashCount  = $crashEvents.Count

    if ($crashCount -eq 0) {
        Write-Host "OK — No crashes detected for '$processName' in the last $windowMinutes minutes." -ForegroundColor Green
    }
    elseif ($crashCount -lt $threshold) {
        Write-Host "WARN — $crashCount crash(es) detected in the last $windowMinutes minutes (threshold: $threshold). Watch this." -ForegroundColor Yellow
        $events | Sort-Object TimeCreated -Descending | Select-Object TimeCreated, Id, Message -First 10
    }
    else {
        $sorted   = $crashEvents | Sort-Object TimeCreated
        $oldest   = ($sorted | Select-Object -First 1).TimeCreated
        $newest   = ($sorted | Select-Object -Last 1).TimeCreated
        $spanSecs = [math]::Round(($newest - $oldest).TotalSeconds)
        $rate     = if ($spanSecs -gt 0) { [math]::Round($crashCount / ($spanSecs / 60), 1) } else { 'N/A' }

        Write-Host ''
        Write-Host '*** CRASH LOOP DETECTED ***' -ForegroundColor Red
        Write-Host "  Process   : $processName"                                      -ForegroundColor Red
        Write-Host "  Crashes   : $crashCount in the last $windowMinutes minutes"    -ForegroundColor Red
        Write-Host "  Time span : ${spanSecs} seconds"                               -ForegroundColor Red
        Write-Host "  Rate      : ~${rate} crashes/min"                              -ForegroundColor Red
        Write-Host ''
        Write-Host 'Recent crash timestamps:' -ForegroundColor Yellow
        $sorted | Select-Object -Last 10 | Sort-Object TimeCreated -Descending | ForEach-Object {
            Write-Host "  $($_.TimeCreated.ToString('HH:mm:ss'))" -ForegroundColor Yellow
        }
    }
}

try {
    Invoke-Main
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
