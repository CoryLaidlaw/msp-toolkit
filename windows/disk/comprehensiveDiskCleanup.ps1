<#!
.SYNOPSIS
    Performs a comprehensive disk cleanup operation with granular logging and optional task toggles.
.DESCRIPTION
    Removes temporary files, clears recycle bin, runs DISM cleanup, adjusts page file settings,
    marks OneDrive folders as online-only, and removes targeted user profiles. Uses takeown,
    icacls, and robocopy to ensure stubborn files are removed. Reports free space before and after
    the cleanup and, if needed, gathers additional diagnostics. Each task can be individually
    toggled and detailed activity is written to a log file and optionally to the console with
    configurable verbosity.
#>

[CmdletBinding()]
param(
    [bool]$CleanUserTemp = $true,
    [bool]$CleanSystemTemp = $true,
    [bool]$CleanCTemp = $true,
    [bool]$CleanWindowsUpdateCache = $true,
    [bool]$CleanPrefetch = $true,
    [bool]$CleanPrintSpooler = $true,
    [bool]$ClearRecycleBin = $true,
    [bool]$RunDismCleanup = $true,
    [bool]$SetOneDriveOnlineOnly = $false,
    [bool]$ConfigurePageFile = $false,
    [bool]$RemoveTargetedProfiles = $true,
    [ValidateSet('Off', 'Steps', 'Substeps', 'Verbose')]
    [string]$ConsoleOutputLevel = 'Steps',
    [string]$LogDirectory = 'C:\\Temp',
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:LogFile = $null
$script:ConsoleThreshold = switch ($ConsoleOutputLevel) {
    'Off'       { 0 }
    'Steps'     { 1 }
    'Substeps'  { 2 }
    'Verbose'   { 3 }
    default     { 1 }
}

$script:IsDryRun = [bool]$DryRun

function Invoke-DryRunOperation {
    param(
        [Parameter(Mandatory)][string]$Description,
        [Parameter()][scriptblock]$Operation,
        [ValidateSet('Step', 'Substep', 'Verbose', 'Info')]
        [string]$Level = 'Verbose'
    )

    if ($script:IsDryRun) {
        Write-Log -Message "DryRun: $Description" -Level $Level
        return $null
    }

    if ($null -ne $Operation) {
        return & $Operation
    }
}

function Initialize-Logging {
    param(
        [Parameter(Mandatory)][string]$Directory
    )

    if (-not (Test-Path -LiteralPath $Directory)) {
        New-Item -ItemType Directory -Path $Directory -Force | Out-Null
    }

    $timestamp = Get-Date -Format 'yyyyMMdd_HHmmss'
    $script:LogFile = Join-Path -Path $Directory -ChildPath "ComprehensiveDiskCleanup_$timestamp.log"
    New-Item -ItemType File -Path $script:LogFile -Force | Out-Null
}

function Write-Log {
    param(
        [Parameter(Mandatory)][string]$Message,
        [ValidateSet('Step', 'Substep', 'Verbose', 'Info', 'Warning', 'Error')]
        [string]$Level = 'Info'
    )

    $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    $entry = "[$timestamp][$Level] $Message"

    if ($script:LogFile) {
        Add-Content -Path $script:LogFile -Value $entry
    }

    $levelRank = switch ($Level) {
        'Error'   { 1 }
        'Warning' { 1 }
        'Step'    { 1 }
        'Info'    { 1 }
        'Substep' { 2 }
        'Verbose' { 3 }
        default   { 3 }
    }

    $shouldWrite = $false

    if ($ConsoleOutputLevel -eq 'Off') {
        if ($Level -in @('Warning', 'Error')) {
            $shouldWrite = $true
        }
    }
    elseif ($levelRank -le $script:ConsoleThreshold) {
        $shouldWrite = $true
    }

    if ($shouldWrite) {
        switch ($Level) {
            'Error'   { Write-Error $Message }
            'Warning' { Write-Warning $Message }
            default   { Write-Output $Message }
        }
    }
}

Initialize-Logging -Directory $LogDirectory
Write-Log -Message "Logging initialized. Log file: $script:LogFile" -Level 'Info'

if ($script:IsDryRun) {
    Write-Log -Message 'DryRun mode enabled. No changes will be made.' -Level 'Info'
}

function Prompt-UserYesNo {
    param(
        [Parameter(Mandatory)][string]$Prompt
    )

    while ($true) {
        $response = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($response)) {
            Write-Log -Message 'No response detected. Please enter Y or N.' -Level 'Warning'
            continue
        }

        switch ($response.Trim().ToLowerInvariant()) {
            { $_ -in @('y', 'yes') } { return $true }
            { $_ -in @('n', 'no') } { return $false }
            default {
                Write-Log -Message 'Invalid response. Please enter Y or N.' -Level 'Warning'
            }
        }
    }
}

