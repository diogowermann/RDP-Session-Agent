param(
    [string]$ApiBaseUrl
)

Set-StrictMode -Version 2.0
$ErrorActionPreference = 'Stop'

$results = @()
$results += [PSCustomObject]@{ Check='PowerShell'; Ok=($PSVersionTable.PSVersion.Major -ge 3); Detail=$PSVersionTable.PSVersion.ToString() }

$logName = 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational'
try {
    $null = Get-WinEvent -ListLog $logName -ErrorAction Stop
    $results += [PSCustomObject]@{ Check='EventLog'; Ok=$true; Detail=$logName }
}
catch {
    $results += [PSCustomObject]@{ Check='EventLog'; Ok=$false; Detail=$_.Exception.Message }
}

$wtsApiPath = Join-Path $env:SystemRoot 'System32\wtsapi32.dll'
$results += [PSCustomObject]@{ Check='WTS API'; Ok=(Test-Path -LiteralPath $wtsApiPath); Detail=$wtsApiPath }

if (-not [string]::IsNullOrWhiteSpace($ApiBaseUrl)) {
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $health = Invoke-RestMethod -Method Get -Uri ($ApiBaseUrl.TrimEnd('/') + '/health') -ErrorAction Stop
        $ok = ($health.status -eq 'ok' -and $health.contract -eq 'v1')
        $results += [PSCustomObject]@{ Check='API health'; Ok=$ok; Detail=($health | ConvertTo-Json -Compress) }
    }
    catch {
        $results += [PSCustomObject]@{ Check='API health'; Ok=$false; Detail=$_.Exception.Message }
    }
}

$results | Format-Table -AutoSize
if (@($results | Where-Object { -not $_.Ok }).Count -gt 0) {
    exit 1
}
exit 0
