Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$updateScript = Join-Path $repositoryRoot 'scripts\Update-Agent.ps1'
$targetVersion = (Get-Content -LiteralPath (Join-Path $repositoryRoot 'VERSION') -Raw).Trim()

function Assert-True {
    param(
        [Parameter(Mandatory=$true)][bool]$Condition,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if (-not $Condition) {
        throw "ASSERT FAILED: $Message"
    }
}

function Assert-Equal {
    param(
        [Parameter(Mandatory=$true)]$Expected,
        [Parameter(Mandatory=$true)]$Actual,
        [Parameter(Mandatory=$true)][string]$Message
    )

    if ($Expected -ne $Actual) {
        throw "ASSERT FAILED: $Message. Expected=[$Expected] Actual=[$Actual]"
    }
}

function New-TestInstallation {
    param(
        [Parameter(Mandatory=$true)][string]$Root,
        [Parameter(Mandatory=$true)][string]$Version
    )

    New-Item -ItemType Directory -Path $Root -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'src') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'spool') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $Root 'logs') -Force | Out-Null

    Set-Content -LiteralPath (Join-Path $Root 'VERSION') -Value $Version -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'config.json') -Value '{"server_id":"preserve-me"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Root 'credential.dat') -Value 'protected-secret-bytes-placeholder' -Encoding ASCII
    Set-Content -LiteralPath (Join-Path $Root 'state.json') -Value '{"checkpoint":123}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Root 'spool\pending.json') -Value '{"event":"pending"}' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Root 'logs\agent.log') -Value 'existing log' -Encoding UTF8
    Set-Content -LiteralPath (Join-Path $Root 'src\old-runtime.txt') -Value 'old runtime' -Encoding UTF8
}

$testRoot = Join-Path ([System.IO.Path]::GetTempPath()) ('RdpSessionAgent-SelfTest-' + [Guid]::NewGuid().ToString('N'))

try {
    Write-Host '[1/2] Testing runtime update with preserved operational state...'
    $installRoot = Join-Path $testRoot 'update-case'
    New-TestInstallation -Root $installRoot -Version '0.3.0'

    $configBefore = Get-Content -LiteralPath (Join-Path $installRoot 'config.json') -Raw
    $credentialBefore = Get-Content -LiteralPath (Join-Path $installRoot 'credential.dat') -Raw
    $stateBefore = Get-Content -LiteralPath (Join-Path $installRoot 'state.json') -Raw
    $spoolBefore = Get-Content -LiteralPath (Join-Path $installRoot 'spool\pending.json') -Raw
    $logBefore = Get-Content -LiteralPath (Join-Path $installRoot 'logs\agent.log') -Raw

    & $updateScript -InstallRoot $installRoot -SkipScheduledTaskControl

    Assert-Equal -Expected $targetVersion -Actual ((Get-Content -LiteralPath (Join-Path $installRoot 'VERSION') -Raw).Trim()) -Message 'VERSION must be updated'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $installRoot 'src\Agent.ps1')) -Message 'new runtime Agent.ps1 must exist'
    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $installRoot 'src\old-runtime.txt'))) -Message 'old runtime marker must be replaced'

    Assert-Equal -Expected $configBefore -Actual (Get-Content -LiteralPath (Join-Path $installRoot 'config.json') -Raw) -Message 'config.json must be preserved byte-for-text'
    Assert-Equal -Expected $credentialBefore -Actual (Get-Content -LiteralPath (Join-Path $installRoot 'credential.dat') -Raw) -Message 'credential.dat must be preserved'
    Assert-Equal -Expected $stateBefore -Actual (Get-Content -LiteralPath (Join-Path $installRoot 'state.json') -Raw) -Message 'state.json must be preserved'
    Assert-Equal -Expected $spoolBefore -Actual (Get-Content -LiteralPath (Join-Path $installRoot 'spool\pending.json') -Raw) -Message 'spool must be preserved'
    Assert-Equal -Expected $logBefore -Actual (Get-Content -LiteralPath (Join-Path $installRoot 'logs\agent.log') -Raw) -Message 'logs must be preserved'

    $backupRoot = Join-Path $installRoot 'rollback'
    $backups = @()
    if (Test-Path -LiteralPath $backupRoot) {
        $backups = @(Get-ChildItem -LiteralPath $backupRoot | Where-Object { $_.PSIsContainer })
    }

    Assert-Equal -Expected 1 -Actual $backups.Count -Message 'exactly one rollback backup must be created'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'src\old-runtime.txt')) -Message 'rollback backup must contain old runtime'
    Assert-Equal -Expected '0.3.0' -Actual ((Get-Content -LiteralPath (Join-Path $backups[0].FullName 'VERSION') -Raw).Trim()) -Message 'rollback VERSION must contain prior version'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $backups[0].FullName 'update-metadata.json')) -Message 'rollback metadata must exist'

    Write-Host '[PASS] Runtime update preserves credential, configuration, state, spool and logs.'

    Write-Host '[2/2] Testing no-op when versions already match...'
    $noopRoot = Join-Path $testRoot 'noop-case'
    New-TestInstallation -Root $noopRoot -Version $targetVersion

    & $updateScript -InstallRoot $noopRoot -SkipScheduledTaskControl

    Assert-True -Condition (-not (Test-Path -LiteralPath (Join-Path $noopRoot 'rollback'))) -Message 'no rollback directory should be created for a no-op'
    Assert-True -Condition (Test-Path -LiteralPath (Join-Path $noopRoot 'src\old-runtime.txt')) -Message 'runtime must remain untouched for a no-op'

    Write-Host '[PASS] Matching-version execution is a no-op.'
    Write-Host 'SELF-TEST PASSED: Update-Agent.ps1 requires no external PowerShell modules for this validation.'
    exit 0
}
catch {
    Write-Error $_
    Write-Host 'SELF-TEST FAILED.'
    exit 1
}
finally {
    if (Test-Path -LiteralPath $testRoot) {
        Remove-Item -LiteralPath $testRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
