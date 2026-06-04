<#
.SYNOPSIS
    Manages printers for the current user with Add, Delete, Rename, and Exit actions.
.DESCRIPTION
    Resolves the active logged-in user SID (with fallback to current process SID), reads
    Registry::HKEY_USERS\<SID>\Printers\Connections, and loops through a menu for Add/Delete/Rename/Exit. Add supports
    network and local/IP paths, each with manual or CSV mode. Rename supports interactive or CSV mode. Delete removes
    selected mapped connection keys by number with one batch confirmation or removes installed printer objects from CSV.
    Intended for elevated admin or technician context. Operator input is prompt-only (no script parameters).
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

function Resolve-TargetUserContext {
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
            # Fall through to current identity fallback.
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

function Get-PrinterConnectionsForSid {
    param(
        [Parameter(Mandatory)]
        [string]$Sid
    )

    $regPath = "Registry::HKEY_USERS\$Sid\Printers\Connections"
    if (-not (Test-Path -LiteralPath $regPath)) {
        return @()
    }

    return @(Get-ChildItem -LiteralPath $regPath -ErrorAction SilentlyContinue | ForEach-Object {
        [pscustomobject]@{
            Sid = $Sid
            PrinterName = $_.PSChildName
            PsPath = $_.PSPath
        }
    })
}

function Show-MappedPrinterConnections {
    param(
        [object[]]$Printers = @()
    )

    Write-Host ''
    Write-Host 'Mapped printer connections (Add/Delete registry):' -ForegroundColor Yellow
    if ($Printers.Count -eq 0) {
        Write-Host '  (none found for current user)' -ForegroundColor DarkYellow
        return
    }

    for ($i = 0; $i -lt $Printers.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $Printers[$i].PrinterName)
    }
}

function Show-InstalledPrinters {
    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Sort-Object -Property Name)

    Write-Host ''
    Write-Host 'Installed printers (Rename/Delete spooler):' -ForegroundColor Yellow
    if ($printers.Count -eq 0) {
        Write-Host '  (none found)' -ForegroundColor DarkYellow
        return
    }

    for ($i = 0; $i -lt $printers.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $printers[$i].Name)
    }
}

