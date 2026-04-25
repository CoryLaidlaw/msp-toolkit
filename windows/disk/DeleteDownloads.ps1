<#
.SYNOPSIS
    Clears the Downloads folder under each profile directory beneath a chosen users root.
.DESCRIPTION
    Prompts for confirmation, then deletes all items inside each profile's Downloads folder.
    Intended for elevated Administrator context so all profiles can be reached.
    No script parameters — operator input via Read-Host only.
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

function Read-UsersRootPath {
    $raw = Read-Host -Prompt 'Users root path [default: C:\Users]'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 'C:\Users'
    }
    return $raw.Trim()
}

function Invoke-Main {
    param(
        [Parameter(Mandatory)]
        [string]$UsersRootPath
    )

    if (-not (Test-Path -LiteralPath $UsersRootPath -PathType Container)) {
        Write-Host "[ERROR] Users root not found or not a folder: $UsersRootPath" -ForegroundColor Red
        return 1
    }

    $profileDirs = Get-ChildItem -LiteralPath $UsersRootPath -Directory -ErrorAction Stop
    $cleared = 0
    $noDownloads = 0
    $failed = 0

    foreach ($profileDir in $profileDirs) {
        $downloadsPath = Join-Path -Path $UsersRootPath -ChildPath $profileDir.Name
        $downloadsPath = Join-Path -Path $downloadsPath -ChildPath 'Downloads'

        if (-not (Test-Path -LiteralPath $downloadsPath -PathType Container)) {
            Write-Host "No Downloads folder: $($profileDir.Name)"
            $noDownloads++
            continue
        }

        try {
            $wildcard = Join-Path -Path $downloadsPath -ChildPath '*'
            if (Test-Path -Path $wildcard) {
                Remove-Item -Path $wildcard -Recurse -Force -ErrorAction Stop
            }
            Write-Host "Cleared: $downloadsPath"
            $cleared++
        }
        catch {
            Write-Warning "Failed to clear: $downloadsPath — $($_.Exception.Message)"
            $failed++
        }
    }

    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    if ($drive) {
        $freeGb = [math]::Round($drive.Free / 1GB, 2)
        $pct = if (($drive.Used + $drive.Free) -eq 0) {
            0
        }
        else {
            [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
        }
        Write-Host ""
        Write-Host "C: free space: $freeGb GB ($pct%)"
    }

    Write-Host ""
    Write-Host "Summary: profiles with Downloads cleared: $cleared | no Downloads folder: $noDownloads | failed: $failed"
    if ($failed -gt 0) {
        Write-Host "[WARN] Completed with one or more failures." -ForegroundColor Yellow
        return 1
    }
    Write-Host "[SUCCESS] DeleteDownloads completed."
    return 0
}

# --- Input collection ---
if (-not (Test-IsAdministrator)) {
    Write-Warning 'Not running elevated: clearing other users'' Downloads may fail due to permissions.'
}

$usersRoot = Read-UsersRootPath

Write-Host "This will delete ALL files and folders inside each profile's Downloads folder under:"
Write-Host "  $usersRoot"
Write-Host ""

if (-not (Test-ReadHostYes -Prompt 'Continue with Downloads cleanup? (Y/N)')) {
    Write-Host 'Aborted by operator.'
    return
}

try {
    $statusCode = Invoke-Main -UsersRootPath $usersRoot
    if ($statusCode -ne 0) {
        Write-Error "[ERROR] DeleteDownloads completed with status code $statusCode."
        return
    }
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
