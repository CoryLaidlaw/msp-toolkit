# windows/network

Scripts for **network discovery, NIC power management, and user-context mapping management**: subnet ping sweeps, NIC power-saving remediation, and current-user drive/printer mapping work. Only run scans and changes on networks and machines you are authorized to touch.

## Script inventory

- `DisableNicPowerSaving.ps1`
- `SubnetPingScan.ps1`
- `ManageCurrentUserMappings.ps1`
- `ManageCurrentUserPrinters.ps1`

## Safety and impact notes

- `DisableNicPowerSaving.ps1` modifies Device Manager registry values and NIC advanced properties; a reboot or adapter restart is recommended after running.
- Subnet scanning is active probing and must be run only on authorized network ranges.
- Mapping scripts can add/remove user drive and printer mappings and should be run with explicit operator confirmation.

## Validation guidance

- Confirm target scope and selected mode before execution.
- Use per-operation success/failure output and summary counts to validate outcomes.
- Verify CSV schema and location under `C:\Temp` for CSV-driven add/remove operations.

## SubnetPingScan.ps1

**Purpose:** Sweep a single **IPv4 /24** by pinging `.1` through `.254` for a caller-supplied **first three octets** (for example `192.168.1` → `192.168.1.0/24` host addresses only). For each responding address, attempts **reverse DNS** via `[System.Net.Dns]::GetHostEntry`. Prints a table and can optionally **export UTF-8 CSV** under **`C:\Temp`**.

**Safety / impact:**

- **Active probing:** one ICMP echo per address; may trigger IDS/IPS alerts or violate policy if run on unfamiliar networks. Confirm authorization before use.
- **DNS:** reverse lookups can be slow or fail benignly (`Unable to resolve`).

**Execution context:** **Windows PowerShell** on Windows 10/11. Works under many accounts; **ICMP and DNS behavior can differ** for **LocalSystem** vs interactive admin (firewall, profile, DNS suffix).

**Operator inputs** (prompted at run time, no parameters):

1. **First three IPv4 octets**: for example `10.20.30` for `10.20.30.1`–`10.20.30.254`. Press **Enter** for default **`192.168.1`**.
2. **`Continue with ping sweep? (Y/N)`**: starts the sweep.
3. **`Export results to CSV under C:\Temp? (Y/N)`**: asked only if at least one host responded.
4. **`CSV path [default: C:\Temp\NetworkScan_yyyyMMdd_HHmmss.csv]`**: must resolve under **`C:\Temp`** if overridden.

**Commands and APIs used:** `Read-Host`, `Test-Connection`, `[System.Net.Dns]::GetHostEntry`, `Sort-Object`, `Format-Table`, `Export-Csv`, `New-Item` (ensure `C:\Temp`).

**File path behavior:** No file writes unless CSV export is chosen; export writes to an operator-selected `.csv` under `C:\Temp` and creates `C:\Temp` if missing.

**Validation:**

- Console shows **Scan Complete** and **Total active hosts found**.
- Spot-check a few **Found:** lines and the formatted table; open the CSV in Excel or `Import-Csv` if exported.

**Usage:** From this folder, `.\SubnetPingScan.ps1`, or paste into Windows PowerShell.

## ManageCurrentUserMappings.ps1

**Purpose:** Current-user mapping manager for drive mappings. Resolves current user SID from loaded hives, shows mapped drives, then provides actions to add/remove mapped drives or exit.

**Safety / impact:**

- **Destructive actions exist** for mapped drives (add/remove drive mappings).
- Scope is **current loaded user context** only; no multi-user operation.

**Execution context:** Elevated technician/admin session is recommended for reliable context resolution and mapping visibility.

**Operator inputs** (prompted at run time, no parameters):

1. **Action menu**: `1) Add mapped drive  2) Remove mapped drive  3) Refresh view  4) Exit`.
2. **Add mapped drive**:
   - Manual: prompt for drive letter and UNC path.
   - CSV: prompt for CSV path under `C:\Temp` (example: `C:\Temp\drive-add-template.csv`) with columns:
     - `DriveLetter`
     - `RemotePath`
