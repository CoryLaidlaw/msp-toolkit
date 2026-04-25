# Script for initial disk cleanup
# Made by Cory Laidlaw

# Capture initial free space and total size
$startDrive = Get-PSDrive -Name C
$startFreeGB = [math]::Round($startDrive.Free / 1GB, 2)
$startTotalGB = [math]::Round($startDrive.Used / 1GB + $startFreeGB, 2)
$startPercentFree = [math]::Round(($startFreeGB / $startTotalGB) * 100, 2)

Write-Output "Start - Free Space: $startFreeGB GB ($startPercentFree% free)"

# Function to run a cleanup command and report errors but keep going
function Run-Cleanup {
    param([string]$Action, [ScriptBlock]$Code)
    try {
        & $Code
        Write-Output "[SUCCESS] $Action"
    } catch {
        Write-Warning "[FAILED] $Action : $($_.Exception.Message)"
    }
}

# Remove Temporary Files
Run-Cleanup "Remove User Temp"      { Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction Stop }
Run-Cleanup "Remove Windows Temp"   { Remove-Item -Path "C:\Windows\Temp\*" -Force -Recurse -ErrorAction Stop }
Run-Cleanup "Remove C:\Temp"        { Get-ChildItem -Path "C:\Temp" -Recurse -Force -ErrorAction Stop | Remove-Item -Recurse -Force -ErrorAction Stop }

# Clear Windows Update Cache
Run-Cleanup "Stop Windows Update Service" { Stop-Service wuauserv -Force -ErrorAction Stop }
Run-Cleanup "Clear Windows Update Cache"  { Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Force -Recurse -ErrorAction Stop }
Run-Cleanup "Start Windows Update Service" { Start-Service wuauserv -ErrorAction Stop }

# Clear Recycle Bin
Run-Cleanup "Clear Recycle Bin" { Clear-RecycleBin -Force -ErrorAction Stop }

# Remove Old Win Update Files
Run-Cleanup "DISM Cleanup" { Dism.exe /Online /Cleanup-Image /StartComponentCleanup }

# Capture final free space
$endDrive = Get-PSDrive -Name C
$endFreeGB = [math]::Round($endDrive.Free / 1GB, 2)
$endTotalGB = [math]::Round($endDrive.Used / 1GB + $endFreeGB, 2)
$endPercentFree = [math]::Round(($endFreeGB / $endTotalGB) * 100, 2)
$freedSpace = [math]::Round($endFreeGB - $startFreeGB, 2)

Write-Output "End - Free Space: $endFreeGB GB ($endPercentFree% free)"
Write-Output "Total Space Freed: $freedSpace GB"
