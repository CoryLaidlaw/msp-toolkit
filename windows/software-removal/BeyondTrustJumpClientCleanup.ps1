<#
.SYNOPSIS
    Removes BeyondTrust / Bomgar Jump Client: run keys, services, uninstall, folders, and orphan registry entries.
.DESCRIPTION
    Elevated or LocalSystem session required. Prompts once before stopping services, killing processes, running vendor
    uninstall (msiexec or bundled uninstaller), and deleting Program Files / ProgramData folders matching Bomgar or
    BeyondTrust. MSI verbose log is written under C:\Temp (folder created if missing). Uses takeown/icacls when
    folder removal fails. The script asks for what it needs at the prompt and takes no parameters.
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

function Remove-BomgarCleanupRunValues {
    $hives = Get-ChildItem -Path 'Registry::HKU' -ErrorAction Stop |
        Where-Object { $_.Name -notlike '*_Classes' }

    foreach ($hive in $hives) {
        $runPath = "Registry::$($hive.Name)\SOFTWARE\Microsoft\Windows\CurrentVersion\Run"
        if (-not (Test-Path -LiteralPath $runPath)) {
            continue
        }

        $names = (Get-Item -LiteralPath $runPath).GetValueNames() |
            Where-Object { $_ -like 'Bomgar_Cleanup_ZD*' }

        foreach ($entry in $names) {
            Remove-ItemProperty -LiteralPath $runPath -Name $entry -Force
            Write-Host "Deleted: $entry from $($hive.Name)"
        }
    }
}

function Stop-BeyondTrustServices {
    $services = Get-Service -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like '*BeyondTrust*' -or
            $_.DisplayName -like '*bomgar*' -or
            $_.DisplayName -like '*Jump Client*'
        }

    foreach ($svc in $services) {
        Write-Host "Stopping service: $($svc.DisplayName)"
        Stop-Service -Name $svc.Name -Force -ErrorAction SilentlyContinue
        Write-Host "Service stopped: $($svc.DisplayName)"
    }
}

function Stop-BeyondTrustProcesses {
    $processes = Get-Process -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -like '*bomgar*' -or
            $_.Name -like '*beyondtrust*' -or
            $_.Name -like '*sra-pin*'
        }

    foreach ($proc in $processes) {
        Write-Host "Killing process: $($proc.Name)"
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
    }
}

function Invoke-BeyondTrustUninstall {
    param(
        [Parameter(Mandatory)]
        [string]$LogPath
    )

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    $apps = Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like '*BeyondTrust*' -or $_.DisplayName -like '*Jump Client*'
        }

    foreach ($item in $apps) {
        Write-Host "Found: $($item.DisplayName)"
        $uninstall = $item.UninstallString
        if ([string]::IsNullOrWhiteSpace($uninstall)) {
            continue
        }

        if ($uninstall -like 'msiexec*') {
            if ($uninstall -notmatch '\{[0-9A-Fa-f-]{36}\}') {
                Write-Warning "Could not parse product code from: $uninstall"
                continue
            }
            $guid = $Matches[0]
            Write-Host "Running MSI uninstall for $guid"
            $msiArgs = @('/x', $guid, '/quiet', '/norestart', '/l*v', $LogPath)
            $proc = Start-Process -FilePath 'msiexec.exe' -ArgumentList $msiArgs -Wait -NoNewWindow -PassThru
            if ($proc.ExitCode -ne 0 -and $proc.ExitCode -ne 3010) {
                Write-Warning "msiexec exited with code $($proc.ExitCode) for $guid"
            }
        }
        else {
            $exe = ($uninstall -split '"')[1]
            if ([string]::IsNullOrWhiteSpace($exe)) {
                Write-Warning "Could not parse EXE path from: $uninstall"
                continue
            }
            Write-Host "Running EXE uninstall: $exe"
            Start-Process -FilePath $exe -ArgumentList @('/silent', '/quiet', '/norestart') -Wait -NoNewWindow
        }

        Write-Host "Done: $($item.DisplayName)"
    }
}

function Wait-UninstallRegistryGone {
    param(
        [Parameter(Mandatory)]
        [int]$TimeoutSeconds
    )

    Write-Host 'Waiting for uninstall to complete...'
    $elapsed = 0
    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )

    while ($elapsed -lt $TimeoutSeconds) {
        $stillInstalled = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
            Where-Object {
                $_.DisplayName -like '*BeyondTrust*' -or $_.DisplayName -like '*Jump Client*'
            })

        if ($stillInstalled.Count -eq 0) {
            Write-Host 'Registry entry removed.' -ForegroundColor Green
            return
        }

        Write-Host "Still uninstalling... ($elapsed seconds elapsed)"
        Start-Sleep -Seconds 5
        $elapsed += 5
    }
}

