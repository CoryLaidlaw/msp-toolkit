<#
.SYNOPSIS
    Interactively creates a new AD user or copies one from an existing user.
.DESCRIPTION
    Prompts for user details and a secure temporary password. New mode asks for the target OU and UPN domain.
    Copy mode pulls the OU, group memberships, and unset manager from the source user. Requires ActiveDirectory RSAT.
#>

function Read-Required {
    param([string]$Prompt)

    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Prompt-UserInfo {
    do {
        $givenName = Read-Required 'First name'
        $surname = Read-Required 'Last name'
        $escapedGivenName = $givenName -replace "'", "''"
        $escapedSurname = $surname -replace "'", "''"
        $nameExists = Get-ADUser -Filter "GivenName -eq '$escapedGivenName' -and Surname -eq '$escapedSurname'" -ErrorAction SilentlyContinue
        if ($nameExists) { Write-Warning 'A user with that first and last name already exists.' }
    } while ($nameExists)

    do {
        $sam = Read-Required 'Desired username'
        $escapedSam = $sam -replace "'", "''"
        $samExists = Get-ADUser -Filter "SamAccountName -eq '$escapedSam'" -ErrorAction SilentlyContinue
        if ($samExists) { Write-Warning "Username $sam already exists." }
    } while ($samExists)

    $title = Read-Host 'Title (if desired)'
    $department = Read-Host 'Department (if desired)'

    do {
        $manager = Read-Host 'Manager (sAMAccountName or DN, leave blank if none)'
        $mgrExists = $null
        if ($manager) {
            try {
                $mgrExists = Get-ADUser -Identity $manager -ErrorAction Stop
            }
            catch {
                Write-Warning "Manager $manager not found."
            }
        }
    } while ($manager -and -not $mgrExists)

    return [pscustomobject]@{
        GivenName      = $givenName
        Surname        = $surname
        SamAccountName = $sam
        Title          = $title
        Department     = $department
        Manager        = $manager
        Phone          = Read-Host 'Phone number (if desired)'
        Email          = Read-Host 'Email (if desired)'
    }
}

function Read-Password {
    do {
        $password = Read-Host 'Temporary password' -AsSecureString
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($password)
        try {
            $plain = [Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            $complex = $plain.Length -ge 12 -and $plain -match '[A-Z]' -and $plain -match '[a-z]' -and $plain -match '[0-9]' -and $plain -match '[^a-zA-Z0-9]'
        }
        finally {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
        if (-not $complex) {
            Write-Warning 'Password must be at least 12 characters and include uppercase, lowercase, number, and symbol.'
        }
    } until ($complex)
    return $password
}

function Invoke-Main {
    if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
        throw 'ActiveDirectory module is not available. Install RSAT Active Directory module first.'
    }
    Import-Module ActiveDirectory -ErrorAction Stop

    do {
        $choice = Read-Host 'Is this a (N)ew user or (C)opy from existing user? (N/C)'
        $choice = $choice.ToUpper()
    } while ($choice -notin @('N', 'C'))

    $userInfo = Prompt-UserInfo
    $password = Read-Password
    $userParams = @{
        GivenName             = $userInfo.GivenName
        Surname               = $userInfo.Surname
        Name                  = "$($userInfo.GivenName) $($userInfo.Surname)"
        SamAccountName        = $userInfo.SamAccountName
        AccountPassword       = $password
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }
    if ($userInfo.Title) { $userParams['Title'] = $userInfo.Title }
    if ($userInfo.Department) { $userParams['Department'] = $userInfo.Department }
    if ($userInfo.Phone) { $userParams['OfficePhone'] = $userInfo.Phone }
    if ($userInfo.Email) { $userParams['EmailAddress'] = $userInfo.Email }

    if ($choice -eq 'N') {
        do {
            $ou = Read-Required 'OU distinguished name to create user in (e.g., OU=Employees,DC=example,DC=com)'
            $ouExists = Get-ADOrganizationalUnit -Identity $ou -ErrorAction SilentlyContinue
            if (-not $ouExists) { Write-Warning "OU $ou not found." }
        } while (-not $ouExists)

        $refUser = Get-ADUser -Filter * -SearchBase $ou | Select-Object -First 1
        $defaultDomain = $null
        if ($refUser -and -not [string]::IsNullOrWhiteSpace($refUser.UserPrincipalName) -and $refUser.UserPrincipalName.Contains('@')) {
            $defaultDomain = $refUser.UserPrincipalName.Split('@')[1]
        }
        $domainInput = Read-Host "UPN domain$(if ($defaultDomain) { " (leave blank for $defaultDomain)" } else { ' (required because this OU has no user UPN)' })"
        $domain = if ([string]::IsNullOrWhiteSpace($domainInput)) { $defaultDomain } else { $domainInput }
        if ([string]::IsNullOrWhiteSpace($domain)) {
            Write-Warning 'No UPN domain was provided. User was not created.'
            return
        }

        $userParams['Path'] = $ou
        $userParams['UserPrincipalName'] = "$($userInfo.SamAccountName)@$domain"
        if ($userInfo.Manager) { $userParams['Manager'] = $userInfo.Manager }
        New-ADUser @userParams
        Write-Host "Created user $($userInfo.SamAccountName) in $ou"
        return
    }

    do {
        $sourceSam = Read-Required 'Enter the username to copy from'
        $sourceUser = $null
        try {
            $sourceUser = Get-ADUser -Identity $sourceSam -Properties MemberOf, Title, Manager, OfficePhone, EmailAddress -ErrorAction Stop
        }
        catch {
            Write-Warning "Source user $sourceSam not found."
        }
    } while (-not $sourceUser)

    $defaultDomain = $null
    if (-not [string]::IsNullOrWhiteSpace($sourceUser.UserPrincipalName) -and $sourceUser.UserPrincipalName.Contains('@')) {
        $defaultDomain = $sourceUser.UserPrincipalName.Split('@')[1]
    }
    $domainInput = Read-Host "UPN domain$(if ($defaultDomain) { " (leave blank for $defaultDomain)" } else { ' (required because the source user has no UPN)' })"
    $domain = if ([string]::IsNullOrWhiteSpace($domainInput)) { $defaultDomain } else { $domainInput }
    if ([string]::IsNullOrWhiteSpace($domain)) {
        Write-Warning 'No UPN domain was provided. User was not created.'
        return
    }
    $ou = $sourceUser.DistinguishedName -replace '^CN=[^,]+,'
    $userParams['Path'] = $ou
    $userParams['UserPrincipalName'] = "$($userInfo.SamAccountName)@$domain"
    if ($userInfo.Manager) { $userParams['Manager'] = $userInfo.Manager } elseif ($sourceUser.Manager) { $userParams['Manager'] = $sourceUser.Manager }
    New-ADUser @userParams
    if ($sourceUser.MemberOf) { Add-ADPrincipalGroupMembership -Identity $userInfo.SamAccountName -MemberOf $sourceUser.MemberOf }
    Write-Host "Created user $($userInfo.SamAccountName) copied from $sourceSam in $ou"
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
