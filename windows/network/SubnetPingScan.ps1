<#
.SYNOPSIS
    Pings each address in a /24 IPv4 range and lists responding hosts with optional reverse DNS names.
.DESCRIPTION
    Prompts for the first three octets (e.g. 192.168.1), then optionally exports results to CSV under C:\Temp. Uses
    Test-Connection (ICMP) and System.Net.Dns for hostnames. Read-only from a data perspective, but it is still
    active network probing, so use it only on networks you are authorized to scan. No script parameters; Windows
    PowerShell only.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Test-ReadHostYes {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    $response = Read-Host -Prompt $Prompt
    if ([string]::IsNullOrWhiteSpace($response)) {
        return $false
    }
    return ($response.Trim() -match '^(?i:y|yes)$')
}

function Test-Ipv4ThreeOctetPrefix {
    param(
        [Parameter(Mandatory)]
        [string]$Prefix
    )

    $parts = $Prefix.Trim().Split('.')
    if ($parts.Count -ne 3) {
        return $false
    }

    foreach ($part in $parts) {
        if ($part -notmatch '^\d{1,3}$') {
            return $false
        }
        $n = [int]$part
        if ($n -lt 0 -or $n -gt 255) {
            return $false
        }
    }

    return $true
}

function Read-SubnetPrefix {
    $default = '192.168.1'
    $entered = Read-Host -Prompt "First three IPv4 octets for /24 scan (e.g. 192.168.1) [default: $default]"
    if ([string]::IsNullOrWhiteSpace($entered)) {
        return $default
    }

    $prefix = $entered.Trim()
    if (-not (Test-Ipv4ThreeOctetPrefix -Prefix $prefix)) {
        throw 'Invalid prefix. Enter three dotted decimal octets (0-255 each), e.g. 10.0.0'
    }

    return $prefix
}

function Invoke-Main {
    $subnet = Read-SubnetPrefix

    Write-Host "This will send one ICMP echo per host for $subnet.1 through $subnet.254."
    if (-not (Test-ReadHostYes -Prompt 'Continue with ping sweep? (Y/N)')) {
        Write-Host 'Aborted by operator.'
        return
    }

    $results = New-Object 'System.Collections.Generic.List[Object]'

    Write-Host "Scanning network $subnet.0/24..." -ForegroundColor Cyan
    Write-Host "This may take a few minutes.`n" -ForegroundColor Yellow

    foreach ($last in 1..254) {
        $ip = "$subnet.$last"

        if (Test-Connection -ComputerName $ip -Count 1 -Quiet -ErrorAction SilentlyContinue) {
            $hostname = 'Unable to resolve'
            try {
                $hostname = [System.Net.Dns]::GetHostEntry($ip).HostName
            }
            catch {
                $hostname = 'Unable to resolve'
            }

            $results.Add([pscustomobject]@{
                IPAddress = $ip
                Status = 'Active'
                Hostname = $hostname
            })

            Write-Host "Found: $ip - $hostname" -ForegroundColor Green
        }

        if (($last % 25) -eq 0) {
            Write-Host "Scanned $last addresses..." -ForegroundColor Yellow
        }
    }

    Write-Host ''
    Write-Host '=== Scan Complete ===' -ForegroundColor Cyan
    Write-Host "Total active hosts found: $($results.Count)`n" -ForegroundColor Yellow

    $sorted = $results | Sort-Object { [int]($_.IPAddress.Split('.') | Select-Object -Last 1) }
    $sorted | Format-Table -AutoSize

    if ($results.Count -eq 0) {
        return
    }

    if (-not (Test-ReadHostYes -Prompt 'Export results to CSV under C:\Temp? (Y/N)')) {
        return
    }

    $tempPath = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $tempPath)) {
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    }

    $defaultFile = Join-Path $tempPath ("NetworkScan_{0}.csv" -f (Get-Date -Format 'yyyyMMdd_HHmmss'))
    $pathEntered = Read-Host -Prompt "CSV path [default: $defaultFile]"
    if ([string]::IsNullOrWhiteSpace($pathEntered)) {
        $csvPath = $defaultFile
    }
    else {
        $csvPath = [System.IO.Path]::GetFullPath($pathEntered.Trim())
        $normalizedRoot = [System.IO.Path]::GetFullPath($tempPath).TrimEnd('\') + '\'
        if (-not ($csvPath.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
            throw "CSV path must be under C:\Temp. Got: $csvPath"
        }
    }

    $sorted | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Exported: $csvPath" -ForegroundColor Green
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
