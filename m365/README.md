# m365

Microsoft 365 PowerShell scripts for SharePoint Online and Microsoft Graph tasks.

## Folder purpose summary

This folder contains interactive technician-run scripts for tenant-wide M365 operations. Scripts are designed for Windows PowerShell sessions on technician workstations, not unattended LocalSystem jobs.

## Script inventory

- `EmptySharePointRecycleBin.ps1`
- `ExportM365GroupsAndMembersCsv.ps1`

## Module exceptions (read first)

These scripts use non-default modules, which are approved deviations from `docs/POWERSHELL_SCRIPT_STANDARDS.md`:

| Module | Exception ID | Use |
|--------|--------------|-----|
| `PnP.PowerShell` | [M365-SPO-PNP-001](../docs/EXCEPTIONS_POLICY.md) | SharePoint admin and site recycle-bin operations |
| `Microsoft.Graph` | [M365-GRAPH-MGSDK-001](../docs/EXCEPTIONS_POLICY.md) | Group and member reporting exports |

Install once per user profile:

```powershell
Install-Module PnP.PowerShell -Scope CurrentUser
Install-Module Microsoft.Graph -Scope CurrentUser
```

## Safety and impact notes

- These scripts can act on tenant-wide data and should be run only in authorized environments.
- `EmptySharePointRecycleBin.ps1` is destructive and irreversible for recycle-bin content.
- `ExportM365GroupsAndMembersCsv.ps1` is read-only for directory objects but writes CSV data to disk.

## Validation guidance

- Confirm prompt inputs before execution, especially tenant/app identifiers and output paths.
- Use completion summaries and warning/failure lines as primary success signals.
- For exports, validate output file existence and row counts in `C:\Temp`.

## EmptySharePointRecycleBin.ps1

- Purpose: Enumerate tenant SharePoint sites and clear first-stage and second-stage recycle bins for each site.
- Required operator inputs:
  - SharePoint hostname prefix used in `https://<prefix>-admin.sharepoint.com`
  - Entra tenant (GUID or domain), optional default to `<prefix>.onmicrosoft.com`
  - Azure application (client) ID
  - Final confirmation prompt to continue
- Assumptions: Interactive Windows PowerShell session on a technician machine with `PnP.PowerShell` installed and sign-in capability for `Connect-PnPOnline -Interactive`.
- File path behavior: No output file by default; optional transcript/logging is operator-managed.
- Key commands/functions used: `Import-Module PnP.PowerShell`, `Connect-PnPOnline`, `Get-PnPTenantSite`, `Clear-PnPRecycleBinItem`, `Disconnect-PnPOnline`.
- Potential impact: Destructive and irreversible recycle-bin clearing across all enumerated tenant sites.
- Validation signals: End-of-run summary reports total/success/failed site counts and explicit `[FAIL]` lines for errors.

## ExportM365GroupsAndMembersCsv.ps1

- Purpose: Export tenant groups plus direct member rows to UTF-8 CSV using Microsoft Graph.
- Required operator inputs:
  - Continue prompt
  - CSV output path under `C:\Temp` (default `C:\Temp\M365-Groups-And-Members.csv`)
  - Optional scopes (defaults: `Group.Read.All`, `Directory.Read.All`, `User.Read.All`)
- Assumptions: Interactive Windows PowerShell session with `Microsoft.Graph` available and permissions granted for requested scopes.
- File path behavior: Creates `C:\Temp` if missing; output CSV must resolve under `C:\Temp`.
- Key commands/functions used: `Import-Module Microsoft.Graph`, `Connect-MgGraph`, `Select-MgProfile`, `Get-MgGroup`, `Get-MgGroupMember`, `Export-Csv`, `Disconnect-MgGraph`.
- Potential impact: Directory read activity only; no object mutation, but may produce large CSV output for large tenants.
- Validation signals: Console prints completion message with saved path; if no groups are found an empty CSV is still written.
