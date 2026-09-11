$repositoryRoot = Split-Path -Parent $PSScriptRoot
$updateScript = Join-Path $repositoryRoot 'scripts\Update-Agent.ps1'
$targetVersion = (Get-Content (Join-Path $repositoryRoot 'VERSION') -Raw).Trim()

Describe 'Update-Agent.ps1' {
    BeforeEach {
        $script:installRoot = Join-Path $TestDrive 'RdpSessionAgent'
        New-Item -ItemType Directory -Path $script:installRoot -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:installRoot 'src') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:installRoot 'spool') -Force | Out-Null
        New-Item -ItemType Directory -Path (Join-Path $script:installRoot 'logs') -Force | Out-Null

        Set-Content -LiteralPath (Join-Path $script:installRoot 'VERSION') -Value '0.3.0' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $script:installRoot 'config.json') -Value '{"server_id":"preserve-me"}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:installRoot 'credential.dat') -Value 'protected-secret-bytes-placeholder' -Encoding ASCII
        Set-Content -LiteralPath (Join-Path $script:installRoot 'state.json') -Value '{"checkpoint":123}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:installRoot 'spool\pending.json') -Value '{"event":"pending"}' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:installRoot 'logs\agent.log') -Value 'existing log' -Encoding UTF8
        Set-Content -LiteralPath (Join-Path $script:installRoot 'src\old-runtime.txt') -Value 'old runtime' -Encoding UTF8
    }

    It 'updates only runtime files and preserves operational state and credential material' {
        $configBefore = Get-Content -LiteralPath (Join-Path $script:installRoot 'config.json') -Raw
        $credentialBefore = Get-Content -LiteralPath (Join-Path $script:installRoot 'credential.dat') -Raw
        $stateBefore = Get-Content -LiteralPath (Join-Path $script:installRoot 'state.json') -Raw
        $spoolBefore = Get-Content -LiteralPath (Join-Path $script:installRoot 'spool\pending.json') -Raw
        $logBefore = Get-Content -LiteralPath (Join-Path $script:installRoot 'logs\agent.log') -Raw

        & $updateScript -InstallRoot $script:installRoot -SkipScheduledTaskControl

        (Get-Content -LiteralPath (Join-Path $script:installRoot 'VERSION') -Raw).Trim() | Should -Be $targetVersion
        Test-Path -LiteralPath (Join-Path $script:installRoot 'src\Agent.ps1') | Should -Be $true
        Test-Path -LiteralPath (Join-Path $script:installRoot 'src\old-runtime.txt') | Should -Be $false

        (Get-Content -LiteralPath (Join-Path $script:installRoot 'config.json') -Raw) | Should -Be $configBefore
        (Get-Content -LiteralPath (Join-Path $script:installRoot 'credential.dat') -Raw) | Should -Be $credentialBefore
        (Get-Content -LiteralPath (Join-Path $script:installRoot 'state.json') -Raw) | Should -Be $stateBefore
        (Get-Content -LiteralPath (Join-Path $script:installRoot 'spool\pending.json') -Raw) | Should -Be $spoolBefore
        (Get-Content -LiteralPath (Join-Path $script:installRoot 'logs\agent.log') -Raw) | Should -Be $logBefore

        $backups = @(Get-ChildItem -LiteralPath (Join-Path $script:installRoot 'rollback') -Directory)
        $backups.Count | Should -Be 1
        Test-Path -LiteralPath (Join-Path $backups[0].FullName 'src\old-runtime.txt') | Should -Be $true
        (Get-Content -LiteralPath (Join-Path $backups[0].FullName 'VERSION') -Raw).Trim() | Should -Be '0.3.0'
        Test-Path -LiteralPath (Join-Path $backups[0].FullName 'update-metadata.json') | Should -Be $true
    }

    It 'does nothing when the installed version already matches the repository version' {
        Set-Content -LiteralPath (Join-Path $script:installRoot 'VERSION') -Value $targetVersion -Encoding ASCII

        & $updateScript -InstallRoot $script:installRoot -SkipScheduledTaskControl

        Test-Path -LiteralPath (Join-Path $script:installRoot 'rollback') | Should -Be $false
        Test-Path -LiteralPath (Join-Path $script:installRoot 'src\old-runtime.txt') | Should -Be $true
    }
}
