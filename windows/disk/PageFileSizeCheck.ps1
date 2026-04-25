<#
.SYNOPSIS
    Reports whether C:\pagefile.sys exists and its size on disk.
.DESCRIPTION
    Read-only check of C:\pagefile.sys. No prompts or script parameters.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PagefileSizeReport {
    param(
        [Parameter(Mandatory)]
        [string]$LiteralPath
    )

    if (-not (Test-Path -LiteralPath $LiteralPath -PathType Leaf)) {
        Write-Output "File does not exist: $LiteralPath"
        return
    }

    $item = Get-Item -LiteralPath $LiteralPath -Force -ErrorAction Stop
    $sizeBytes = $item.Length
    $sizeGB = [Math]::Round($sizeBytes / 1GB, 4)
    Write-Output "Path: $LiteralPath"
    Write-Output "Size: $sizeGB GB ($sizeBytes bytes)"
}

try {
    Get-PagefileSizeReport -LiteralPath 'C:\pagefile.sys'
    Write-Host '[SUCCESS] PageFileSizeCheck completed.'
}
catch {
    Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
    throw
}
