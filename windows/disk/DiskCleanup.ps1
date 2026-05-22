<#
.SYNOPSIS
    Empties the Recycle Bin on the C drive for all user profiles.
.DESCRIPTION
    Deletes all items under C:\$Recycle.Bin for every SID sub-folder, leaving
    desktop.ini intact. Requires elevation to clear bins belonging to other
    user profiles. All choices are made through Read-Host prompts (no script
    parameters).
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

function Clear-CRecycleBin {
    Write-Output 'Cleaning: Recycle Bin (C drive, all users)'

    $binRoot = 'C:\$Recycle.Bin'
    if (-not (Test-Path -LiteralPath $binRoot)) {
        Write-Output '  Recycle Bin path not found on C:.'
        return
    }

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
                    Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                }
                $touched = $true
                Write-Output "  Removed $count item(s) under $($sidFolder.FullName)"
            }
        }
        catch {
            Write-Warning "Could not clear $($sidFolder.FullName) — $($_.Exception.Message)"
        }
    }

    if (-not $touched) {
        Write-Output '  Recycle Bin already empty.'
    }
}

function Invoke-Main {
    if (-not (Test-IsAdministrator)) {
        Write-Warning 'Not running elevated: bins belonging to other user profiles may not be cleared.'
    }

    Write-Output 'This script empties the Recycle Bin on the C drive for all user profiles.'
    if (-not (Test-ReadHostYes -Prompt 'Continue? (Y/N)')) {
        Write-Output 'Aborted by operator.'
        return
    }

    $drive = Get-PSDrive -Name C -ErrorAction Stop
    $initialFree = [math]::Round($drive.Free / 1GB, 2)
    $total = [math]::Round(($drive.Used + $drive.Free) / 1GB, 2)
    $initialPct = 0
    if (($drive.Used + $drive.Free) -ne 0) {
        $initialPct = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
    }
    Write-Output "Initial free space on C: $initialFree GB of $total GB ($initialPct%)"

    Clear-CRecycleBin

    $drive = Get-PSDrive -Name C -ErrorAction Stop
    $finalFree = [math]::Round($drive.Free / 1GB, 2)
    $finalPct = 0
    if (($drive.Used + $drive.Free) -ne 0) {
        $finalPct = [math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2)
    }
    $freed = [math]::Round($finalFree - $initialFree, 2)
    $pctChange = [math]::Round($finalPct - $initialPct, 2)

    Write-Output ''
    Write-Output 'Cleanup complete.'
    Write-Output "Drive size:         $total GB"
    Write-Output "Initial free space: $initialFree GB ($initialPct%)"
    Write-Output "Final free space:   $finalFree GB ($finalPct%)"
    Write-Output "Space freed:        $freed GB (free % change: $pctChange)"
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
