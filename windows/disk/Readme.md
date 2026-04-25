# windows/disk

PowerShell helpers for disk space, cleanup, and sizing.

## DiskCleanup.ps1

**Purpose:** Clear common Windows temporary data and caches on `C:`, and when elevated run the Disk Cleanup utility (`cleanmgr`) and DISM component cleanup.

**Execution context:** Intended for **elevated Administrator** or **LocalSystem**. Some steps require elevation; the script warns and skips those when not admin. **Profile-bound steps** (current user `%LOCALAPPDATA%` temp, thumbnail cache, Edge/Chrome/Firefox caches) run only when **not** LocalSystem (`S-1-5-18`); under LocalSystem those steps are skipped with a short log line.

**Operator inputs (prompts only — no parameters):**

1. **`Continue with cleanup? (Y/N)`** — Must be **Y** or **yes** (case-insensitive) to proceed; empty or anything else aborts.

When elevated, **cleanmgr** runs automatically after file cleanup (no separate prompt): it sets `HKLM:\...\VolumeCaches\*\StateFlags0001` and runs `cleanmgr.exe /sagerun:1`.

**What it does (summary):**

- Ensures **`C:\Temp` exists**, then deletes its contents (not the folder itself).
- Clears **`C:\Windows\Temp`**, **recycle bin**, **WER** report queue/archive, **`C:\Windows\Downloaded Program Files`**, and **IIS logs** if `C:\inetpub\logs\LogFiles` exists.
- When elevated: **Windows Update** download cache, **Prefetch**, **Delivery Optimization** cache.
- When elevated: **cleanmgr** `/sagerun` as above.
- When elevated: **DISM** `/AnalyzeComponentStore` and `/StartComponentCleanup` with **`/ResetBase`** (irreversible servicing-store reduction; see Microsoft DISM guidance).
- Does **not** delete files from **`C:\Windows\Installer`** (avoids breaking uninstall/repair).

**Commands and APIs used:** `Get-PSDrive`, `Get-ChildItem`, `Remove-Item`, `Clear-RecycleBin`, `New-Item`, `Start-Process` (`cleanmgr.exe`, `Dism.exe`), `Set-ItemProperty` (VolumeCaches for cleanmgr), `Read-Host`.

**Safety / impact:**

- Frees space by **deleting files** under known paths; operators should run on non-production first when unsure.
- **DISM `/ResetBase`** removes superseded component versions; recovery from some servicing failures can require installation media.
- **Browser caches** affect only the **invoking user profile** when not LocalSystem.
- **`cleanmgr`** may still be unsuitable in some locked-down or session-zero scenarios even with `/sagerun`.

**Usage:** Paste the entire script into an elevated Windows PowerShell 5.1 session and answer the prompt, or run the file with `.\DiskCleanup.ps1` from its directory.

## TargetFolderSizeDrilldown.ps1

**Purpose:** Read-only **folder size drilldown**. Starting at a root path, measures each immediate child folder’s total size, then **recurses only into children** that are both larger than a size threshold (GB) and more than **N percentage points** above the **average** sibling share of the parent’s size. Outputs a tree table; **`[+]`** marks branches that were expanded deeper.

**Execution context:** Intended for **elevated Administrator** or **LocalSystem**. The script only **reads** metadata and file sizes (no deletes). Under **LocalSystem**, paths like `C:\Users` still enumerate, but permission denials may appear as **zero-size** or skipped subtrees where `Get-ChildItem` is denied; compare with an interactive admin session when results look unexpected.

**Operator inputs (prompts only — no parameters):**

1. **`Folder path to analyze [default: C:\Users]`** — Target root. Press **Enter** to use `C:\Users`. Must exist and be a **folder**; otherwise the script prints an error and exits with code **1**.
2. **`Minimum child size to consider for expansion, in GB [default: 10]`** — Child must be **strictly greater** than this value (in GB) to qualify for expansion. Press **Enter** for **10**. Non-positive or non-numeric input is rejected until valid or Enter for default.
3. **`Percentage points above average sibling share required to expand [default: 10]`** — Let `avg` be the average of each child’s **% of parent** among immediate siblings. A child qualifies only if `(child % of parent - avg)` is **strictly greater** than this number. Press **Enter** for **10**. Enter **0** to require only “above average” (still combined with the size threshold). Invalid input is rejected until valid or Enter for default.

**What it does (summary):**

- Recursively walks the tree according to the rules above, printing `[Expanding]` lines when a level has qualifying children.
- Prints a **FINAL TREE** table: folder display name, size (GB), and **% of parent** for each row; root row shows total size for the target path.

