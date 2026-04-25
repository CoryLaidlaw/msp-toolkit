# Set PageFile.sys
# Disable automatic pagefile management
$sys = Get-CimInstance -ClassName Win32_ComputerSystem
Set-CimInstance -InputObject $sys -Property @{AutomaticManagedPagefile = $false}

# Set pagefile on C:\ to 2048–4096 MB
$pagefile = Get-CimInstance -ClassName Win32_PageFileSetting -Filter "Name = 'C:\\pagefile.sys'"
if (-not $pagefile) {
    # Create it if not found
    New-CimInstance -ClassName Win32_PageFileSetting -Property @{
        Name = "C:\\pagefile.sys"
        InitialSize = 2048
        MaximumSize = 4096
    }
} else {
    # Modify existing pagefile size
    Set-CimInstance -InputObject $pagefile -Property @{
        InitialSize = 2048
        MaximumSize = 4096
    }
}

# Display result
Get-CimInstance Win32_PageFileSetting | Select-Object Name, InitialSize, MaximumSize
