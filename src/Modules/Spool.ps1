function Get-SpoolDirectory {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $path = Join-Path $RootPath 'spool'
    if (-not (Test-Path -LiteralPath $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
    return $path
}

function Save-SpoolBatch {
    param(
        [Parameter(Mandatory=$true)][string]$RootPath,
        [Parameter(Mandatory=$true)]$Envelope,
        [Parameter(Mandatory=$true)][long]$CheckpointRecordId
    )

    $spoolDirectory = Get-SpoolDirectory -RootPath $RootPath
    $name = '{0}-{1}.json' -f [DateTime]::UtcNow.ToString('yyyyMMddTHHmmssfff'), ([Guid]::NewGuid().ToString('N'))
    $path = Join-Path $spoolDirectory $name
    $wrapper = [ordered]@{
        checkpoint_record_id = $CheckpointRecordId
        envelope = $Envelope
    }
    $wrapper | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $path -Encoding UTF8
    return $path
}

function Get-SpoolBatches {
    param([Parameter(Mandatory=$true)][string]$RootPath)

    $spoolDirectory = Get-SpoolDirectory -RootPath $RootPath
    return @(Get-ChildItem -LiteralPath $spoolDirectory -Filter '*.json' -File | Sort-Object Name)
}

function Read-SpoolBatch {
    param([Parameter(Mandatory=$true)][string]$Path)
    return (Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json)
}
