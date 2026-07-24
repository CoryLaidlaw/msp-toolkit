<#
.SYNOPSIS
    Bulk removes local user profiles listed in DisabledUsers.csv.
.DESCRIPTION
    Reads C:\Temp\DisabledUsers.csv, validates input rows, lists every profile path it is about to
    remove, requires a Y/N confirmation, then deletes matching Win32_UserProfile entries and reports
    deleted/not-found/failed/skipped counts. Intended for elevated admin or LocalSystem execution and
    prints C: free-space status when complete.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -Path $tempPath)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }
}

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

function Show-FreeSpace {
    $drive = Get-PSDrive C
    Write-Output "Free: $([math]::Round($drive.Free / 1GB, 2)) GB ($([math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2))%)"
}

function Invoke-Main {
    Ensure-TempDirectory
    $csvPath = 'C:\Temp\DisabledUsers.csv'

    if (-not (Test-Path -Path $csvPath)) {
        throw "CSV file not found: $csvPath"
    }

    $userProfiles = Import-Csv -Path $csvPath
    if ($null -eq $userProfiles -or $userProfiles.Count -eq 0) {
        throw "CSV file contains no rows: $csvPath"
    }

    $deletedCount = 0
    $notFoundCount = 0
    $failedCount = 0
    $skippedCount = 0

    $rowsToRemove = @()

    foreach ($user in $userProfiles) {
        $username = $user.Username
        if ([string]::IsNullOrWhiteSpace($username)) {
            $username = '<unknown>'
        }

        if ($null -eq $user.PSObject.Properties['ProfilePath']) {
            Write-Output "[WARN] Skipping row for '$username' because the CSV has no ProfilePath column."
            $skippedCount++
            continue
        }

        $profilePath = $user.ProfilePath

        if ([string]::IsNullOrWhiteSpace($profilePath) -or $profilePath -notlike 'C:\Users\*') {
            Write-Output "[WARN] Skipping row for '$username' due to missing/invalid ProfilePath."
            $skippedCount++
            continue
        }

        $rowsToRemove += [PSCustomObject]@{ Username = $username; ProfilePath = $profilePath }
    }

    if ($rowsToRemove.Count -eq 0) {
        Write-Output '[INFO] No valid profiles to remove after validation.'
        Write-Output "[INFO] Summary: Deleted=$deletedCount NotFound=$notFoundCount Failed=$failedCount Skipped=$skippedCount"
        return
    }

    Write-Host ""
    Write-Host "Profiles flagged for removal ($($rowsToRemove.Count)):`n" -ForegroundColor Yellow
    $rowsToRemove | Format-Table -Property Username, ProfilePath -AutoSize

    if (-not (Test-ReadHostYes -Prompt "Delete these $($rowsToRemove.Count) profile(s)? (Y/N)")) {
        Write-Host 'Cancelled. No profiles were deleted.' -ForegroundColor Cyan
        return
    }

    foreach ($row in $rowsToRemove) {
        $username = $row.Username
        $profilePath = $row.ProfilePath

        Write-Output "[INFO] Attempting to remove profile for user '$username' at path '$profilePath'."

        try {
            $matchingProfiles = Get-WmiObject Win32_UserProfile | Where-Object { $_.LocalPath -eq $profilePath }
            if ($null -eq $matchingProfiles -or $matchingProfiles.Count -eq 0) {
                Write-Output "[WARN] Profile not found for '$username' at '$profilePath'."
                $notFoundCount++
                continue
            }

            foreach ($profile in $matchingProfiles) {
                $null = $profile.Delete()
                Write-Output "[SUCCESS] Profile for '$username' removed successfully."
                $deletedCount++
            }
        }
        catch {
            Write-Output "[ERROR] Failed to remove '$username' at '$profilePath': $($_.Exception.Message)"
            $failedCount++
        }
    }

    Write-Output "[SUCCESS] RemoveMultipleUserProfile.ps1 completed."
    Write-Output "[INFO] Summary: Deleted=$deletedCount NotFound=$notFoundCount Failed=$failedCount Skipped=$skippedCount"
    Show-FreeSpace
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    Show-FreeSpace
    return
}