function Get-LargeOneDriveFolders {
    $results = @()
    try {
        $oneDriveFolders = Get-ChildItem -Path 'C:\Users' -Directory -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -match '\\OneDrive' } |
            Select-Object -Unique -Property FullName

        foreach ($folder in $oneDriveFolders) {
            try {
                $sizeBytes = (Get-ChildItem -LiteralPath $folder.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } |
                    Measure-Object -Property Length -Sum).Sum
                $sizeGB = if ($sizeBytes) { [math]::Round($sizeBytes / 1GB, 2) } else { 0 }
                $results += [pscustomobject]@{
                    FullName = $folder.FullName
                    SizeGB   = $sizeGB
                }
            }
            catch {
                Write-Log -Message "Unable to evaluate size for OneDrive folder $($folder.FullName) : $($_.Exception.Message)" -Level 'Warning'
            }
        }
    }
    catch {
        Write-Log -Message "Unable to enumerate OneDrive folders : $($_.Exception.Message)" -Level 'Warning'
    }

    return $results | Where-Object { $_.SizeGB -gt 10 }
}

function Get-PageFileSizeInfo {
    $pageFiles = @()
    try {
        $pageFileUsage = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop
        foreach ($entry in $pageFileUsage) {
            $sizeGB = if ($entry.AllocatedBaseSize) { [math]::Round($entry.AllocatedBaseSize / 1024, 2) } else { 0 }
            $pageFiles += [pscustomobject]@{
                Path   = $entry.Name
                SizeGB = $sizeGB
            }
        }
    }
    catch {
        Write-Log -Message "Unable to retrieve page file usage information : $($_.Exception.Message)" -Level 'Warning'
    }

    if (-not $pageFiles -and (Test-Path -LiteralPath 'C:\pagefile.sys')) {
        try {
            $pageFile = Get-Item -LiteralPath 'C:\pagefile.sys' -ErrorAction Stop
            $sizeGB = [math]::Round($pageFile.Length / 1GB, 2)
            $pageFiles += [pscustomobject]@{
                Path   = $pageFile.FullName
                SizeGB = $sizeGB
            }
        }
        catch {
            Write-Log -Message "Unable to access C:\\pagefile.sys : $($_.Exception.Message)" -Level 'Warning'
        }
    }

    return $pageFiles
}

$script:OneDriveDeclinedInitially = $false
$script:PageFileDeclinedInitially = $false

if (-not $SetOneDriveOnlineOnly) {
    $largeOneDriveFolders = Get-LargeOneDriveFolders
    if ($largeOneDriveFolders) {
        foreach ($folder in $largeOneDriveFolders) {
            Write-Log -Message "Detected OneDrive folder exceeding 10 GB: $($folder.FullName) ($($folder.SizeGB) GB)." -Level 'Info'
        }

        if (Prompt-UserYesNo -Prompt 'Run Set OneDrive folders to online-only now? (Y/N)') {
            $SetOneDriveOnlineOnly = $true
            Write-Log -Message 'User opted to run the OneDrive online-only step based on initial prompt.' -Level 'Info'
        }
        else {
            $script:OneDriveDeclinedInitially = $true
            Write-Log -Message 'User declined the OneDrive online-only step during the initial prompt.' -Level 'Info'
        }
    }
}

