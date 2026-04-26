# windows/software-removal

PowerShell helpers for **removing third-party Windows software** end-to-end (services, autostart, uninstaller invocation, filesystem and registry cleanup). Scripts are product-specific; add new removal flows here when they do not fit an existing `windows/` domain folder.

## Folder purpose summary

This folder contains targeted software-removal scripts for technician-led endpoint remediation workflows.

## Script inventory

- `BeyondTrustJumpClientCleanup.ps1`

## Safety and impact notes

- Removal flows in this folder are destructive and can interrupt active support tooling.
- Run only with approved change context and validate operator privileges before execution.

## Validation guidance

- Use final success/warning output plus residual file/registry checks to confirm cleanup state.
- Review uninstall logs under `C:\Temp` when warnings or partial removal results appear.

## BeyondTrustJumpClientCleanup.ps1

**Purpose:** Fully remove BeyondTrust/Bomgar Jump Client from a machine: delete `Bomgar_Cleanup_ZD*` per-user Run values, stop matching services and processes, run the vendor uninstaller (MSI or EXE), wait for uninstall registry entries to clear, delete Bomgar/BeyondTrust-named folders under `C:\ProgramData`, `C:\Program Files`, and `C:\Program Files (x86)` (using `takeown`/`icacls` and `rd /s /q` when needed), remove matching uninstall keys, then re-scan Run keys and report remaining files/registry.

**Safety / impact:**

- **Destructive:** stops remote-support services, uninstalls software, deletes folders and registry keys. Intended for intentional removal only; test on non-production first.
- **Elevation:** without admin/SYSTEM, the script exits before changes.
- **Scope risk:** folder deletion matches **folder names** under the three standard roots; the final verification uses **path substring** matches on all descendants (can be slow on large disks).
- **msiexec** exit code **3010** (success, reboot pending) is treated as non-fatal; other non-zero exit codes log a warning.

**Execution context:** **Elevated Administrator** or **LocalSystem** required. The script checks this before the confirmation prompt and stops if neither applies.

**Operator inputs (prompts only — no parameters):**

1. **`Continue with BeyondTrust / Bomgar removal? (Y/N)`** — Must be **Y** or **yes** (case-insensitive) to proceed; anything else aborts.

**What it does (summary):**

- Ensures **`C:\Temp`** exists; MSI verbose logging (when uninstall uses `msiexec`) goes to **`C:\Temp\beyondtrust-uninstall.log`**.
- Removes **`Bomgar_Cleanup_ZD*`** values from each loaded user hive under `HKCU`-equivalent `Registry::HKU\...\Run` (excluding `*_Classes`).
- Stops services whose display name matches BeyondTrust, Bomgar, or Jump Client; force-stops processes whose name matches `*bomgar*`, `*beyondtrust*`, or `*sra-pin*`.
- Invokes uninstall via **`msiexec.exe /x`** (quiet, no restart, verbose log) when `UninstallString` is MSI-style, otherwise runs the quoted EXE with **`/silent /quiet /norestart`**.
- Polls uninstall registry for up to **120** seconds.
- Deletes top-level folders under ProgramData / Program Files whose names match `*bomgar*` or `*beyondtrust*` (not a full-machine substring wipe outside those trees beyond the final recursive verification pass).
- Final verification: recursive search under the same three roots for paths containing `bomgar` or `beyondtrust`, plus uninstall registry display names.

**Commands and APIs used:** `Read-Host`, `Get-ChildItem`, `Get-Item`, `Get-ItemProperty`, `Remove-Item`, `Remove-ItemProperty`, `Get-Service`, `Stop-Service`, `Get-Process`, `Stop-Process`, `Start-Process` (`msiexec.exe`, uninstall EXE), `Start-Sleep`, `cmd /c rd`, `takeown`, `icacls`, registry providers under `HKLM:` and `Registry::HKU`.

**File path behavior:** Ensures `C:\Temp` exists and writes MSI uninstall log to `C:\Temp\beyondtrust-uninstall.log` when MSI uninstall is used; scans and deletes matching folders under `C:\ProgramData`, `C:\Program Files`, and `C:\Program Files (x86)`.

**Validation:**

- Script prints **SUCCESS** when no matching files or uninstall registry entries remain; otherwise lists **WARNING** lines with paths or display names.
- After MSI uninstall, inspect **`C:\Temp\beyondtrust-uninstall.log`** if removal failed.
- Script ends with **`Computer:`** name and log path for RMM transcript context.

**Usage:** Paste into an elevated Windows PowerShell session and confirm **Y**, or run `.\BeyondTrustJumpClientCleanup.ps1` from this folder.

