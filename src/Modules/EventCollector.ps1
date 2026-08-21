function Get-EventTypeName {
    param([Parameter(Mandatory=$true)][int]$EventId)

    switch ($EventId) {
        21 { return 'LOGON' }
        23 { return 'LOGOFF' }
        24 { return 'DISCONNECT' }
        25 { return 'RECONNECT' }
        default { return $null }
    }
}

function Split-AccountName {
    param([Parameter(Mandatory=$true)][string]$Account)

    $separator = $Account.IndexOf('\')
    if ($separator -gt 0 -and $separator -lt ($Account.Length - 1)) {
        return [PSCustomObject]@{
            domain = $Account.Substring(0, $separator)
            username = $Account.Substring($separator + 1)
        }
    }

    return [PSCustomObject]@{
        domain = $null
        username = $Account
    }
}

function Get-LsmDataMap {
    param([Parameter(Mandatory=$true)][xml]$Xml)

    $data = @{}

    $eventDataNodes = $Xml.SelectNodes("//*[local-name()='EventData']/*[local-name()='Data']")
    foreach ($node in @($eventDataNodes)) {
        $name = [string]$node.GetAttribute('Name')
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $data[$name] = [string]$node.InnerText
        }
    }

    $userDataNodes = $Xml.SelectNodes("//*[local-name()='UserData']/*[local-name()='EventXML']/*")
    foreach ($node in @($userDataNodes)) {
        $name = [string]$node.LocalName
        if (-not [string]::IsNullOrWhiteSpace($name)) {
            $data[$name] = [string]$node.InnerText
        }
    }

    return $data
}

function Convert-LsmXmlToAgentEvent {
    param(
        [Parameter(Mandatory=$true)][string]$XmlText,
        [Parameter(Mandatory=$true)][bool]$IncludeLocalSessions
    )

    [xml]$xml = $XmlText
    $eventIdNode = $xml.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='EventID']")
    $recordIdNode = $xml.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='EventRecordID']")
    $timeNode = $xml.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='TimeCreated']")
    $channelNode = $xml.SelectSingleNode("/*[local-name()='Event']/*[local-name()='System']/*[local-name()='Channel']")

    if ($null -eq $eventIdNode -or $null -eq $recordIdNode -or $null -eq $timeNode -or $null -eq $channelNode) {
        return $null
    }

    $eventId = [int]$eventIdNode.InnerText
    $eventType = Get-EventTypeName -EventId $eventId
    if ($null -eq $eventType) {
        return $null
    }

    $data = Get-LsmDataMap -Xml $xml
    $user = [string]$data['User']
    $sessionIdText = [string]$data['SessionID']
    if ([string]::IsNullOrWhiteSpace($user) -or [string]::IsNullOrWhiteSpace($sessionIdText)) {
        return $null
    }

    $address = [string]$data['Address']
    if (-not $IncludeLocalSessions -and $address -eq 'LOCAL') {
        return $null
    }

    $sessionId = 0
    if (-not [int]::TryParse($sessionIdText, [ref]$sessionId)) {
        return $null
    }

    $account = Split-AccountName -Account $user
    $systemTime = [string]$timeNode.GetAttribute('SystemTime')
    if ([string]::IsNullOrWhiteSpace($systemTime)) {
        return $null
    }

    return [PSCustomObject][ordered]@{
        event_id = $eventId
        record_id = [long]$recordIdNode.InnerText
        type = $eventType
        session_id = $sessionId
        username = $account.username
        domain = $account.domain
        occurred_at = [DateTime]::Parse($systemTime).ToUniversalTime().ToString('o')
        channel = [string]$channelNode.InnerText
    }
}

function Get-LatestRelevantRecordId {
    param([Parameter(Mandatory=$true)][string]$LogName)

    $latest = Get-WinEvent -FilterHashtable @{ LogName=$LogName; Id=@(21,23,24,25) } -MaxEvents 1 -ErrorAction Stop
    if ($null -eq $latest) {
        return 0
    }
    return [long]$latest.RecordId
}

function Get-RdpSessionEvents {
    param(
        [Parameter(Mandatory=$true)]$Config,
        [Parameter(Mandatory=$true)]$State
    )

    $logName = [string]$Config.event_log_name
    $maximum = [int]$Config.max_events_per_batch
    if ($maximum -le 0) { $maximum = 200 }
    $includeLocal = [bool]$Config.include_local_sessions

    if (-not [bool]$State.initialized) {
        $lookback = [int]$Config.initial_lookback_minutes
        if ($lookback -le 0) { $lookback = 60 }
        $records = @(Get-WinEvent -FilterHashtable @{
            LogName=$logName
            Id=@(21,23,24,25)
            StartTime=(Get-Date).AddMinutes(-1 * $lookback)
        } -MaxEvents $maximum -Oldest -ErrorAction Stop)
    }
    else {
        $lastRecordId = [long]$State.last_record_id
        $xpath = '*[System[(EventID=21 or EventID=23 or EventID=24 or EventID=25) and EventRecordID>' + $lastRecordId + ']]'
        $records = @(Get-WinEvent -LogName $logName -FilterXPath $xpath -MaxEvents $maximum -Oldest -ErrorAction Stop)
    }

    $events = @()
    $lastScannedRecordId = if ([bool]$State.initialized) { [long]$State.last_record_id } else { 0 }
    foreach ($record in ($records | Sort-Object RecordId)) {
        if ([long]$record.RecordId -gt $lastScannedRecordId) {
            $lastScannedRecordId = [long]$record.RecordId
        }
        $converted = Convert-LsmXmlToAgentEvent -XmlText $record.ToXml() -IncludeLocalSessions $includeLocal
        if ($null -ne $converted) {
            $events += $converted
        }
    }

    return [PSCustomObject]@{
        events = @($events)
        last_scanned_record_id = $lastScannedRecordId
        scanned_count = $records.Count
    }
}
