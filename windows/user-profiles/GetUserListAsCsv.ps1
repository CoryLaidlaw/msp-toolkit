<#
.SYNOPSIS
    Exports local domain profile inventory and unresolved profiles to CSV.
.DESCRIPTION
    Prompts for domain short name, enumerates local non-special user profiles, resolves SID-to-account
    mappings, and writes matched and unresolved results to C:\Temp CSV files. Designed for one-paste
    execution with concise success/error outcomes.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-RequiredInput {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt
    )

    do {
        $value = Read-Host -Prompt $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -Path $tempPath)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }
}

function Invoke-Main {
    $targetDomain = Read-RequiredInput -Prompt 'Enter domain short name (example: CONTOSO, no .local/.com)'
    $targetDomain = $targetDomain.ToUpperInvariant()

    Ensure-TempDirectory

    $matchedProfiles = @()
    $unresolvedProfiles = @()

    $profiles = Get-WmiObject Win32_UserProfile | Where-Object {
        -not $_.Special -and $_.LocalPath -like 'C:\Users\*' -and $_.SID -like 'S-1-5-21*'
    }

    foreach ($profile in $profiles) {
        try {
            $user = New-Object System.Security.Principal.SecurityIdentifier($profile.SID)
            $account = $user.Translate([System.Security.Principal.NTAccount]).Value
            $parts = $account -split '\\'

            if ($parts.Count -eq 2 -and $parts[0].ToUpperInvariant() -eq $targetDomain) {
                $matchedProfiles += [PSCustomObject]@{
                    Domain      = $parts[0]
                    Username    = $parts[1]
                    AccountName = $account
                    ProfilePath = $profile.LocalPath
                }
            }
        }
        catch {
            $userFolder = Split-Path $profile.LocalPath -Leaf
            $unresolvedProfiles += [PSCustomObject]@{
                Domain      = 'UNKNOWN'
                Username    = $userFolder
                AccountName = 'UNRESOLVED'
                ProfilePath = $profile.LocalPath
            }
        }
    }

    $matchedPath = 'C:\Temp\DomainUserProfiles.csv'
    $unresolvedPath = 'C:\Temp\DisabledUsers.csv'

    $matchedProfiles | Export-Csv -Path $matchedPath -NoTypeInformation
    $unresolvedProfiles | Export-Csv -Path $unresolvedPath -NoTypeInformation

    Write-Output "[SUCCESS] Exported $($matchedProfiles.Count) domain profiles for '$targetDomain' to $matchedPath"
    Write-Output "[SUCCESS] Exported $($unresolvedProfiles.Count) unresolved profiles to $unresolvedPath"
    return 0
}

try {
    $statusCode = Invoke-Main
    if ($statusCode -ne 0) {
        Write-Error "[ERROR] GetUserListAsCsv completed with status code $statusCode."
        return
    }
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    return
}