**Commands and APIs used:** `Read-Host`, `Test-Path`, `Get-ChildItem`, `Measure-Object`, `Write-Host`, `[decimal]::TryParse`, `[System.Collections.Generic.List[PSCustomObject]]`.

**Safety / impact:**

- **No deletions or configuration changes** — sizing only.
- **Heavy disk and CPU use** on large paths: each measured folder performs a **full recursive** file enumeration under that folder. Prefer narrow targets or maintenance windows.

**Validation:**

- Successful run ends with **`[OK] Folder size drilldown completed.`** in green.
- Invalid root path: **`[ERROR] Path not found or not a folder:`** and **exit code 1**.
- **`[+]`** in the tree means that folder met both thresholds and child subfolders were analyzed the same way.

**Usage:** Paste the entire script into Windows PowerShell 5.1 and answer the prompts, or run `.\TargetFolderSizeDrilldown.ps1` from this folder.

## DeleteDownloads.ps1

**Purpose:** Delete **all contents** of each user profile’s **Downloads** folder under a chosen users root (default `C:\Users`).

**Execution context:** Intended for **elevated Administrator**. Without elevation, clearing other users’ Downloads may **fail** or be incomplete; the script warns when not running as admin.

**Operator inputs (prompts only — no parameters):**

1. **`Users root path [default: C:\Users]`** — Folder that contains profile directories (each named for a user). Press **Enter** for `C:\Users`.
2. **`Continue with Downloads cleanup? (Y/N)`** — Must be **Y** or **yes** (case-insensitive) to proceed.

**What it does (summary):**

- For each **immediate child directory** of the users root, if `Downloads` exists, runs **`Remove-Item`** on `Downloads\*` (recursive, force).
- Prints per-profile status and a short summary (cleared / no folder / failed).
- Prints **C:** free space at the end when the **C:** drive is available.

**Commands and APIs used:** `Read-Host`, `Get-ChildItem`, `Test-Path`, `Remove-Item`, `Get-PSDrive`, `[Security.Principal.WindowsPrincipal]` (admin test).

**Safety / impact:**

- **Destructive:** permanently removes files and folders inside every profile’s Downloads under the chosen root.
- Does **not** remove the Downloads folder itself, only its contents.

**Validation:**

