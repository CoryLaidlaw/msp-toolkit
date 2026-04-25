Function Get-LargestFolders {
    Param (
        [string]$Path = "C:\",
        [int]$Top = 10
    )

    Get-ChildItem -Path $Path -Directory -Recurse | `
        Where-Object { 
            $_.FullName -notlike "C:\\Users*" -and 
            $_.FullName -notlike "C:\\Windows*" 
        } | `
        ForEach-Object {
            [PSCustomObject]@{
                Folder = $_.FullName
                Size   = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            }
        } | `
        Sort-Object -Property Size -Descending | `
        Select-Object -First $Top | `
        Format-Table -Property Folder, @{Label='Size (GB)'; Expression={[math]::Round($_.Size / 1GB, 2)}} -AutoSize
}

# Execute the function
Get-LargestFolders
