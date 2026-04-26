<#
.SYNOPSIS
    Exports all Entra ID / Microsoft 365 groups and direct members to a UTF-8 CSV under C:\Temp.
.DESCRIPTION
    Requires Microsoft.Graph PowerShell SDK (see m365/README.md and docs/EXCEPTIONS_POLICY.md M365-GRAPH-MGSDK-001).
    Prompts for CSV path (must be under C:\Temp), optional comma-separated Graph scopes, then Connect-MgGraph (browser
    sign-in). Enumerates groups with Get-MgGroup, then Get-MgGroupMember per group (direct membership only). Creates
    C:\Temp if missing. Operator input is prompt-only (no script parameters).
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

function Assert-MicrosoftGraphModuleAvailable {
    if (-not (Get-Module -ListAvailable -Name Microsoft.Graph)) {
        throw 'Microsoft.Graph is not installed. Run: Install-Module Microsoft.Graph -Scope CurrentUser (see m365/README.md).'
    }

    Import-Module Microsoft.Graph -ErrorAction Stop | Out-Null
}

function Ensure-TempDirectory {
    $tempPath = 'C:\Temp'
    if (-not (Test-Path -LiteralPath $tempPath)) {
        New-Item -ItemType Directory -Path $tempPath -Force | Out-Null
    }
}

