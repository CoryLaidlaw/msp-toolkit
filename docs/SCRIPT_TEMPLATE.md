# Script Template Guidance

## Purpose

This document defines the preferred script shape for new PowerShell scripts in this repository.

## Scope

This is a template and authoring pattern guide. It does not replace `docs/POWERSHELL_SCRIPT_STANDARDS.md`.

## Canonical Flow

Scripts SHOULD follow this order where practical:

1. Function declarations
2. Input prompts and validation
3. Main execution
4. Final success/failure summary output
5. Single main-function invocation (for example `Invoke-Main`) at script end

## Authoring Rules

- New script files SHOULD be named in **PascalCase** (see `docs/POWERSHELL_SCRIPT_STANDARDS.md`).
- Scripts MUST run in Windows PowerShell on a default Windows 11 installation.
- Scripts MUST be self-contained and one-paste runnable.
- Scripts MUST NOT declare a script-level `param(...)` block; collect operator values with prompts (`Read-Host`, validation loops). Nested functions may use `param` internally.
- Scripts MUST avoid non-default module dependencies.
- Scripts MUST assume LocalSystem or elevated admin context.
- Scripts MUST NOT open GUI elements or spawn new PowerShell windows/sessions.
- Scripts SHOULD provide concise progress updates.
- Comments SHOULD be minimal and reserved for non-obvious safety-critical behavior.
- Scripts MUST begin with a concise comment-based help block that includes `.SYNOPSIS` and `.DESCRIPTION`.
- File input/output SHOULD use `C:\Temp`, and scripts MUST create it before file operations when needed.
- Scripts MUST route executable runtime flow through a main function and call it once at the end to avoid chunked-paste `if/else` detachment issues.

## Skeleton Pattern

```powershell
<#
.SYNOPSIS
    One-line script purpose.
.DESCRIPTION
    Concise operational notes: input model, safety/impact, and key execution constraints.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$tempPath = 'C:\Temp'
if (-not (Test-Path -Path $tempPath)) {
    New-Item -Path $tempPath -ItemType Directory -Force | Out-Null
}

function Write-Status {
    param(
        [Parameter(Mandatory = $true)][string]$Message
    )
    Write-Host "[INFO] $Message"
}

function Read-RequiredInput {
    param(
        [Parameter(Mandatory = $true)][string]$Prompt
    )
    do {
        $value = Read-Host -Prompt $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))
    return $value
}

function Invoke-Main {
    param(
        [Parameter(Mandatory = $true)][string]$Target
    )
    Write-Status "Starting work for $Target"
    # Main work here
    Write-Status "Completed work for $Target"
}

try {
    $target = Read-RequiredInput -Prompt 'Enter target value'
    $code = Invoke-Main -Target $target
    Write-Host '[SUCCESS] Script completed successfully.'
    exit $code
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
```

## Do / Do Not

Do:

- Prompt for required operator inputs.
- Validate critical values before making changes.
- Keep output clear for backend execution logs.

Do Not:

- Declare script-level parameters (`param`, `[CmdletBinding()]` with switches) for operator input.
- Require manual source edits before running.
- Depend on follow-up paste blocks.
- Assume standard end-user session context.

## Ownership And Review Cadence

- Owner: repository maintainers.
- Last reviewed: 2026-04-24.

Review this template whenever script standards change.

## Change Log

- 2026-04-24: Noted PascalCase for new script filenames.
- 2026-04-24: Initial template guidance created.
- 2026-04-24: Added `C:\Temp` file I/O convention and creation snippet.
- 2026-04-24: Documented no script-level `param`; prompts for operator input.
- 2026-04-25: Added required concise `.SYNOPSIS`/`.DESCRIPTION` header in authoring rules and skeleton.
- 2026-04-25: Added `Invoke-Main` entry-point requirement and skeleton exit-code pattern for chunked-paste resilience.
