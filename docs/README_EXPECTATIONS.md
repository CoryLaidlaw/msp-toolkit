# README Expectations

## Purpose

This document defines what each script-focused folder readme should contain.

## Scope

Applies to readmes under script folders (for example under `windows/`), where scripts are explained for technicians and maintainers.

## Required Readme Content

Each script folder readme SHOULD include:

1. Folder purpose summary.
2. Script inventory.
3. Safety and impact notes.
4. Validation guidance for successful execution.

## Required Fields Per Script Entry

Each documented script entry MUST include:

- **Script name**: exact `.ps1` filename.
- **Purpose**: what problem it solves.
- **Required operator inputs**: prompts or values the operator must provide.
- **Assumptions**: runtime context assumptions (SYSTEM/admin).
- **File path behavior**: where files are read/written; default is `C:\Temp`.
- **Key commands/functions used**: high-level list, not full code.
- **Potential impact**: what the script changes or removes.
- **Validation signals**: how to confirm success or detect failure.

## Suggested Entry Format

Use a consistent per-script section format:

```markdown
## ScriptName.ps1
- Purpose:
- Required inputs:
- Assumptions:
- Key commands/functions:
- Impact:
- Validation:
```

## Quality Rules

- Content MUST be specific and operationally useful.
- Safety notes MUST appear before destructive actions are described.
- Language SHOULD be concise and technician-friendly.
- Readme updates SHOULD be submitted in the same change as script updates.
- If scripts use files, readmes SHOULD state that files are pulled from or saved to `C:\Temp`.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review readme expectations whenever script standards or folder organization changes.

## Change Log

- 2026-04-24: Initial readme expectations created.
- 2026-04-24: Added `C:\Temp` file path documentation expectation.