if (-not $ConfigurePageFile) {
    $pageFiles = Get-PageFileSizeInfo | Where-Object { $_.SizeGB -gt 10 }
    if ($pageFiles) {
        foreach ($pageFile in $pageFiles) {
            Write-Log -Message "Detected page file exceeding 10 GB: $($pageFile.Path) ($($pageFile.SizeGB) GB)." -Level 'Info'
        }

        if (Prompt-UserYesNo -Prompt 'Run Configure page file size now? (Y/N)') {
            $ConfigurePageFile = $true
            Write-Log -Message 'User opted to configure the page file based on initial prompt.' -Level 'Info'
        }
        else {
            $script:PageFileDeclinedInitially = $true
            Write-Log -Message 'User declined the page file configuration during the initial prompt.' -Level 'Info'
        }
    }
}

function Get-FreeSpaceInfo {
    param(
        [Parameter(Mandatory)][string]$DriveLetter
    )

    $drive = Get-PSDrive -Name $DriveLetter
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    $totalGB = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $percentFree = if ($totalGB -eq 0) { 0 } else { [math]::Round(($freeGB / $totalGB) * 100, 2) }

    [pscustomobject]@{
        Drive       = $DriveLetter
        FreeGB      = $freeGB
        TotalGB     = $totalGB
        PercentFree = $percentFree
    }
}

function Invoke-ManagedStep {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][bool]$Enabled,
        [Parameter(Mandatory)][scriptblock]$ScriptBlock
    )

    if (-not $Enabled) {
        Write-Log -Message "Skipping $Name (disabled)." -Level 'Step'
        return
    }

    Write-Log -Message "Starting $Name." -Level 'Step'
    try {
        & $ScriptBlock
        Write-Log -Message "Completed $Name." -Level 'Step'
    }
    catch {
        Write-Log -Message "Failed $Name : $($_.Exception.Message)" -Level 'Error'
        throw
    }
}

