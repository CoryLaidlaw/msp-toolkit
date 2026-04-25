Get-ChildItem -Path "C:\Users" -Directory | ForEach-Object {
    $folderPath = $_.FullName
    $folderSize = (Get-ChildItem -Path $folderPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB
    [PSCustomObject]@{
        UserFolder = $_.Name
        SizeGB = "{0:N2}" -f $folderSize
    }
} | Format-Table -AutoSize

