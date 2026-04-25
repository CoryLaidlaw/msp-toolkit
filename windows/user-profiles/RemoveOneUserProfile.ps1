<#
.SYNOPSIS
    Removes one local user profile selected by prompt input.
.DESCRIPTION
    Prompts for username and profile path, validates that the path is under C:\Users, then
    deletes the matching Win32_UserProfile entry. Emits deterministic success/not-found/error
    outcomes and prints C: free-space status at completion.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Status {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    Write-Output "[INFO] $Message"
}

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

function Show-FreeSpace {
    $drive = Get-PSDrive C
    Write-Output "Free: $([math]::Round($drive.Free / 1GB, 2)) GB ($([math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2))%)"
}

function Invoke-Main {
    $username = Read-RequiredInput -Prompt 'Enter the username for the profile to remove'
    $profilePath = Read-RequiredInput -Prompt 'Enter the full profile path (example: C:\Users\Username)'

    if ($profilePath -notlike 'C:\Users\*') {
        throw "Profile path must be under C:\Users."
    }

    Write-Status "Attempting to remove profile for user '$username' at path '$profilePath'."

    $matchingProfiles = Get-WmiObject Win32_UserProfile | Where-Object { $_.LocalPath -eq $profilePath }

    if ($null -eq $matchingProfiles -or $matchingProfiles.Count -eq 0) {
        Write-Output "[WARN] No profile was found at path '$profilePath'."
        Show-FreeSpace
        exit 1
    }

    foreach ($profile in $matchingProfiles) {
        $null = $profile.Delete()
        Write-Output "[SUCCESS] Profile for '$username' removed successfully."
    }

    Write-Output '[SUCCESS] RemoveOneUserProfile.ps1 completed successfully.'
    Show-FreeSpace
    return 0
}

try {
    $code = Invoke-Main
    exit $code
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    Show-FreeSpace
    exit 1
}
