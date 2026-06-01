<#
.SYNOPSIS
    Disables all NIC power-management settings that can drop connectivity while the machine is powered on.
.DESCRIPTION
    Enumerates all network adapters via Get-NetAdapter, then for each: sets PnPCapabilities in the Device
    Manager registry to prevent Windows from powering off the adapter, and disables common vendor
    power-saving advanced properties (EEE variants, selective suspend, wake offloads, ULP mode, etc.).
    Requires elevated administrator or LocalSystem context. A single confirmation prompt is shown before
    any changes are made. Restarting the affected adapters or rebooting is recommended after the script
    completes for PnPCapabilities changes to take full effect in Device Manager.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# GUID for the Network Adapters device class in Device Manager
$script:NicClassGuid = '{4D36E972-E325-11CE-BFC1-08002bE10318}'

# PnPCapabilities 0x10 = disable OS power-off, 0x08 = disable wake; combined = 24 (0x18)
$script:PnpNoShutdownValue = 24

# Standard NDIS and common vendor-specific keywords associated with power-saving behavior.
# 0 = Disabled for all of these properties across all known vendors.
$script:PowerSavingKeywords = @(
    '*EEE',                  # Energy Efficient Ethernet (NDIS standard)
    'AdvancedEEE',           # Intel vendor name for EEE
    'EEE',                   # Generic vendor name for EEE
    'EeeLinkAdvertisement',  # EEE link advertisement
    'EeePhyEnable',          # PHY-level EEE enable
    'GigabitEcoEEEEnabled',  # Gigabit-specific EEE
    '*WakeOnMagicPacket',    # Wake on Magic Packet (NDIS standard)
    '*WakeOnPattern',        # Wake on pattern match (NDIS standard)
    '*PMARPOffload',         # ARP offload in low-power state
    '*PMNSOffload',          # NS offload in low-power state
    '*SelectiveSuspend',     # USB NIC selective suspend
    'PowerSavingMode',       # Realtek vendor power-saving mode
    'AutoPowerSavingMode',   # Generic vendor auto power-saving
    'ULPMode',               # Intel Ultra Low Power mode (can drop link)
    'S5WakeOnLan'            # Wake from S5 (powered off)
)

function Get-NicRegistryPath {
    param(
        [Parameter(Mandatory)]
        [string]$InterfaceGuid
    )

    $classBase = "HKLM:\SYSTEM\CurrentControlSet\Control\Class\$script:NicClassGuid"
    if (-not (Test-Path -LiteralPath $classBase)) {
        return $null
    }

    foreach ($key in (Get-ChildItem -LiteralPath $classBase -ErrorAction SilentlyContinue)) {
        try {
            $id = (Get-ItemProperty -LiteralPath $key.PSPath -Name 'NetCfgInstanceId' -ErrorAction Stop).NetCfgInstanceId
            if ($id -eq $InterfaceGuid) {
                return $key.PSPath
            }
        }
        catch {
            $null = $_  # Subkey has no NetCfgInstanceId (e.g. Properties key); skip
        }
    }
    return $null
}

function Invoke-PnpNoShutdown {
    param(
        [Parameter(Mandatory)]
        [string]$RegistryPath
    )

    $current = $null
    try {
        $current = (Get-ItemProperty -LiteralPath $RegistryPath -Name 'PnPCapabilities' -ErrorAction Stop).PnPCapabilities
    }
    catch {
        $current = $null
    }

    if ($current -eq $script:PnpNoShutdownValue) {
        return 'already-set'
    }

    Set-ItemProperty -LiteralPath $RegistryPath -Name 'PnPCapabilities' -Value $script:PnpNoShutdownValue -Type DWord
    return 'changed'
}

