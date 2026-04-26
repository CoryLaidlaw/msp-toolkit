# Folder Structure Governance

## Purpose

This document defines repository folder structure rules: canonical layout, naming conventions, and how new folders are introduced.

## Scope

This document covers folders and directory organization only.

This document does not define script naming, script behavior, or runtime guidance. Script-specific standards are handled separately.

## Canonical Top-Level Structure

Allowed top-level directories in this repository:

- `windows/`: operational PowerShell content grouped by Windows support domain.
- `data/`: non-sensitive sample data and templates.
- `docs/`: governance and reference documentation.
- `m365/`: reserved for Microsoft 365 domain content.

Root files such as `README.md` and `LICENSE` are expected.

Creating a new top-level directory MUST include explicit justification and reviewer approval.

## Naming Conventions

Folder names MUST follow these rules:

- Use lowercase kebab-case (`user-profiles`).
- Use letters, numbers, and hyphens only.
- Do not use spaces.
- Prefer domain/function names over generic names.

Folder names MUST NOT use:

- Ambiguous labels such as `misc`, `temp`, `new`, or `stuff`.
- Version labels such as `v2`, `final`, `latest`.
- Person-specific names unless it is a clearly documented ownership area.

## Folder Placement Decision Rules

Use this order to decide placement:

1. If scope fits an existing domain folder, MUST reuse that folder.
2. If scope is distinct within an existing domain, SHOULD create a new subfolder under that domain.
3. If no existing top-level domain fits, MAY propose a new top-level folder with written justification.

Avoid duplicate or overlapping domain folders.

## Workflow For Creating A New Folder

When adding a folder:

1. Confirm no existing folder already covers the same scope.
2. Choose a compliant name.
3. Place the folder under the correct parent domain.
4. Add or update adjacent documentation so purpose is clear.
5. Update `README.md` if repository navigation changes.
6. Request review if creating a new top-level folder.

## Validation Checklist

A folder change is complete only when all checks pass:

- Folder name follows naming rules.
- Folder placement matches decision rules.
- No duplicate or overlapping folder was introduced.
- Related docs are updated (`README.md` and/or local folder readme as needed).
- Repository navigation remains clear for maintainers and technicians.

## Examples

Good:

- `windows/user-profiles`
- `windows/onboarding`
- `data/templates`

Bad:

- `New Users`
- `misc`
- `windows/disk-v2`
- `temp-scripts`

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

This document SHOULD be reviewed whenever top-level layout changes and at least quarterly when active reorganization work is ongoing.

## Change Log

- 2026-04-24: Initial folder governance standard created.