function Resolve-OutputCsvPath {
    param(
        [Parameter(Mandatory)]
        [string]$DefaultFileName
    )

    $defaultFull = Join-Path -Path 'C:\Temp' -ChildPath $DefaultFileName
    $entered = Read-Host -Prompt "CSV output path [default: $defaultFull]"
    if ([string]::IsNullOrWhiteSpace($entered)) {
        return $defaultFull
    }

    $full = [System.IO.Path]::GetFullPath($entered.Trim())
    $normalizedRoot = [System.IO.Path]::GetFullPath('C:\Temp').TrimEnd('\') + '\'
    if (-not ($full.StartsWith($normalizedRoot, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "Output path must be under C:\Temp (repository file I/O rule). Got: $full"
    }

    return $full
}

function Read-GraphScopes {
    $defaultScopes = @('Group.Read.All', 'Directory.Read.All', 'User.Read.All')
    $defaultText = $defaultScopes -join ', '
    Write-Host "Default Graph scopes: $defaultText"
    $raw = Read-Host -Prompt 'Scopes (comma-separated) [Enter for defaults]'
    if ([string]::IsNullOrWhiteSpace($raw)) {
        return $defaultScopes
    }

    $parsed = @(
        $raw.Split(',') |
            ForEach-Object { $_.Trim() } |
            Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    )

    if ($parsed.Count -eq 0) {
        return $defaultScopes
    }

    return $parsed
}

function Get-GroupTypeString {
    param(
        [Parameter(Mandatory)]
        [object]$Group
    )

    $groupTypes = @($Group.GroupTypes)
    $isUnified = ($groupTypes -contains 'Unified')
    $mailEnabled = [bool]$Group.MailEnabled
    $secEnabled = [bool]$Group.SecurityEnabled

    if ($isUnified) {
        return 'Microsoft 365 Group'
    }
    if ($mailEnabled -and $secEnabled) {
        return 'Mail-enabled Security'
    }
    if ($mailEnabled -and -not $secEnabled) {
        return 'Distribution List'
    }
    if ($secEnabled -and -not $mailEnabled) {
        return 'Security Group'
    }
    return 'Other'
}

function Get-MemberRowProperties {
    param(
        [Parameter(Mandatory)]
        [object]$Group,
        [Parameter(Mandatory)]
        [string]$GroupType,
        [Parameter(Mandatory)]
        [object]$Member
    )

    $props = $Member.AdditionalProperties
    if ($null -eq $props) {
        $props = @{}
    }

    $typeHint = [string]$props['@odata.type']
    $upn = $null
    $mail = $null
    $memberType = $null

    switch -Regex ($typeHint) {
        '^#?microsoft\.graph\.user$' {
            $memberType = 'User'
            $upn = [string]$props['userPrincipalName']
            $mail = [string]$props['mail']
        }
        '^#?microsoft\.graph\.group$' {
            $memberType = 'Group'
            $mail = [string]$props['mail']
        }
        '^#?microsoft\.graph\.device$' {
            $memberType = 'Device'
        }
        '^#?microsoft\.graph\.servicePrincipal$' {
            $memberType = 'ServicePrincipal'
            $mail = [string]$props['appId']
        }
        '^#?microsoft\.graph\.orgContact$' {
            $memberType = 'Contact'
            $mail = [string]$props['mail']
        }
        default {
            $memberType = ($typeHint -replace '^#', '')
            $mail = [string]$props['mail']
        }
    }

    return [pscustomobject]@{
        GroupId = $Group.Id
        GroupDisplayName = $Group.DisplayName
        GroupMail = $Group.Mail
        GroupType = $GroupType
        MemberId = $Member.Id
        MemberDisplayName = [string]$props['displayName']
        MemberUserPrincipalName = $upn
        MemberMail = $mail
        MemberType = $memberType
    }
}

function Invoke-Main {
    Assert-MicrosoftGraphModuleAvailable
    Ensure-TempDirectory

    Write-Host 'This script exports all groups and direct members to CSV using Microsoft Graph. Sign-in uses a browser.'
    if (-not (Test-ReadHostYes -Prompt 'Continue? (Y/N)')) {
        Write-Host 'Aborted by operator.'
        return
    }

    $outputPath = Resolve-OutputCsvPath -DefaultFileName 'M365-Groups-And-Members.csv'
    $scopes = Read-GraphScopes

    Write-Host 'Signing in to Microsoft Graph...' -ForegroundColor Cyan
    Connect-MgGraph -Scopes $scopes | Out-Null

    try {
        try {
            Select-MgProfile -Name 'v1.0' -ErrorAction Stop
        }
        catch {
            Write-Warning "Select-MgProfile v1.0 skipped: $($_.Exception.Message)"
        }

        Write-Host 'Retrieving groups...' -ForegroundColor Cyan
        $allGroups = @(Get-MgGroup -All -Property 'id,displayName,groupTypes,securityEnabled,mailEnabled,mail')
        $total = $allGroups.Count

        if ($total -eq 0) {
            Write-Warning 'No groups found.'
            '' | Set-Content -Path $outputPath -Encoding UTF8
            Write-Host "Wrote empty file: $outputPath" -ForegroundColor Yellow
            return
        }

        $rows = New-Object 'System.Collections.Generic.List[Object]'
        $index = 0

        foreach ($g in $allGroups) {
            $index++
            $groupType = Get-GroupTypeString -Group $g
            Write-Progress -Activity 'Processing groups' -Status $g.DisplayName -PercentComplete (($index / $total) * 100)

            $members = @()
            try {
                $members = @(Get-MgGroupMember -GroupId $g.Id -All -Property 'id,displayName,userPrincipalName,mail')
            }
            catch {
                Write-Warning "Could not retrieve members for group '$($g.DisplayName)': $($_.Exception.Message)"
                $members = @()
            }

            if ($members.Count -eq 0) {
                $rows.Add([pscustomobject]@{
                    GroupId = $g.Id
                    GroupDisplayName = $g.DisplayName
                    GroupMail = $g.Mail
                    GroupType = $groupType
                    MemberId = $null
                    MemberDisplayName = $null
                    MemberUserPrincipalName = $null
                    MemberMail = $null
                    MemberType = $null
                })
                continue
            }

            foreach ($m in $members) {
                $rows.Add((Get-MemberRowProperties -Group $g -GroupType $groupType -Member $m))
            }
        }

        Write-Progress -Activity 'Processing groups' -Completed

        Write-Host "Writing $($rows.Count) rows to $outputPath ..." -ForegroundColor Cyan
        $rows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $outputPath

        Write-Host "Done. CSV saved to: $outputPath" -ForegroundColor Green
    }
    finally {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
    }
}

try {
    Invoke-Main
}
catch {
    Write-Error "[ERROR] $($_.Exception.Message)"
    throw
}