function Convert-SelectionTextToIndexes {
    param(
        [Parameter(Mandatory)]
        [string]$InputText,
        [Parameter(Mandatory)]
        [int]$MaximumIndex
    )

    $selected = New-Object 'System.Collections.Generic.HashSet[int]'
    $parts = @($InputText.Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' })
    if ($parts.Count -eq 0) {
        throw 'No selections entered.'
    }

    foreach ($part in $parts) {
        if ($part -match '^\d+$') {
            $n = [int]$part
            if ($n -lt 1 -or $n -gt $MaximumIndex) {
                throw "Selection $n is out of range (1-$MaximumIndex)."
            }
            [void]$selected.Add($n)
            continue
        }

        if ($part -match '^(\d+)-(\d+)$') {
            $start = [int]$Matches[1]
            $end = [int]$Matches[2]
            if ($start -gt $end) {
                throw "Invalid range '$part' (start must be <= end)."
            }
            if ($start -lt 1 -or $end -gt $MaximumIndex) {
                throw "Range '$part' is out of range (1-$MaximumIndex)."
            }

            foreach ($i in $start..$end) {
                [void]$selected.Add($i)
            }
            continue
        }

        throw "Invalid token '$part'. Use numbers and optional ranges (example: 1,3,5-7)."
    }

    return @($selected.ToArray() | Sort-Object)
}

function Read-PrinterSelectionIndexes {
    param(
        [Parameter(Mandatory)]
        [int]$MaximumIndex
    )

    do {
        $raw = Read-Host -Prompt "Enter printer numbers to delete (comma-separated, ranges allowed, e.g. 1,3,5-7)"
        try {
            return @(Convert-SelectionTextToIndexes -InputText $raw -MaximumIndex $MaximumIndex)
        }
        catch {
            Write-Warning $_.Exception.Message
        }
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
    $resolved = [System.IO.Path]::GetFullPath($entered.Trim())
    if ([System.IO.Path]::GetExtension($resolved) -notmatch '^(?i:\.csv)$') {
        throw "CSV path must end with .csv. Got: $resolved"
    }

    $tempRoot = [System.IO.Path]::GetFullPath('C:\Temp').TrimEnd('\') + '\'
    if (-not ($resolved.StartsWith($tempRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Path must be under C:\Temp. Got: $resolved"
    }

    return $resolved
}

function Test-PrinterConnectionName {
    param(
        [Parameter(Mandatory)]
        [string]$ConnectionName
    )
    return ($ConnectionName -match '^\\\\[^\\]+\\[^\\]+$')
}

function Add-NetworkPrinterManual {
    $connectionName = Read-RequiredNonEmpty -Prompt 'Network printer UNC (example: \\server\queue)'
    if (-not (Test-PrinterConnectionName -ConnectionName $connectionName)) {
        throw "Invalid UNC printer path: $connectionName"
    }

    Add-Printer -ConnectionName $connectionName -ErrorAction Stop
    Write-Host "Added mapped network printer: $connectionName" -ForegroundColor Green
}

function Add-NetworkPrintersFromCsv {
    Ensure-TempDirectory
    $csvPath = Read-CsvPathUnderTemp -Prompt 'Network add CSV path under C:\Temp (example: C:\Temp\printer-add-network-template.csv)'
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
        $connectionName = $null
        if (-not [string]::IsNullOrWhiteSpace($row.ConnectionName)) {
            $connectionName = $row.ConnectionName.Trim()
        }
        elseif ((-not [string]::IsNullOrWhiteSpace($row.Server)) -and (-not [string]::IsNullOrWhiteSpace($row.Queue))) {
            $connectionName = "\\$($row.Server.Trim())\$($row.Queue.Trim())"
        }

        if ([string]::IsNullOrWhiteSpace($connectionName) -or (-not (Test-PrinterConnectionName -ConnectionName $connectionName))) {
            $fail++
            Write-Warning "Invalid network printer row. Expected ConnectionName or Server+Queue. Row: $($row | Out-String)"
            continue
        }

        try {
            Add-Printer -ConnectionName $connectionName -ErrorAction Stop
            $ok++
            Write-Host "Added: $connectionName" -ForegroundColor Green
        }
        catch {
            $fail++
            Write-Warning "Failed to add $($connectionName): $($_.Exception.Message)"
        }
    }

    Write-Host "Network CSV add complete. Success: $ok  Failed: $fail" -ForegroundColor Cyan
}

function ConvertTo-BoolOrDefault {
    param(
        [AllowNull()]
        [string]$Text,
        [bool]$DefaultValue = $false
    )

    if ([string]::IsNullOrWhiteSpace($Text)) {
        return $DefaultValue
    }
    switch -Regex ($Text.Trim()) {
        '^(?i:true|t|yes|y|1)$' { return $true }
        '^(?i:false|f|no|n|0)$' { return $false }
        default { return $DefaultValue }
    }
}

function Ensure-PrinterPortExists {
    param(
        [Parameter(Mandatory)]
        [string]$PortName,
        [string]$PrinterHostAddress
    )

    $existing = Get-PrinterPort -Name $PortName -ErrorAction SilentlyContinue
    if ($null -ne $existing) {
        return
    }

    if ([string]::IsNullOrWhiteSpace($PrinterHostAddress)) {
        throw "Port '$PortName' does not exist and no PrinterHostAddress was provided."
    }

    Add-PrinterPort -Name $PortName -PrinterHostAddress $PrinterHostAddress -ErrorAction Stop
    Write-Host "Created printer port $PortName ($PrinterHostAddress)" -ForegroundColor Green
}

function Add-LocalPrinter {
    param(
        [Parameter(Mandatory)]
        [string]$PrinterName,
        [Parameter(Mandatory)]
        [string]$DriverName,
        [Parameter(Mandatory)]
        [string]$PortName,
        [string]$PrinterHostAddress,
        [bool]$Shared = $false,
        [string]$ShareName
    )

    Ensure-PrinterPortExists -PortName $PortName -PrinterHostAddress $PrinterHostAddress

    $addParams = @{
        Name       = $PrinterName
        DriverName = $DriverName
        PortName   = $PortName
        ErrorAction = 'Stop'
    }
    Add-Printer @addParams

    if ($Shared) {
        $finalShare = $ShareName
        if ([string]::IsNullOrWhiteSpace($finalShare)) {
            $finalShare = $PrinterName
        }
        Set-Printer -Name $PrinterName -Shared $true -ShareName $finalShare -ErrorAction Stop
    }
}

function Add-LocalPrinterManual {
    $printerName = Read-RequiredNonEmpty -Prompt 'Printer name'
    $driverName = Read-RequiredNonEmpty -Prompt 'Driver name (must already exist on system)'
    $portName = Read-RequiredNonEmpty -Prompt 'Port name (existing or new, e.g. IP_10.0.0.50)'
    $hostAddress = Read-Host -Prompt 'Printer host/IP for new port (optional if port already exists)'

    $isShared = Test-ReadHostYes -Prompt 'Share this printer? (Y/N)'
    $shareName = $null
    if ($isShared) {
        $shareName = Read-Host -Prompt "Share name [Enter for $printerName]"
    }

    Add-LocalPrinter -PrinterName $printerName -DriverName $driverName -PortName $portName -PrinterHostAddress $hostAddress -Shared $isShared -ShareName $shareName
    Write-Host "Added local/IP printer: $printerName" -ForegroundColor Green
}

function Add-LocalPrintersFromCsv {
    Ensure-TempDirectory
    $csvPath = Read-CsvPathUnderTemp -Prompt 'Local/IP add CSV path under C:\Temp (example: C:\Temp\printer-add-local-template.csv)'
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
        $printerName = [string]$row.PrinterName
        $driverName = [string]$row.DriverName
        $portName = [string]$row.PortName
        if ([string]::IsNullOrWhiteSpace($printerName) -or [string]::IsNullOrWhiteSpace($driverName) -or [string]::IsNullOrWhiteSpace($portName)) {
            $fail++
            Write-Warning "Invalid local row. Required: PrinterName, DriverName, PortName. Row: $($row | Out-String)"
            continue
        }

        try {
            $shared = ConvertTo-BoolOrDefault -Text ([string]$row.Shared) -DefaultValue $false
            Add-LocalPrinter -PrinterName $printerName.Trim() -DriverName $driverName.Trim() -PortName $portName.Trim() -PrinterHostAddress ([string]$row.PrinterHostAddress) -Shared $shared -ShareName ([string]$row.ShareName)
            $ok++
            Write-Host "Added: $($printerName.Trim())" -ForegroundColor Green
        }
        catch {
            $fail++
            Write-Warning "Failed to add $($printerName): $($_.Exception.Message)"
        }
    }

    Write-Host "Local/IP CSV add complete. Success: $ok  Failed: $fail" -ForegroundColor Cyan
}

function Invoke-AddAction {
    Write-Host ''
    Write-Host 'Add options:' -ForegroundColor Yellow
    Write-Host '  [1] Network mapped printer'
    Write-Host '  [2] Local/IP printer'
    $typeChoice = Read-MenuChoice -Prompt 'Choose add type (1-2)' -AllowedChoices @('1', '2')

    Write-Host '  [1] Manual'
    Write-Host '  [2] CSV'
    $modeChoice = Read-MenuChoice -Prompt 'Choose add mode (1-2)' -AllowedChoices @('1', '2')

    if ($typeChoice -eq '1' -and $modeChoice -eq '1') {
        Add-NetworkPrinterManual
        return
    }
    if ($typeChoice -eq '1' -and $modeChoice -eq '2') {
        Add-NetworkPrintersFromCsv
        return
    }
    if ($typeChoice -eq '2' -and $modeChoice -eq '1') {
        Add-LocalPrinterManual
        return
    }
    Add-LocalPrintersFromCsv
}

function Invoke-DeleteAction {
    param(
        [object[]]$MappedPrinters = @()
    )

    Write-Host ''
    Write-Host 'Delete options:' -ForegroundColor Yellow
    Write-Host '  [1] Delete mapped connections for current user (registry)'
    Write-Host '  [2] Delete installed printers from CSV (Remove-Printer)'
    $deleteMode = Read-MenuChoice -Prompt 'Choose delete mode (1-2)' -AllowedChoices @('1', '2')

    if ($deleteMode -eq '2') {
        Ensure-TempDirectory
        $csvPath = Read-CsvPathUnderTemp -Prompt 'Installed-printer delete CSV path under C:\Temp (example: C:\Temp\printer-remove-template.csv)'
        if (-not (Test-Path -LiteralPath $csvPath)) {
            throw "CSV file not found: $csvPath"
        }

        $rows = @(Import-Csv -Path $csvPath)
        if ($rows.Count -eq 0) {
            throw "CSV has no rows: $csvPath"
        }

        $ok = 0
        $fail = 0
        $skip = 0
        foreach ($row in $rows) {
            $printerName = [string]$row.PrinterName
            if ([string]::IsNullOrWhiteSpace($printerName)) {
                $skip++
                Write-Warning "Skipping row with blank PrinterName: $($row | Out-String)"
                continue
            }

            try {
                Remove-Printer -Name $printerName.Trim() -ErrorAction Stop
                $ok++
                Write-Host "Successfully removed printer: $($printerName.Trim())" -ForegroundColor Green
            }
            catch {
                $fail++
                Write-Warning "Failed to remove printer '$($printerName.Trim())': $($_.Exception.Message)"
            }
        }

        Write-Host "Installed printer removal complete. Success: $ok  Failed: $fail  Skipped: $skip" -ForegroundColor Cyan
        return
    }

    if ($MappedPrinters.Count -eq 0) {
        Write-Host 'No mapped printer connections to delete for this user.' -ForegroundColor Green
        return
    }

    $selectedIndexes = @(Read-PrinterSelectionIndexes -MaximumIndex $MappedPrinters.Count)
    $targets = @($selectedIndexes | ForEach-Object { $MappedPrinters[$_ - 1] })

    Write-Host ''
    Write-Host "Selected $($targets.Count) printer connection(s) for deletion:" -ForegroundColor Yellow
    $targets | Select-Object -Property PrinterName | Format-Table -AutoSize

    if (-not (Test-ReadHostYes -Prompt "Remove these $($targets.Count) selected printer connection(s)? (Y/N)")) {
        Write-Host 'Cancelled. No changes made.' -ForegroundColor Cyan
        return
    }

    foreach ($t in $targets) {
        Write-Host "Removing printer connection: $($t.PrinterName) (SID $($t.Sid))" -ForegroundColor Yellow
        try {
            Remove-Item -LiteralPath $t.PsPath -Recurse -Force -ErrorAction Stop
        }
        catch {
            Write-Warning "Could not remove $($t.PsPath): $($_.Exception.Message)"
        }
    }

    Write-Host 'Delete action complete.' -ForegroundColor Green
}

function Invoke-RenameActionCsv {
    Ensure-TempDirectory
    $csvPath = Read-CsvPathUnderTemp -Prompt 'Rename CSV path under C:\Temp (example: C:\Temp\printer-rename-template.csv)'
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
        $oldName = [string]$row.OldName
        $newName = [string]$row.NewName
        if ([string]::IsNullOrWhiteSpace($oldName) -or [string]::IsNullOrWhiteSpace($newName)) {
            $fail++
            Write-Warning "Invalid rename row. Required columns: OldName, NewName. Row: $($row | Out-String)"
            continue
        }

        try {
            Rename-Printer -Name $oldName.Trim() -NewName $newName.Trim() -ErrorAction Stop
            try {
                $printer = Get-Printer -Name $newName.Trim() -ErrorAction Stop
                if ($printer.Shared) {
                    Set-Printer -Name $newName.Trim() -ShareName $newName.Trim() -Shared $true -ErrorAction Stop
                }
            }
            catch {
                # Renamed printer may not be shared or query may fail; keep rename result.
            }
            $ok++
            Write-Host "Successfully renamed printer $oldName to $newName" -ForegroundColor Green
        }
        catch {
            $fail++
            Write-Warning "Error renaming printer $($oldName): $($_.Exception.Message)"
        }
    }

    Write-Host "Rename CSV complete. Success: $ok  Failed: $fail" -ForegroundColor Cyan
}

function Invoke-RenameActionInteractive {
    $printers = @(Get-Printer -ErrorAction SilentlyContinue | Sort-Object -Property Name)
    if ($printers.Count -eq 0) {
        Write-Host 'No installed printers available to rename.' -ForegroundColor Yellow
        return
    }

    Write-Host ''
    Write-Host 'Installed printers:' -ForegroundColor Yellow
    for ($i = 0; $i -lt $printers.Count; $i++) {
        Write-Host ("[{0}] {1}" -f ($i + 1), $printers[$i].Name)
    }

    $choice = [int](Read-MenuChoice -Prompt "Choose printer to rename (1-$($printers.Count))" -AllowedChoices (1..$printers.Count | ForEach-Object { "$_" }))
    $oldName = $printers[$choice - 1].Name
    $newName = Read-RequiredNonEmpty -Prompt "New printer name for '$oldName'"

    if (-not (Test-ReadHostYes -Prompt "Rename '$oldName' to '$newName'? (Y/N)")) {
        Write-Host 'Cancelled. No changes made.' -ForegroundColor Cyan
        return
    }

    Rename-Printer -Name $oldName -NewName $newName -ErrorAction Stop
    try {
        $renamed = Get-Printer -Name $newName -ErrorAction Stop
        if ($renamed.Shared) {
            Set-Printer -Name $newName -ShareName $newName -Shared $true -ErrorAction Stop
        }
    }
    catch {
        # Keep successful rename result even if share update fails.
    }

    Write-Host "Renamed printer '$oldName' to '$newName'." -ForegroundColor Green
}

function Invoke-RenameAction {
    Write-Host ''
    Write-Host 'Rename options:' -ForegroundColor Yellow
    Write-Host '  [1] CSV mode (OldName,NewName)'
    Write-Host '  [2] Interactive mode'
    $modeChoice = Read-MenuChoice -Prompt 'Choose rename mode (1-2)' -AllowedChoices @('1', '2')

    if ($modeChoice -eq '1') {
        Invoke-RenameActionCsv
        return
    }
    Invoke-RenameActionInteractive
}

function Invoke-Main {
    $loadedSids = @(Get-ChildItem -Path 'Registry::HKEY_USERS' -ErrorAction SilentlyContinue |
        ForEach-Object { $_.PSChildName } |
        Where-Object { $_ -notmatch '_Classes$' })

    if ($loadedSids.Count -eq 0) {
        Write-Host 'No loaded user hives were found under HKEY_USERS.' -ForegroundColor Yellow
        return
    }

    $targetContext = Resolve-TargetUserContext -LoadedSids $loadedSids
    if ($null -eq $targetContext) {
        Write-Host 'Could not resolve a currently logged-in/current loaded user SID to target.' -ForegroundColor Yellow
        return
    }

    Write-Host "Target user: $($targetContext.UserDisplay) [$($targetContext.Sid)] via $($targetContext.Source)" -ForegroundColor Cyan

    while ($true) {
        $mappedPrinters = @(Get-PrinterConnectionsForSid -Sid $targetContext.Sid)
        Show-MappedPrinterConnections -Printers $mappedPrinters
        Show-InstalledPrinters

        Write-Host ''
        Write-Host 'Actions:' -ForegroundColor Yellow
        Write-Host '  [1] Add'
        Write-Host '  [2] Delete'
        Write-Host '  [3] Rename'
        Write-Host '  [4] Exit'
        $action = Read-MenuChoice -Prompt 'Choose action (1-4)' -AllowedChoices @('1', '2', '3', '4')

        try {
            switch ($action) {
                '1' { Invoke-AddAction }
                '2' { Invoke-DeleteAction -MappedPrinters $mappedPrinters }
                '3' { Invoke-RenameAction }
                '4' {
                    Write-Host 'Exiting printer management.' -ForegroundColor Cyan
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
