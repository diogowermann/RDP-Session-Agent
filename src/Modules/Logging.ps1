function Write-AgentLog {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)][string]$Level,
        [Parameter(Mandatory=$true)][string]$Message
    )

    $logDirectory = Join-Path $RootPath 'logs'
    if (-not (Test-Path -LiteralPath $logDirectory)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $timestamp = [DateTime]::UtcNow.ToString('yyyy-MM-dd HH:mm:ss')
    $line = '[{0}] [{1}] {2}' -f $timestamp, $Level.ToUpperInvariant(), $Message
    $logFile = Join-Path $logDirectory ('agent-{0}.log' -f [DateTime]::UtcNow.ToString('yyyyMMdd'))
    Add-Content -LiteralPath $logFile -Value $line -Encoding UTF8
    Write-Host $line
}
