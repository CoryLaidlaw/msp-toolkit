<#
.SYNOPSIS
    Scans the Application event log for crash-looping Windows processes.
.DESCRIPTION
    Queries Application event log ID 1000 (application error) within a rolling look-back
    window and groups results by faulting application name (from event Properties[0]).
    Reports OK (no crashes), WARN (below threshold), or CRASH LOOP (at or above threshold)
    for each affected process, with crash rate and timing detail. Read-only; no changes
    are made to the system. Runs as LocalSystem or elevated admin without non-default
    module dependencies.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Invoke-Main {
    $windowMinutes = Read-PositiveInt -Prompt 'Look-back window in minutes'          -Default 60
    $threshold     = Read-PositiveInt -Prompt 'Crash count threshold for CRASH LOOP' -Default 5

    $cutoff = (Get-Date).AddMinutes(-$windowMinutes)
    Write-Host ''
    Write-Host "Scanning Application event log (last $windowMinutes minutes, threshold: $threshold)..." -ForegroundColor Cyan

    $crashEvents = @(Get-WinEvent -FilterHashtable @{
        LogName   = 'Application'
        Id        = 1000
        StartTime = $cutoff
    } -ErrorAction SilentlyContinue)

    if ($crashEvents.Count -eq 0) {
        Write-Host "OK — No application crashes detected in the last $windowMinutes minutes." -ForegroundColor Green
        return
    }

    $grouped = $crashEvents |
        Group-Object {
            if ($_.Properties.Count -gt 0) {
                $n = [string]$_.Properties[0].Value
                if (-not [string]::IsNullOrWhiteSpace($n)) { $n.Trim() } else { '(unknown)' }
            } else { '(unknown)' }
        } |
        Sort-Object Count -Descending

    $loopCount = 0
    $warnCount = 0

    foreach ($group in $grouped) {
        $appName    = $group.Name
        $count      = $group.Count
        $appCrashes = @($group.Group | Sort-Object TimeCreated)

        if ($count -lt $threshold) {
            $warnCount++
            Write-Host "WARN — $appName : $count crash(es) in the last $windowMinutes minutes (threshold: $threshold)." -ForegroundColor Yellow
        } else {
            $loopCount++
            $oldest   = ($appCrashes | Select-Object -First 1).TimeCreated
            $newest   = ($appCrashes | Select-Object -Last 1).TimeCreated
            $spanSecs = [math]::Round(($newest - $oldest).TotalSeconds)
            $rate     = if ($spanSecs -gt 0) { [math]::Round($count / ($spanSecs / 60), 1) } else { 'N/A' }

            Write-Host ''
            Write-Host '*** CRASH LOOP DETECTED ***'                                          -ForegroundColor Red
            Write-Host "  Process   : $appName"                                               -ForegroundColor Red
            Write-Host "  Crashes   : $count in the last $windowMinutes minutes"              -ForegroundColor Red
            Write-Host "  Time span : ${spanSecs} seconds"                                    -ForegroundColor Red
            Write-Host "  Rate      : ~${rate} crashes/min"                                   -ForegroundColor Red
            Write-Host ''
            Write-Host '  Recent crash timestamps:' -ForegroundColor Yellow
            $appCrashes | Select-Object -Last 10 | Sort-Object TimeCreated -Descending | ForEach-Object {
                Write-Host "    $($_.TimeCreated.ToString('HH:mm:ss'))" -ForegroundColor Yellow
            }
        }
    }

    Write-Host ''
    if ($loopCount -gt 0) {
        Write-Host "Summary: $loopCount process(es) in CRASH LOOP, $warnCount in WARN state." -ForegroundColor Red
    } else {
        Write-Host "Summary: No crash loops detected. $warnCount process(es) with below-threshold crashes." -ForegroundColor Yellow
    }
}

try {
    Invoke-Main
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
