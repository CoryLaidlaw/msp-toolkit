# PowerShell script to check size of all folders in C:\Windows and C:\Users

function Get-FolderSizes {
    param (
        [string]$targetPath
    )

    # Calculate total size
    $totalSize = (Get-ChildItem -Path $targetPath -Recurse -Force -ErrorAction SilentlyContinue |
                  Where-Object { -not $_.PSIsContainer } |
                  Measure-Object -Property Length -Sum).Sum
    $totalSizeGB = [Math]::Round($totalSize / 1GB, 2)

    Write-Output "Total size of ${targetPath}: ${totalSizeGB} GB"

    # Collect folder sizes
    $folderStats = Get-ChildItem -Path $targetPath -Directory | ForEach-Object {
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
    }

    $folderStats | Sort-Object SizeGB -Descending | Format-Table -AutoSize
    Write-Output ""
}

# Run for both directories
Get-FolderSizes -targetPath "C:\Windows"
Get-FolderSizes -targetPath "C:\Users"