function Invoke-DeletionSequence {
    param(
        [Parameter(Mandatory)][string]$TargetPath
    )

    Write-Log -Message "Preparing to delete $TargetPath." -Level 'Substep'

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-Log -Message "Path not found: $TargetPath. Skipping." -Level 'Substep'
        return
    }

    try {
        $item = Get-Item -LiteralPath $TargetPath -Force -ErrorAction Stop
    }
    catch {
        Write-Log -Message "Unable to access $TargetPath : $($_.Exception.Message)" -Level 'Warning'
        return
    }

    if ($script:IsDryRun) {
        Write-Log -Message "DryRun: Would delete $TargetPath." -Level 'Substep'
        return
    }

    if ($item.PSIsContainer) {
        Write-Log -Message "Taking ownership of directory $TargetPath." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Taking ownership of directory $TargetPath with takeown.exe." -Operation {
            takeown.exe /F "$TargetPath" /A /R /D Y | Out-Null
        } | Out-Null
        Write-Log -Message "Granting Administrators full control on $TargetPath." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Grant Administrators full control on $TargetPath with icacls.exe." -Operation {
            icacls.exe "$TargetPath" /grant Administrators:F /T /C | Out-Null
        } | Out-Null

        $emptyDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        Write-Log -Message "Creating temporary directory $emptyDir for robocopy mirror." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Create temporary directory $emptyDir." -Operation {
            New-Item -ItemType Directory -Path $emptyDir | Out-Null
        } | Out-Null
        try {
            $arguments = @($emptyDir, $TargetPath, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS')
            Write-Log -Message "Executing robocopy to clear directory $TargetPath." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Execute robocopy.exe to mirror empty directory to $TargetPath." -Operation {
                robocopy.exe @arguments | Out-Null
            } | Out-Null
        }
        finally {
            Write-Log -Message "Removing temporary directory $emptyDir." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Remove temporary directory $emptyDir." -Operation {
                Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
            } | Out-Null
        }

        if (Test-Path -LiteralPath $TargetPath) {
            Write-Log -Message "Removing directory $TargetPath using Remove-Item." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Remove directory $TargetPath." -Operation {
                Remove-Item -LiteralPath $TargetPath -Force -Recurse -ErrorAction SilentlyContinue
            } | Out-Null
        }
    }
    else {
        Write-Log -Message "Taking ownership of file $TargetPath." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Taking ownership of file $TargetPath with takeown.exe." -Operation {
            takeown.exe /F "$TargetPath" /A | Out-Null
        } | Out-Null
        Write-Log -Message "Granting Administrators full control on file $TargetPath." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Grant Administrators full control on file $TargetPath with icacls.exe." -Operation {
            icacls.exe "$TargetPath" /grant Administrators:F /C | Out-Null
        } | Out-Null

        $emptyDir = Join-Path -Path ([System.IO.Path]::GetTempPath()) -ChildPath ([guid]::NewGuid().Guid)
        Write-Log -Message "Creating temporary directory $emptyDir for robocopy mirror." -Level 'Verbose'
        Invoke-DryRunOperation -Description "Create temporary directory $emptyDir." -Operation {
            New-Item -ItemType Directory -Path $emptyDir | Out-Null
        } | Out-Null
        try {
            $parent = Split-Path -Path $TargetPath -Parent
            $arguments = @($emptyDir, $parent, $item.Name, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS')
            Write-Log -Message "Executing robocopy to clear file $TargetPath." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Execute robocopy.exe to mirror empty directory to $TargetPath." -Operation {
                robocopy.exe @arguments | Out-Null
            } | Out-Null
        }
        finally {
            Write-Log -Message "Removing temporary directory $emptyDir." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Remove temporary directory $emptyDir." -Operation {
                Remove-Item -LiteralPath $emptyDir -Recurse -Force -ErrorAction SilentlyContinue
            } | Out-Null
        }

        if (Test-Path -LiteralPath $TargetPath) {
            Write-Log -Message "Removing file $TargetPath using Remove-Item." -Level 'Verbose'
            Invoke-DryRunOperation -Description "Remove file $TargetPath." -Operation {
                Remove-Item -LiteralPath $TargetPath -Force -ErrorAction SilentlyContinue
            } | Out-Null
        }
    }

    if (Test-Path -LiteralPath $TargetPath) {
        Write-Log -Message "Failed to delete $TargetPath." -Level 'Warning'
    }
    else {
        Write-Log -Message "Deleted $TargetPath." -Level 'Substep'
    }
}

function Clear-DirectoryContents {
    param(
        [Parameter(Mandatory)][string]$DirectoryPath
    )

    Write-Log -Message "Clearing contents of $DirectoryPath." -Level 'Substep'

    if (-not (Test-Path -LiteralPath $DirectoryPath)) {
        Write-Log -Message "Directory not found: $DirectoryPath. Skipping." -Level 'Warning'
        return
    }

    Get-ChildItem -LiteralPath $DirectoryPath -Force -ErrorAction SilentlyContinue |
        ForEach-Object { Invoke-DeletionSequence -TargetPath $_.FullName }
}

$initialInfo = Get-FreeSpaceInfo -DriveLetter 'C'
Write-Log -Message "Initial Free Space: $($initialInfo.FreeGB) GB ($($initialInfo.PercentFree)% of $($initialInfo.TotalGB) GB)." -Level 'Info'

Invoke-ManagedStep -Name 'Clear user TEMP folder' -Enabled $CleanUserTemp -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath $env:TEMP
}

Invoke-ManagedStep -Name 'Clear system TEMP folder' -Enabled $CleanSystemTemp -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath 'C:\\Windows\\Temp'
}

Invoke-ManagedStep -Name 'Clear C:\\Temp contents' -Enabled $CleanCTemp -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath 'C:\\Temp'
}

Invoke-ManagedStep -Name 'Clear Windows Update Download cache' -Enabled $CleanWindowsUpdateCache -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath 'C:\\Windows\\SoftwareDistribution\\Download'
}

Invoke-ManagedStep -Name 'Clear Windows Prefetch data' -Enabled $CleanPrefetch -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath 'C:\\Windows\\Prefetch'
}

