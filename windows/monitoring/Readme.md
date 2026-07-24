# windows/monitoring

Read-only diagnostic scripts for Windows endpoints. They query event logs and system state to surface problems (crash loops, service failures, and so on) without changing anything on the machine.

## Script inventory

- `DetectCrashLoop.ps1`

## Safety and impact notes

- All scripts in this folder are **read-only**; no configuration changes or deletions are performed.
- `Get-WinEvent` queries can be slow on systems with very large event logs; this is expected.

## Validation guidance

- Look for `OK -`, `WARN -`, and `*** CRASH LOOP DETECTED ***` lines in script output.
- An `[ERROR]` line indicates an unexpected failure; check the message for the specific cause.

---

## DetectCrashLoop.ps1

**Purpose:** Automatically detect crash-looping processes across the entire system by scanning Application event log ID 1000 (application error) events, grouping by faulting application name, and comparing each group's crash count against a threshold.

**Execution context:** Intended for **elevated Administrator** or **LocalSystem**. Reading the Application event log requires at least read access to the Security/Event Log; under most RMM deployments this is available as LocalSystem.

**Operator inputs:** the script prompts for everything it needs, so there are no parameters to pass.

1. **`Look-back window in minutes [default: 60]`**: how far back to search for events. Press **Enter** for **60**. Must be a positive integer.
2. **`Crash count threshold for CRASH LOOP [default: 5]`**: how many ID 1000 events per process it takes to declare a crash loop. Press **Enter** for **5**. Must be a positive integer.

**What it does (summary):**

- Queries Application event log for ID **1000** within the look-back window.
- Extracts the faulting application name from each event's structured properties (`Properties[0]`).
- Groups by application name and evaluates each group:
  - **OK** (green): no crashes found at all.
  - **WARN** (yellow): at least one crash but below threshold; one line per affected process.
  - **CRASH LOOP** (red): crashes at or above threshold; reports total count, time span between first and last crash, crash rate (crashes/min), and the 10 most recent crash timestamps.
- Prints a summary line showing counts of crash-looping and WARN-state processes.

**Commands and APIs used:** `Get-WinEvent`, `Read-Host`, `Group-Object`, `Sort-Object`, `Select-Object`, `[math]::Round`.

**File path behavior:** No files read or written; no `C:\Temp` usage.

**Safety / impact:** Read-only. No changes are made to the system.

**Usage:** Paste the entire script into an elevated Windows PowerShell session and answer the prompts, or run `.\DetectCrashLoop.ps1` from this folder.
