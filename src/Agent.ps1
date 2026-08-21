param(
    [string]$RootPath
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($RootPath)) {
    $RootPath = Split-Path -Parent $PSScriptRoot
}

. (Join-Path $PSScriptRoot 'Modules\Logging.ps1')
. (Join-Path $PSScriptRoot 'Modules\Config.ps1')
. (Join-Path $PSScriptRoot 'Modules\Credential.ps1')
. (Join-Path $PSScriptRoot 'Modules\State.ps1')
. (Join-Path $PSScriptRoot 'Modules\Spool.ps1')
. (Join-Path $PSScriptRoot 'Modules\ApiClient.ps1')
. (Join-Path $PSScriptRoot 'Modules\EventCollector.ps1')
. (Join-Path $PSScriptRoot 'Modules\WtsSessionCollector.ps1')

function Get-BootTimeUtc {
    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
    return [System.Management.ManagementDateTimeConverter]::ToDateTime($os.LastBootUpTime).ToUniversalTime().ToString('o')
}

function Send-PendingSpool {
    param($Config, [string]$Secret, [string]$AgentRoot)

    foreach ($file in (Get-SpoolBatches -RootPath $AgentRoot)) {
        $batch = Read-SpoolBatch -Path $file.FullName
        Write-AgentLog -RootPath $AgentRoot -Level 'INFO' -Message ('Sending spool batch {0}' -f $file.Name)
        $response = Send-AgentEnvelope -Config $Config -Secret $Secret -Envelope $batch.envelope
        Save-AgentState -RootPath $AgentRoot -LastRecordId ([long]$batch.checkpoint_record_id)
        Remove-Item -LiteralPath $file.FullName -Force
        Write-AgentLog -RootPath $AgentRoot -Level 'INFO' -Message ('API accepted={0} duplicates={1}' -f $response.accepted, $response.duplicates)
    }
}

function Invoke-WtsReconciliationIfDue {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Secret,
        [Parameter(Mandatory=$true)][string]$Version,
        [Parameter(Mandatory=$true)][string]$AgentRoot
    )

    $state = Get-AgentState -RootPath $AgentRoot
    $interval = 5
    if ($null -ne $Config.PSObject.Properties['snapshot_interval_minutes']) {
        $interval = [int]$Config.snapshot_interval_minutes
    }
    if (-not (Test-AgentSnapshotDue -State $state -IntervalMinutes $interval)) {
        return
    }

    $sessions = @(Get-WtsRdpSessions)
    $metadata = Get-AgentHostMetadata
    $snapshotAt = [DateTime]::UtcNow.ToString('o')
    $snapshot = [ordered]@{
        contract_version = 1
        agent_version = $Version
        boot_time_utc = Get-BootTimeUtc
        agent_time_utc = $snapshotAt
        hostname = $metadata.hostname
        fqdn = $metadata.fqdn
        os_version = $metadata.os_version
        sessions = $sessions
    }

    $response = Send-AgentSnapshot -Config $Config -Secret $Secret -Snapshot $snapshot
    Save-AgentSnapshotTime -RootPath $AgentRoot -SnapshotAtUtc $snapshotAt
    Write-AgentLog -RootPath $AgentRoot -Level 'INFO' -Message ('WTS snapshot observed={0} created={1} updated={2} closed={3}' -f $response.observed, $response.created, $response.updated, $response.closed)
}

try {
    $config = Get-AgentConfig -RootPath $RootPath
    $secret = Get-AgentSecret -RootPath $RootPath
    $version = Get-AgentVersion -RootPath $RootPath

    Send-PendingSpool -Config $config -Secret $secret -AgentRoot $RootPath

    $state = Get-AgentState -RootPath $RootPath
    $collection = Get-RdpSessionEvents -Config $config -State $state
    $events = @($collection.events)

    if ($events.Count -eq 0) {
        if ([long]$collection.last_scanned_record_id -gt [long]$state.last_record_id) {
            Save-AgentState -RootPath $RootPath -LastRecordId ([long]$collection.last_scanned_record_id)
            Write-AgentLog -RootPath $RootPath -Level 'INFO' -Message ('Scanned {0} event record(s); no remote RDP lifecycle events to send. Checkpoint={1}' -f $collection.scanned_count, $collection.last_scanned_record_id)
        }
        elseif (-not [bool]$state.initialized) {
            $baseline = Get-LatestRelevantRecordId -LogName ([string]$config.event_log_name)
            Save-AgentState -RootPath $RootPath -LastRecordId $baseline
            Write-AgentLog -RootPath $RootPath -Level 'INFO' -Message ('No recent RDP events. Baseline checkpoint={0}' -f $baseline)
        }
        else {
            Write-AgentLog -RootPath $RootPath -Level 'INFO' -Message 'No new RDP session events.'
        }
    }
    else {
        $checkpoint = [long]$collection.last_scanned_record_id
        $envelope = [ordered]@{
            contract_version = 1
            agent_version = $version
            boot_time_utc = Get-BootTimeUtc
            agent_time_utc = [DateTime]::UtcNow.ToString('o')
            events = $events
        }

        $spoolPath = Save-SpoolBatch -RootPath $RootPath -Envelope $envelope -CheckpointRecordId $checkpoint
        Write-AgentLog -RootPath $RootPath -Level 'INFO' -Message ('Collected {0} event(s); spool={1}' -f $events.Count, (Split-Path -Leaf $spoolPath))
        Send-PendingSpool -Config $config -Secret $secret -AgentRoot $RootPath
    }

    Invoke-WtsReconciliationIfDue -Config $config -Secret $secret -Version $version -AgentRoot $RootPath
    exit 0
}
catch {
    try {
        Write-AgentLog -RootPath $RootPath -Level 'ERROR' -Message $_.Exception.Message
    }
    catch {
        Write-Error $_.Exception.Message
    }
    exit 1
}