Invoke-ManagedStep -Name 'Clear print spooler cache' -Enabled $CleanPrintSpooler -ScriptBlock {
    Clear-DirectoryContents -DirectoryPath 'C:\\Windows\\System32\\spool\\PRINTERS'
}

Invoke-ManagedStep -Name 'Clear Recycle Bin' -Enabled $ClearRecycleBin -ScriptBlock {
    Write-Log -Message 'Emptying recycle bin.' -Level 'Substep'
    if ($script:IsDryRun) {
        Write-Log -Message 'DryRun: Would execute Clear-RecycleBin -Force.' -Level 'Substep'
    }
    else {
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            Write-Log -Message 'Recycle bin emptied successfully.' -Level 'Substep'
        }
        catch {
            Write-Log -Message "Failed to clear recycle bin : $($_.Exception.Message)" -Level 'Warning'
            throw
        }
    }
}

Invoke-ManagedStep -Name 'Run DISM component cleanup' -Enabled $RunDismCleanup -ScriptBlock {
    $arguments = '/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase'
    Write-Log -Message "Executing DISM with arguments: $($arguments -join ' ')." -Level 'Substep'
    $process = Invoke-DryRunOperation -Description 'Execute DISM component cleanup.' -Operation {
        Start-Process -FilePath 'dism.exe' -ArgumentList $arguments -Wait -NoNewWindow -PassThru
    } -Level 'Substep'
    if (-not $script:IsDryRun) {
        if ($process.ExitCode -ne 0) {
            Write-Log -Message "DISM exited with code $($process.ExitCode)." -Level 'Warning'
            throw "DISM failed with exit code $($process.ExitCode)."
        }
        Write-Log -Message 'DISM component cleanup completed successfully.' -Level 'Substep'
    }
}

$setOneDriveOnlineOnlyScript = {
    Write-Log -Message 'Searching for OneDrive folders.' -Level 'Substep'
    $oneDriveFolders = Get-ChildItem -Path 'C:\\Users' -Directory -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -match '\\OneDrive' } |
        Select-Object -Unique -Property FullName

    foreach ($folder in $oneDriveFolders) {
        Write-Log -Message "Setting OneDrive folder to online-only: $($folder.FullName)." -Level 'Substep'
        Invoke-DryRunOperation -Description "Set OneDrive folder to online-only at $($folder.FullName)." -Operation {
            attrib.exe +U -P "$($folder.FullName)" /S /D | Out-Null
        } -Level 'Substep' | Out-Null
    }

    if (-not $oneDriveFolders) {
        Write-Log -Message 'No OneDrive folders located.' -Level 'Substep'
    }
}

Invoke-ManagedStep -Name 'Set OneDrive folders to online-only' -Enabled $SetOneDriveOnlineOnly -ScriptBlock $setOneDriveOnlineOnlyScript

$configurePageFileScript = {
    Write-Log -Message 'Disabling automatic page file management.' -Level 'Substep'
    Invoke-DryRunOperation -Description 'Disable automatic page file management with WMIC.' -Operation {
        wmic.exe computersystem where "name='%computername%'" set AutomaticManagedPagefile=False | Out-Null
    } -Level 'Substep' | Out-Null

    Write-Log -Message 'Configuring pagefile to InitialSize=4096, MaximumSize=8192.' -Level 'Substep'
    Invoke-DryRunOperation -Description 'Set existing pagefile size with WMIC.' -Operation {
        wmic.exe pagefileset where "name='C:\\pagefile.sys'" set InitialSize=4096,MaximumSize=8192
    } -Level 'Substep' | Out-Null
    if (-not $script:IsDryRun) {
        if ($LASTEXITCODE -ne 0) {
            Write-Log -Message 'Existing pagefile entry not found. Creating new pagefile configuration.' -Level 'Warning'
            Invoke-DryRunOperation -Description 'Create new pagefile configuration with WMIC.' -Operation {
                wmic.exe pagefileset create name="C:\\pagefile.sys" | Out-Null
                wmic.exe pagefileset where "name='C:\\pagefile.sys'" set InitialSize=4096,MaximumSize=8192 | Out-Null
            } -Level 'Substep' | Out-Null
        }
    }
}