function Remove-BeyondTrustFoldersUnderPath {
    param(
        [Parameter(Mandatory)]
        [string]$SearchPath
    )

    if (-not (Test-Path -LiteralPath $SearchPath)) {
        return
    }

    Get-ChildItem -LiteralPath $SearchPath -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like '*bomgar*' -or $_.Name -like '*beyondtrust*' } |
        ForEach-Object {
            $full = $_.FullName
            Write-Host "Removing folder: $full"
            cmd /c "rd /S /Q `"$full`""

            if (Test-Path -LiteralPath $full) {
                Write-Host "Folder locked, taking ownership: $full" -ForegroundColor Yellow
                takeown /F "$full" /R /D Y 2>$null | Out-Null
                icacls "$full" /grant Administrators:F /T 2>$null | Out-Null
                cmd /c "rd /S /Q `"$full`""
            }

            if (Test-Path -LiteralPath $full) {
                Write-Host "WARNING: Could not remove $full" -ForegroundColor Red
            }
            else {
                Write-Host "Removed: $full" -ForegroundColor Green
            }
        }
}

function Remove-BeyondTrustUninstallRegistryKeys {
    $bases = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall'
    )

    foreach ($base in $bases) {
        if (-not (Test-Path -LiteralPath $base)) {
            continue
        }

        Get-ChildItem -LiteralPath $base -ErrorAction SilentlyContinue | ForEach-Object {
            $prop = Get-ItemProperty -Path $_.PSPath -ErrorAction SilentlyContinue
            if ($null -eq $prop) {
                return
            }
            $dn = $prop.DisplayName
            if (
                ($dn -like '*BeyondTrust*') -or
                ($dn -like '*Jump Client*') -or
                ($dn -like '*bomgar*')
            ) {
                Remove-Item -LiteralPath $_.PsPath -Recurse -Force
                Write-Host "Deleted registry key: $($_.PsPath)"
            }
        }
    }
}

function Get-BeyondTrustRemainingArtifacts {
    $searchRoots = @('C:\ProgramData', 'C:\Program Files', 'C:\Program Files (x86)')
    $remainingFiles = @(
        foreach ($root in $searchRoots) {
            if (-not (Test-Path -LiteralPath $root)) {
                continue
            }
            Get-ChildItem -LiteralPath $root -Recurse -ErrorAction SilentlyContinue |
                Where-Object { $_.FullName -like '*bomgar*' -or $_.FullName -like '*beyondtrust*' }
        }
    )

    $uninstallRoots = @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    $remainingReg = @(Get-ItemProperty -Path $uninstallRoots -ErrorAction SilentlyContinue |
        Where-Object {
            $_.DisplayName -like '*BeyondTrust*' -or $_.DisplayName -like '*Jump Client*'
        })

    return [pscustomobject]@{
        Files = $remainingFiles
        Registry = $remainingReg
    }
}

function Invoke-Main {
    $isAdmin = Test-IsAdministrator
    $isSystem = Test-IsLocalSystem
    if (-not ($isAdmin -or $isSystem)) {
        Write-Warning 'Run from elevated Administrator or LocalSystem. Stopping services, uninstall, and HKLM cleanup require elevation.'
        return
    }

    Write-Host 'This script stops BeyondTrust/Bomgar services and processes, uninstalls Jump Client, deletes matching folders under Program Files and ProgramData, and removes related registry keys.'
    if (-not (Test-ReadHostYes -Prompt 'Continue with BeyondTrust / Bomgar removal? (Y/N)')) {
        Write-Host 'Aborted by operator.'
        return
    }

    $tempPath = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $tempPath)) {
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    }
    $logPath = Join-Path $tempPath 'beyondtrust-uninstall.log'

    Remove-BomgarCleanupRunValues

    Stop-BeyondTrustServices
    Stop-BeyondTrustProcesses
    Start-Sleep -Seconds 2

    Invoke-BeyondTrustUninstall -LogPath $logPath
    Wait-UninstallRegistryGone -TimeoutSeconds 120

    Write-Host 'Starting file cleanup...'
    Stop-BeyondTrustProcesses
    Start-Sleep -Seconds 2

    foreach ($searchPath in @('C:\ProgramData', 'C:\Program Files', 'C:\Program Files (x86)')) {
        Remove-BeyondTrustFoldersUnderPath -SearchPath $searchPath
    }

    Write-Host 'Cleaning up registry...'
    Remove-BeyondTrustUninstallRegistryKeys

    Write-Host 'Cleaning up startup entries...'
    Remove-BomgarCleanupRunValues

    Write-Host ''
    Write-Host 'Running final verification...' -ForegroundColor Cyan
    $remaining = Get-BeyondTrustRemainingArtifacts

    if (($remaining.Files.Count -eq 0) -and ($remaining.Registry.Count -eq 0)) {
        Write-Host 'SUCCESS: BeyondTrust fully removed - no files or registry entries remaining.' -ForegroundColor Green
    }
    else {
        if ($remaining.Files.Count -gt 0) {
            Write-Host 'WARNING: Some files still remain:' -ForegroundColor Red
            $remaining.Files | Select-Object -ExpandProperty FullName
        }
        if ($remaining.Registry.Count -gt 0) {
            Write-Host 'WARNING: Registry entry still present:' -ForegroundColor Red
            $remaining.Registry | Select-Object -ExpandProperty DisplayName
        }
    }

    Write-Host "Computer: $env:COMPUTERNAME"
    Write-Host "MSI verbose log (if used): $logPath"
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
