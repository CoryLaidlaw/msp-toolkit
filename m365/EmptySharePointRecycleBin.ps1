<#
.SYNOPSIS
    Clears first- and second-stage SharePoint recycle bins for every site returned by Get-PnPTenantSite.
.DESCRIPTION
    Requires PnP.PowerShell (see m365/README.md and docs/EXCEPTIONS_POLICY.md, M365-SPO-PNP-001). Prompts for
    SharePoint admin URL inputs, Entra tenant, Azure app Client Id, and a final confirmation before destructive work.
    Uses Connect-PnPOnline -Interactive (browser sign-in). Connects per site and runs Clear-PnPRecycleBinItem for all
    items in stage 1 and stage 2. Technician workstation; not LocalSystem-friendly.
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

function Read-RequiredNonEmpty {
    param(
        [Parameter(Mandatory)]
        [string]$Prompt
    )

    do {
        $value = Read-Host -Prompt $Prompt
    } while ([string]::IsNullOrWhiteSpace($value))

    return $value.Trim()
}

function Test-IsGuid {
    param(
        [Parameter(Mandatory)]
        [string]$Text
    )

    $g = [guid]::Empty
    return [guid]::TryParse($Text.Trim(), [ref]$g)
}

function Test-SharePointTenantKey {
    param(
        [Parameter(Mandatory)]
        [string]$Key
    )

    if ($Key.Length -lt 1 -or $Key.Length -gt 63) {
        return $false
    }
    return ($Key -match '^[A-Za-z0-9-]+$')
}

function Assert-PnPModuleAvailable {
    if (-not (Get-Module -ListAvailable -Name PnP.PowerShell)) {
        throw 'PnP.PowerShell is not installed. Run: Install-Module PnP.PowerShell -Scope CurrentUser (see m365/README.md).'
    }

    Import-Module PnP.PowerShell -ErrorAction Stop | Out-Null
}

function Invoke-Main {
    Assert-PnPModuleAvailable

    Write-Host 'SharePoint tenant recycle bin cleanup requires PnP.PowerShell and an Entra app registration with appropriate SharePoint admin permissions.'
    $tenantKey = Read-RequiredNonEmpty -Prompt 'SharePoint hostname prefix (e.g. contoso for https://contoso-admin.sharepoint.com)'

    if (-not (Test-SharePointTenantKey -Key $tenantKey)) {
        throw 'Invalid tenant key. Use letters, digits, and hyphens only; length 1-63.'
    }

    $defaultEntra = "$tenantKey.onmicrosoft.com"
    Write-Host "Default Entra tenant string: $defaultEntra"
    $entraTenant = Read-Host -Prompt "Entra tenant (GUID or domain) [Enter for $defaultEntra]"
    if ([string]::IsNullOrWhiteSpace($entraTenant)) {
        $entraTenant = $defaultEntra
    }
    else {
        $entraTenant = $entraTenant.Trim()
    }

    $clientId = Read-RequiredNonEmpty -Prompt 'Azure application (client) ID for PnP sign-in (GUID)'
    if (-not (Test-IsGuid -Text $clientId)) {
        throw 'Client ID must be a valid GUID.'
    }

    $adminUrl = "https://$tenantKey-admin.sharepoint.com"

    Write-Host "Connecting to SharePoint admin: $adminUrl" -ForegroundColor Cyan
    Write-Host 'Complete sign-in in the browser when prompted.' -ForegroundColor Yellow

    $adminConnection = $null
    try {
        $adminConnection = Connect-PnPOnline -Url $adminUrl -Interactive -ClientId $clientId -Tenant $entraTenant -ReturnConnection
    }
    catch {
        throw "Could not connect to SharePoint admin: $($_.Exception.Message)"
    }

    if ($null -eq $adminConnection) {
        throw 'Connect-PnPOnline did not return a connection object.'
    }

    Write-Host 'Retrieving all SharePoint sites...' -ForegroundColor Cyan
    $sites = @(Get-PnPTenantSite -Connection $adminConnection)
    $siteCount = $sites.Count

    Write-Host "Found $siteCount site(s)." -ForegroundColor Cyan
    Write-Host 'This permanently deletes items in first- and second-stage recycle bins for each site.' -ForegroundColor Yellow

    if (-not (Test-ReadHostYes -Prompt "Continue and clear recycle bins for all $siteCount site(s)? (Y/N)")) {
        Write-Host 'Aborted by operator.'
        Disconnect-PnPOnline -Connection $adminConnection -ErrorAction SilentlyContinue
        return
    }

    $successCount = 0
    $failCount = 0
    $index = 0

    foreach ($site in $sites) {
        $index++
        $siteConnection = $null
        try {
            Write-Host "[$index/$siteCount] Processing: $($site.Url)" -ForegroundColor Yellow

            $siteConnection = Connect-PnPOnline -Url $site.Url -Interactive -ClientId $clientId -Tenant $entraTenant -ReturnConnection

            Clear-PnPRecycleBinItem -All -Force -Connection $siteConnection -ErrorAction Stop
            Clear-PnPRecycleBinItem -All -SecondStageOnly -Force -Connection $siteConnection -ErrorAction Stop

            $successCount++
            Write-Host '  [OK] Completed' -ForegroundColor Green
        }
        catch {
            $failCount++
            Write-Host "  [FAIL] $($_.Exception.Message)" -ForegroundColor Red
        }
        finally {
            if ($null -ne $siteConnection) {
                Disconnect-PnPOnline -Connection $siteConnection -ErrorAction SilentlyContinue
            }
        }

        Write-Host ''
    }

    Disconnect-PnPOnline -Connection $adminConnection -ErrorAction SilentlyContinue

    Write-Host '================================================' -ForegroundColor Cyan
    Write-Host 'Summary:' -ForegroundColor Cyan
    Write-Host "  Total sites: $siteCount" -ForegroundColor White
    Write-Host "  Successful: $successCount" -ForegroundColor Green
    Write-Host "  Failed: $failCount" -ForegroundColor Red
    Write-Host '================================================' -ForegroundColor Cyan
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
