# windows/user-profiles

Scripts to inventory local Windows user profiles, spot profiles that map to disabled or unresolved domain users, and remove selected profiles to recover disk space.

## Safety and Impact Notes

Run these as LocalSystem or an elevated admin. `RemoveOneUserProfile.ps1` and `RemoveMultipleUserProfile.ps1` are destructive; they permanently delete local user profiles, including profile data and profile registry state, so double-check target users and paths before you run them.

## Validation Guidance

A good run prints explicit `[SUCCESS]`/`[INFO]` lines and leaves the expected CSV files in `C:\Temp` where applicable. Failures print `[ERROR]` without killing your PowerShell session.

## GetUserListAsCsv.ps1
- Purpose: Enumerate local non-special user profiles, export domain-matched profiles, and export profiles whose SID could not be translated to an account.
- Required inputs: Prompted domain short name (for example `CONTOSO`).
- Assumptions: Run as LocalSystem/elevated admin; Windows PowerShell; WMI access to `Win32_UserProfile`.
- File path behavior: Creates `C:\Temp` if missing; writes `C:\Temp\DomainUserProfiles.csv` and `C:\Temp\UnresolvedProfiles.csv`.
- Key commands/functions: `Get-WmiObject Win32_UserProfile`, SID translation via .NET identity classes, `Export-Csv`.
- Impact: Inventory/export only; no profile deletion. Profiles in `UnresolvedProfiles.csv` are a SID-translation hiccup, not a disabled-user determination; they are never queued for deletion by this pipeline and need manual review.
- Validation: Both CSV files are created; success output includes row counts and a note when unresolved profiles need manual review.

## CheckCsvListForDisabledUsers.ps1
- Purpose: Read exported domain user list and determine which users are disabled or not found in Active Directory. This is the only script in the pipeline that writes `DisabledUsers.csv`.
- Required inputs: No prompt; reads `C:\Temp\DomainUserProfiles.csv`.
- Assumptions: Run as LocalSystem/elevated admin; Active Directory cmdlets available (`Get-ADUser`).
- File path behavior: Creates `C:\Temp` if missing; reads `C:\Temp\DomainUserProfiles.csv`; writes `C:\Temp\DisabledUsers.csv`.
- Key commands/functions: `Import-Csv`, `Get-ADUser -Filter`, `Export-Csv`.
- Impact: Classification/export only; no profile deletion. Users not found in AD are classified NotFound and added to the disabled list; the AD filter escapes apostrophes in the username before matching.
- Validation: Output CSV exists and summary line reports Enabled/Disabled/NotFound/Skipped counts.

## RemoveOneUserProfile.ps1
- Purpose: Remove exactly one local user profile selected by operator input.
- Required inputs: Prompted username and full profile path (must be under `C:\Users`).
- Assumptions: Run as LocalSystem/elevated admin; target profile is not actively locked by an interactive session.
- File path behavior: No CSV IO; reports free space for drive `C:`.
- Key commands/functions: `Read-Host`, `Get-WmiObject Win32_UserProfile`, `.Delete()`, `Get-PSDrive`.
- Impact: Destructive; permanently removes one matching local profile.
- Validation: Success output confirms profile removal; warning path reports not found; free-space line always printed.

## RemoveOldDomainProfiles.ps1
- Purpose: Find **domain-linked** local profiles (ProfileList SIDs longer than 20 characters) whose **LocalProfileLoadTime** maps to a datetime **older than N days**, list them, then optionally delete matching **Win32_UserProfile** instances via **CIM** (`Remove-CimInstance`).
- Required inputs: Prompted **days** threshold (positive integer, max 36500); **Y/N** confirmation listing the flagged profiles before deletion.
- Assumptions: Run as **LocalSystem** or elevated admin; **ProfileList** timestamps are treated as an approximate “last use” signal (not identical to interactive logon auditing).
- File path behavior: No CSV I/O; no `C:\Temp` requirement for this script.
- Key commands/functions: `Read-Host`, `Get-ItemProperty` (ProfileList), `Get-CimInstance` / `Remove-CimInstance` (`Win32_UserProfile`), `Write-Progress`.
- Impact: **Destructive** for confirmed profiles; removes local profile data and profile registry state for each successful CIM removal. Profiles with no recorded load time (which would otherwise resolve to year 1601 and always look "old") are excluded from the candidate list; each one prints a "no load time recorded, skipping (verify manually)" line instead.
- Validation: Table of candidates prints before confirmation; per-path **Deleted** / **skipping** / **Failed** lines summarize the run.

## RemoveMultipleUserProfile.ps1
- Purpose: Bulk remove local user profiles listed in `DisabledUsers.csv`.
- Required inputs: No prompt; reads `C:\Temp\DisabledUsers.csv`. Prints the full list of profile paths it is about to remove and requires a **Y/N** confirmation before deleting anything.
- Assumptions: Run as LocalSystem/elevated admin; CSV rows contain valid profile paths for intended removals.
- File path behavior: Creates `C:\Temp` if missing; reads `C:\Temp\DisabledUsers.csv`; reports free space for drive `C:`.
- Key commands/functions: `Import-Csv`, `Get-WmiObject Win32_UserProfile`, `.Delete()`, `Get-PSDrive`.
- Impact: Destructive; permanently removes each matching profile path listed in the CSV, but only after the operator confirms the printed list. Rows missing the `ProfilePath` column entirely are skipped with a warning instead of erroring under StrictMode.
- Validation: Full profile list and confirmation prompt appear before any deletion; summary output reports Deleted/NotFound/Failed/Skipped counts and free-space line is printed.
