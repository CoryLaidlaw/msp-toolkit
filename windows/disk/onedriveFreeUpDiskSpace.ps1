# === Configure this variable ===
$onedrivePath = "C:\Users\USERNAME\OneDrive"

# Ensure OneDrive path is valid
if (-not (Test-Path $onedrivePath)) {
    Write-Host "Specified OneDrive path does not exist: $onedrivePath" -ForegroundColor Red
    return
}

# Get initial free space
$drive = Get-PSDrive C
$startFreeGB = [math]::Round($drive.Free / 1GB, 2)

Write-Host "Processing OneDrive files..." -ForegroundColor Cyan
Write-Host "Path: $onedrivePath`n"

# Dehydrate files
$files = Get-ChildItem -Path $onedrivePath -Recurse -File -ErrorAction SilentlyContinue

if (-not $files) {
    Write-Host "No files found in OneDrive to process." -ForegroundColor Yellow
} else {
    $counter = 0
    foreach ($file in $files) {
        try {
            attrib.exe +U -P $file.FullName
            Write-Host "✔ Marked for online-only: $($file.FullName)" -ForegroundColor Green
            $counter++
        }
        catch {
            Write-Host "✖ Failed: $($file.FullName) - $_" -ForegroundColor Yellow
        }
    }

    # Wait for OneDrive to dehydrate files
    Start-Sleep -Seconds 15

    # Get final free space
    $endDrive = Get-PSDrive C
    $endFreeGB = [math]::Round($endDrive.Free / 1GB, 2)
    $spaceFreed = [math]::Round($endFreeGB - $startFreeGB, 2)

    # Summary
    Write-Host "`nSummary:" -ForegroundColor Cyan
    Write-Host "Files processed: $counter"
    Write-Host "Free space before: $startFreeGB GB"
    Write-Host "Free space after:  $endFreeGB GB"
    Write-Host "Space freed:       $spaceFreed GB" -ForegroundColor Green
}

Write-Host "Script complete." -ForegroundColor Cyan


