<#
.SYNOPSIS
    Updates AD user Department, Title, and Manager from a CSV file.
.DESCRIPTION
    Prompts for CSV path (default under C:\Temp), identity column, optional domain controller, optional alternate
    credential, and preview/apply mode. Resolves users/managers, writes a pre-change backup CSV, then applies delta
    updates with Set-ADUser. Logs and transcript are written under C:\Temp. Intended for elevated admin/LocalSystem
    with ActiveDirectory module available.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function New-Timestamp {
    return (Get-Date -Format 'yyyyMMdd_HHmmss')
}

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $tempPath)) {
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
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

function Read-RequiredNonEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    do {
        $value = Read-Host -Prompt $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Read-CsvPathUnderTemp {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [string]$DefaultPath
    )

    $entered = Read-Host -Prompt "$Prompt [default: $DefaultPath]"
    if ([string]::IsNullOrWhiteSpace($entered)) {
        $resolved = $DefaultPath
    }
    else {
        $resolved = [System.IO.Path]::GetFullPath($entered.Trim())
    }

    if ([System.IO.Path]::GetExtension($resolved) -notmatch '^(?i:\.csv)$') {
        throw "CSV path must end with .csv. Got: $resolved"
    }

    $tempRoot = [System.IO.Path]::GetFullPath('C:\Temp').TrimEnd('\') + '\'
    if (-not ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "CSV path must be under C:\Temp. Got: $resolved"
    }

    return $resolved
}

function Read-IdentityColumn {
    Write-Host 'Identity column options:' -ForegroundColor Yellow
    Write-Host '  [1] Name'
    Write-Host '  [2] sAMAccountName'
    Write-Host '  [3] UserPrincipalName'
    Write-Host '  [4] DistinguishedName'
    do {
        $choice = Read-Host -Prompt 'Choose identity column (1-4) [default: 1]'
        if ([string]::IsNullOrWhiteSpace($choice) -or $choice.Trim() -eq '1') { return 'Name' }
        if ($choice.Trim() -eq '2') { return 'sAMAccountName' }
        if ($choice.Trim() -eq '3') { return 'UserPrincipalName' }
        if ($choice.Trim() -eq '4') { return 'DistinguishedName' }
        Write-Warning 'Invalid choice. Enter 1, 2, 3, or 4.'
    } while ($true)
}

function Write-Log {
    param(
        [Parameter(Mandatory)][ValidateSet('INFO', 'WARN', 'ERROR')][string]$Level,
        [Parameter(Mandatory)][string]$Message
    )

    $ts = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    $line = "[$ts][$Level] $Message"
    Add-Content -LiteralPath $script:LogPath -Value $line
    if ($Level -ne 'INFO') {
        Write-Host $line
    }
}

function Resolve-ADUser {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][ValidateSet('Name', 'sAMAccountName', 'UserPrincipalName', 'DistinguishedName')][string]$By,
        [Parameter(Mandatory)][hashtable]$CommonParams
    )

    switch ($By) {
        'DistinguishedName' { return Get-ADUser -Identity $Value @CommonParams }
        'sAMAccountName' { return Get-ADUser -Identity $Value @CommonParams }
        'UserPrincipalName' {
            $escaped = $Value.Replace("'", "''")
            return Get-ADUser -Filter "UserPrincipalName -eq '$escaped'" -Properties * @CommonParams
        }
        'Name' {
            $escaped = $Value.Replace("'", "''")
            $candidates = Get-ADUser -Filter "displayName -eq '$escaped'" -Properties Enabled @CommonParams
            if (-not $candidates) { return $null }
            if ($candidates.Count -gt 1) {
                $enabled = $candidates | Where-Object Enabled
                if ($enabled.Count -eq 1) { return $enabled }
                throw "Multiple users found for Name '$Value'. Use a unique identifier column."
            }
            return $candidates
        }
    }
}

function Resolve-Manager {
    param(
        [Parameter(Mandatory)][string]$Value,
        [Parameter(Mandatory)][hashtable]$CommonParams
    )

    if ([string]::IsNullOrWhiteSpace($Value)) { return $null }
    foreach ($by in @('DistinguishedName', 'sAMAccountName', 'UserPrincipalName', 'Name')) {
        try {
            $mgr = Resolve-ADUser -Value $Value -By $by -CommonParams $CommonParams
            if ($mgr) { return $mgr }
        }
        catch {
            continue
        }
    }
    return $null
}

