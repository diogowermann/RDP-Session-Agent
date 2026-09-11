param(
    [string]$InstallRoot = 'C:\ProgramData\RdpSessionAgent',
    [string]$TaskName = 'RDP Session Agent',
    [switch]$SkipScheduledTaskControl
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSVersion.Major -lt 3) {
    throw 'PowerShell 3.0 or newer is required.'
}

$repositoryRoot = Split-Path -Parent $PSScriptRoot
$sourcePath = Join-Path $repositoryRoot 'src'
$versionPath = Join-Path $repositoryRoot 'VERSION'
$installedSource = Join-Path $InstallRoot 'src'
$installedVersionPath = Join-Path $InstallRoot 'VERSION'
$configPath = Join-Path $InstallRoot 'config.json'
$credentialPath = Join-Path $InstallRoot 'credential.dat'
$rollbackRoot = Join-Path $InstallRoot 'rollback'

foreach ($requiredPath in @($sourcePath, $versionPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Required repository path not found: $requiredPath"
    }
}

foreach ($requiredPath in @($InstallRoot, $installedSource, $installedVersionPath, $configPath, $credentialPath)) {
    if (-not (Test-Path -LiteralPath $requiredPath)) {
        throw "Existing Agent installation is incomplete; required path not found: $requiredPath"
    }
}

$targetVersion = (Get-Content -LiteralPath $versionPath -Raw).Trim()
$installedVersion = (Get-Content -LiteralPath $installedVersionPath -Raw).Trim()

if ([string]::IsNullOrWhiteSpace($targetVersion)) {
    throw 'Repository VERSION is empty.'
}

if ([string]::IsNullOrWhiteSpace($installedVersion)) {
    throw 'Installed VERSION is empty.'
}

if ($targetVersion -eq $installedVersion) {
    Write-Host "RDP Session Agent is already at version $targetVersion. No files changed."
    return
}

$agentEntryPoint = Join-Path $sourcePath 'Agent.ps1'
if (-not (Test-Path -LiteralPath $agentEntryPoint)) {
    throw "Repository runtime is invalid; Agent.ps1 was not found at $agentEntryPoint"
}

$stagingRoot = Join-Path $InstallRoot ('.update-staging-' + [Guid]::NewGuid().ToString('N'))
$stagingSource = Join-Path $stagingRoot 'src'
$backupPath = $null
$task = $null
$taskWasEnabled = $false
$taskDisabledByUpdater = $false
$runtimeReplacementStarted = $false
$updateSucceeded = $false

try {
    New-Item -ItemType Directory -Path $stagingRoot -Force | Out-Null
    Copy-Item -LiteralPath $sourcePath -Destination $stagingSource -Recurse -Force
    Copy-Item -LiteralPath $versionPath -Destination (Join-Path $stagingRoot 'VERSION') -Force

    if (-not (Test-Path -LiteralPath (Join-Path $stagingSource 'Agent.ps1'))) {
        throw 'Staged runtime validation failed: Agent.ps1 is missing.'
    }

    New-Item -ItemType Directory -Path $rollbackRoot -Force | Out-Null
    $safeInstalledVersion = $installedVersion -replace '[^0-9A-Za-z._-]', '_'
    $backupName = '{0}-v{1}-{2}' -f (Get-Date -Format 'yyyyMMdd-HHmmss'), $safeInstalledVersion, ([Guid]::NewGuid().ToString('N').Substring(0, 8))
    $backupPath = Join-Path $rollbackRoot $backupName
    New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    Copy-Item -LiteralPath $installedSource -Destination (Join-Path $backupPath 'src') -Recurse -Force
    Copy-Item -LiteralPath $installedVersionPath -Destination (Join-Path $backupPath 'VERSION') -Force

    $metadata = [ordered]@{
        created_at_utc = [DateTime]::UtcNow.ToString('o')
        installed_version = $installedVersion
        target_version = $targetVersion
        runtime_only = $true
        preserved_paths = @('config.json', 'credential.dat', 'state.json', 'spool', 'logs')
    }
    $metadata | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath (Join-Path $backupPath 'update-metadata.json') -Encoding UTF8

    if (-not $SkipScheduledTaskControl) {
        try {
            $scheduler = New-Object -ComObject 'Schedule.Service'
            $scheduler.Connect()
            $taskFolder = $scheduler.GetFolder('\')
            $task = $taskFolder.GetTask($TaskName)
        }
        catch {
            throw "Scheduled Task '$TaskName' could not be opened. No runtime files were replaced. $($_.Exception.Message)"
        }

        $taskWasEnabled = [bool]$task.Enabled
        if ($taskWasEnabled) {
            $task.Enabled = $false
            $taskDisabledByUpdater = $true
        }

        & schtasks.exe /End /TN $TaskName 2>$null | Out-Null
    }

    $runtimeReplacementStarted = $true
    Remove-Item -LiteralPath $installedSource -Recurse -Force
    Move-Item -LiteralPath $stagingSource -Destination $installedSource
    Copy-Item -LiteralPath (Join-Path $stagingRoot 'VERSION') -Destination $installedVersionPath -Force

    foreach ($preservedPath in @($configPath, $credentialPath)) {
        if (-not (Test-Path -LiteralPath $preservedPath)) {
            throw "Preserved installation path disappeared during update: $preservedPath"
        }
    }

    $installedVersionAfter = (Get-Content -LiteralPath $installedVersionPath -Raw).Trim()
    if ($installedVersionAfter -ne $targetVersion) {
        throw "Installed VERSION validation failed. Expected '$targetVersion', got '$installedVersionAfter'."
    }

    $updateSucceeded = $true
    Write-Host "RDP Session Agent updated from $installedVersion to $targetVersion."
    Write-Host "Runtime rollback backup: $backupPath"
    Write-Host 'Preserved: config.json, credential.dat, state.json, spool and logs.'
}
catch {
    $updateError = $_

    if ($runtimeReplacementStarted -and $backupPath -and (Test-Path -LiteralPath (Join-Path $backupPath 'src'))) {
        try {
            if (Test-Path -LiteralPath $installedSource) {
                Remove-Item -LiteralPath $installedSource -Recurse -Force
            }
            Copy-Item -LiteralPath (Join-Path $backupPath 'src') -Destination $installedSource -Recurse -Force
            Copy-Item -LiteralPath (Join-Path $backupPath 'VERSION') -Destination $installedVersionPath -Force
            Write-Warning "Update failed; previous runtime version $installedVersion was restored automatically."
        }
        catch {
            Write-Warning "Automatic runtime restore also failed. Backup remains at: $backupPath"
        }
    }

    throw $updateError
}
finally {
    if ($taskDisabledByUpdater -and $taskWasEnabled -and $task) {
        try {
            $task.Enabled = $true
        }
        catch {
            Write-Warning "The updater could not re-enable Scheduled Task '$TaskName'. Re-enable it manually before leaving the server."
        }
    }

    if (Test-Path -LiteralPath $stagingRoot) {
        Remove-Item -LiteralPath $stagingRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}

if ($updateSucceeded) {
    Write-Host "Validation: schtasks.exe /Run /TN `"$TaskName`""
    Write-Host "Then inspect $InstallRoot\logs and confirm API last_seen advances with no growing spool backlog."
}