function Disable-PowerSavingProperty {
    param(
        [Parameter(Mandatory)]
        [string]$AdapterName
    )

    $changed = 0
    $alreadyOff = 0

    foreach ($kw in $script:PowerSavingKeywords) {
        try {
            $prop = Get-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -ErrorAction Stop
            if ($prop.RegistryValue -eq 0) {
                $alreadyOff++
            }
            else {
                Set-NetAdapterAdvancedProperty -Name $AdapterName -RegistryKeyword $kw -RegistryValue 0 -NoRestart -ErrorAction Stop
                Write-Host "      [$kw] disabled" -ForegroundColor Green
                $changed++
            }
        }
        catch {
            $null = $_  # Property not supported on this adapter; silently skip
        }
    }

    return @{ Changed = $changed; AlreadyOff = $alreadyOff }
}

function Invoke-Main {
    $adapters = @(Get-NetAdapter -ErrorAction Stop)

    if ($adapters.Count -eq 0) {
        Write-Host 'No network adapters found.' -ForegroundColor Yellow
        return
    }

    Write-Host 'Network adapters found:' -ForegroundColor Cyan
    foreach ($a in $adapters) {
        Write-Host "  $($a.Name)  -  $($a.InterfaceDescription)" -ForegroundColor Cyan
    }
    Write-Host ''
    Write-Host 'This script will:' -ForegroundColor Yellow
    Write-Host '  1. Set PnPCapabilities = 24 in Device Manager registry (prevents OS from powering off each NIC).' -ForegroundColor Yellow
    Write-Host '  2. Disable EEE, selective suspend, wake-offload, ULP mode, and other power-saving NIC properties.' -ForegroundColor Yellow
    Write-Host '  A reboot or adapter restart is recommended after completion.' -ForegroundColor Yellow
    Write-Host ''

    $confirm = Read-Host 'Apply changes to all adapters? (Y/N)'
    if ($confirm.Trim() -notmatch '^(?i:y|yes)$') {
        Write-Host 'Aborted by operator.' -ForegroundColor Yellow
        return
    }

    $pnpChanged = 0
    $pnpSkipped = 0
    $totalPropsChanged = 0

    foreach ($adapter in $adapters) {
        Write-Host ''
        Write-Host "  [$($adapter.Name)]  $($adapter.InterfaceDescription)" -ForegroundColor White

        $regPath = Get-NicRegistryPath -InterfaceGuid $adapter.InterfaceGuid
        if ($regPath) {
            $result = Invoke-PnpNoShutdown -RegistryPath $regPath
            if ($result -eq 'changed') {
                Write-Host '    [PnP] Power-off disabled (PnPCapabilities = 24)' -ForegroundColor Green
                $pnpChanged++
            }
            else {
                Write-Host '    [PnP] Already set - no change needed' -ForegroundColor Gray
            }
        }
        else {
            Write-Host '    [PnP] No Device Manager registry entry found - virtual adapter, skipped' -ForegroundColor Gray
            $pnpSkipped++
        }

        $propResult = Disable-PowerSavingProperty -AdapterName $adapter.Name
        $totalPropsChanged += $propResult.Changed

        if ($propResult.Changed -eq 0 -and $propResult.AlreadyOff -eq 0) {
            Write-Host '    [Props] No supported power-saving properties found on this adapter' -ForegroundColor Gray
        }
        elseif ($propResult.Changed -eq 0) {
            Write-Host "    [Props] $($propResult.AlreadyOff) supported property/properties already disabled - no change needed" -ForegroundColor Gray
        }
    }

    Write-Host ''
    Write-Host '=== Done ===' -ForegroundColor Cyan
    Write-Host "PnP: $pnpChanged adapter(s) updated, $pnpSkipped skipped (virtual or no registry entry)." -ForegroundColor White
    Write-Host "Advanced properties: $totalPropsChanged power-saving setting(s) disabled across all adapters." -ForegroundColor White

    if (($pnpChanged + $totalPropsChanged) -gt 0) {
        Write-Host 'Restart the affected adapter(s) or reboot for all changes to take full effect.' -ForegroundColor Yellow
    }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
