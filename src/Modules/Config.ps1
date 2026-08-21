function Get-AgentConfig {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $configPath = Join-Path $RootPath 'config.json'
    if (-not (Test-Path -LiteralPath $configPath)) {
        throw "Agent configuration not found: $configPath"
    }

    $config = Get-Content -LiteralPath $configPath -Raw | ConvertFrom-Json
    if ([string]::IsNullOrWhiteSpace([string]$config.api_base_url)) {
        throw 'api_base_url is required in config.json'
    }
    if ([string]::IsNullOrWhiteSpace([string]$config.server_id)) {
        throw 'server_id is required in config.json'
    }

    return $config
}

function Get-AgentVersion {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $versionPath = Join-Path $RootPath 'VERSION'
    if (-not (Test-Path -LiteralPath $versionPath)) {
        throw "VERSION file not found: $versionPath"
    }
    return (Get-Content -LiteralPath $versionPath -Raw).Trim()
}
