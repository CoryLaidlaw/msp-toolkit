# Requires: ActiveDirectory module

Import-Module ActiveDirectory

function Read-Required {
    param(
        [string]$Prompt
    )
    do {
        $value = Read-Host $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Prompt-UserInfo {
    do {
        $givenName = Read-Required "First name"
        $surname = Read-Required "Last name"
        $nameExists = Get-ADUser -Filter "GivenName -eq '$givenName' -and Surname -eq '$surname'" -ErrorAction SilentlyContinue
        if ($nameExists) { Write-Warning "A user with that first and last name already exists." }
    } while ($nameExists)

    do {
        $sam = Read-Required "Desired username"
        $samExists = Get-ADUser -Filter "SamAccountName -eq '$sam'" -ErrorAction SilentlyContinue
        if ($samExists) { Write-Warning "Username $sam already exists." }
    } while ($samExists)

    $title = Read-Host "Title (if desired)"
    $department = Read-Host "Department (if desired)"

    do {
        $manager = Read-Host "Manager (sAMAccountName or DN, leave blank if none)"
        if ($manager) {
            $mgrExists = Get-ADUser -Identity $manager -ErrorAction SilentlyContinue
            if (-not $mgrExists) { Write-Warning "Manager $manager not found." }
        }
    } while ($manager -and -not $mgrExists)

    $phone = Read-Host "Phone number (if desired)"
    $email = Read-Host "Email (if desired)"

    return [pscustomobject]@{
        GivenName     = $givenName
        Surname       = $surname
        SamAccountName= $sam
        Title         = $title
        Department    = $department
        Manager       = $manager
        Phone         = $phone
        Email         = $email
    }
}

function Read-Password {
    do {
        $plain = Read-Host "Temporary password"
        $complex = $plain.Length -ge 12 -and
                   $plain -match '[A-Z]' -and
                   $plain -match '[a-z]' -and
                   $plain -match '[0-9]' -and
                   $plain -match '[^a-zA-Z0-9]'
        if (-not $complex) {
            Write-Warning "Password must be ≥12 chars and include uppercase, lowercase, number, and symbol."
        }
    } until ($complex)

    ConvertTo-SecureString $plain -AsPlainText -Force
}

$choice = ""
while ($choice -notin @('N','C')) {
    $choice = Read-Host "Is this a (N)ew user or (C)opy from existing user? (N/C)"
    $choice = $choice.ToUpper()
}

$userInfo = Prompt-UserInfo
$password = Read-Password

if ($choice -eq 'N') {
    do {
        $ou = Read-Required "OU distinguished name to create user in (e.g., OU=Employees,DC=example,DC=com)"
        $ouExists = Get-ADOrganizationalUnit -Identity $ou -ErrorAction SilentlyContinue
        if (-not $ouExists) { Write-Warning "OU $ou not found." }
    } while (-not $ouExists)

    $refUser = Get-ADUser -Filter * -SearchBase $ou ` | Select-Object -First 1
    $defaultDomain = $refUser.UserPrincipalName.Split('@')[1]
    $domainInput = Read-Host "UPN domain (leave blank for $defaultDomain)"
    if ([string]::IsNullOrWhiteSpace($domainInput)) {
        $domain = $defaultDomain
    } else {
        $domain = $domainInput
    }
    $userParams = @{
        GivenName             = $userInfo.GivenName
        Surname               = $userInfo.Surname
        Name                  = "$($userInfo.GivenName) $($userInfo.Surname)"
        SamAccountName        = $userInfo.SamAccountName
        UserPrincipalName     = "$($userInfo.SamAccountName)@$domain"
        Path                  = $ou
        AccountPassword       = $password
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }

    if ($userInfo.Title)      { $userParams['Title']        = $userInfo.Title }
    if ($userInfo.Department) { $userParams['Department']   = $userInfo.Department }
    if ($userInfo.Manager)    { $userParams['Manager']      = $userInfo.Manager }
    if ($userInfo.Phone)      { $userParams['OfficePhone']  = $userInfo.Phone }
    if ($userInfo.Email)      { $userParams['EmailAddress'] = $userInfo.Email }
    
    New-ADUser @userParams
    Write-Host "Created user $($userInfo.SamAccountName) in $ou"
} else {
    $sourceUser = $null
    do {
        $sourceSam = Read-Required "Enter the username to copy from"
        $sourceUser = Get-ADUser -Identity $sourceSam -Properties MemberOf,Title,Manager,OfficePhone,EmailAddress -ErrorAction SilentlyContinue
        if (-not $sourceUser) { Write-Warning "Source user $sourceSam not found." }
    } while (-not $sourceUser)

    $domain = $sourceUser.UserPrincipalName.Split('@')[1]
    $ou = $sourceUser.DistinguishedName -replace '^CN=[^,]+,',''
    $userParams = @{
        GivenName             = $userInfo.GivenName
        Surname               = $userInfo.Surname
        Name                  = "$($userInfo.GivenName) $($userInfo.Surname)"
        SamAccountName        = $userInfo.SamAccountName
        UserPrincipalName     = "$($userInfo.SamAccountName)@$domain"
        Path                  = $ou
        AccountPassword       = $password
        ChangePasswordAtLogon = $true
        Enabled               = $true
    }

    if ($userInfo.Title)      { $userParams['Title']        = $userInfo.Title }
    if ($userInfo.Department) { $userParams['Department']   = $userInfo.Department }
    if ($userInfo.Manager)    { $userParams['Manager']      = $userInfo.Manager } elseif ($sourceUser.Manager) { $userParams['Manager'] = $sourceUser.Manager }
    if ($userInfo.Phone)      { $userParams['OfficePhone']  = $userInfo.Phone }
    if ($userInfo.Email)      { $userParams['EmailAddress'] = $userInfo.Email }
    
    New-ADUser @userParams
    $groups = $sourceUser.MemberOf
    if ($groups) { Add-ADPrincipalGroupMembership -Identity $userInfo.SamAccountName -MemberOf $groups }
    Write-Host "Created user $($userInfo.SamAccountName) copied from $sourceSam  in $ou"
}
