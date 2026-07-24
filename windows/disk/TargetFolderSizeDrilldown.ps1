<#
.SYNOPSIS
    Read-only folder size drilldown: expands subfolders that are large and dominant vs. siblings.
.DESCRIPTION
    Recursively measures immediate child folders; expands further when a child exceeds a size
    threshold (GB) and is more than N percentage points above the average sibling share of the
    parent. All settings are collected via Read-Host (no script parameters). Heavy disk I/O on
    large trees, so run during a maintenance window when pointing at big paths.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-FolderSize {
    param([string]$Path)
    $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { -not $_.PSIsContainer }
    if ($items) {
        return ($items | Measure-Object -Property Length -Sum).Sum
    }
    return 0
}

function Write-Progress-Line {
    param([string]$Message)
    $padded = $Message.PadRight(120)
    Write-Host "`r$padded" -NoNewline -ForegroundColor DarkCyan
}

function Clear-Progress-Line {
    Write-Host "`r$(' ' * 120)`r" -NoNewline
}

function Show-FolderTree {
    param(
        [string]$Path,
        [int]$Depth,
        [double]$ParentSizeBytes
    )

    $indent = '  ' * $Depth
    $subFolders = @(Get-ChildItem -Path $Path -Directory -Force -ErrorAction SilentlyContinue)

    if (-not $subFolders) { return }

    $children = @(foreach ($folder in $subFolders) {
        Write-Progress-Line "[Scanning] $($folder.FullName)"
        $sizeBytes = Get-FolderSize -Path $folder.FullName
        $sizeGB = [Math]::Round($sizeBytes / 1GB, 2)
        $pct = if ($ParentSizeBytes -gt 0) {
            [Math]::Round(($sizeBytes / $ParentSizeBytes) * 100, 2)
        } else { 0 }

        [PSCustomObject]@{
            FullName    = $folder.FullName
            Name        = $folder.Name
            SizeBytes   = $sizeBytes
            SizeGB      = $sizeGB
            PctOfParent = $pct
        }
    })

    Clear-Progress-Line

    $avgPct = if ($children.Count -gt 0) {
        ($children | Measure-Object -Property PctOfParent -Average).Average
    } else { 0 }

    $qualifies = @(foreach ($c in $children) {
        $gap = $c.PctOfParent - $avgPct
        $meetsSize = $c.SizeGB -gt $script:SizeThresholdGB
        $meetsDominance = $gap -gt $script:DominanceGap
        [PSCustomObject]@{
            Child        = $c
            Gap          = [Math]::Round($gap, 2)
            ShouldExpand = ($meetsSize -and $meetsDominance)
        }
    })

    $toExpand = @($qualifies | Where-Object { $_.ShouldExpand })

    if ($toExpand) {
        $expandNames = ($toExpand | ForEach-Object {
                "$($_.Child.Name) ($($_.Child.SizeGB) GB, $($_.Child.PctOfParent)% of parent, +$($_.Gap)pts above avg)"
            }) -join '  |  '
        Write-Host "[Expanding] $Path  -->  $($toExpand.Count) subfolder(s) qualify:" -ForegroundColor Yellow
        Write-Host "            $expandNames" -ForegroundColor Yellow
        Write-Host ""
    }

    foreach ($q in $qualifies) {
        $c = $q.Child
        $marker = if ($q.ShouldExpand) { ' [+]' } else { '' }
        $prefix = if ($Depth -eq 0) { '' } else { $indent + '  |- ' }

        $Script:TreeNodes.Add([PSCustomObject]@{
                Display     = "$prefix$($c.Name)$marker"
                SizeGB      = $c.SizeGB
                PctOfParent = $c.PctOfParent
                Depth       = $Depth
            })

        if ($q.ShouldExpand) {
            Show-FolderTree -Path $c.FullName -Depth ($Depth + 1) -ParentSizeBytes $c.SizeBytes
        }
    }
}

function Read-TargetPath {
    $raw = Read-Host -Prompt 'Folder path to analyze [default: C:\Users]'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return 'C:\Users'
    }
    return $raw.Trim()
}