Invoke-ManagedStep -Name 'Configure page file size' -Enabled $ConfigurePageFile -ScriptBlock $configurePageFileScript

Invoke-ManagedStep -Name 'Remove targeted user profiles' -Enabled $RemoveTargetedProfiles -ScriptBlock {
    Write-Log -Message 'Locating targeted user profiles.' -Level 'Substep'
    $profiles = Get-CimInstance -ClassName Win32_UserProfile -ErrorAction Stop |
        Where-Object {
            $_.LocalPath -and (
                $_.LocalPath.ToLower().EndsWith('_jit') -or
                (Split-Path -Leaf $_.LocalPath) -like 'phreedom*'
            )
        }

    foreach ($profile in $profiles) {
        $path = $profile.LocalPath
        Write-Log -Message "Attempting to remove profile via WMI: $path." -Level 'Substep'
        if ($script:IsDryRun) {
            Write-Log -Message "DryRun: Would remove user profile $path via WMI." -Level 'Substep'
        }
        else {
            try {
                Remove-CimInstance -InputObject $profile -ErrorAction Stop
                Write-Log -Message "Removed profile via WMI: $path." -Level 'Substep'
            }
            catch {
                Write-Log -Message "Failed to remove profile via WMI for $path : $($_.Exception.Message)" -Level 'Warning'
            }
        }

        if (Test-Path -LiteralPath $path) {
            Invoke-DeletionSequence -TargetPath $path
        }
    }

    if (-not $profiles) {
        Write-Log -Message 'No targeted profiles found.' -Level 'Substep'
    }
}

$finalInfo = Get-FreeSpaceInfo -DriveLetter 'C'
Write-Log -Message "Final Free Space: $($finalInfo.FreeGB) GB ($($finalInfo.PercentFree)% of $($finalInfo.TotalGB) GB)." -Level 'Info'

$freed = [math]::Round($finalInfo.FreeGB - $initialInfo.FreeGB, 2)
Write-Log -Message "Net Space Freed: $freed GB." -Level 'Info'

$additionalActionsRun = $false