- **`[SUCCESS] DeleteDownloads completed.`** when no per-profile failures occurred.
- **`[WARN] Completed with one or more failures.`** if any profile cleanup threw; script exits with **non-zero** in that case.
- **`Aborted by operator.`** if confirmation was not **Y**/**yes**.

**Usage:** Paste into Windows PowerShell 5.1 or run `.\DeleteDownloads.ps1` from this folder.

## RobustFolderClean.ps1

**Purpose:** **Wipe all contents** of a target folder by mirroring an **empty** staging directory over it with **`robocopy /MIR`**. The **target folder itself is kept** (only its contents are removed via the mirror).

**Execution context:** Intended for **elevated Administrator** or **LocalSystem** when the target paths require it.

**Operator inputs (prompts only — no parameters):**

1. **`Folder path to empty (robocopy /MIR wipe)`** — Must exist and be a **directory**. Entering the path is the only prompt; the script then runs the wipe.

**What it does (summary):**

- Ensures **`C:\Temp`** exists, creates a **unique** empty subfolder under it, runs **`robocopy.exe`** with **`/MIR /R:1 /W:1`** from empty staging to the target.
- Treats robocopy **exit codes 0–7** as success (standard robocopy semantics).
- Removes the staging folder in a **`finally`** block.

**Commands and APIs used:** `Read-Host`, `Test-Path`, `New-Item`, `Remove-Item`, `Start-Process` (`robocopy.exe`).

**Safety / impact:**

- **Highly destructive** to the target path’s **contents**; operators must enter the correct path at the single prompt.

**File path behavior:** Staging uses **`C:\Temp\RobustFolderClean_<guid>`** (created and removed by the script).

**Validation:**

- **`[SUCCESS] RobustFolderClean completed.`** when robocopy succeeds and no terminating error occurred.
- **`[ERROR]`** messages for missing path, robocopy failure (exit code outside 0–7), or other failures; **non-zero exit**.

**Usage:** Paste into Windows PowerShell 5.1 or run `.\RobustFolderClean.ps1` from this folder.

## OneDriveFreeUpDiskSpace.ps1

**Purpose:** Encourage **OneDrive Files On-Demand** behavior by running **`attrib.exe +U -P`** on files under a local OneDrive sync folder whose **last access time** is older than a prompted number of days.

**Execution context:** Run in a context that can read the OneDrive path and modify attributes (typically the **user** who owns the sync, or **Administrator** with rights to that profile).

**Operator inputs (prompts only — no parameters):**

1. **`OneDrive folder path (local sync root)`** — Must exist and be a **folder**.
2. **`Minimum age in days ... [default: 30]`** — Files with **`LastAccessTime`** **on or after** the cutoff are **skipped**. Press **Enter** for **30**.

**What it does (summary):**

- **Single** recursive **`Get-ChildItem -File`** pass, then filters and sorts in memory.
- After showing counts, runs **`attrib +U -P`** on all matched files (no second confirmation).
- Invokes **`attrib.exe`** via **`Start-Process`** and treats **non-zero process exit** as failure for that file.
- Waits **15 seconds** after the attrib loop only when **at least one** attrib call **succeeded** (`exit 0`), then re-checks **C:** free space for a rough before/after delta.

**Commands and APIs used:** `Read-Host`, `Get-ChildItem`, `Start-Process` (`attrib.exe`), `Get-PSDrive`, `Sort-Object`.

**Safety / impact:**

- **Many attribute updates** on cloud-backed files; can be **slow** and **I/O heavy** on large libraries.
- **Does not delete** files; behavior depends on **OneDrive sync** and policy. **C:** free space may not change immediately.

**File path behavior:** No files written under **`C:\Temp`**; only reads the prompted OneDrive path and runs **`attrib`**.

**Validation:**

- **`[SUCCESS] OneDriveFreeUpDiskSpace completed.`** at the end of a normal run.
- **`[SUCCESS] No files matched the criteria.`** when the age filter leaves nothing to process (no attrib run).
- **`[WARN]`** if any **`attrib`** calls returned non-zero.

**Usage:** Paste into Windows PowerShell 5.1 or run `.\OneDriveFreeUpDiskSpace.ps1` from this folder.

## SetPageFile.ps1

**Purpose:** Turn off **automatic** Windows pagefile management and set a **fixed** paging file via the registry (`PagingFiles` under memory management).

**Execution context:** Requires **elevated Administrator** (registry `HKLM` and `Win32_ComputerSystem` changes). A **reboot** is usually required before the new page file layout applies fully.

**Operator inputs:** **None** in the script (no `Read-Host`); the path and sizes are **fixed in the file** (`C:\pagefile.sys` with **4096** / **8192** MB as written in `SetPageFile.ps1`).

**What it does (summary):**

- Queries **`Win32_ComputerSystem`**; if **`AutomaticManagedPagefile`** is true, sets it to **false** with **`Set-CimInstance`**.
- Sets **`HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management\PagingFiles`** to the configured string.

**Commands and APIs used:** `Get-CimInstance`, `Set-CimInstance`, `Set-ItemProperty`.

**Safety / impact:**

- Changes **virtual memory** configuration; inappropriate sizing can hurt stability under load.
- Does **not** follow the repo’s usual prompt-only operator input pattern; confirm the hardcoded values before running.

**Validation:** No script-emitted completion line; verify in **System Properties → Advanced → Performance → Advanced → Virtual memory** after reboot, or use **`PageFileSizeCheck.ps1`** for on-disk **`C:\pagefile.sys`** size only.

**Usage:** From an **elevated** Windows PowerShell 5.1 session: `.\SetPageFile.ps1` (after editing the script if defaults are wrong for the machine).

## PageFileSizeCheck.ps1

**Purpose:** **Read-only** check: reports whether **`C:\pagefile.sys`** exists and its **size** on disk.

**Execution context:** **Administrator** may be required if the account cannot read **`C:\pagefile.sys`**.

**Operator inputs:** **None** (always checks **`C:\pagefile.sys`**).

**What it does (summary):**

- If **`C:\pagefile.sys`** exists as a **file**, prints path, size in GB (4 decimal places), and raw byte length.
- If the file does not exist, prints a short **does not exist** message.

**Commands and APIs used:** `Test-Path`, `Get-Item`.

**Safety / impact:** **None** (read-only). Does not read registry or change page file configuration.

**File path behavior:** No writes; no **`C:\Temp`** use.

**Validation:**

- **`[SUCCESS] PageFileSizeCheck completed.`** after the report.
- **`[ERROR]`** with message if **`Get-Item`** fails unexpectedly.

**Usage:** Paste into Windows PowerShell 5.1 or run `.\PageFileSizeCheck.ps1` from this folder.
