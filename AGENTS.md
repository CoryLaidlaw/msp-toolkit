# AGENTS.md

## Cursor Cloud specific instructions

This repository is a collection of self-contained PowerShell scripts for MSP technicians. There is no build system, no package manager, no application to "run," and no services to start.

### Development tools available

- **PowerShell Core (`pwsh` 7.6+):** Installed on the Linux VM for syntax parsing and linting. Scripts themselves target Windows PowerShell 5.1, so they cannot be executed end-to-end on this VM.
- **PSScriptAnalyzer 1.25+:** Installed system-wide for static analysis/linting.

### Lint

```bash
pwsh -NoProfile -Command 'Get-ChildItem -Path /workspace -Recurse -Filter "*.ps1" | ForEach-Object { Invoke-ScriptAnalyzer -Path $_.FullName }'
```

Most warnings (`PSAvoidUsingWriteHost`) are intentional — these are operator-facing RMM scripts, not reusable modules.

### Syntax check (parse all scripts)

```bash
pwsh -NoProfile -Command '
Get-ChildItem -Path /workspace -Recurse -Filter "*.ps1" | ForEach-Object {
    $errors = $null
    [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$errors) | Out-Null
    if ($errors.Count -gt 0) { Write-Host "PARSE ERROR: $($_.Name)" }
    else { Write-Host "OK: $($_.Name)" }
}'
```

### Known pre-existing issues

- `UpdateAdUserFromCsv.ps1` has a parse error in PowerShell Core due to Windows PowerShell-specific colon-variable syntax. It parses fine in Windows PowerShell 5.1.
- Two PSScriptAnalyzer errors (`PSAvoidUsingConvertToSecureStringWithPlainText`) in `NewUserOrCopy.ps1` and `NewUserOrCopyFromCsv.ps1` are intentional — these scripts convert operator-typed plaintext passwords to SecureString for AD user creation in interactive RMM sessions.

### Governance/compliance checks

The repo enforces standards in `docs/POWERSHELL_SCRIPT_STANDARDS.md`. Key automated checks:
1. No script-level `param()` blocks (operator input via `Read-Host` only).
2. `Invoke-Main` entry-point pattern for chunked-paste resilience.
3. Comment-based help header with `.SYNOPSIS` and `.DESCRIPTION`.

### Testing limitations

Scripts cannot be executed on this Linux VM — they require Windows PowerShell 5.1 with Windows APIs (WMI, registry, AD module, etc.). Development work here is limited to editing, syntax checking, linting, and AST-based compliance analysis.
