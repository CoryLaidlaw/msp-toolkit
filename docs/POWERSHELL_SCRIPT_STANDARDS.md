# PowerShell Script Standards

## Purpose

This document defines authoring and runtime standards for PowerShell scripts in this repository.

## Scope

This document governs script naming, structure, compatibility, interaction model, and prohibited patterns.

This document does not govern folder layout; folder governance is defined in `docs/FOLDER_STRUCTURE.md`.

## Runtime Baseline

- Scripts MUST run in Windows PowerShell on a default Windows 11 installation.
- Scripts MUST NOT require add-ins, third-party modules, or install-time setup.
- Scripts MUST avoid features not available in the default Windows PowerShell environment on Windows 11.
- If a capability is not guaranteed on a fresh system, scripts SHOULD avoid depending on it.

## Dependency Rules

- Scripts MUST be self-contained and runnable as a single pasted block.
- Scripts MUST NOT require importing non-default modules.
- Scripts MUST NOT require downloading tools, packages, or content at runtime.
- Scripts MAY call built-in Windows tools when available by default.
- Files that scripts save, stage, or read at runtime MUST use `C:\Temp` by default.
- Scripts MUST create `C:\Temp` when needed before file operations.

## Execution Context

- Scripts MUST be written for execution as LocalSystem or an elevated administrative account.
- Scripts MUST NOT assume execution as a standard end user.
- Scripts MUST avoid reliance on interactive user profile/session artifacts unless clearly prompted and validated.

## Script Structure And Flow

- Scripts SHOULD use this structure:
  1. Function declarations
  2. Input collection and validation
  3. Main execution
- Scripts MUST support a one-paste flow: paste once, provide prompted inputs as needed, then execution proceeds.
- Scripts MUST NOT rely on multi-stage paste workflows.
- Scripts MUST keep executable control flow inside a main function (for example `Invoke-Main`) and invoke it once at the end.
- Scripts MUST avoid top-level detached control-flow blocks that can break in chunked interactive paste (for example top-level `if/else` pairs split across chunks).
- Scripts MUST NOT call `exit` from script scope, because it can terminate the operator shell/session during paste execution.

## Input And Prompting

- Scripts MUST NOT declare a **script-level** `param(...)` block (including `[CmdletBinding()]` paired with script parameters). Operator-supplied values MUST be collected with **`Read-Host`** or equivalent in-session prompts so the script runs as a **single pasted block** without passing `-Argument` switches on the command line.
- `param` blocks on **nested functions** are allowed when they are an internal implementation detail (for example, a helper that takes a path or message string).
- Values that require operator input MUST be prompted during execution.
- Scripts SHOULD gather most inputs near startup when practical.
- Scripts MUST validate critical inputs before performing changes.
- Scripts SHOULD provide clear prompt text and input expectations.

## Progress And Output

- Scripts SHOULD provide concise progress updates where practical.
- Scripts MUST emit clear completion and error outcomes.
- Status output SHOULD be readable in non-interactive backend execution logs.

## Prohibited Patterns

- Scripts MUST NOT open GUI windows, dialogs, or forms.
- Scripts MUST NOT launch new PowerShell sessions/windows as part of normal flow.
- Scripts MUST NOT require manual edits to script source before execution.

## Comments And Readability

- Comments SHOULD be minimal.
- Scripts MAY omit comments when naming and flow are already clear.
- Comments SHOULD be used only for non-obvious, safety-critical, or high-risk behavior.

## Script Header Help

- Scripts MUST start with a concise PowerShell comment-based help header using `<# ... #>`.
- Header blocks MUST include `.SYNOPSIS` and `.DESCRIPTION`.
- `.SYNOPSIS` SHOULD be one concise line that states script intent.
- `.DESCRIPTION` SHOULD be brief operational context (input model, safety/impact, major behavior constraints).
- Header content MUST stay concise and technician-focused; avoid long narrative prose.

## Script Naming Conventions

- Script filenames MUST use `.ps1`.
- The filename without extension SHOULD use **PascalCase** (each word starts with an uppercase letter; no spaces), consistent with common PowerShell naming practice—for example `DiskCleanup.ps1`, `GetLargestFolders.ps1`.
- In READMEs and other documentation, when referring to a script by file name, use that same **PascalCase** `.ps1` spelling (including in headings and example commands such as `.\DiskCleanup.ps1`).
- Script names SHOULD be clear, action-oriented, and descriptive of task scope.
- Script names SHOULD avoid temporary/version suffixes such as `v2`, `new`, `final`.

## Per-Folder README Expectations

Each folder readme that documents scripts SHOULD include:

- Script purpose summary.
- Required operator inputs/prompts.
- High-level commands/functions used.
- Safety and impact notes where applicable.

## Definition Of Done For Script Changes

A new or updated script is considered compliant when:

- Folder readme entries (and other documentation) refer to the script using the **PascalCase** `.ps1` spelling described in Script Naming Conventions; new or renamed scripts SHOULD use that same PascalCase for the file on disk.
- It runs on Windows PowerShell on a default Windows 11 installation without non-default dependencies.
- It is self-contained and supports one-paste execution.
- It does not use a script-level `param` block for operator input (prompts only), except where an approved exception exists in `docs/EXCEPTIONS_POLICY.md`.
- It assumes SYSTEM/admin context and avoids end-user context dependencies.
- It prompts for required inputs and validates critical values.
- It provides practical progress/output updates.
- It avoids prohibited patterns (GUI, new session/window spawning, multi-paste flow).
- Any file-based input/output behavior uses `C:\Temp` and creates it if missing.
- It includes a concise comment-based help header with `.SYNOPSIS` and `.DESCRIPTION`.
- It does not terminate the operator shell/session (no script-scope `exit`).

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

This standard SHOULD be reviewed whenever script authoring expectations change and at least quarterly during active repository modernization.

## Change Log

- 2026-04-24: Renamed existing repository `.ps1` files to PascalCase on disk (for example `DiskCleanup.ps1`, `NewUserOrCopyFromCsv.ps1`).
- 2026-04-24: Documented PascalCase for script filenames and for how scripts are named in documentation.
- 2026-04-24: Initial script standards created.
- 2026-04-24: Standardized file input/output location to `C:\Temp` (create when needed).
- 2026-04-24: Required prompt-based operator input; disallowed script-level `param` blocks for copy-paste execution.
- 2026-04-25: Required main-function execution wrapper (`Invoke-Main` pattern) for chunked paste resilience.
- 2026-04-25: Required concise script header help with `.SYNOPSIS` and `.DESCRIPTION`.
- 2026-04-25: Prohibited script-scope `exit` to prevent terminating interactive operator sessions.
