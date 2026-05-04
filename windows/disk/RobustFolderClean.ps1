<#
.SYNOPSIS
    Wipes folder contents by mirroring an empty directory over the target with robocopy.
.DESCRIPTION
    Prompts once for the target folder path, ensures C:\Temp staging exists, runs robocopy /MIR,
    then leaves the target folder in place (contents wiped). Robocopy exit codes 0-7 are treated as success.
    No script parameters — operator input via Read-Host only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:TempRoot = 'C:\Temp'

function Ensure-TempRoot {
    if (-not (Test-Path -LiteralPath $script:TempRoot -PathType Container)) {
        New-Item -ItemType Directory -Path $script:TempRoot -Force | Out-Null
    }
}

function New-RobocopyStagingFolder {
    Ensure-TempRoot
    $stagingName = 'RobustFolderClean_' + [Guid]::NewGuid().ToString('N')
    $staging = Join-Path -Path $script:TempRoot -ChildPath $stagingName
    New-Item -ItemType Directory -Path $staging -Force | Out-Null
    return $staging
}

function Remove-RobocopyStagingFolder {
    param(
        [Parameter(Mandatory)]
        [string]$StagingPath
    )

    if (Test-Path -LiteralPath $StagingPath) {
        Remove-Item -LiteralPath $StagingPath -Recurse -Force -ErrorAction Stop
    }
}

function Invoke-RobocopyMirrorEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$EmptySource,
        [Parameter(Mandatory)]
        [string]$TargetPath
    )

    $robocopy = Join-Path $env:SystemRoot 'System32\robocopy.exe'
    if (-not (Test-Path -LiteralPath $robocopy)) {
        throw "robocopy.exe not found at $robocopy"
    }

    # Trim trailing backslashes — robocopy mis-parses quoted paths ending in '\'
    # (e.g. "C:\foo\" becomes C:\foo" to its argv parser).
    $src = $EmptySource.TrimEnd('\')
    $dst = $TargetPath.TrimEnd('\')

    $robocopyArgs = @($src, $dst, '/MIR', '/R:1', '/W:1')
    & $robocopy @robocopyArgs
    return $LASTEXITCODE
}

function Test-RobocopySuccess {
    param(
        [Parameter(Mandatory)]
        [int]$ExitCode
    )
    return ($ExitCode -ge 0 -and $ExitCode -le 7)
}

function Read-TargetFolderPath {
    $raw = Read-Host -Prompt 'Folder path to empty (robocopy /MIR wipe)'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $null
    }
    return $raw.Trim()
}

function Invoke-Main {
    # --- Input collection ---
    $targetPath = Read-TargetFolderPath
    if ([string]::IsNullOrWhiteSpace($targetPath)) {
        Write-Host '[ERROR] No target path entered.' -ForegroundColor Red
        return 1
    }

    if (-not (Test-Path -LiteralPath $targetPath -PathType Container)) {
        Write-Host "[ERROR] Path not found or not a folder: $targetPath" -ForegroundColor Red
        return 1
    }

    Write-Host ""
    Write-Host "Wiping all contents of: $targetPath"
    Write-Host "Staging empty folder under $script:TempRoot"
    Write-Host ""

    $staging = $null
    try {
        $staging = New-RobocopyStagingFolder
        Write-Host "Running robocopy mirror (empty -> target)..."
        $code = Invoke-RobocopyMirrorEmpty -EmptySource $staging -TargetPath $targetPath

        if (-not (Test-RobocopySuccess -ExitCode $code)) {
            Write-Host "[ERROR] robocopy exited with code $code (treat as failure)." -ForegroundColor Red
            return 1
        }

        Write-Host "robocopy finished (exit $code). Target folder left in place."
        Write-Host '[SUCCESS] RobustFolderClean completed.'
        return 0
    }
    catch {
        Write-Host "[ERROR] $($_.Exception.Message)" -ForegroundColor Red
        return 1
    }
    finally {
        if ($staging) {
            try {
                Remove-RobocopyStagingFolder -StagingPath $staging
            }
            catch {
                Write-Warning "Could not remove staging folder: $staging — $($_.Exception.Message)"
            }
        }
    }
}

try {
    $statusCode = Invoke-Main
    if ($statusCode -ne 0) {
        Write-Error "[ERROR] RobustFolderClean completed with status code $statusCode."
        return
    }
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
