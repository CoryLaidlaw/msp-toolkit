<#
.SYNOPSIS
    Creates or copies AD users in bulk from a CSV file.
.DESCRIPTION
    Prompts for a CSV path, defaulting to C:\Temp. Action N creates users in the row OU, and Action C copies a source
    user. Invalid rows, including missing source users or managers, are skipped with warnings. Requires ActiveDirectory RSAT.
#>

function Test-PasswordComplexity {
    param([string]$Plain)

    return $Plain.Length -ge 12 -and $Plain -match '[A-Z]' -and $Plain -match '[a-z]' -and $Plain -match '[0-9]' -and $Plain -match '[^a-zA-Z0-9]'
}

function Invoke-Main {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module is not available. Install RSAT Active Directory module first.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    $defaultCsvPath = 'C:\Temp\new-user-or-copy-template.csv'
    do {
        $csvPath = Read-Host -Prompt "CSV file path, expected format like $defaultCsvPath (Enter for default)"
        if ([string]::IsNullOrWhiteSpace($csvPath)) { $csvPath = $defaultCsvPath }
        if (-not (Test-Path -Path $csvPath)) {
            Write-Warning "CSV file '$csvPath' was not found."
            $csvPath = $null
        }
    } while (-not $csvPath)

    [int]$failed = 0
    foreach ($record in Import-Csv -Path $csvPath) {
        if ([string]::IsNullOrWhiteSpace($record.Action)) {
            Write-Warning "Action is missing for $($record.SamAccountName). Skipping."
            continue
        }
        $choice = $record.Action.ToUpper()
        $userInfo = [pscustomobject]@{
            GivenName = $record.GivenName; Surname = $record.Surname; SamAccountName = $record.SamAccountName
            Title = $record.Title; Department = $record.Department; Manager = $record.Manager
            Phone = $record.Phone; Email = $record.Email
        }

        $sourceSam = $null
        $sourceUser = $null
        if ($choice -eq 'C') {
            $sourceSam = $record.SourceSam
            if ([string]::IsNullOrWhiteSpace($sourceSam)) {
                Write-Warning "SourceSam is required for copy action for $($userInfo.SamAccountName). Skipping."
                continue
            }
            try {
                $sourceUser = Get-ADUser -Identity $sourceSam -Properties MemberOf, Title, Manager, OfficePhone, EmailAddress -ErrorAction Stop
            }
            catch {
                Write-Warning "Source user $sourceSam not found. Skipping $($userInfo.SamAccountName)."
                continue
            }
        }

        $escapedGivenName = $userInfo.GivenName -replace "'", "''"
        $escapedSurname = $userInfo.Surname -replace "'", "''"
        $nameExists = Get-ADUser -Filter "GivenName -eq '$escapedGivenName' -and Surname -eq '$escapedSurname'" -ErrorAction SilentlyContinue
        if ($nameExists) { Write-Warning "A user with first name '$($userInfo.GivenName)' and last name '$($userInfo.Surname)' already exists. Skipping."; continue }
        $escapedSam = $userInfo.SamAccountName -replace "'", "''"
        $samExists = Get-ADUser -Filter "SamAccountName -eq '$escapedSam'" -ErrorAction SilentlyContinue
        if ($samExists) { Write-Warning "Username $($userInfo.SamAccountName) already exists. Skipping."; continue }

        if ($userInfo.Manager) {
            try {
                $mgrExists = Get-ADUser -Identity $userInfo.Manager -ErrorAction Stop
            }
            catch {
                Write-Warning "Manager $($userInfo.Manager) not found. Skipping $($userInfo.SamAccountName)."
                continue
            }
        }

        if (-not (Test-PasswordComplexity $record.Password)) {
            Write-Warning "Password for $($userInfo.SamAccountName) must be at least 12 characters and include uppercase, lowercase, number, and symbol. Skipping."
            continue
        }

        $password = ConvertTo-SecureString $record.Password -AsPlainText -Force
        $userParams = @{
            GivenName = $userInfo.GivenName; Surname = $userInfo.Surname; Name = "$($userInfo.GivenName) $($userInfo.Surname)"
            SamAccountName = $userInfo.SamAccountName; AccountPassword = $password; ChangePasswordAtLogon = $true; Enabled = $true
        }
        if ($userInfo.Title) { $userParams['Title'] = $userInfo.Title }
        if ($userInfo.Department) { $userParams['Department'] = $userInfo.Department }
        if ($userInfo.Phone) { $userParams['OfficePhone'] = $userInfo.Phone }
        if ($userInfo.Email) { $userParams['EmailAddress'] = $userInfo.Email }

        if ($choice -eq 'N') {
            $ou = $record.OU
            $ouExists = Get-ADOrganizationalUnit -Identity $ou -ErrorAction SilentlyContinue
            if (-not $ouExists) { Write-Warning "OU $ou not found. Skipping $($userInfo.SamAccountName)."; continue }
            $refUser = Get-ADUser -Filter * -SearchBase $ou | Select-Object -First 1
            $defaultDomain = $null
            if ($refUser -and -not [string]::IsNullOrWhiteSpace($refUser.UserPrincipalName) -and $refUser.UserPrincipalName.Contains('@')) {
                $defaultDomain = $refUser.UserPrincipalName.Split('@')[1]
            }
            $domain = if ([string]::IsNullOrWhiteSpace($record.Domain)) { $defaultDomain } else { $record.Domain }
            if ([string]::IsNullOrWhiteSpace($domain)) {
                Write-Warning "OU $ou has no user UPN and Domain is blank. Skipping $($userInfo.SamAccountName)."
                continue
            }
            $userParams['Path'] = $ou
            $userParams['UserPrincipalName'] = "$($userInfo.SamAccountName)@$domain"
            if ($userInfo.Manager) { $userParams['Manager'] = $userInfo.Manager }
            try {
                New-ADUser @userParams
                Write-Host "Created user $($userInfo.SamAccountName) in $ou"
            }
            catch {
                $failed++
                Write-Warning "Failed to create $($userInfo.SamAccountName). Skipping: $($_.Exception.Message)"
            }
        }
        elseif ($choice -eq 'C') {
            $domain = $null
            if (-not [string]::IsNullOrWhiteSpace($sourceUser.UserPrincipalName) -and $sourceUser.UserPrincipalName.Contains('@')) {
                $domain = $sourceUser.UserPrincipalName.Split('@')[1]
            }
            if ([string]::IsNullOrWhiteSpace($domain)) {
                Write-Warning "Source user $sourceSam has no UPN. Skipping $($userInfo.SamAccountName)."
                continue
            }
            $ou = $sourceUser.DistinguishedName -replace '^CN=[^,]+,'
            $userParams['Path'] = $ou
            $userParams['UserPrincipalName'] = "$($userInfo.SamAccountName)@$domain"
            if ($userInfo.Manager) { $userParams['Manager'] = $userInfo.Manager } elseif ($sourceUser.Manager) { $userParams['Manager'] = $sourceUser.Manager }
            try {
                New-ADUser @userParams
                if ($sourceUser.MemberOf) { Add-ADPrincipalGroupMembership -Identity $userInfo.SamAccountName -MemberOf $sourceUser.MemberOf }
                Write-Host "Created user $($userInfo.SamAccountName) copied from $sourceSam in $ou"
            }
            catch {
                $failed++
                Write-Warning "Failed to create $($userInfo.SamAccountName). Skipping: $($_.Exception.Message)"
            }
        }
        else {
            Write-Warning "Invalid action '$choice' for $($userInfo.SamAccountName). Use 'N' for new or 'C' for copy."
        }
    }
    if ($failed -gt 0) { Write-Warning "CSV processing complete. Failed rows: $failed." }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
