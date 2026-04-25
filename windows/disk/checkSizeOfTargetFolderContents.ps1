# PowerShell script to check size of all folders and items in a target path, including pagefile.sys if it exists

$targetPath = "C:\path\to\folder"

# Calculate total size of C:\Windows using recursive method
$totalSize = (Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue |
              Where-Object { -not $_.PSIsContainer } |
              Measure-Object -Property Length -Sum).Sum
$totalSizeGB = [Math]::Round($totalSize / 1GB, 2)

Write-Output "Total size of Target Folder: $totalSizeGB GB"

# Get all directories and their sizes in GB and percentage of total
Get-ChildItem -Path $targetPath -Directory | ForEach-Object {
    $folderPath = $_.FullName
    $items = Get-ChildItem -Path $folderPath -Recurse -Force -ErrorAction SilentlyContinue
    if ($items) {
        $size = ($items | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum
    } else {
        $size = 0
    }

    [PSCustomObject]@{
        Folder = $folderPath
        SizeGB = [Math]::Round($size / 1GB, 2)
        PercentOfTotal = if ($totalSize -gt 0) { [Math]::Round(($size / $totalSize) * 100, 2) } else { 0 }
    }
} | Sort-Object SizeGB -Descending | Format-Table -AutoSize