function Read-PositiveDecimal {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [decimal]$Default
    )

    do {
        $raw = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }
        $value = [decimal]0
        if ([decimal]::TryParse($raw.Trim(), [ref]$value) -and $value -gt 0) {
            return $value
        }
        Write-Host "Invalid number. Enter a positive value or press Enter for default ($Default)." -ForegroundColor Red
    } while ($true)
}

function Read-NonNegativeDecimal {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt,
        [Parameter(Mandatory)]
        [decimal]$Default
    )

    do {
        $raw = Read-Host -Prompt $Prompt
        if ([string]::IsNullOrWhiteSpace($raw)) {
            return $Default
        }
        $value = [decimal]0
        if ([decimal]::TryParse($raw.Trim(), [ref]$value) -and $value -ge 0) {
            return $value
        }
        Write-Host "Invalid number. Enter zero or a positive value, or press Enter for default ($Default)." -ForegroundColor Red
    } while ($true)
}

function Invoke-Main {
    # --- Input collection and validation ---
    $TargetPath = Read-TargetPath
    if (-not (Test-Path -LiteralPath $TargetPath -PathType Container)) {
        Write-Host "[ERROR] Path not found or not a folder: $TargetPath" -ForegroundColor Red
        return 1
    }

    $script:SizeThresholdGB = [double](Read-PositiveDecimal -Prompt 'Minimum child size to consider for expansion, in GB [default: 10]' -Default 10)
    $script:DominanceGap = [double](Read-NonNegativeDecimal -Prompt 'Percentage points above average sibling share required to expand [default: 10]' -Default 10)

    $Script:TreeNodes = [System.Collections.Generic.List[PSCustomObject]]::new()

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  Folder Size Drilldown (TargetFolderSizeDrilldown.ps1)" -ForegroundColor Cyan
    Write-Host "  Target : $TargetPath" -ForegroundColor Cyan
    Write-Host "  Expand if : >$($script:SizeThresholdGB) GB AND >$($script:DominanceGap) pts above sibling avg" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    Write-Progress-Line "[Scanning] $TargetPath (root total)..."
    $rootSizeBytes = Get-FolderSize -Path $TargetPath
    $rootSizeGB = [Math]::Round($rootSizeBytes / 1GB, 2)
    Clear-Progress-Line

    Write-Host "[Root] $TargetPath  -  $rootSizeGB GB total" -ForegroundColor Green
    Write-Host ""

    Show-FolderTree -Path $TargetPath -Depth 0 -ParentSizeBytes $rootSizeBytes

    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host "  FINAL TREE  ([+] = expanded further)" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    $colFolder = 70
    $colSize = 10
    $colPct = 14

    $header = "  {0,-$colFolder} {1,$colSize}  {2,$colPct}" -f 'Folder', 'Size (GB)', '% of Parent'
    $divider = '  ' + ('-' * ($colFolder + $colSize + $colPct + 4))
    Write-Host $header -ForegroundColor White
    Write-Host $divider -ForegroundColor DarkGray

    $rootRow = "  {0,-$colFolder} {1,$colSize}  {2,$colPct}" -f $TargetPath, $rootSizeGB, '-'
    Write-Host $rootRow -ForegroundColor Green

    foreach ($node in $Script:TreeNodes) {
        $color = if ($node.Display -match '\[\+\]') { 'Yellow' } else { 'Gray' }
        $row = "  {0,-$colFolder} {1,$colSize}  {2,$colPct}" -f `
            $node.Display, "$($node.SizeGB) GB", "$($node.PctOfParent)%"
        Write-Host $row -ForegroundColor $color
    }

    Write-Host ""
    Write-Host "  [+] = folder was expanded  |  Thresholds: >$($script:SizeThresholdGB) GB and >$($script:DominanceGap) pts above sibling avg" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[OK] Folder size drilldown completed." -ForegroundColor Green
    return 0
}

try {
    $statusCode = Invoke-Main
    if ($statusCode -ne 0) {
        Write-Error "[ERROR] TargetFolderSizeDrilldown completed with status code $statusCode."
        return
    }
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
