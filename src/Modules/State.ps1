function Get-AgentState {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $statePath = Join-Path $RootPath 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [PSCustomObject]@{
            initialized = $false
            last_record_id = 0
            last_snapshot_at_utc = $null
        }
    }

    $parsed = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
    $lastSnapshot = $null
    if ($null -ne $parsed.PSObject.Properties['last_snapshot_at_utc']) {
        $lastSnapshot = [string]$parsed.last_snapshot_at_utc
    }

    return [PSCustomObject]@{
        initialized = [bool]$parsed.initialized
        last_record_id = [long]$parsed.last_record_id
        last_snapshot_at_utc = $lastSnapshot
    }
}

function Save-AgentState {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][long]$LastRecordId,
        [string]$LastSnapshotAtUtc
    )

    $existing = Get-AgentState -RootPath $RootPath
    $snapshotValue = $existing.last_snapshot_at_utc
    if ($PSBoundParameters.ContainsKey('LastSnapshotAtUtc')) {
        $snapshotValue = $LastSnapshotAtUtc
    }

    $statePath = Join-Path $RootPath 'state.json'
    $state = [ordered]@{
        initialized = $true
        last_record_id = $LastRecordId
        last_snapshot_at_utc = $snapshotValue
        updated_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
}

function Save-AgentSnapshotTime {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$SnapshotAtUtc
    )

    $state = Get-AgentState -RootPath $RootPath
    Save-AgentState -RootPath $RootPath -LastRecordId ([long]$state.last_record_id) -LastSnapshotAtUtc $SnapshotAtUtc
}

function Test-AgentSnapshotDue {
    param(
        [Parameter(Mandatory=$true)]$State,
        [Parameter(Mandatory=$true)][int]$IntervalMinutes
    )

    if ($IntervalMinutes -le 0) {
        $IntervalMinutes = 5
    }
    if ([string]::IsNullOrWhiteSpace([string]$State.last_snapshot_at_utc)) {
        return $true
    }

    try {
        $lastSnapshot = [DateTime]::Parse([string]$State.last_snapshot_at_utc).ToUniversalTime()
        return ([DateTime]::UtcNow -ge $lastSnapshot.AddMinutes($IntervalMinutes))
    }
    catch {
        return $true
    }
}
