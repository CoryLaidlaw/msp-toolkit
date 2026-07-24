<#
.SYNOPSIS
    Marks older OneDrive files for cloud-only (dehydration) via attrib +U -P.
.DESCRIPTION
    Enumerates files under a prompted OneDrive path, filters by last access time,
    then runs attrib.exe per file. Prompts for path and age threshold in days only.
    Everything is collected at the prompts, so no parameters are needed.
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

    # Call attrib.exe directly so PowerShell native-command quoting handles paths
    # with spaces, commas, brackets, and other characters. Start-Process
    # -ArgumentList does not quote arguments and produced
    # "Parameter format not correct" errors on real OneDrive paths.
    $null = & attrib.exe +U -P $FilePath 2>&1
    return $LASTEXITCODE
}

function Invoke-Main {
    # --- Input collection ---
    $OneDrivePath = Read-OneDriveRootPath
    if ([string]::IsNullOrWhiteSpace($OneDrivePath)) {
        Write-Host '[ERROR] No path entered.' -ForegroundColor Red
        return
    }

    if (-not (Test-Path -LiteralPath $OneDrivePath -PathType Container)) {
        Write-Host "[ERROR] Path not found or not a folder: $OneDrivePath" -ForegroundColor Red
        return
    }

    $DaysOld = Read-PositiveIntDays

    Write-Host ""
    Write-Host "OneDrive path: $OneDrivePath"
    Write-Host "Age threshold: $DaysOld days (files newer than cutoff are skipped)"

    # --- Main execution ---
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
            $done = $counter + $failed
            $percentComplete = [Math]::Round(($done / $filesToProcess.Count) * 100, 1)
            $elapsedSeconds = $stopwatch.Elapsed.TotalSeconds
            $secondsRemaining = -1
            if ($elapsedSeconds -gt 0) {
                $rate = $done / $elapsedSeconds
                if ($rate -gt 0) {
                    $secondsRemaining = [int](($filesToProcess.Count - $done) / $rate)
                }
            }
            Write-Progress -Activity 'Dehydrating OneDrive files' -Status "$done of $($filesToProcess.Count) ($percentComplete%)" -PercentComplete $percentComplete -SecondsRemaining $secondsRemaining
            $batchCounter = 0
        }
    }

    Write-Progress -Activity 'Dehydrating OneDrive files' -Completed
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

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
