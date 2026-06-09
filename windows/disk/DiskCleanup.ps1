<#
.SYNOPSIS
    Clears common Windows caches and temporary data on the system drive.
.DESCRIPTION
    Removes files under well-known temp, update, WER, prefetch, and optional user-profile
    cache paths; runs cleanmgr and DISM component cleanup automatically when elevated.
    Profile-bound steps run only when not executing as LocalSystem.
    All choices are made through Read-Host prompts (no script parameters).
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

function Test-IsAdministrator {
    $principal = [Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()
    return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Test-IsLocalSystem {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ($id.User.Value -eq 'S-1-5-18')
}

function Remove-FilesSafely {
    param(
        [Parameter(Mandatory)]
        [string]$Path,
        [Parameter(Mandatory)]
        [string]$Description
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return
    }

    try {
        $items = Get-ChildItem -LiteralPath $Path -Recurse -Force -ErrorAction SilentlyContinue
        $count = ($items | Measure-Object).Count

        if ($count -gt 0) {
            Write-Output "Cleaning: $Description"
            $wildcard = Join-Path $Path '*'
            Remove-Item -Path $wildcard -Recurse -Force -ErrorAction SilentlyContinue
            Write-Output "  Removed $count item(s) under $Path"
        }
    }
    catch {
        Write-Warning "Could not clean: $Path — $($_.Exception.Message)"
    }
}

function Invoke-DismWithExitCheck {
    param(
        [Parameter(Mandatory)]
        [string[]]$ArgumentList,
        [Parameter(Mandatory)]
        [string]$StepName
    )

    $dism = Join-Path $env:SystemRoot 'System32\Dism.exe'
    if (-not (Test-Path -LiteralPath $dism)) {
        Write-Warning "DISM not found at $dism; skipping $StepName."
        return
    }

    $proc = Start-Process -FilePath $dism -ArgumentList $ArgumentList -Wait -NoNewWindow -PassThru
    if ($proc.ExitCode -ne 0) {
        Write-Warning "$StepName exited with code $($proc.ExitCode)."
    }
    else {
        Write-Output "  $StepName completed (exit 0)."
    }
}

function Remove-RecycleBinItem {
    param(
        [Parameter(Mandatory)]
        [System.IO.FileSystemInfo]$Item,
        [Parameter(Mandatory)]
        [string]$EmptyDir
    )

    if (-not $Item.PSIsContainer) {
        Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue
        return
    }

    # Directories may contain paths that exceed MAX_PATH, causing Remove-Item
    # -Recurse to hang. Mirror an empty directory into the target first to wipe
    # its contents via robocopy (which handles long paths natively), then remove
    # the resulting empty directory. The SID folder itself is never touched here.
    if (-not (Test-Path -LiteralPath $EmptyDir)) {
        New-Item -ItemType Directory -Path $EmptyDir -Force | Out-Null
    }

    $proc = Start-Process -FilePath 'robocopy.exe' `
        -ArgumentList @($EmptyDir, $Item.FullName, '/MIR', '/R:1', '/W:0', '/NFL', '/NDL', '/NJH', '/NJS') `
        -Wait -NoNewWindow -PassThru

    if ($proc.ExitCode -le 7) {
        Remove-Item -LiteralPath $Item.FullName -Force -ErrorAction SilentlyContinue
    }
    else {
        Write-Warning "  robocopy /MIR failed (exit $($proc.ExitCode)) for $($Item.FullName)"
    }
}

function Clear-AllRecycleBin {
    Write-Output 'Cleaning: Recycle Bin (all users, C drive)'

    $binRoot = 'C:\$Recycle.Bin'
    if (-not (Test-Path -LiteralPath $binRoot)) {
        Write-Output '  Recycle Bin path not found on C:.'
        return
    }

    $emptyDir = 'C:\empty'
    $sidFolders = Get-ChildItem -LiteralPath $binRoot -Force -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'S-1-5-*' }

    $touched = $false
    foreach ($sidFolder in $sidFolders) {
        try {
            $items = Get-ChildItem -LiteralPath $sidFolder.FullName -Force -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne 'desktop.ini' }
            $count = ($items | Measure-Object).Count
            if ($count -gt 0) {
                foreach ($item in $items) {
                    Remove-RecycleBinItem -Item $item -EmptyDir $emptyDir
                }
                $touched = $true
                Write-Output "  Removed $count item(s) under $($sidFolder.FullName)"
            }
        }
        catch {
            Write-Warning "Could not clear $($sidFolder.FullName) — $($_.Exception.Message)"
        }
    }

    if (Test-Path -LiteralPath $emptyDir) {
        Remove-Item -LiteralPath $emptyDir -Force -ErrorAction SilentlyContinue
    }

    if (-not $touched) {
        Write-Output '  Recycle Bin already empty.'
    }
}

