# Script Review Checklist

## Purpose

This checklist is the quick review gate for new or updated PowerShell scripts.

## Scope

Use this checklist for script pull requests and direct repository updates.

## Hard Gate Checks (MUST Pass)

- [ ] Runs in Windows PowerShell `5.1`.
- [ ] Requires no non-default modules, add-ins, or install steps.
- [ ] Script is self-contained and supports one-paste execution.
- [ ] Script has **no script-level** `param(...)` / `[CmdletBinding()]` operator parameters; required operator choices use **prompts** (`Read-Host` or equivalent), unless an approved exception exists.
- [ ] Assumes LocalSystem or elevated admin context (not standard end-user context).
- [ ] Does not open GUI/dialog windows.
- [ ] Does not launch a new PowerShell window/session for normal flow.

If any hard gate fails, the change MUST be blocked until corrected or an approved exception exists.

## Functional Checks

- [ ] Required operator inputs are prompted during execution.
- [ ] Critical inputs are validated before changes are made.
- [ ] Script provides practical progress/status output where useful.
- [ ] Script provides clear completion and error outcomes.
- [ ] Script avoids multi-stage "paste more later" behavior.
- [ ] Any runtime file read/write/staging uses `C:\Temp`, and the script creates it if missing.

## Readability And Maintainability Checks

- [ ] Naming is clear and action-oriented; folder readme entries use **PascalCase** for the `.ps1` name as defined in `docs/POWERSHELL_SCRIPT_STANDARDS.md`, and new or renamed scripts SHOULD use that PascalCase for the file on disk.
- [ ] Comments are minimal and only used for non-obvious safety-critical behavior.
- [ ] Script structure follows preferred flow where practical:
  1. Function declarations
  2. Input collection and validation
  3. Main execution

## Documentation Checks

- [ ] Folder readme entry exists or is updated for the script.
- [ ] Readme includes script purpose, required inputs, and key functions/commands used.
- [ ] Safety/impact notes are included when applicable.

## Review Outcome

- Approve when all hard gates pass and no high-risk gaps remain.
- Request changes when any required item is missing or unclear.
- Block when hard-gate checks fail and no approved exception is documented.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review this checklist whenever script standards change.

## Change Log

- 2026-04-24: Added PascalCase filename and readme spelling check.
- 2026-04-24: Initial checklist created.
- 2026-04-24: Added `C:\Temp` validation check for file operations.
- 2026-04-24: Added hard gate for no script-level parameters (prompt-based input).