function Get-UpdateValue {
    param(
        [Parameter(Mandatory)]$Row,
        [Parameter(Mandatory)][string]$Primary,
        [string]$Secondary
    )

    $value = $null
    if ($Row.PSObject.Properties.Name -contains $Primary) {
        $value = [string]$Row.$Primary
    }
    elseif ($Secondary -and ($Row.PSObject.Properties.Name -contains $Secondary)) {
        $value = [string]$Row.$Secondary
    }
    return $value
}

function Invoke-Main {
    Ensure-TempDirectory

    $runId = New-Timestamp
    $script:LogPath = "C:\Temp\UpdateAdUserFromCsv_$runId.log"
    $script:TranscriptPath = "C:\Temp\UpdateAdUserFromCsv_$runId.transcript.txt"

    try { Start-Transcript -Path $script:TranscriptPath -ErrorAction Stop | Out-Null } catch { }
    Write-Log -Level INFO -Message "Run started. Log: '$($script:LogPath)'. Transcript: '$($script:TranscriptPath)'."

    try {
        if (-not (Get-Module -ListAvailable -Name ActiveDirectory)) {
            throw 'ActiveDirectory module is not available. Install RSAT Active Directory module first.'
        }
        Import-Module ActiveDirectory -ErrorAction Stop
        Write-Log -Level INFO -Message 'ActiveDirectory module imported.'

        $csvPath = Read-CsvPathUnderTemp -Prompt 'Path to updates CSV under C:\Temp' -DefaultPath 'C:\Temp\ad-user-updates-template.csv'
        if (-not (Test-Path -LiteralPath $csvPath)) {
            throw "CSV file not found: $csvPath"
        }

        $identityColumn = Read-IdentityColumn
        $domainController = Read-Host -Prompt 'Domain controller (optional, Enter to use default)'
        $useAltCredential = Test-ReadHostYes -Prompt 'Use alternate AD credential? (Y/N)'
        $preview = Test-ReadHostYes -Prompt 'Preview mode only (no AD changes)? (Y/N)'

        $commonParams = @{ ErrorAction = 'Stop' }
        if (-not [string]::IsNullOrWhiteSpace($domainController)) {
            $commonParams['Server'] = $domainController.Trim()
        }
        if ($useAltCredential) {
            $commonParams['Credential'] = Get-Credential
        }

        $rows = @(Import-Csv -LiteralPath $csvPath)
        if ($rows.Count -eq 0) {
            Write-Log -Level WARN -Message 'CSV contains no rows. Nothing to do.'
            return
        }

        $headers = @($rows[0].PSObject.Properties.Name)
        if (-not ($headers -contains $identityColumn)) {
            throw "CSV is missing identity column '$identityColumn'. Present headers: $($headers -join ', ')"
        }

        $hasDept = $headers -contains 'Department'
        $hasTitle = ($headers -contains 'Title') -or ($headers -contains 'JobTitle')
        $hasMgr = $headers -contains 'Manager'
        if (-not ($hasDept -or $hasTitle -or $hasMgr)) {
            Write-Log -Level WARN -Message 'CSV has no update columns (Department, Title/JobTitle, Manager). Nothing to update.'
            return
        }

        $backupPath = "C:\Temp\ADUserBackup_$runId.csv"
        $backup = New-Object 'System.Collections.Generic.List[object]'

        [int]$processed = 0
        [int]$updated = 0
        [int]$skipped = 0
        [int]$errors = 0
        $sw = [System.Diagnostics.Stopwatch]::StartNew()

        foreach ($row in $rows) {
            $processed++
            $pct = [int](($processed / [double]$rows.Count) * 100)
            Write-Progress -Activity 'Processing AD update rows' -PercentComplete $pct -Status "$pct%"

            try {
                $idValue = [string]$row.$identityColumn
                if ([string]::IsNullOrWhiteSpace($idValue)) {
                    Write-Log -Level WARN -Message "Row $processed: Missing '$identityColumn'. Skipping."
                    $skipped++
                    continue
                }

                $user = Resolve-ADUser -Value $idValue -By $identityColumn -CommonParams $commonParams
                if (-not $user) {
                    Write-Log -Level WARN -Message "Row $processed: User not found for '$identityColumn'='$idValue'. Skipping."
                    $skipped++
                    continue
                }

                $current = Get-ADUser -Identity $user.DistinguishedName -Properties department, title, manager @commonParams
                $backup.Add([pscustomobject]@{
                    Row                = $processed
                    UserDN             = $user.DistinguishedName
                    sAMAccountName     = $user.SamAccountName
                    UserPrincipalName  = $user.UserPrincipalName
                    DisplayName        = $user.Name
                    Department_Current = $current.Department
                    Title_Current      = $current.Title
                    ManagerDN_Current  = $current.Manager
                })

                $newDept = Get-UpdateValue -Row $row -Primary 'Department'
                $newTitle = Get-UpdateValue -Row $row -Primary 'Title' -Secondary 'JobTitle'
                $newMgrRaw = Get-UpdateValue -Row $row -Primary 'Manager'

                $mgrTarget = $null
                if (-not [string]::IsNullOrWhiteSpace($newMgrRaw)) {
                    $mgrTarget = Resolve-Manager -Value $newMgrRaw -CommonParams $commonParams
                    if (-not $mgrTarget) {
                        Write-Log -Level WARN -Message "Row $processed ($($user.SamAccountName)): Manager '$newMgrRaw' not found. Manager will not be updated."
                    }
                }

                $pending = @{}
                if ($hasDept -and $null -ne $newDept -and $newDept -ne $current.Department) { $pending['Department'] = $newDept }
                if ($hasTitle -and $null -ne $newTitle -and $newTitle -ne $current.Title) { $pending['Title'] = $newTitle }
                if ($hasMgr -and $mgrTarget -and ($current.Manager -ne $mgrTarget.DistinguishedName)) { $pending['Manager'] = $mgrTarget.DistinguishedName }

                if ($pending.Count -eq 0) {
                    Write-Log -Level INFO -Message "Row $processed ($($user.SamAccountName)): No changes needed. Skipping."
                    $skipped++
                    continue
                }

                $changeDesc = ($pending.GetEnumerator() | ForEach-Object { "{0}='{1}'" -f $_.Key, $_.Value }) -join '; '
                if ($preview) {
                    Write-Log -Level INFO -Message "Row $processed ($($user.SamAccountName)): PREVIEW -> $changeDesc"
                    continue
                }

                $setParams = @{ Identity = $user.DistinguishedName; Confirm = $false; ErrorAction = 'Stop' }
                if ($commonParams.ContainsKey('Server')) { $setParams['Server'] = $commonParams['Server'] }
                if ($commonParams.ContainsKey('Credential')) { $setParams['Credential'] = $commonParams['Credential'] }
                if ($pending.ContainsKey('Department')) { $setParams['Department'] = $pending['Department'] }
                if ($pending.ContainsKey('Title')) { $setParams['Title'] = $pending['Title'] }
                if ($pending.ContainsKey('Manager')) { $setParams['Manager'] = $pending['Manager'] }

                Set-ADUser @setParams
                Write-Log -Level INFO -Message "Row $processed ($($user.SamAccountName)): Updated -> $changeDesc"
                $updated++
            }
            catch {
                $errors++
                Write-Log -Level ERROR -Message ("Row {0}: Error processing user '{1}': {2}" -f $processed, $row.$identityColumn, $_.Exception.Message)
            }
        }

        try {
            $backup | Export-Csv -LiteralPath $backupPath -NoTypeInformation -Encoding UTF8
            Write-Log -Level INFO -Message "Backup of current values written to: $backupPath"
        }
        catch {
            Write-Log -Level ERROR -Message "Failed to write backup CSV: $($_.Exception.Message)"
        }

        $sw.Stop()
        Write-Progress -Activity 'Processing complete' -PercentComplete 100 -Status '100%'
        Write-Log -Level INFO -Message ("Run complete. Processed={0}; Updated={1}; Skipped={2}; Errors={3}; Elapsed={4}s" -f $processed, $updated, $skipped, $errors, [int]$sw.Elapsed.TotalSeconds)

        if ($errors -gt 0) {
            Write-Host '[WARN] One or more rows failed. Review the log for details.' -ForegroundColor Yellow
        }
        else {
            Write-Host '[SUCCESS] AD user update processing completed.' -ForegroundColor Green
        }
    }
    finally {
        try { Stop-Transcript | Out-Null } catch { }
    }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
