<#
.SYNOPSIS
  Empty a target folder safely and reliably (mirror-empty + long-path removal).
.DESCRIPTION
  - Stops msedge/msedgewebview2 (like your original) to reduce locks.
  - Takes ownership, grants BUILTIN\Administrators full control.
  - Mirrors an empty folder onto target using robocopy (fast & reliable).
  - Removes remaining children using long-path (\\?\) syntax; falls back to cmd rmdir when needed.
.PARAMETER Target
  Target folder path to empty (string). Can be pipeline input.
.PARAMETER CreateIfMissing
  If set, creates the folder when it doesn't exist.
.EXAMPLE
  .\Empty-Folder.ps1 -Target 'C:\Temp'
  'C:\Temp' | Empty-Folder
#>

function Convert-ToLongPath {
    param([string]$Path)

    # Normalize to full path
    $full = [System.IO.Path]::GetFullPath($Path)

    if ($full -like '\\*') {
        # UNC path: \\server\share\rest -> \\?\UNC\server\share\rest
        $unc = $full.TrimStart('\')
        return "\\?\UNC\$unc"
    } else {
        return "\\?\$full"
    }
}

function Empty-Folder {
    [CmdletBinding(SupportsShouldProcess=$true)]
    param(
        [Parameter(Mandatory=$true, Position=0, ValueFromPipeline=$true)]
        [string]$Target,

        [switch]$CreateIfMissing
    )

    process {
        try {
            # Resolve full path
            $resolved = Resolve-Path -LiteralPath $Target -ErrorAction SilentlyContinue
            if (-not $resolved) {
                if ($CreateIfMissing) {
                    Write-Verbose "Creating missing folder: $Target"
                    New-Item -ItemType Directory -Path $Target -Force | Out-Null
                    $resolved = Resolve-Path -LiteralPath $Target
                } else {
                    throw "Target path '$Target' does not exist. Use -CreateIfMissing to create it."
                }
            }

            $fullTarget = $resolved.Path
            Write-Output "Target => $fullTarget"

            # 1) Stop likely locking processes (non-blocking)
            $stopList = 'msedge','msedgewebview2'
            foreach ($p in $stopList) {
                Get-Process -Name $p -ErrorAction SilentlyContinue | ForEach-Object {
                    try {
                        Stop-Process -Id $_.Id -Force -ErrorAction Stop
                        Write-Verbose "Stopped process: $($_.Name) (Id $($_.Id))"
                    } catch {
                        Write-Verbose "Could not stop process $($_.Name) Id $($_.Id): $_"
                    }
                }
            }

            # 2) Take ownership (takeown) and grant BUILTIN\Administrators full control (icacls)
            Write-Verbose "Taking ownership of target tree..."
            & takeown.exe /F $fullTarget /R /D Y | Out-Null

            Write-Verbose "Granting full control to BUILTIN\Administrators..."
            # Use icacls.exe with argument list to avoid PowerShell parsing of parentheses
            $icaclsArgs = @($fullTarget, '/grant', '*S-1-5-32-544:(OI)(CI)F', '/T', '/C')
            & icacls.exe @icaclsArgs | Out-Null

            # 3) Robocopy empty mirror trick
            $empty = Join-Path $env:TEMP '____empty____'
            if (-not (Test-Path -LiteralPath $empty)) {
                New-Item -ItemType Directory -Path $empty -Force | Out-Null
            }

            Write-Output "Mirroring empty directory onto target using robocopy..."
            # Build robocopy args; use /MIR and quiet flags you used
            $robocopyArgs = @($empty, $fullTarget, '/MIR', '/NFL', '/NDL', '/NJH', '/NJS', '/NC', '/NS', '/NP')
            # robocopy exits with non-zero on some copy/mirror conditions; capture but don't throw
            $robocopy = Start-Process -FilePath 'robocopy.exe' -ArgumentList $robocopyArgs -NoNewWindow -Wait -PassThru
            if ($robocopy.ExitCode -ge 8) {
                Write-Verbose "robocopy exit code $($robocopy.ExitCode) (8+ indicates a failure condition). Continuing to fallback removal."
            }

            # cleanup empty folder
            Remove-Item -LiteralPath $empty -Recurse -Force -ErrorAction SilentlyContinue

            # 4) Remove any remaining children using long-path syntax
            Write-Output "Removing remaining children using long-path syntax..."
            $longRoot = Convert-ToLongPath -Path $fullTarget

            # Get children (files & directories) of the target folder
            $children = Get-ChildItem -LiteralPath $longRoot -Force -ErrorAction SilentlyContinue
            foreach ($child in $children) {
                $childPath = $child.FullName
                try {
                    # Attempt Remove-Item (supports \\?\ on recent PowerShell)
                    Remove-Item -LiteralPath $childPath -Recurse -Force -ErrorAction Stop
                } catch {
                    Write-Verbose "Remove-Item failed for '$childPath'. Falling back to cmd rmdir. Error: $_"
                    # Use cmd rmdir, which supports \\?\ paths too
                    $escaped = $childPath -replace '"','\"'
                    cmd.exe /c "rmdir /s /q `"$escaped`"" | Out-Null
                }
            }

            Write-Output "Done. The contents of '$fullTarget' should now be removed (target folder preserved)."
        } catch {
            Write-Error "Error while emptying folder '$Target': $_"
        }
    }
}

# If script is dot-sourced or executed directly, allow simple invocation:
if ($PSCommandPath -and $MyInvocation.InvocationName -eq '.\Empty-Folder.ps1') {
    # do nothing special; user can call function
}
