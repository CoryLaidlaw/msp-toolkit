<#
.SYNOPSIS
    Exports local domain profile inventory and unresolved profiles to CSV.
.DESCRIPTION
    Prompts for the domain short name, enumerates local non-special user profiles, resolves SID-to-account
    mappings, and writes matched profiles and unresolved (SID translation failed) profiles to separate CSV
    files under C:\Temp. Unresolved profiles are NOT queued for deletion; they need manual review. It asks
    for anything it needs at the prompt and prints a clear success or error message when it finishes.
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
    $unresolvedPath = 'C:\Temp\UnresolvedProfiles.csv'

    $matchedProfiles | Export-Csv -Path $matchedPath -NoTypeInformation
    $unresolvedProfiles | Export-Csv -Path $unresolvedPath -NoTypeInformation

    Write-Output "[SUCCESS] Exported $($matchedProfiles.Count) domain profiles for '$targetDomain' to $matchedPath"
    Write-Output "[SUCCESS] Exported $($unresolvedProfiles.Count) unresolved profiles to $unresolvedPath"
    if ($unresolvedProfiles.Count -gt 0) {
        Write-Output "[NOTE] Unresolved profiles need manual review and are NOT queued for deletion by the disabled-user pipeline."
    }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    return
}
