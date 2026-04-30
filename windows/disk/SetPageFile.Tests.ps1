<#
.SYNOPSIS
    Pester v5 tests for SetPageFile.ps1.
.DESCRIPTION
    Exercises the helper functions and Invoke-Main from SetPageFile.ps1 in
    isolation. All side-effecting calls (Read-Host, Get-CimInstance,
    Set-CimInstance, Set-ItemProperty) are mocked, so:

      * No real registry keys are read or written.
      * No real CIM instances are queried or modified.
      * The tests do NOT require administrator/elevated rights.

    The production script SetPageFile.ps1 itself, when executed normally,
    writes to HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\
    Memory Management which DOES require administrator rights — but the
    tests in this file never reach that code path against the real system.
#>

#Requires -Version 5.1
#Requires -Modules @{ ModuleName = 'Pester'; ModuleVersion = '5.0.0' }

BeforeAll {
    $script:ScriptPath = Join-Path $PSScriptRoot 'SetPageFile.ps1'
    if (-not (Test-Path -LiteralPath $script:ScriptPath)) {
        throw "SetPageFile.ps1 not found next to test file at: $script:ScriptPath"
    }

    # The production script ends with a top-level try { Invoke-Main } catch
    # block that auto-executes on dot-source. To load the function
    # definitions WITHOUT running Invoke-Main (which would call Read-Host,
    # Get-CimInstance, Set-CimInstance, Set-ItemProperty against the real
    # system), we strip that trailing try/catch block before dot-sourcing.
    $rawContent = Get-Content -LiteralPath $script:ScriptPath -Raw

    # Find the start of the top-level "try {" that wraps Invoke-Main. It is
    # the only top-level try block in the file and lives after the function
    # definitions, so a regex anchored at start-of-line is sufficient.
    $tryMatch = [regex]::Match(
        $rawContent,
        '(?ms)^\s*try\s*\{\s*\r?\n\s*\$statusCode\s*=\s*Invoke-Main.*$'
    )
    if (-not $tryMatch.Success) {
        throw "Could not locate the top-level 'try { Invoke-Main } catch' block in SetPageFile.ps1; test harness needs updating."
    }

    $strippedContent = $rawContent.Substring(0, $tryMatch.Index)

    # Dot-source the trimmed script body so Read-InputWithDefault,
    # Read-PositiveIntWithDefault, and Invoke-Main are defined in this
    # scope, but the trailing try/catch never runs.
    . ([scriptblock]::Create($strippedContent))

    # On non-Windows hosts (e.g. PowerShell Core on Linux used purely to
    # run these tests in CI), the CIM cmdlets are not present. Pester's
    # Mock requires the target command to exist before it can be stubbed,
    # so we define no-op shim functions only when the real cmdlets are
    # missing. On Windows these shims are skipped and the real cmdlets
    # are mocked directly — neither path ever talks to a real CIM session.
    if (-not (Get-Command -Name Get-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Get-CimInstance {
            [CmdletBinding()]
            param([Parameter(Position = 0)][string]$ClassName)
            throw 'Get-CimInstance shim should always be mocked in tests.'
        }
    }
    if (-not (Get-Command -Name Set-CimInstance -ErrorAction SilentlyContinue)) {
        function global:Set-CimInstance {
            [CmdletBinding()]
            param(
                [Parameter(ValueFromPipeline = $true)] $InputObject,
                [hashtable]$Property
            )
            throw 'Set-CimInstance shim should always be mocked in tests.'
        }
    }
    if (-not (Get-Command -Name Set-ItemProperty -ErrorAction SilentlyContinue)) {
        function global:Set-ItemProperty {
            [CmdletBinding()]
            param(
                [string]$Path,
                [string]$Name,
                $Value
            )
            throw 'Set-ItemProperty shim should always be mocked in tests.'
        }
    }
}

Describe 'Read-InputWithDefault' {
    It 'returns the default when the user presses Enter (empty input)' {
        Mock Read-Host { return '' }

        $result = Read-InputWithDefault -Prompt 'Pagefile path' -Default 'C:\pagefile.sys'

        $result | Should -Be 'C:\pagefile.sys'
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'returns the default when the user enters only whitespace' {
        Mock Read-Host { return '   ' }

        $result = Read-InputWithDefault -Prompt 'Pagefile path' -Default 'C:\pagefile.sys'

        $result | Should -Be 'C:\pagefile.sys'
    }

    It 'returns trimmed user input when provided' {
        Mock Read-Host { return '  D:\pagefile.sys  ' }

        $result = Read-InputWithDefault -Prompt 'Pagefile path' -Default 'C:\pagefile.sys'

        $result | Should -Be 'D:\pagefile.sys'
    }
}

Describe 'Read-PositiveIntWithDefault' {
    It 'returns the default on empty input' {
        Mock Read-Host { return '' }

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 4096
        $result | Should -BeOfType ([int])
        Should -Invoke Read-Host -Times 1 -Exactly
    }

    It 'returns the parsed value for a valid positive integer' {
        Mock Read-Host { return '2048' }

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 2048
        $result | Should -BeOfType ([int])
    }

    It 'trims whitespace around a valid integer' {
        Mock Read-Host { return '  1024  ' }

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 1024
    }

    It 'loops on non-numeric input and returns a valid value on the next attempt' {
        $script:responses = @('not-a-number', '512')
        $script:idx = 0
        Mock Read-Host {
            $value = $script:responses[$script:idx]
            $script:idx++
            return $value
        }
        Mock Write-Host {}

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 512
        Should -Invoke Read-Host -Times 2 -Exactly
        Should -Invoke Write-Host -ParameterFilter { $Object -match 'Invalid value' } -Times 1
    }

    It 'rejects zero and re-prompts until a positive integer is supplied' {
        $script:responses = @('0', '256')
        $script:idx = 0
        Mock Read-Host {
            $value = $script:responses[$script:idx]
            $script:idx++
            return $value
        }
        Mock Write-Host {}

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 256
        Should -Invoke Read-Host -Times 2 -Exactly
    }

    It 'rejects negative numbers and re-prompts until a positive integer is supplied' {
        $script:responses = @('-100', '128')
        $script:idx = 0
        Mock Read-Host {
            $value = $script:responses[$script:idx]
            $script:idx++
            return $value
        }
        Mock Write-Host {}

        $result = Read-PositiveIntWithDefault -Prompt 'Initial size (MB)' -Default 4096

        $result | Should -Be 128
        Should -Invoke Read-Host -Times 2 -Exactly
    }
}

Describe 'Invoke-Main' {
    BeforeEach {
        # Default Read-Host sequence drives Invoke-Main's three prompts in
        # order: pagefile path, initial size (MB), maximum size (MB). Each
        # individual test overrides this when it needs different inputs.
        $script:readHostResponses = @('D:\pagefile.sys', '4096', '8192')
        $script:readHostIdx = 0
        Mock Read-Host {
            $value = $script:readHostResponses[$script:readHostIdx]
            $script:readHostIdx++
            return $value
        }

        Mock Write-Host {}
        Mock Write-Error {}

        # Default CIM stub: AutomaticManagedPagefile is enabled. Tests that
        # need the alternate branch override this mock.
        Mock Get-CimInstance {
            [pscustomobject]@{ AutomaticManagedPagefile = $true }
        }
        Mock Set-CimInstance {}
        Mock Set-ItemProperty {}
    }

    It 'returns 1 (without touching CIM or registry) when maximumSizeMb < initialSizeMb' {
        $script:readHostResponses = @('C:\pagefile.sys', '8192', '4096')
        $script:readHostIdx = 0

        $result = Invoke-Main

        $result | Should -Be 1
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke Set-CimInstance -Times 0 -Exactly
        Should -Invoke Set-ItemProperty -Times 0 -Exactly
    }

    It 'calls Set-CimInstance to disable AutomaticManagedPagefile when it is currently true' {
        Mock Get-CimInstance {
            [pscustomobject]@{ AutomaticManagedPagefile = $true }
        }

        $result = Invoke-Main

        $result | Should -Be 0
        Should -Invoke Get-CimInstance -Times 1 -Exactly
        Should -Invoke Set-CimInstance -Times 1 -Exactly -ParameterFilter {
            $Property.AutomaticManagedPagefile -eq $false
        }
    }

    It 'skips Set-CimInstance when AutomaticManagedPagefile is already false' {
        Mock Get-CimInstance {
            [pscustomobject]@{ AutomaticManagedPagefile = $false }
        }

        $result = Invoke-Main

        $result | Should -Be 0
        Should -Invoke Get-CimInstance -Times 1 -Exactly
        Should -Invoke Set-CimInstance -Times 0 -Exactly
    }

    It 'calls Set-ItemProperty with the correct registry path, name, and formatted value string' {
        $script:readHostResponses = @('D:\pagefile.sys', '4096', '8192')
        $script:readHostIdx = 0

        $result = Invoke-Main

        $result | Should -Be 0
        Should -Invoke Set-ItemProperty -Times 1 -Exactly -ParameterFilter {
            $Path  -eq 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Memory Management' -and
            $Name  -eq 'PagingFiles' -and
            $Value -eq 'D:\pagefile.sys 4096 8192'
        }
    }

    It 'returns 0 on success' {
        $result = Invoke-Main

        $result | Should -Be 0
        Should -Invoke Set-ItemProperty -Times 1 -Exactly
    }
}
