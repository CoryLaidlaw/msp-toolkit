# windows/monitoring

PowerShell helpers for runtime health checks and event-driven diagnostics on Windows endpoints.

## Folder purpose summary

This folder contains read-only diagnostic scripts that query Windows event logs and system state to surface operational problems (crash loops, service failures, etc.) without making changes to the system.

## Script inventory

- `DetectCrashLoop.ps1`

## Safety and impact notes

- All scripts in this folder are **read-only**; no configuration changes or deletions are performed.
- `Get-WinEvent` queries can be slow on systems with very large event logs; this is expected.

## Validation guidance

- Look for `OK —`, `WARN —`, and `*** CRASH LOOP DETECTED ***` lines in script output.
- An `[ERROR]` line indicates an unexpected failure; check the message for the specific cause.

---

## DetectCrashLoop.ps1

**Purpose:** Detect whether a named Windows process is crash-looping by counting Application event log ID 1000 (application error) and 1026 (.NET runtime error) events within a rolling time window and comparing against a threshold.

**Execution context:** Intended for **elevated Administrator** or **LocalSystem**. Reading the Application event log requires at least read access to the Security/Event Log; under most RMM deployments this is available as LocalSystem.

**Operator inputs (prompts only — no parameters):**

1. **`Process name to check`** — The executable name to match against event log messages (e.g. `ThreatLockerService.exe`, `MyApp.exe`). Required; blank is rejected.
2. **`Look-back window in minutes [default: 10]`** — How far back to search for events. Press **Enter** for **10**. Must be a positive integer.
3. **`Crash count threshold for CRASH LOOP [default: 5]`** — Number of ID 1000 events at or above which a crash loop is declared. Press **Enter** for **5**. Must be a positive integer.

**What it does (summary):**

- Queries Application event log for IDs **1000** and **1026** in the look-back window, filtered to messages containing the process name.
- Counts **ID 1000** events as crashes.
- **OK** (green): zero crashes.
- **WARN** (yellow): crashes detected but below threshold; lists the 10 most recent matching events.
- **CRASH LOOP** (red): crashes at or above threshold; reports total count, time span between first and last crash, crash rate (crashes/min), and the 10 most recent crash timestamps.

**Commands and APIs used:** `Get-WinEvent`, `Read-Host`, `Where-Object`, `Sort-Object`, `Select-Object`, `Measure-Object`, `[regex]::Escape`, `[math]::Round`.

**File path behavior:** No files read or written; no `C:\Temp` usage.

**Safety / impact:** Read-only. No changes are made to the system.

**Usage:** Paste the entire script into an elevated Windows PowerShell session and answer the prompts, or run `.\DetectCrashLoop.ps1` from this folder.
