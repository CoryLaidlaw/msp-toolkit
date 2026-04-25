# Purpose: Remove a single user profile manually specified
# Created by: Cory Laidlaw

# === Manual Input Section ===
# Specify the username and profile path manually
$Username = "USERNAME"  # <-- Replace with actual username
$ProfilePath = "C:\Users\USERNAME"  # <-- Replace with actual profile path

# Output to keep track of progress
Write-Output "Attempting to remove profile for user: $Username at path: $ProfilePath"

# Remove user profile
Get-WmiObject Win32_UserProfile |
    Where-Object { $_.LocalPath -eq $ProfilePath } |
    ForEach-Object {
        $_.Delete()
        Write-Output "Profile for $Username removed successfully."
    }

# Display free space on C drive
$drive = Get-PSDrive C
"Free: $([math]::Round($drive.Free / 1GB, 2)) GB ($([math]::Round(($drive.Free / ($drive.Used + $drive.Free)) * 100, 2))%)"
