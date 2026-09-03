param(
    [string]$InstallRoot = 'C:\ProgramData\RdpSessionAgent',
    [string]$TaskName = 'RDP Session Agent',
    [string]$OutputPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $stamp = [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssZ')
    $OutputPath = Join-Path $env:TEMP ('rdp-session-agent-phase0-' + $stamp + '.json')
}

function Get-FileTextOrNull {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    return (Get-Content -LiteralPath $Path -Raw).Trim()
}

function Get-DirectorySummary {
    param([string]$Path, [string]$Filter = '*')
    if (-not (Test-Path -LiteralPath $Path)) {
        return [ordered]@{ exists = $false; count = 0; total_bytes = 0; oldest_utc = $null; newest_utc = $null }
    }

    $files = @(Get-ChildItem -LiteralPath $Path -Filter $Filter -File -ErrorAction Stop | Sort-Object LastWriteTimeUtc)
    $total = 0L
    foreach ($file in $files) { $total += [long]$file.Length }

    return [ordered]@{
        exists = $true
        count = $files.Count
        total_bytes = $total
        oldest_utc = if ($files.Count -gt 0) { $files[0].LastWriteTimeUtc.ToString('o') } else { $null }
        newest_utc = if ($files.Count -gt 0) { $files[$files.Count - 1].LastWriteTimeUtc.ToString('o') } else { $null }
    }
}

function Get-ScheduledTaskSummary {
    param([string]$Name)

    $getTask = Get-Command -Name Get-ScheduledTask -ErrorAction SilentlyContinue
    if ($null -ne $getTask) {
        $task = Get-ScheduledTask -TaskName $Name -ErrorAction SilentlyContinue
        if ($null -eq $task) { return $null }

        $runtime = Get-ScheduledTaskInfo -TaskName $Name -ErrorAction Stop
        return [ordered]@{
            provider = 'ScheduledTasks'
            state = [string]$task.State
            last_run_time = if ($runtime.LastRunTime) { $runtime.LastRunTime.ToUniversalTime().ToString('o') } else { $null }
            last_task_result = $runtime.LastTaskResult
            next_run_time = if ($runtime.NextRunTime) { $runtime.NextRunTime.ToUniversalTime().ToString('o') } else { $null }
            principal_user_id = [string]$task.Principal.UserId
            run_level = [string]$task.Principal.RunLevel
        }
    }

    # Windows Server 2008 R2 does not provide the ScheduledTasks PowerShell module.
    # Use the Task Scheduler 2.0 COM API instead; this is available on 2008 R2 and later.
    try {
        $service = New-Object -ComObject 'Schedule.Service'
        $service.Connect()
        $folder = $service.GetFolder('\')
        $task = $folder.GetTask($Name)
        if ($null -eq $task) { return $null }

        $stateMap = @{
            0 = 'Unknown'
            1 = 'Disabled'
            2 = 'Queued'
            3 = 'Ready'
            4 = 'Running'
        }
        $state = if ($stateMap.ContainsKey([int]$task.State)) { $stateMap[[int]$task.State] } else { [string]$task.State }
        $definition = $task.Definition

        return [ordered]@{
            provider = 'TaskSchedulerCOM'
            state = $state
            last_run_time = if ($task.LastRunTime -and $task.LastRunTime.Year -gt 1900) { $task.LastRunTime.ToUniversalTime().ToString('o') } else { $null }
            last_task_result = $task.LastTaskResult
            next_run_time = if ($task.NextRunTime -and $task.NextRunTime.Year -gt 1900) { $task.NextRunTime.ToUniversalTime().ToString('o') } else { $null }
            principal_user_id = if ($null -ne $definition -and $null -ne $definition.Principal) { [string]$definition.Principal.UserId } else { $null }
            run_level = if ($null -ne $definition -and $null -ne $definition.Principal) { [string]$definition.Principal.RunLevel } else { $null }
        }
    }
    catch {
        return [ordered]@{
            provider = 'TaskSchedulerCOM'
            error = $_.Exception.Message
        }
    }
}

$configPath = Join-Path $InstallRoot 'config.json'
$statePath = Join-Path $InstallRoot 'state.json'
$versionPath = Join-Path $InstallRoot 'VERSION'
$credentialPath = Join-Path $InstallRoot 'credential.dat'

$config = $null
if (Test-Path -LiteralPath $configPath) {
    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
}

$state = $null
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
}

$taskInfo = Get-ScheduledTaskSummary -Name $TaskName
$os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop

$evidence = [ordered]@{
    schema_version = 1
    captured_at = [DateTime]::UtcNow.ToString('o')
    warning = 'Internal operational evidence. Do not commit this JSON to the public repository.'
    host = [ordered]@{
        computer_name = [string]$env:COMPUTERNAME
        os_caption = [string]$os.Caption
        os_version = [string]$os.Version
        os_build = [string]$os.BuildNumber
        last_boot_utc = [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime).ToUniversalTime().ToString('o')
        powershell_version = $PSVersionTable.PSVersion.ToString()
    }
    agent = [ordered]@{
        install_root = $InstallRoot
        version = Get-FileTextOrNull -Path $versionPath
        config_present = Test-Path -LiteralPath $configPath
        credential_present = Test-Path -LiteralPath $credentialPath
        state_present = Test-Path -LiteralPath $statePath
        server_id = if ($null -ne $config) { [string]$config.server_id } else { $null }
        api_base_url = if ($null -ne $config) { [string]$config.api_base_url } else { $null }
        snapshot_interval_minutes = if ($null -ne $config) { $config.snapshot_interval_minutes } else { $null }
        state = $state
        spool = Get-DirectorySummary -Path (Join-Path $InstallRoot 'spool') -Filter '*.json'
        logs = Get-DirectorySummary -Path (Join-Path $InstallRoot 'logs') -Filter '*.log'
    }
    scheduled_task = $taskInfo
}

$parent = Split-Path -Parent $OutputPath
if (-not [string]::IsNullOrWhiteSpace($parent) -and -not (Test-Path -LiteralPath $parent)) {
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
}

$evidence | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
Write-Host ('Phase 0 baseline written to: {0}' -f $OutputPath)
Write-Host 'This file contains internal identifiers and configuration. Do not commit it to Git.'