3. **Remove mapped drive**:
   - Select mode: choose from current mapped drives or CSV.
   - CSV: prompt for CSV path under `C:\Temp` (example: `C:\Temp\drive-remove-template.csv`) with column:
     - `DriveLetter`

**Commands and APIs used:** `Get-ChildItem` (registry provider), `Get-ItemProperty`, SID translation via `.NET` (`NTAccount`/`SecurityIdentifier`), `New-PSDrive`, `Remove-PSDrive`, `Import-Csv`, `Write-Host`.

**File paths:** CSV modes prompt for explicit `.csv` paths under `C:\Temp`. Script creates `C:\Temp` when needed.

Template starters are available under `data/templates`:
- `data/templates/drive-add-template.csv`
- `data/templates/drive-remove-template.csv`

**Validation:**

- Current mappings display each loop with numbered drive entries.
- Add/remove CSV modes report success/failure counts.
- Remove-by-selection requires explicit confirmation.

**Usage:** From this folder, `.\ManageCurrentUserMappings.ps1`, or paste into Windows PowerShell.

## ManageCurrentUserPrinters.ps1

**Purpose:** Resolve the current logged-in/current loaded user context, display that user’s mapped printer connections from **`Registry::HKEY_USERS\<SID>\Printers\Connections`**, then run an action menu: **Add**, **Delete**, **Rename**, or **Exit**.

**Safety / impact:**

- **Destructive actions exist**: delete mapped connections and rename printer objects.
- **Scope:** Targets the resolved current user SID only; there is no multi-user selection loop.
- **Offline users:** Only **currently loaded** hives are eligible; profiles not loaded in this session are not processed.
- **Privilege requirements:** local/IP add and rename operations can require elevated rights and installed drivers.

**Execution context:** **Elevated Administrator** or technician session recommended so all relevant hives are visible.

**Operator inputs** (prompted at run time, no parameters):

1. **Action menu**: `1) Add  2) Delete  3) Rename  4) Exit`.
2. **Add path**:
   - Choose type: **Network mapped** or **Local/IP**.
   - Choose mode: **Manual** or **CSV**.
   - Network manual: prompt for UNC (`\\server\queue`).
   - Network CSV: prompt for path under `C:\Temp` with columns:
     - `ConnectionName` **or** `Server` + `Queue`.
   - Local/IP manual: prompt for `PrinterName`, `DriverName`, `PortName`, optional `PrinterHostAddress`, optional shared settings.
   - Local/IP CSV: prompt for path under `C:\Temp` with columns:
     - required: `PrinterName`, `DriverName`, `PortName`
     - optional: `PrinterHostAddress`, `Shared`, `ShareName`
3. **Delete path**:
   - Choose mode:
     - **Mapped connections (current user)**: select printer numbers from mapped list (comma/range format like `1,3,5-7`) and confirm batch delete.
     - **Installed printers from CSV**: prompt for CSV path under `C:\Temp` (example: `C:\Temp\printer-remove-template.csv`) and remove each `PrinterName` via `Remove-Printer`.
4. **Rename path**:
   - Choose mode: **CSV** or **Interactive**.
   - Rename CSV: prompt for path under `C:\Temp` with columns `OldName`, `NewName`.
   - Interactive: pick installed printer by number, enter new name, confirm.

**Commands and APIs used:** `Read-Host`, `Get-ChildItem` (registry), `Get-CimInstance` (`Win32_ComputerSystem`), SID translation (`NTAccount`/`SecurityIdentifier`), `Add-Printer`, `Add-PrinterPort`, `Get-Printer`, `Get-PrinterPort`, `Rename-Printer`, `Set-Printer`, `Remove-Item`, `Import-Csv`, `Format-Table`.

**File paths:** CSV modes prompt for explicit `.csv` file path under `C:\Temp`. Script creates `C:\Temp` when needed.

