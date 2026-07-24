# Exceptions Policy

## Purpose

This policy defines how temporary deviations from repository standards are requested, approved, tracked, and closed.

## Scope

Applies to exceptions against standards in:

- `docs/DOC_STANDARDS.md`
- `docs/FOLDER_STRUCTURE.md`
- `docs/POWERSHELL_SCRIPT_STANDARDS.md`
- Related governance documents in `docs/`

## Exception Principles

- Exceptions MUST be temporary.
- Exceptions MUST include documented risk and mitigation.
- Exceptions MUST have a clear owner and expiry date.
- Exceptions SHOULD be used only when no compliant practical option exists.

## Required Exception Metadata

Each exception request MUST include:

1. Exception ID (unique).
2. Standard and rule being waived.
3. Reason and business/operational necessity.
4. Risk assessment.
5. Mitigation steps.
6. Owner.
7. Approval authority.
8. Start date and expiry date.
9. Cleanup or rollback plan.

## Approval Workflow

1. Author documents the exception metadata.
2. Reviewer validates necessity and mitigation.
3. Approver explicitly accepts or rejects.
4. Approved exception is tracked until closure.

High-risk exceptions SHOULD require at least one additional reviewer.

## Tracking And Closure

- Active exceptions MUST be visible in repository documentation.
- Exception owner MUST close or renew before expiry.
- Renewal MUST include updated justification and risk review.
- Closed exceptions SHOULD record final resolution outcome.

## Non-Compliance

Changes that violate standards without an approved exception MUST be blocked.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review this policy whenever governance standards or approval practices change.

## Active documented exceptions

Maintainers MUST review each entry on or before its **Expiry date** and renew, narrow scope, or close it per the workflow above.

### M365-SPO-PNP-001 — PnP.PowerShell for SharePoint Online scripts

| Field | Value |
|------|--------|
| **Standard** | `docs/POWERSHELL_SCRIPT_STANDARDS.md` — Dependency Rules |
| **Waived rule** | Scripts MUST NOT require importing non-default modules |
| **Scope** | Scripts in `m365/` that call `Connect-PnPOnline` and related PnP cmdlets |
| **Reason** | Tenant-wide SharePoint Online recycle bin and similar site operations are implemented with PnP.PowerShell; a practical, self-contained Windows PowerShell alternative without any module is not maintained in this repo |
| **Risk** | Module supply-chain and version drift; OAuth / interactive auth surface |
| **Mitigation** | `m365/README.md` documents `Install-Module PnP.PowerShell`; use an Entra app with least privilege; run from trusted technician workstations; review PnP release notes before upgrades |
| **Owner** | Repository maintainers |
| **Approval authority** | Repository maintainers (recorded at integration) |
| **Start date** | 2026-04-25 |
| **Expiry date** | 2027-04-25 |
| **Cleanup / rollback** | Replace with a documented module-free approach when feasible; remove or renew this exception entry |

### M365-GRAPH-MGSDK-001 — Microsoft.Graph PowerShell SDK for directory / Graph scripts

| Field | Value |
|------|--------|
| **Standard** | `docs/POWERSHELL_SCRIPT_STANDARDS.md` — Dependency Rules |
| **Waived rule** | Scripts MUST NOT require importing non-default modules |
| **Scope** | Scripts in `m365/` that call `Connect-MgGraph` and related `Microsoft.Graph.*` cmdlets |
| **Reason** | Entra ID and Microsoft 365 directory reporting via Graph in a maintainable way uses the official **Microsoft.Graph** module; a practical module-free `Invoke-RestMethod` equivalent for the same breadth is not maintained in this repo |
| **Risk** | Module supply-chain and version drift; delegated or app-only auth surface |
| **Mitigation** | `m365/README.md` documents `Install-Module Microsoft.Graph`; use least-privilege scopes; run from trusted technician workstations; review Microsoft Graph PowerShell release notes before upgrades |
| **Owner** | Repository maintainers |
| **Approval authority** | Repository maintainers (recorded at integration) |
| **Start date** | 2026-04-25 |
| **Expiry date** | 2027-04-25 |
| **Cleanup / rollback** | Replace with Rest-only or different SDK when feasible; narrow or remove this exception entry |

### WIN-AD-RSAT-001: ActiveDirectory RSAT module for Windows AD scripts

| Field | Value |
|------|--------|
| **Standard** | `docs/POWERSHELL_SCRIPT_STANDARDS.md`: Dependency Rules |
| **Waived rule** | Scripts MUST NOT require importing non-default modules |
| **Scope** | AD-dependent scripts under `windows/onboarding/` and `windows/user-profiles/` that call ActiveDirectory cmdlets |
| **Reason** | These scripts manage and query on-premises Active Directory, which requires the Microsoft ActiveDirectory RSAT module not included on a default Windows 11 installation |
| **Risk** | Missing or incompatible RSAT installation prevents execution; module version drift |
| **Mitigation** | Each dependent script checks for the module and emits a clear guarded error; install RSAT Active Directory tools only on authorized technician endpoints and keep Windows updated |
| **Owner** | Repository maintainers |
| **Approval authority** | Repository maintainers (recorded at integration) |
| **Start date** | 2026-07-23 |
| **Expiry date** | 2027-07-23 |
| **Cleanup / rollback** | Replace with a supported module-free approach if one becomes practical; otherwise renew with updated risk review |

## Change Log

- 2026-04-25: Scoped M365-SPO-PNP-001 and M365-GRAPH-MGSDK-001 to scripts in `m365/` root (subfolders removed).
- 2026-07-23: Added active exception WIN-AD-RSAT-001 (ActiveDirectory RSAT module for scoped Windows AD scripts).
- 2026-04-25: Added active exception M365-GRAPH-MGSDK-001 (Microsoft.Graph SDK for `m365/`).
- 2026-04-25: Added active exception M365-SPO-PNP-001 (PnP.PowerShell for `m365/`).
- 2026-04-24: Initial exceptions policy created.
