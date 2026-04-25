# Requires: ActiveDirectory module

Import-Module ActiveDirectory

while ($true) {
    $CsvPath = Read-Host -Prompt "Enter the path to the CSV file"

    if ([string]::IsNullOrWhiteSpace($CsvPath)) {
        Write-Warning "CSV path cannot be empty."
        continue
    }

    if (-not (Test-Path -Path $CsvPath)) {
        Write-Warning "CSV file '$CsvPath' was not found. Please enter a valid path."
        continue
    }

    break
}

function Test-PasswordComplexity {
    param([string]$Plain)
    $Plain.Length -ge 12 -and
    $Plain -match '[A-Z]' -and
    $Plain -match '[a-z]' -and
    $Plain -match '[0-9]' -and
    $Plain -match '[^a-zA-Z0-9]'
}

$records = Import-Csv -Path $CsvPath

foreach ($record in $records) {
    $choice = $record.Action.ToUpper()

    $userInfo = [pscustomobject]@{
        GivenName      = $record.GivenName
        Surname        = $record.Surname
        SamAccountName = $record.SamAccountName
        Title          = $record.Title
        Department     = $record.Department
        Manager        = $record.Manager
        Phone          = $record.Phone
        Email          = $record.Email
    }

    $sourceSam = $null
    $sourceUser = $null
    if ($choice -eq 'C') {
        $sourceSam = $record.SourceSam

        if ([string]::IsNullOrWhiteSpace($sourceSam)) {
            Write-Warning "SourceSam is required for copy action for $($userInfo.SamAccountName). Skipping."
            continue
        }

        $sourceUser = Get-ADUser -Identity $sourceSam -Properties MemberOf,Title,Manager,OfficePhone,EmailAddress -ErrorAction SilentlyContinue

        if (-not $sourceUser) {
            Write-Warning "Source user $sourceSam not found. Skipping $($userInfo.SamAccountName)."
            continue
        }
    }

    $nameExists = Get-ADUser -Filter "GivenName -eq '$($userInfo.GivenName)' -and Surname -eq '$($userInfo.Surname)'" -ErrorAction SilentlyContinue
    if ($nameExists) { Write-Warning "A user with first name '$($userInfo.GivenName)' and last name '$($userInfo.Surname)' already exists. Skipping."; continue }

    $samExists = Get-ADUser -Filter "SamAccountName -eq '$($userInfo.SamAccountName)'" -ErrorAction SilentlyContinue
    if ($samExists) { Write-Warning "Username $($userInfo.SamAccountName) already exists. Skipping."; continue }

    if ($userInfo.Manager) {
        $mgrExists = Get-ADUser -Identity $userInfo.Manager -ErrorAction SilentlyContinue
        if (-not $mgrExists) {
            Write-Warning "Manager $($userInfo.Manager) not found. Manager will be ignored."
            $userInfo.Manager = $null
        }
    }

    if (-not (Test-PasswordComplexity $record.Password)) {
        Write-Warning "Password for $($userInfo.SamAccountName) must be ≥12 chars and include uppercase, lowercase, number, and symbol. Skipping."
        continue
    }

    $password = ConvertTo-SecureString $record.Password -AsPlainText -Force

    if ($choice -eq 'N') {
        $ou = $record.OU
        $ouExists = Get-ADOrganizationalUnit -Identity $ou -ErrorAction SilentlyContinue
        if (-not $ouExists) { Write-Warning "OU $ou not found. Skipping $($userInfo.SamAccountName)."; continue }

        $refUser = Get-ADUser -Filter * -SearchBase $ou | Select-Object -First 1
        $defaultDomain = $refUser.UserPrincipalName.Split('@')[1]
        $domain = if ([string]::IsNullOrWhiteSpace($record.Domain)) { $defaultDomain } else { $record.Domain }

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
    }
    elseif ($choice -eq 'C') {
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
        Write-Host "Created user $($userInfo.SamAccountName) copied from $sourceSam in $ou"
    }
    else {
        Write-Warning "Invalid action '$choice' for $($userInfo.SamAccountName). Use 'N' for new or 'C' for copy."
    }
}
