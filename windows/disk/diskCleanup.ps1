# Script for initial disk cleanup
# Made by Cory Laidlaw

# Capture initial free space and total size
$startDrive = Get-PSDrive -Name C
$startFreeGB = [math]::Round($startDrive.Free / 1GB, 2)
$startTotalGB = [math]::Round($startDrive.Used / 1GB + $startFreeGB, 2)
$startPercentFree = [math]::Round(($startFreeGB / $startTotalGB) * 100, 2)

Write-Output "Start - Free Space: $startFreeGB GB ($startPercentFree% free)"

# Remove Temporary Files
Remove-Item -Path "$env:TEMP\*" -Force -Recurse -ErrorAction SilentlyContinue
Remove-Item -Path "C:\Windows\Temp\*" -Force -Recurse -ErrorAction SilentlyContinue
Get-ChildItem -Path "C:\Temp" -Recurse -Force | Remove-Item -Recurse -Force -ErrorAction SilentlyContinue


# Clear Windows Update Cache
Stop-Service wuauserv -Force
Remove-Item -Path "C:\Windows\SoftwareDistribution\*" -Force -Recurse -ErrorAction SilentlyContinue
Start-Service wuauserv

# Clear Recycle Bin
Clear-RecycleBin -Force -ErrorAction SilentlyContinue

#Remove Old Win Update Files
Dism.exe /Online /Cleanup-Image /StartComponentCleanup

# Capture final free space
$endDrive = Get-PSDrive -Name C
$endFreeGB = [math]::Round($endDrive.Free / 1GB, 2)
$endTotalGB = [math]::Round($endDrive.Used / 1GB + $endFreeGB, 2)
$endPercentFree = [math]::Round(($endFreeGB / $endTotalGB) * 100, 2)
$freedSpace = [math]::Round($endFreeGB - $startFreeGB, 2)

Write-Output "End - Free Space: $endFreeGB GB ($endPercentFree% free)"
Write-Output "Total Space Freed: $freedSpace GB"
