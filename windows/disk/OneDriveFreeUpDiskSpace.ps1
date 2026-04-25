<#
.SYNOPSIS
    Marks older OneDrive files for cloud-only (dehydration) via attrib +U -P.
.DESCRIPTION
    Enumerates files under a prompted OneDrive path, filters by last access time,
    then runs attrib.exe per file. Prompts for path and age threshold in days only.
    No script parameters — operator input via Read-Host only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-OneDriveRootPath {
    $raw = Read-Host -Prompt 'OneDrive folder path (local sync root)'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }
    return $raw.Trim()
}

function Read-PositiveIntDays {
    do {
        $raw = Read-Host -Prompt 'Minimum age in days (files accessed MORE recently are skipped) [default: 30]'
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return 30
        }
        $value = 0
        if ([int]::TryParse($raw.Trim(), [ref]$value) -and $value -gt 0) {
            return $value
        }
        Write-Host 'Enter a positive integer or press Enter for 30.' -ForegroundColor Red
    } while ($true)
}

function Invoke-AttribDehydrate {
    param(
        [Parameter(Mandatory)]
        [string]$FilePath
    )

    $attrib = Join-Path $env:SystemRoot 'System32\attrib.exe'
    if (-not (Test-Path -LiteralPath $attrib)) {
        throw "attrib.exe not found at $attrib"
    }

    $p = Start-Process -FilePath $attrib -ArgumentList @('+U', '-P', $FilePath) -Wait -NoNewWindow -PassThru
    return $p.ExitCode
}

function Invoke-Main {
    param(
        [Parameter(Mandatory)]
        [string]$OneDrivePath,
        [Parameter(Mandatory)]
        [int]$DaysOld
    )

    $cutoffDate = (Get-Date).AddDays(-$DaysOld)
    Write-Host ""
    Write-Host "Cutoff (files with LastAccessTime before this are processed): $($cutoffDate.ToString('yyyy-MM-dd HH:mm'))"
    Write-Host "Enumerating files (single pass)..."
    $allFiles = @(Get-ChildItem -LiteralPath $OneDrivePath -Recurse -File -Force -ErrorAction SilentlyContinue)
    $totalFiles = $allFiles.Count

    $filesToProcess = @(
        $allFiles |
            Where-Object { $_.LastAccessTime -lt $cutoffDate } |
            Sort-Object -Property LastAccessTime -Descending
    )
    $skipped = $totalFiles - $filesToProcess.Count

    $drive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $startFreeGB = if ($drive) { [math]::Round($drive.Free / 1GB, 2) } else { 0 }

    Write-Host "Total files under path: $totalFiles"
    Write-Host "Files to dehydrate:     $($filesToProcess.Count) (skipping $skipped more recently accessed)"

    if ($filesToProcess.Count -eq 0) {
        Write-Host '[SUCCESS] No files matched the criteria.'
        return
    }

    Write-Host ""
    Write-Host 'Running attrib +U -P on matched files...'

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    $batchSize = [Math]::Max(10, [Math]::Min(500, [Math]::Ceiling($filesToProcess.Count * 0.01)))
    $counter = 0
    $failed = 0
    $batchCounter = 0

    foreach ($file in $filesToProcess) {
        $code = Invoke-AttribDehydrate -FilePath $file.FullName
        if ($code -ne 0) {
            $failed++
        }
        else {
            $counter++
        }
        $batchCounter++

        if ($batchCounter -ge $batchSize) {
            $percentComplete = [Math]::Round((($counter + $failed) / $filesToProcess.Count) * 100, 1)
            $elapsedMinutes = $stopwatch.Elapsed.TotalMinutes
            if ($elapsedMinutes -gt 0) {
                $done = $counter + $failed
                $filesPerMinute = [Math]::Round($done / $elapsedMinutes, 0)
                $remaining = $filesToProcess.Count - $done
                $eta = [Math]::Round($remaining / [Math]::Max($filesPerMinute, 1), 1)
                Write-Host "Progress: $done of $($filesToProcess.Count) ($percentComplete%) | ~$filesPerMinute items/min | ETA: $eta min"
            }
            else {
                Write-Host "Progress: $($counter + $failed) of $($filesToProcess.Count) ($percentComplete%)"
            }
            $batchCounter = 0
        }
    }

    $stopwatch.Stop()

    if ($counter -gt 0) {
        Write-Host ""
        Write-Host 'Waiting briefly for OneDrive to process dehydration...'
        Start-Sleep -Seconds 15
    }

    $endDrive = Get-PSDrive -Name C -ErrorAction SilentlyContinue
    $endFreeGB = if ($endDrive) { [math]::Round($endDrive.Free / 1GB, 2) } else { 0 }
    $spaceFreed = [math]::Round($endFreeGB - $startFreeGB, 2)
    $totalMinutes = $stopwatch.Elapsed.TotalMinutes
    $avgFilesPerMinute = if ($totalMinutes -gt 0) { [Math]::Round(($counter + $failed) / $totalMinutes, 0) } else { 0 }

    Write-Host ""
    Write-Host 'Summary:'
    Write-Host "  attrib succeeded: $counter"
    Write-Host "  attrib failed:    $failed"
    Write-Host "  skipped (recent): $skipped"
    Write-Host "  elapsed:          $($stopwatch.Elapsed.ToString('mm\:ss'))"
    Write-Host "  avg rate:         $avgFilesPerMinute items/min"
    Write-Host "  C: free before:   $startFreeGB GB"
    Write-Host "  C: free after:    $endFreeGB GB"
    Write-Host "  delta free:       $spaceFreed GB"

    if ($failed -gt 0) {
        Write-Host '[WARN] One or more attrib calls returned non-zero exit code.' -ForegroundColor Yellow
    }
    Write-Host '[SUCCESS] OneDriveFreeUpDiskSpace completed.'
}

# --- Input collection ---
$onedrivePath = Read-OneDriveRootPath
if ([string]::IsNullOrWhiteSpace($onedrivePath)) {
    Write-Host '[ERROR] No path entered.' -ForegroundColor Red
    return
}

if (-not (Test-Path -LiteralPath $onedrivePath -PathType Container)) {
    Write-Host "[ERROR] Path not found or not a folder: $onedrivePath" -ForegroundColor Red
    return
}

$daysOld = Read-PositiveIntDays

Write-Host ""
Write-Host "OneDrive path: $onedrivePath"
Write-Host "Age threshold: $daysOld days (files newer than cutoff are skipped)"

try {
    Invoke-Main -OneDrivePath $onedrivePath -DaysOld $daysOld
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
