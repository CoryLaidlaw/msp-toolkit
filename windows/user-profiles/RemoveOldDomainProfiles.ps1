<#
.SYNOPSIS
    Finds domain-linked local profiles whose ProfileList last-load time is older than N days and removes them via CIM.
.DESCRIPTION
    Uses HKLM ProfileList (SID length > 20) and LocalProfileLoadTime high/low as an approximate last-use signal, lists
    matches, then prompts Y/N before Remove-CimInstance on Win32_UserProfile. Intended for elevated admin or
    LocalSystem. Does not remove Entra-only or local accounts without domain-style SIDs in that key. Operator input
    is prompt-only (no script parameters).
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ReadHostYes {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $response = Read-Host -Prompt $Prompt
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $false
    }
    return ($response.Trim() -match '^(?i:y|yes)$')
}

function Read-PositiveDays {
    do {
        $raw = Read-Host -Prompt 'Delete profiles with last logon older than how many days? (positive integer, e.g. 90)'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            Write-Warning 'Enter a whole number of days.'
            continue
        }

        $days = 0
        if (-not [int]::TryParse($raw.Trim(), [ref]$days)) {
            Write-Warning 'Enter a whole number of days.'
            continue
        }

        if ($days -lt 1) {
            Write-Warning 'Days must be at least 1.'
            continue
        }

        if ($days -gt 36500) {
            Write-Warning 'Days is unreasonably large; enter a smaller value.'
            continue
        }

        return $days
    } while ($true)
}

function Get-DomainProfiles {
    Get-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\ProfileList\*' |
        Where-Object { $_.PSChildName.Length -gt 20 } |
        ForEach-Object {
            $high = if ($null -ne $_.PSObject.Properties['LocalProfileLoadTimeHigh']) { $_.LocalProfileLoadTimeHigh } else { 0 }
            $low  = if ($null -ne $_.PSObject.Properties['LocalProfileLoadTimeLow'])  { $_.LocalProfileLoadTimeLow  } else { 0 }
            $time = [datetime]::FromFileTime(([long]$high -shl 32) -bor ([long]$low -band [long]0xFFFFFFFF))
            [pscustomobject]@{
                SID = $_.PSChildName
                ProfilePath = $_.ProfileImagePath
                LastLogon = $time
            }
        }
}

function Remove-OldDomainProfiles {
    param(
        [Parameter(Mandatory)]
        [int]$Days
    )

    $cutoff = (Get-Date).AddDays(-$Days)
    $targets = @(Get-DomainProfiles | Where-Object { $_.LastLogon -lt $cutoff } | Sort-Object LastLogon)

    if ($targets.Count -eq 0) {
        Write-Host "No profiles found older than $Days days." -ForegroundColor Green
        return
    }

    Write-Host ""
    Write-Host "Profiles flagged for deletion (last logon older than $Days days):`n" -ForegroundColor Yellow
    $targets | Format-Table -Property ProfilePath, LastLogon -AutoSize

    if (-not (Test-ReadHostYes -Prompt "Delete these $($targets.Count) profile(s)? (Y/N)")) {
        Write-Host 'Cancelled. No profiles were deleted.' -ForegroundColor Cyan
        return
    }

    $total = $targets.Count
    $index = 0

    foreach ($profile in $targets) {
        $index++
        Write-Progress -Activity 'Deleting Profiles' -Status "($index of $total) $($profile.ProfilePath)" -PercentComplete (($index / $total) * 100)
        try {
            $cimProfile = Get-CimInstance -ClassName Win32_UserProfile -Filter "SID='$($profile.SID)'"
            if ($cimProfile) {
                $cimProfile | Remove-CimInstance
                Write-Host "Deleted: $($profile.ProfilePath)" -ForegroundColor Green
            }
            else {
                Write-Host "CIM profile not found for: $($profile.ProfilePath) — skipping" -ForegroundColor DarkYellow
            }
        }
        catch {
            Write-Host "Failed to delete $($profile.ProfilePath): $_" -ForegroundColor Red
        }
    }

    Write-Progress -Activity 'Deleting Profiles' -Completed
    Write-Host ""
    Write-Host 'Done.' -ForegroundColor Green
}

function Invoke-Main {
    $days = Read-PositiveDays
    Remove-OldDomainProfiles -Days $days
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