Template starters are available under `data/templates`:
- `data/templates/printer-add-network-template.csv`
- `data/templates/printer-add-local-template.csv`
- `data/templates/printer-rename-template.csv`
- `data/templates/printer-remove-template.csv`

**Validation:**

- Script prints target user + SID and returns to action menu after each operation.
- CSV modes report per-row success/failure and summary counts.
- Delete and interactive rename require explicit confirmation before changes.

**Usage:** `.\ManageCurrentUserPrinters.ps1` from this folder, or paste into Windows PowerShell.

## DisableNicPowerSaving.ps1

**Purpose:** Enumerate all **Ethernet** and **Wi-Fi** adapters and eliminate every OS- and vendor-level power-saving setting that can drop connectivity while the machine is powered on. Bluetooth, cellular (WirelessWan), VPN tunnel adapters (e.g. FortiClient), and other virtual adapters are automatically excluded by `PhysicalMediaType` and left untouched. Two categories of changes are made per qualifying adapter:

1. **PnPCapabilities registry flag** (`HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972...}\<subkey>`) set to `24` (0x18), which prevents Windows from powering off the adapter (Device Manager "Allow the computer to turn off this device to save power") and disables the wake capability flag.
2. **NIC advanced properties**: disables EEE variants (`*EEE`, `AdvancedEEE`, `EEE`, `EeeLinkAdvertisement`, `EeePhyEnable`, `GigabitEcoEEEEnabled`), wake offloads (`*WakeOnMagicPacket`, `*WakeOnPattern`, `*PMARPOffload`, `*PMNSOffload`), USB selective suspend (`*SelectiveSuspend`), and vendor power-saving modes (`PowerSavingMode`, `AutoPowerSavingMode`, `ULPMode`, `S5WakeOnLan`). Only properties that exist on the adapter are processed; unsupported keywords are silently skipped.

Adapters are filtered in two stages. First, only `PhysicalMediaType` values `802.3` (Ethernet) and `Native 802.11` (Wi-Fi) are considered. Second, a description-pattern list (`$script:ExcludeDescriptionPatterns`) excludes adapters by `InterfaceDescription` substring. The built-in patterns cover: VMware, VirtualBox, Hyper-V, Docker (virtualization); Fortinet, Cisco, TAP-Windows, WireGuard, Tailscale, SonicWall, Palo Alto, GlobalProtect, Juniper, Ivanti, Barracuda, Check Point, NordVPN, ExpressVPN (VPN clients). To add more, extend `$script:ExcludeDescriptionPatterns` in the script.

**Safety / impact:**

- **Registry write:** modifies `PnPCapabilities` under `HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4D36E972-E325-11CE-BFC1-08002bE10318}`. The change persists across reboots.
- **Adapter restart required** for `PnPCapabilities` to take effect in Device Manager UI; advanced property changes apply at next driver load or reboot.
- Script does **not** disable or restart adapters during execution, so NIC traffic is uninterrupted while it runs.

**Execution context:** Must run as **LocalSystem** or **elevated Administrator** to write registry keys and NIC advanced properties.

**Operator inputs** (prompted at run time, no parameters):

1. **`Apply changes to all adapters? (Y/N)`**: single confirmation before any modifications are made.

**Commands and APIs used:** `Get-NetAdapter`, `Get-ChildItem` (registry), `Get-ItemProperty`, `Set-ItemProperty`, `Get-NetAdapterAdvancedProperty`, `Set-NetAdapterAdvancedProperty`.

**Validation:**

- Each adapter prints `[PnP]` and `[Props]` lines showing what changed or was already set.
- Final summary shows count of adapters updated and total properties disabled.
- After reboot, verify in Device Manager (adapter Properties > Power Management) that "Allow the computer to turn off this device to save power" is unchecked and greyed out.

**Usage:** `.\DisableNicPowerSaving.ps1` from this folder, or paste into an elevated Windows PowerShell session.
