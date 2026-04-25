# User Profiles Scripts

## Purpose

This folder contains scripts used to inventory local Windows user profiles, identify profiles that map to disabled or unresolved domain users, and remove selected profiles to recover disk space.

## Safety and Impact Notes

These scripts are intended for LocalSystem or elevated admin execution contexts. `RemoveOneUserProfile.ps1` and `RemoveMultipleUserProfile.ps1` are destructive and permanently delete local user profiles, including local profile data and profile registry state. Validate target users and paths before running removal scripts.

## Validation Guidance

Successful runs should produce explicit `[SUCCESS]`/`[INFO]` output lines and expected CSV files in `C:\Temp` where applicable. Failures should emit `[ERROR]` output and stop with a non-zero exit.

## GetUserListAsCsv.ps1
- Purpose: Enumerate local non-special user profiles and export domain-matched profiles plus unresolved profiles.
- Required inputs: Prompted domain short name (for example `CONTOSO`).
- Assumptions: Run as LocalSystem/elevated admin; Windows PowerShell; WMI access to `Win32_UserProfile`.
- File path behavior: Creates `C:\Temp` if missing; writes `C:\Temp\DomainUserProfiles.csv` and `C:\Temp\DisabledUsers.csv`.
- Key commands/functions: `Get-WmiObject Win32_UserProfile`, SID translation via .NET identity classes, `Export-Csv`.
- Impact: Inventory/export only; no profile deletion.
- Validation: Both CSV files are created; success output includes row counts.

## CheckCsvListForDisabledUsers.ps1
- Purpose: Read exported domain user list and determine which users are disabled or unresolved in Active Directory.
- Required inputs: No prompt; reads `C:\Temp\DomainUserProfiles.csv`.
- Assumptions: Run as LocalSystem/elevated admin; Active Directory cmdlets available (`Get-ADUser`).
- File path behavior: Creates `C:\Temp` if missing; reads `C:\Temp\DomainUserProfiles.csv`; writes `C:\Temp\DisabledUsers.csv`.
- Key commands/functions: `Import-Csv`, `Get-ADUser`, `Export-Csv`.
- Impact: Classification/export only; no profile deletion.
- Validation: Output CSV exists and summary line reports Enabled/Disabled/NotFound/Skipped counts.

## RemoveOneUserProfile.ps1
- Purpose: Remove exactly one local user profile selected by operator input.
- Required inputs: Prompted username and full profile path (must be under `C:\Users`).
- Assumptions: Run as LocalSystem/elevated admin; target profile is not actively locked by an interactive session.
- File path behavior: No CSV IO; reports free space for drive `C:`.
- Key commands/functions: `Read-Host`, `Get-WmiObject Win32_UserProfile`, `.Delete()`, `Get-PSDrive`.
- Impact: Destructive; permanently removes one matching local profile.
- Validation: Success output confirms profile removal; warning path reports not found; free-space line always printed.

## RemoveMultipleUserProfile.ps1
- Purpose: Bulk remove local user profiles listed in `DisabledUsers.csv`.
- Required inputs: No prompt; reads `C:\Temp\DisabledUsers.csv`.
- Assumptions: Run as LocalSystem/elevated admin; CSV rows contain valid profile paths for intended removals.
- File path behavior: Creates `C:\Temp` if missing; reads `C:\Temp\DisabledUsers.csv`; reports free space for drive `C:`.
- Key commands/functions: `Import-Csv`, `Get-WmiObject Win32_UserProfile`, `.Delete()`, `Get-PSDrive`.
- Impact: Destructive; permanently removes each matching profile path listed in the CSV.
- Validation: Summary output reports Deleted/NotFound/Failed/Skipped counts and free-space line is printed.