if ($finalInfo.PercentFree -lt 10) {
    Write-Log -Message 'Free space remains below 10% after initial cleanup.' -Level 'Warning'

    if ($script:OneDriveDeclinedInitially) {
        $largeOneDriveFolders = Get-LargeOneDriveFolders
        if ($largeOneDriveFolders) {
            foreach ($folder in $largeOneDriveFolders) {
                Write-Log -Message "OneDrive folder still exceeds 10 GB: $($folder.FullName) ($($folder.SizeGB) GB)." -Level 'Info'
            }

            if (Prompt-UserYesNo -Prompt 'Set OneDrive folders to online-only now? (Y/N)') {
                $SetOneDriveOnlineOnly = $true
                $script:OneDriveDeclinedInitially = $false
                Write-Log -Message 'User opted to run the OneDrive online-only step after the final prompt.' -Level 'Info'
                Invoke-ManagedStep -Name 'Set OneDrive folders to online-only' -Enabled $true -ScriptBlock $setOneDriveOnlineOnlyScript
                $additionalActionsRun = $true
            }
            else {
                Write-Log -Message 'User declined the OneDrive online-only step during the final prompt.' -Level 'Info'
            }
        }
    }

    if ($script:PageFileDeclinedInitially) {
        $pageFiles = Get-PageFileSizeInfo | Where-Object { $_.SizeGB -gt 10 }
        if ($pageFiles) {
            foreach ($pageFile in $pageFiles) {
                Write-Log -Message "Page file still exceeds 10 GB: $($pageFile.Path) ($($pageFile.SizeGB) GB)." -Level 'Info'
            }

            if (Prompt-UserYesNo -Prompt 'Configure page file size now? (Y/N)') {
                $ConfigurePageFile = $true
                $script:PageFileDeclinedInitially = $false
                Write-Log -Message 'User opted to configure the page file after the final prompt.' -Level 'Info'
                Invoke-ManagedStep -Name 'Configure page file size' -Enabled $true -ScriptBlock $configurePageFileScript
                $additionalActionsRun = $true
            }
            else {
                Write-Log -Message 'User declined page file configuration during the final prompt.' -Level 'Info'
            }
        }
    }

    if ($additionalActionsRun) {
        $finalInfo = Get-FreeSpaceInfo -DriveLetter 'C'
        Write-Log -Message "Free Space After Additional Actions: $($finalInfo.FreeGB) GB ($($finalInfo.PercentFree)% of $($finalInfo.TotalGB) GB)." -Level 'Info'
        $freed = [math]::Round($finalInfo.FreeGB - $initialInfo.FreeGB, 2)
        Write-Log -Message "Net Space Freed After Additional Actions: $freed GB." -Level 'Info'
    }

    if ($finalInfo.PercentFree -lt 10) {
        Write-Log -Message 'Free space remains below 10% after additional actions. Gathering diagnostics.' -Level 'Warning'

        $userProfiles = Get-ChildItem -Path 'C:\\Users' -Directory -ErrorAction SilentlyContinue
        $profileSizes = foreach ($profile in $userProfiles) {
            Write-Log -Message "Calculating size for profile $($profile.FullName)." -Level 'Substep'
            $sizeBytes = (Get-ChildItem -LiteralPath $profile.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum).Sum

            [pscustomobject]@{
                Profile = $profile.FullName
                SizeGB  = if ($sizeBytes) { [math]::Round($sizeBytes / 1GB, 2) } else { 0 }
            }
        }

        if ($profileSizes) {
            $formattedProfiles = $profileSizes | Sort-Object -Property SizeGB -Descending | Format-Table -AutoSize | Out-String
            Write-Log -Message "User Profile Sizes (GB):`n$formattedProfiles" -Level 'Info'
        }
        else {
            Write-Log -Message 'No user profiles found during diagnostic collection.' -Level 'Info'
        }

        Write-Log -Message 'Calculating size for C:\\Windows.' -Level 'Substep'
        $windowsSizeBytes = (Get-ChildItem -LiteralPath 'C:\\Windows' -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { -not $_.PSIsContainer } |
            Measure-Object -Property Length -Sum).Sum
        $windowsSizeGB = if ($windowsSizeBytes) { [math]::Round($windowsSizeBytes / 1GB, 2) } else { 0 }
        Write-Log -Message "C:\\Windows Size: $windowsSizeGB GB." -Level 'Info'

        if ($windowsSizeGB -gt 35) {
            Write-Log -Message 'Gathering sizes for top 10 largest C:\\Windows subfolders.' -Level 'Substep'
            $subfolderSizes = Get-ChildItem -Path 'C:\\Windows' -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $subSizeBytes = (Get-ChildItem -LiteralPath $_.FullName -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object { -not $_.PSIsContainer } |
                    Measure-Object -Property Length -Sum).Sum

                [pscustomobject]@{
                    Folder = $_.FullName
                    SizeGB = if ($subSizeBytes) { [math]::Round($subSizeBytes / 1GB, 2) } else { 0 }
                }
            }

            if ($subfolderSizes) {
                $formattedSubfolders = $subfolderSizes | Sort-Object -Property SizeGB -Descending | Select-Object -First 10 | Format-Table -AutoSize | Out-String
                Write-Log -Message "Top 10 Largest C:\\Windows Subfolders (GB):`n$formattedSubfolders" -Level 'Info'
            }
            else {
                Write-Log -Message 'Unable to gather C:\\Windows subfolder sizes.' -Level 'Warning'
            }
        }
    }
    else {
        Write-Log -Message 'Additional actions increased free space above 10%; skipping further diagnostics.' -Level 'Info'
    }
}
else {
    Write-Log -Message 'Post-cleanup free space is above 10%; no additional diagnostics required.' -Level 'Info'
}

Write-Log -Message 'Comprehensive disk cleanup script completed.' -Level 'Info'
