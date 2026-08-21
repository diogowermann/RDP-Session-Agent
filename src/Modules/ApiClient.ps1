function Enable-AgentTls12 {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
    }
    catch {
        throw "TLS 1.2 could not be enabled for this PowerShell process: $($_.Exception.Message)"
    }
}

function Get-AgentHeaders {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Secret
    )

    return @{
        'X-Server-ID' = [string]$Config.server_id
        'Authorization' = 'Bearer ' + $Secret
    }
}

function Send-AgentEnvelope {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Secret,
        [Parameter(Mandatory=$true)]$Envelope
    )

    Enable-AgentTls12
    $baseUrl = ([string]$Config.api_base_url).TrimEnd('/')
    $uri = $baseUrl + '/agent/events'
    $headers = Get-AgentHeaders -Config $Config -Secret $Secret
    $json = $Envelope | ConvertTo-Json -Depth 12
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $json -ErrorAction Stop
}

function Send-AgentSnapshot {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)][string]$Secret,
        [Parameter(Mandatory=$true)]$Snapshot
    )

    Enable-AgentTls12
    $baseUrl = ([string]$Config.api_base_url).TrimEnd('/')
    $uri = $baseUrl + '/agent/snapshot'
    $headers = Get-AgentHeaders -Config $Config -Secret $Secret
    $json = $Snapshot | ConvertTo-Json -Depth 12
    return Invoke-RestMethod -Method Post -Uri $uri -Headers $headers -ContentType 'application/json' -Body $json -ErrorAction Stop
}
