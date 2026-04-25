# Finds users on PC
$usersPath = "C:\Users"

# Get all user profiles
$users = Get-ChildItem -Path $usersPath -Directory

foreach ($user in $users) {
    $downloadsPath = "$usersPath\$user\Downloads"

    if (Test-Path $downloadsPath) {
        try {
            # Delete all files and folders inside the Downloads directory
            Remove-Item -Path "$downloadsPath\*" -Recurse -Force -ErrorAction Stop
            Write-Host "Cleared: $downloadsPath"
        } catch {
            Write-Host "Failed to clear: $downloadsPath - $_"
        }
    } else {
        Write-Host "No Downloads folder found for: $user"
    }
}

Write-Host "Cleanup complete."
$drive = Get-PSDrive C; "Free: $([math]::Round($drive.Free / 1GB, 2)) GB ($([math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2))%)"
