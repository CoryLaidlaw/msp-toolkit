<#
.SYNOPSIS
    Classifies exported domain users as disabled/unresolved and writes DisabledUsers.csv.
.DESCRIPTION
    Validates input CSV and AD cmdlet availability, checks each user with Get-ADUser, and exports
    disabled or unresolved users to C:\Temp\DisabledUsers.csv. Emits per-user status plus a final
    summary for enabled/disabled/not-found/skipped results.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -Path $tempPath)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }
}

function Invoke-Main {
    Ensure-TempDirectory

    $csvPath = 'C:\Temp\DomainUserProfiles.csv'
    $outputPath = 'C:\Temp\DisabledUsers.csv'

    if (-not (Test-Path -Path $csvPath)) {
        throw "Input CSV file not found: $csvPath"
    }

    if (-not (Get-Command -Name Get-ADUser -ErrorAction SilentlyContinue)) {
        throw "Get-ADUser is unavailable. This script requires Active Directory cmdlets in the runtime session."
    }

    $users = Import-Csv -Path $csvPath
    if ($null -eq $users -or $users.Count -eq 0) {
        throw "Input CSV contains no rows: $csvPath"
    }

    $disabledUsers = @()
    $enabledCount = 0
    $disabledCount = 0
    $notFoundCount = 0
    $skippedCount = 0

    foreach ($user in $users) {
        $samAccountName = $user.Username

        if ([string]::IsNullOrWhiteSpace($samAccountName)) {
            Write-Output '[WARN] Skipping row with empty Username.'
            $skippedCount++
            continue
        }

        $safeSamAccountName = $samAccountName -replace "'", "''"
        $adUser = Get-ADUser -Filter "SamAccountName -eq '$safeSamAccountName'" -Properties DistinguishedName, Enabled -ErrorAction Stop

        if ($null -eq $adUser) {
            Write-Output "[WARN] User '$samAccountName' could not be found in AD. Adding to Disabled Users list."
            $disabledUsers += $user
            $notFoundCount++
            continue
        }

        $ou = ''
        if (-not [string]::IsNullOrWhiteSpace($adUser.DistinguishedName)) {
            $ou = ($adUser.DistinguishedName -split ',', 2)[1]
        }

        if (-not $adUser.Enabled) {
            if (-not [string]::IsNullOrWhiteSpace($ou) -and $ou -notlike '*OU=Disabled Users,*') {
                Write-Output "[INFO] User '$samAccountName' is DISABLED. OU: $ou"
            }
            else {
                Write-Output "[INFO] User '$samAccountName' is DISABLED."
            }

            $disabledUsers += $user
            $disabledCount++
        }
        else {
            Write-Output "[INFO] User '$samAccountName' is ENABLED."
            $enabledCount++
        }
    }

    $disabledUsers | Export-Csv -Path $outputPath -NoTypeInformation
    Write-Output "[SUCCESS] Exported $($disabledUsers.Count) rows to $outputPath"
    Write-Output "[INFO] Summary: Enabled=$enabledCount Disabled=$disabledCount NotFound=$notFoundCount Skipped=$skippedCount"
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    return
}
