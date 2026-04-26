<#
.SYNOPSIS
    Manages mapped drives for the current user and displays current-user printer mappings.
.DESCRIPTION
    Resolves current user SID from loaded HKEY_USERS and presents a menu to view mappings, add mapped drives (manual or
    CSV), remove mapped drives (selection or CSV), or exit. Also displays current-user HKU printer connection entries
    for context. CSV paths are prompted and must be under C:\Temp.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

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

function Read-MenuChoice {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [string[]]$AllowedChoices
    )

    do {
        $choice = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($choice)) {
            Write-Warning "Choose one of: $($AllowedChoices -join ', ')"
            continue
        }

        $trimmed = $choice.Trim()
        if ($AllowedChoices -contains $trimmed) {
            return $trimmed
        }

        Write-Warning "Invalid choice '$trimmed'. Choose one of: $($AllowedChoices -join ', ')"
    } while ($true)
}

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $tempPath)) {
        New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
    }
}

function Read-CsvPathUnderTemp {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $entered = Read-RequiredNonEmpty -Prompt $Prompt
    $resolved = [System.IO.Path]::GetFullPath($entered)
    if ([System.IO.Path]::GetExtension($resolved) -notmatch '^(?i:\.csv)$') {
        throw "CSV path must end with .csv. Got: $resolved"
    }

    $tempRoot = [System.IO.Path]::GetFullPath('C:\Temp').TrimEnd('\') + '\'
    if (-not ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "CSV path must be under C:\Temp. Got: $resolved"
    }
    return $resolved
}

function Resolve-CurrentUserContext {
    param(
        [Parameter(Mandatory)]
        [string[]]$LoadedSids
    )

    $username = $null
    try {
        $username = (Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop).UserName
    }
    catch {
        $username = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($username)) {
        try {
            $sidValue = ([System.Security.Principal.NTAccount]$username).Translate([System.Security.Principal.SecurityIdentifier]).Value
            if ($LoadedSids -contains $sidValue) {
                return [pscustomobject]@{
                    UserDisplay = $username
                    Sid = $sidValue
                    Source = 'ConsoleUser'
                }
            }
        }
        catch {
            # Fall through to current process.
        }
    }

    $currentSid = [System.Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($LoadedSids -contains $currentSid) {
        return [pscustomobject]@{
            UserDisplay = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
            Sid = $currentSid
            Source = 'CurrentProcess'
        }
    }

    return $null
}

function Get-MappedDrivesForSid {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $drivePath = "Registry::HKEY_USERS\$Sid\Network"
    if (-not (Test-Path -LiteralPath $drivePath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $drivePath -ErrorAction SilentlyContinue | ForEach-Object {
        $letter = $_.PSChildName
        $remote = (Get-ItemProperty -LiteralPath $_.PSPath -Name RemotePath -ErrorAction SilentlyContinue).RemotePath
        [pscustomobject]@{
            DriveLetter = $letter
            RemotePath  = $remote
        }
    })
}

function Get-PrinterMappingsForSid {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $printerPath = "Registry::HKEY_USERS\$Sid\Printers\Connections"
    if (-not (Test-Path -LiteralPath $printerPath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $printerPath -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            ConnectionName = $_.PSChildName
        }
    })
}

function Show-CurrentMappings {
    param(
        [Parameter(Mandatory)]
        [object[]]$Drives,
        [Parameter(Mandatory)]
        [object[]]$Printers
    )

    Write-Host ''
    Write-Host 'Mapped Drives:' -ForegroundColor Yellow
    if ($Drives.Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor DarkYellow
    }
    else {
        for ($i = 0; $i -lt $Drives.Count; $i++) {
            $d = $Drives[$i]
            Write-Host ("  [{0}] {1}: -> {2}" -f ($i + 1), $d.DriveLetter, $d.RemotePath)
        }
    }

    Write-Host ''
    Write-Host 'Mapped Printer Connections:' -ForegroundColor Green
    if ($Printers.Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor DarkYellow
    }
    else {
        foreach ($p in $Printers) {
            Write-Host "  $($p.ConnectionName)"
        }
    }
}

function Add-MappedDrive {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter,
        [Parameter(Mandatory)]
        [string]$RemotePath
    )

    $letter = $DriveLetter.TrimEnd(':').ToUpper()
    if ($letter -notmatch '^[A-Z]$') {
        throw "Invalid drive letter '$DriveLetter'. Use one letter, e.g. Z"
    }
    if ($RemotePath -notmatch '^\\\\[^\\]+\\[^\\]+') {
        throw "Invalid remote path '$RemotePath'. Use UNC format like \\server\share"
    }

    New-PSDrive -Name $letter -PSProvider FileSystem -Root $RemotePath -Persist -ErrorAction Stop | Out-Null
    Write-Host "Added mapped drive $letter`: -> $RemotePath" -ForegroundColor Green
}

function Invoke-AddAction {
    Write-Host ''
    Write-Host 'Add mapped drive:' -ForegroundColor Yellow
    Write-Host '  [1] Manual'
    Write-Host '  [2] CSV'
    $mode = Read-MenuChoice -Prompt 'Choose add mode (1-2)' -AllowedChoices @('1', '2')

    if ($mode -eq '1') {
        $letter = Read-RequiredNonEmpty -Prompt 'Drive letter (example: Z)'
        $remote = Read-RequiredNonEmpty -Prompt 'UNC remote path (example: \\server\share)'
        Add-MappedDrive -DriveLetter $letter -RemotePath $remote
        return
    }

    Ensure-TempDirectory
    $csvPath = Read-CsvPathUnderTemp -Prompt 'Drive add CSV path under C:\Temp (example: C:\Temp\drive-add-template.csv)'
    if (-not (Test-Path -LiteralPath $csvPath)) {
        throw "CSV file not found: $csvPath"
    }
    $rows = @(Import-Csv -Path $csvPath)
    if ($rows.Count -eq 0) {
        throw "CSV has no rows: $csvPath"
    }

    $ok = 0
    $fail = 0
    foreach ($row in $rows) {
        try {
            Add-MappedDrive -DriveLetter ([string]$row.DriveLetter) -RemotePath ([string]$row.RemotePath)
            $ok++
        }
        catch {
            $fail++
            Write-Warning "Failed add row: $($_.Exception.Message)"
        }
    }
    Write-Host "Drive add CSV complete. Success: $ok  Failed: $fail" -ForegroundColor Cyan
}

function Remove-MappedDrive {
    param(
        [Parameter(Mandatory)]
        [string]$DriveLetter
    )

    $letter = $DriveLetter.TrimEnd(':').ToUpper()
    if ($letter -notmatch '^[A-Z]$') {
        throw "Invalid drive letter '$DriveLetter'. Use one letter."
    }

    Remove-PSDrive -Name $letter -Force -ErrorAction Stop
    Write-Host "Removed mapped drive $letter`:" -ForegroundColor Green
}

function Invoke-DeleteAction {
    param(
        [Parameter(Mandatory)]
        [object[]]$Drives
    )

    Write-Host ''
    Write-Host 'Delete mapped drive:' -ForegroundColor Yellow
    Write-Host '  [1] Select from current mapped drives'
    Write-Host '  [2] CSV'
    $mode = Read-MenuChoice -Prompt 'Choose delete mode (1-2)' -AllowedChoices @('1', '2')

    if ($mode -eq '1') {
        if ($Drives.Count -eq 0) {
            Write-Host 'No mapped drives to remove.' -ForegroundColor Yellow
            return
        }

        $choices = (1..$Drives.Count | ForEach-Object { "$_" })
        $idx = [int](Read-MenuChoice -Prompt "Choose drive to remove (1-$($Drives.Count))" -AllowedChoices $choices)
        $target = $Drives[$idx - 1]
        if (-not (Test-ReadHostYes -Prompt "Remove $($target.DriveLetter): -> $($target.RemotePath)? (Y/N)")) {
            Write-Host 'Cancelled. No changes made.' -ForegroundColor Cyan
            return
        }

        Remove-MappedDrive -DriveLetter $target.DriveLetter
        return
    }

    Ensure-TempDirectory
    $csvPath = Read-CsvPathUnderTemp -Prompt 'Drive remove CSV path under C:\Temp (example: C:\Temp\drive-remove-template.csv)'
    if (-not (Test-Path -LiteralPath $csvPath)) {
        throw "CSV file not found: $csvPath"
    }
    $rows = @(Import-Csv -Path $csvPath)
    if ($rows.Count -eq 0) {
        throw "CSV has no rows: $csvPath"
    }

    $ok = 0
    $fail = 0
    foreach ($row in $rows) {
        try {
            Remove-MappedDrive -DriveLetter ([string]$row.DriveLetter)
            $ok++
        }
        catch {
            $fail++
            Write-Warning "Failed remove row: $($_.Exception.Message)"
        }
    }
    Write-Host "Drive remove CSV complete. Success: $ok  Failed: $fail" -ForegroundColor Cyan
}

function Invoke-Main {
    $loadedSids = @(Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSChildName } |
        Where-Object { $_ -notmatch '_Classes$' })

    if ($loadedSids.Count -eq 0) {
        Write-Host 'No loaded user hives were found under HKEY_USERS.' -ForegroundColor Yellow
        return
    }

    $context = Resolve-CurrentUserContext -LoadedSids $loadedSids
    if ($null -eq $context) {
        Write-Host 'Could not resolve currently logged-in/current loaded user SID.' -ForegroundColor Yellow
        return
    }

    Write-Host "Target user: $($context.UserDisplay) [$($context.Sid)] via $($context.Source)" -ForegroundColor Cyan

    while ($true) {
        $drives = @(Get-MappedDrivesForSid -Sid $context.Sid)
        $printers = @(Get-PrinterMappingsForSid -Sid $context.Sid)
        Show-CurrentMappings -Drives $drives -Printers $printers

        Write-Host ''
        Write-Host 'Actions:' -ForegroundColor Yellow
        Write-Host '  [1] Add mapped drive'
        Write-Host '  [2] Remove mapped drive'
        Write-Host '  [3] Refresh view'
        Write-Host '  [4] Exit'
        $action = Read-MenuChoice -Prompt 'Choose action (1-4)' -AllowedChoices @('1', '2', '3', '4')

        try {
            switch ($action) {
                '1' { Invoke-AddAction }
                '2' { Invoke-DeleteAction -Drives $drives }
                '3' { continue }
                '4' {
                    Write-Host 'Exiting user mapping management.' -ForegroundColor Cyan
                    return
                }
            }
        }
        catch {
            Write-Warning $_.Exception.Message
        }
    }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
