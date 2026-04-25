# Purpose: Finds all non-service and non-local user profiles 
# on a PC and checks if they are located on the server or not.
# If they are not then that means they are old users that have
# been deleted from the server at this point. If they are on
# the server then they could be disabled users or active users. 
# Created By: Cory Laidlaw

# Replace YOURDOMAINHERE with the domain name (do not include .local, .com, ect)
$targetDomain = "DOMAIN"

# Initializes empty arrays to store users
$matchedProfiles = @()
$unresolvedProfiles = @()

$profiles = Get-WmiObject Win32_UserProfile | Where-Object {
    -not $_.Special -and $_.LocalPath -like "C:\Users\*" -and $_.SID -like "S-1-5-21*"
}

# This does the actual comparison work to generate two arrays of users
foreach ($profile in $profiles) {
    try {
        $user = New-Object System.Security.Principal.SecurityIdentifier($profile.SID)
        $account = $user.Translate([System.Security.Principal.NTAccount]).Value  # e.g., DOMAIN\User
        $parts = $account -split '\\'

        if ($parts.Count -eq 2 -and $parts[0].ToUpper() -eq $targetDomain.ToUpper()) {
            $matchedProfiles += [PSCustomObject]@{
                Domain      = $parts[0]
                Username    = $parts[1]
                AccountName = $account
                ProfilePath = $profile.LocalPath
            }
        }
    } catch {
        $userFolder = Split-Path $profile.LocalPath -Leaf
        $unresolvedProfiles += [PSCustomObject]@{
            Domain      = "UNKNOWN"
            Username    = $userFolder
            AccountName = "UNRESOLVED"
            ProfilePath = $profile.LocalPath
        }
    }
}

# Exports arrays as seperate CSVs in C:\Temp
$matchedProfiles | Export-Csv -Path "C:\Temp\DomainUserProfiles.csv" -NoTypeInformation
$unresolvedProfiles | Export-Csv -Path "C:\Temp\DisabledUsers.csv" -NoTypeInformation

# Output to console to indicate completion
Write-Output "Exported profiles for domain '$targetDomain' to DomainUserProfiles.csv"
Write-Output "Exported unresolved profiles to DisabledUsers.csv"