function Invoke-CleanMgrSageRun {
    $volumeCachesPath = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\VolumeCaches'
    if (-not (Test-Path -LiteralPath $volumeCachesPath)) {
        Write-Warning "VolumeCaches registry path not found; skipping cleanmgr configuration."
        return
    }

    try {
        $caches = Get-ChildItem -Path $volumeCachesPath -ErrorAction Stop
        foreach ($cache in $caches) {
            Set-ItemProperty -Path $cache.PSPath -Name 'StateFlags0001' -Value 2 -ErrorAction SilentlyContinue
        }

        $proc = Start-Process -FilePath 'cleanmgr.exe' -ArgumentList '/sagerun:1' -WindowStyle Hidden -PassThru
        if (-not $proc.WaitForExit(300000)) {
            $proc.Kill()
            Write-Warning "cleanmgr did not finish within 5 minutes; process was terminated."
        }
        elseif ($proc.ExitCode -ne 0) {
            Write-Warning "cleanmgr exited with code $($proc.ExitCode)."
        }
        else {
            Write-Output "  Disk Cleanup utility (sagerun) finished (exit 0)."
        }
    }
    catch {
        Write-Warning "Could not run Disk Cleanup utility — $($_.Exception.Message)"
    }
}

function Invoke-Main {
    # --- Input collection and validation ---
    $isAdmin = Test-IsAdministrator
    $isSystem = Test-IsLocalSystem

    if (-not $isAdmin) {
        Write-Warning 'Not running elevated: admin-only steps (Windows Update cache, Prefetch, Delivery Optimization, cleanmgr, DISM) will be skipped.'
    }

    Write-Output 'This script deletes temporary files, caches, and when elevated runs cleanmgr (Disk Cleanup) and DISM /ResetBase.'
    Write-Output 'Profile cache steps are skipped when running as LocalSystem.'
    if (-not (Test-ReadHostYes -Prompt 'Continue with cleanup? (Y/N)')) {
        Write-Output 'Aborted by operator.'
        return
    }

    # --- Main execution ---
    $drive = Get-PSDrive -Name C -ErrorAction Stop
    $initialFreeSpace = [math]::Round($drive.Free / 1GB, 2)
    $totalSpace = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $initialPercentFree = 0
    if (($drive.Used + $drive.Free) -ne 0) {
        $initialPercentFree = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
    }

    Write-Output "Initial free space on C: $initialFreeSpace GB of $totalSpace GB ($initialPercentFree%)"

    Remove-FilesSafely -Path 'C:\Windows\Temp' -Description 'Windows Temp folder'

    if (-not $isSystem) {
        $tempPath = [System.IO.Path]::GetTempPath().TrimEnd('\')
        Remove-FilesSafely -Path $tempPath -Description 'Current user Temp folder'
    }

    if (-not (Test-Path -LiteralPath 'C:\Temp')) {
        New-Item -ItemType Directory -Path 'C:\Temp' -Force | Out-Null
    }
    Remove-FilesSafely -Path 'C:\Temp' -Description 'C:\Temp folder'

    Clear-AllRecycleBin

    if ($isAdmin) {
        Remove-FilesSafely -Path 'C:\Windows\SoftwareDistribution\Download' -Description 'Windows Update cache'
    }

    Remove-FilesSafely -Path 'C:\ProgramData\Microsoft\Windows\WER\ReportQueue' -Description 'Windows Error Reports'
    Remove-FilesSafely -Path 'C:\ProgramData\Microsoft\Windows\WER\ReportArchive' -Description 'Windows Error Report Archives'

    if ($isAdmin) {
        Remove-FilesSafely -Path 'C:\Windows\Prefetch' -Description 'Prefetch files'
    }

    if (-not $isSystem) {
        Remove-FilesSafely -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Windows\Explorer') -Description 'Thumbnail cache'

        Remove-FilesSafely -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Cache') -Description 'Microsoft Edge cache'
        Remove-FilesSafely -Path (Join-Path $env:LOCALAPPDATA 'Microsoft\Edge\User Data\Default\Code Cache') -Description 'Microsoft Edge code cache'

        Remove-FilesSafely -Path (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Cache') -Description 'Google Chrome cache'
        Remove-FilesSafely -Path (Join-Path $env:LOCALAPPDATA 'Google\Chrome\User Data\Default\Code Cache') -Description 'Google Chrome code cache'

        $ffProfilesRoot = Join-Path $env:LOCALAPPDATA 'Mozilla\Firefox\Profiles'
        if (Test-Path -LiteralPath $ffProfilesRoot) {
            Get-ChildItem -LiteralPath $ffProfilesRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $cache2 = Join-Path $_.FullName 'cache2'
                Remove-FilesSafely -Path $cache2 -Description "Firefox cache ($($_.Name))"
            }
        }
    }
    else {
        Write-Output 'Skipping current-user profile caches (running as LocalSystem).'
    }

    if ($isAdmin) {
        Remove-FilesSafely -Path 'C:\Windows\ServiceProfiles\NetworkService\AppData\Local\Microsoft\Windows\DeliveryOptimization\Cache' -Description 'Delivery Optimization cache'
    }

    Remove-FilesSafely -Path 'C:\Windows\Downloaded Program Files' -Description 'Downloaded Program Files'

    if (Test-Path -LiteralPath 'C:\inetpub\logs\LogFiles') {
        Remove-FilesSafely -Path 'C:\inetpub\logs\LogFiles' -Description 'IIS Log Files'
    }

    if ($isAdmin -and -not $isSystem) {
        Write-Output ''
        Write-Output 'Running Windows Disk Cleanup utility (cleanmgr /sagerun); sets HKLM VolumeCaches flags and may show UI on some systems.'
        Invoke-CleanMgrSageRun
    }

    if ($isAdmin) {
        Write-Output 'Analyzing Windows Component Store (DISM)...'
        Invoke-DismWithExitCheck -ArgumentList @('/Online', '/Cleanup-Image', '/AnalyzeComponentStore', '/NoRestart', '/Quiet') -StepName 'DISM AnalyzeComponentStore'

        Write-Output 'Cleaning Windows Component Store (DISM /StartComponentCleanup /ResetBase)...'
        Invoke-DismWithExitCheck -ArgumentList @('/Online', '/Cleanup-Image', '/StartComponentCleanup', '/ResetBase', '/NoRestart', '/Quiet') -StepName 'DISM StartComponentCleanup'
    }

    $drive = Get-PSDrive -Name C -ErrorAction Stop
    $finalFreeSpace = [math]::Round($drive.Free / 1GB, 2)
    $finalPercentFree = 0
    if (($drive.Used + $drive.Free) -ne 0) {
        $finalPercentFree = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
    }

    $freedSpace = [math]::Round($finalFreeSpace - $initialFreeSpace, 2)
    $percentPointsChange = [math]::Round($finalPercentFree - $initialPercentFree, 2)

    Write-Output ''
    Write-Output 'Cleanup complete.'
    Write-Output "Drive size:         $totalSpace GB"
    Write-Output "Initial free space: $initialFreeSpace GB ($initialPercentFree%)"
    Write-Output "Final free space:   $finalFreeSpace GB ($finalPercentFree%)"
    Write-Output "Space freed:        $freedSpace GB (free % change: $percentPointsChange)"
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
