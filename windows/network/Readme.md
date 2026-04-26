# windows/network

PowerShell helpers for **network discovery and user-context mapping management** (ICMP reachability, mapped drives, and printer mapping/management workflows). Intended for technician use on authorized environments.

## Folder purpose summary

This folder contains technician scripts for subnet reachability scanning and current-user drive/printer mapping operations.

## Script inventory

- `SubnetPingScan.ps1`
- `ManageCurrentUserMappings.ps1`
- `ManageCurrentUserPrinters.ps1`

## Safety and impact notes

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

**Operator inputs (prompts only — no script parameters):**

1. **First three IPv4 octets** — Example: `10.20.30` for `10.20.30.1`–`10.20.30.254`. Press **Enter** for default **`192.168.1`**.
2. **`Continue with ping sweep? (Y/N)`** — Starts the sweep.
3. **`Export results to CSV under C:\Temp? (Y/N)`** — Only if at least one host responded.
4. **`CSV path [default: C:\Temp\NetworkScan_yyyyMMdd_HHmmss.csv]`** — Must resolve under **`C:\Temp`** if overridden.

**Commands and APIs used:** `Read-Host`, `Test-Connection`, `[System.Net.Dns]::GetHostEntry`, `Sort-Object`, `Format-Table`, `Export-Csv`, `New-Item` (ensure `C:\Temp`).

**File path behavior:** No file writes unless CSV export is chosen; export writes to an operator-selected `.csv` under `C:\Temp` and creates `C:\Temp` if missing.

**Validation:**

- Console shows **Scan Complete** and **Total active hosts found**.
- Spot-check a few **Found:** lines and the formatted table; open the CSV in Excel or `Import-Csv` if exported.

**Usage:** From this folder, `.\SubnetPingScan.ps1`, or paste into Windows PowerShell.

## ManageCurrentUserMappings.ps1

**Purpose:** Current-user mapping manager for drive mappings with context display of printer mappings. Resolves current user SID from loaded hives, shows mapped drives/printers, then provides actions to add/remove mapped drives or exit.

**Safety / impact:**

- **Destructive actions exist** for mapped drives (add/remove drive mappings).
- Scope is **current loaded user context** only; no multi-user operation.
- Printer entries are displayed for context and are not changed by this script.

**Execution context:** Elevated technician/admin session is recommended for reliable context resolution and mapping visibility.

**Operator inputs (prompts only — no script parameters):**

1. **Action menu** — `1) Add mapped drive  2) Remove mapped drive  3) Refresh view  4) Exit`.
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

**Operator inputs (prompts only — no script parameters):**

1. **Action menu** — `1) Add  2) Delete  3) Rename  4) Exit`.
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
