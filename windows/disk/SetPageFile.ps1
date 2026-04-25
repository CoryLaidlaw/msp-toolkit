<#
.SYNOPSIS
    Disables automatic pagefile management and sets a paging file value from prompts.
.DESCRIPTION
    Prompts for pagefile path, initial size (MB), and maximum size (MB) with built-in defaults.
    Disables AutomaticManagedPagefile when enabled, then writes PagingFiles in the registry.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Read-InputWithDefault {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [string]$Default
    )

    $raw = Read-Host -Prompt "$Prompt [default: $Default]"
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $Default
    }
    return $raw.Trim()
}

function Read-PositiveIntWithDefault {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [int]$Default
    )

    do {
        $raw = Read-Host -Prompt "$Prompt [default: $Default]"
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }

        $value = 0
        if ([int]::TryParse($raw.Trim(), [ref]$value) -and $value -gt 0) {
            return $value
        }

        Write-Host "Invalid value. Enter a positive integer or press Enter for $Default." -ForegroundColor Red
    } while ($true)
}

# --- Input collection ---
$pagefilePath = Read-InputWithDefault -Prompt 'Pagefile path' -Default 'C:\pagefile.sys'
$initialSizeMb = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096
$maximumSizeMb = Read-PositiveIntWithDefault -Prompt 'Maximum size (MB)' -Default 8192

if ($maximumSizeMb -lt $initialSizeMb) {
    Write-Host "[ERROR] Maximum size must be greater than or equal to initial size." -ForegroundColor Red
    exit 1
}

# --- Main execution ---
$cs = Get-CimInstance Win32_ComputerSystem
if ($cs.AutomaticManagedPagefile) {
    Set-CimInstance -InputObject $cs -Property @{ AutomaticManagedPagefile = $false }
    Write-Host 'Disabled AutomaticManagedPagefile.'
}
else {
    Write-Host 'AutomaticManagedPagefile already disabled.'
}

$regPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management'
$pagingValue = "$pagefilePath $initialSizeMb $maximumSizeMb"
Set-ItemProperty -Path $regPath -Name 'PagingFiles' -Value $pagingValue

Write-Host "PagingFiles set to: $pagingValue"
Write-Host '[SUCCESS] SetPageFile completed. Reboot is typically required for full effect.'
