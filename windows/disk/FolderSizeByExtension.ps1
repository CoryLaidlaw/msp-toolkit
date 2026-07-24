<#
.SYNOPSIS
    Read-only rollup of file sizes by extension under a target folder.
.DESCRIPTION
    Prompts for a root folder path (default C:\Users), recursively enumerates files only, groups
    by extension, and prints count and total size per type sorted largest-first. No deletions.
    Heavy disk I/O on large trees, so prefer maintenance windows or narrow paths.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-TargetPath {
    $raw = Read-Host -Prompt 'Folder path to analyze [default: C:\Users]'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 'C:\Users'
    }
    return $raw.Trim()
}

function Invoke-Main {
    $TargetPath = Read-TargetPath
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        Write-Host "[ERROR] Path not found or not a folder: $TargetPath" -ForegroundColor Red
        return 1
    }

    Write-Host "[INFO] Enumerating files under $TargetPath (this may take a while)..." -ForegroundColor DarkCyan

    $files = @(Get-ChildItem -LiteralPath $TargetPath -File -Recurse -Force -ErrorAction SilentlyContinue)

    if ($files.Count -eq 0) {
        Write-Host "[INFO] No files were enumerated (empty tree or access denied everywhere)." -ForegroundColor Yellow
        Write-Host "[SUCCESS] FolderSizeByExtension completed." -ForegroundColor Green
        return 0
    }

    $rows = $files |
        Group-Object -Property Extension |
        ForEach-Object {
            $extKey = $_.Name
            $label = if ([string]::IsNullOrWhiteSpace($extKey)) {
                'No Extension'
            }
            else {
                "*$extKey"
            }
            $sumBytes = ($_.Group | Measure-Object -Property Length -Sum).Sum
            if ($null -eq $sumBytes) { $sumBytes = 0 }
            [PSCustomObject]@{
                FileType        = $label
                Count           = $_.Count
                'TotalSize (GB)' = [math]::Round($sumBytes / 1GB, 2)
            }
        } |
        Sort-Object -Property 'TotalSize (GB)' -Descending

    # Format-* output must not reach the function output stream or $statusCode = Invoke-Main captures it.
    $rows | Format-Table -AutoSize | Out-Host

    Write-Host "[SUCCESS] FolderSizeByExtension completed. ($($files.Count) files, $($rows.Count) extension groups.)" -ForegroundColor Green
    return 0
}

try {
    $statusCode = Invoke-Main
    if ($statusCode -ne 0) {
        Write-Error "[ERROR] FolderSizeByExtension completed with status code $statusCode."
        return
    }
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
