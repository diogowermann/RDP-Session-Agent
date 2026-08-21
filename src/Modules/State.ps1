function Get-AgentState {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $statePath = Join-Path $RootPath 'state.json'
    if (-not (Test-Path -LiteralPath $statePath)) {
        return [PSCustomObject]@{
            initialized = $false
            last_record_id = 0
        }
    }

    return (Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json)
}

function Save-AgentState {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][long]$LastRecordId
    )

    $statePath = Join-Path $RootPath 'state.json'
    $state = [ordered]@{
        initialized = $true
        last_record_id = $LastRecordId
        updated_at_utc = [DateTime]::UtcNow.ToString('o')
    }
    $state | ConvertTo-Json -Depth 4 | Set-Content -LiteralPath $statePath -Encoding UTF8
}
