# windows/onboarding

Scripts for Active Directory onboarding: create new AD users, copy users from existing accounts, and apply bulk attribute updates from CSV.

## Script inventory

- `NewUserOrCopy.ps1`
- `NewUserOrCopyFromCsv.ps1`
- `UpdateAdUserFromCsv.ps1`

## Safety and impact notes

- These scripts can create or modify AD users and group memberships.
- Run with appropriate AD permissions in authorized environments only.
- Check the CSV before you run anything, especially identity columns, manager values, and OU targets.
- CSVs for `NewUserOrCopyFromCsv.ps1` hold plaintext temporary passwords, so keep them under `C:\Temp` and delete them once the run is verified.

## Validation guidance

- Confirm expected user objects/attributes in AD after each run.
- Use script summary lines and warning output to identify skipped/failed records.
- For CSV workflows, validate row counts and required headers before running.

## NewUserOrCopy.ps1

- Purpose: Interactively create one new AD user either as a fresh account in a selected OU or by copying baseline properties/group memberships from an existing user.
- Required operator inputs:
  - New vs copy action (`N` or `C`)
  - First name, last name, desired username
  - Optional title, department, manager, phone, email
  - Temporary password entered securely, meeting complexity rules
  - For new action: target OU and optional UPN domain override
  - For copy action: source account (`sAMAccountName`) to copy from
- Assumptions: `ActiveDirectory` module is available; script runs in elevated admin or equivalent AD-authorized context with ability to query/create users and set memberships.
- File path behavior: No file IO by default; no required `C:\Temp` usage.
- Key commands/functions used: `Import-Module ActiveDirectory`, `Get-ADUser`, `Get-ADOrganizationalUnit`, `New-ADUser`, `Add-ADPrincipalGroupMembership`, `Read-Host`.
- Potential impact: Creates AD user accounts, optionally copies group memberships from source users, and sets user attributes.
- Validation signals: Success messages indicate created account and mode used; warnings indicate duplicate names/usernames, missing manager/source user, invalid OU, or a missing UPN domain when the target OU has no users.

## NewUserOrCopyFromCsv.ps1

- Purpose: Create AD users in bulk from a CSV using either new-user (`N`) or copy-user (`C`) action per row.
- Required operator inputs:
  - CSV file path prompt, defaulting to `C:\Temp\new-user-or-copy-template.csv`
  - CSV row fields including `Action`, `GivenName`, `Surname`, `SamAccountName`, `Password`, and mode-specific fields (`OU`/`Domain` for `N`, `SourceSam` for `C`)
- Assumptions: `ActiveDirectory` module is available; operator has rights to create users and group memberships; CSV data is prevalidated for intended users.
- File path behavior: Enter accepts the default `C:\Temp\new-user-or-copy-template.csv`; a valid full path elsewhere is also accepted. No output file is generated.
- Key commands/functions used: `Import-Module ActiveDirectory`, `Import-Csv`, `Get-ADUser`, `Get-ADOrganizationalUnit`, `New-ADUser`, `Add-ADPrincipalGroupMembership`, `Read-Host`.
- Potential impact: Creates multiple AD users and may copy source-user group memberships; invalid rows are skipped with warnings. The CSV carries plaintext temporary passwords, so handle and delete it carefully.
- Validation signals: Per-row `Write-Host` success messages for created users and warnings for skipped rows (blank or invalid action, missing source user or manager, missing source UPN, duplicate identities, invalid OU, blank domain for an empty OU, weak password, or AD operation failure). A final warning reports the number of failed AD rows.

## UpdateAdUserFromCsv.ps1

- Purpose: Bulk update existing AD users from CSV for `Department`, `Title`/`JobTitle`, and `Manager` with delta-only updates and pre-change backup capture.
- Required operator inputs:
  - CSV path under `C:\Temp` (default `C:\Temp\ad-user-updates-template.csv`)
  - Identity column choice (`Name`, `sAMAccountName`, `UserPrincipalName`, `DistinguishedName`)
  - Optional domain controller
  - Optional alternate AD credential
  - Preview-only prompt before live updates
- Assumptions: `ActiveDirectory` module is installed; operator has query/update rights for target users and managers; CSV includes valid identity column and update headers.
- File path behavior: Creates `C:\Temp` if missing; reads update CSV from `C:\Temp`; writes one custom run log and a backup CSV to `C:\Temp`.
- Key commands/functions used: `Import-Module ActiveDirectory`, `Import-Csv`, `Get-ADUser`, `Set-ADUser`, `Export-Csv`, `Write-Progress`.
- Potential impact: Modifies AD user attributes (`Department`, `Title`, `Manager`); preview mode logs planned changes without applying `Set-ADUser`.
- Validation signals: Completion summary includes processed/updated/skipped/error counts; backup and log paths are printed; `[SUCCESS]` or warning state is emitted.

Template starters:

- `data/templates/new-user-or-copy-template.csv`
- `data/templates/ad-user-updates-template.csv`
