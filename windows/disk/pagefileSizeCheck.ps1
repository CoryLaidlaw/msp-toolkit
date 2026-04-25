# Check for pagefile.sys in root of C:
$pagefilePath = "C:\pagefile.sys"
if (Test-Path $pagefilePath) {
    $pagefileSize = (Get-Item $pagefilePath).Length
    $pagefileSizeGB = [Math]::Round($pagefileSize / 1GB, 2)
    Write-Output "Pagefile.sys size: $pagefileSizeGB GB"
} else {
    Write-Output "pagefile.sys does not exist."
}
