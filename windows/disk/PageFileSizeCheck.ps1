<#
.SYNOPSIS
    Reports whether C:\pagefile.sys exists and its configured/allocated size.
.DESCRIPTION
    Read-only check of C:\pagefile.sys. No prompts or script parameters.
    Queries CIM (Win32_PageFileUsage / Win32_PageFileSetting / Win32_ComputerSystem)
    rather than Test-Path, because pagefile.sys is held with an exclusive
    handle by the OS Memory Manager and the FileSystem provider reports it
    as missing on access-denied.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PagefileSizeReport {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    $reported = $false

    try {
        $usage = Get-CimInstance -ClassName Win32_PageFileUsage -ErrorAction Stop |
            Where-Object { $_.Name -ieq $LiteralPath }
        foreach ($u in $usage) {
            $reported = $true
            Write-Host "Active pagefile: $($u.Name)"
            Write-Host "  Allocated:    $($u.AllocatedBaseSize) MB"
            Write-Host "  Current use:  $($u.CurrentUsage) MB"
            Write-Host "  Peak use:     $($u.PeakUsage) MB"
        }
    }
    catch {
        Write-Host "Win32_PageFileUsage query failed: $($_.Exception.Message)"
    }

    try {
        $setting = Get-CimInstance -ClassName Win32_PageFileSetting -ErrorAction Stop |
            Where-Object { $_.Name -ieq $LiteralPath }
        foreach ($s in $setting) {
            Write-Host "Configured pagefile: $($s.Name)"
            Write-Host "  Initial size: $($s.InitialSize) MB (0 = system-managed)"
            Write-Host "  Maximum size: $($s.MaximumSize) MB (0 = system-managed)"
            $reported = $true
        }
    }
    catch {
        Write-Host "Win32_PageFileSetting query failed: $($_.Exception.Message)"
    }

    try {
        $cs = Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop
        if ($cs.AutomaticManagedPagefile) {
            Write-Host 'AutomaticManagedPagefile: ENABLED (size managed by Windows; may not appear in Win32_PageFileSetting).'
        }
        else {
            Write-Host 'AutomaticManagedPagefile: disabled.'
        }
    }
    catch {
        Write-Host "Win32_ComputerSystem query failed: $($_.Exception.Message)"
    }

    if (-not $reported) {
        Write-Host "No active or configured pagefile found at: $LiteralPath"
        Write-Host 'Note: pagefile.sys is a locked OS file. If you expect it to exist,'
        Write-Host 'rerun this script from an elevated (Administrator) PowerShell.'
    }
}

function Invoke-Main {
    Get-PagefileSizeReport -LiteralPath 'C:\pagefile.sys'
    Write-Host '[SUCCESS] PageFileSizeCheck completed.'
}

try {
    Invoke-Main
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
