$modulePath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Modules\EventCollector.ps1'
. $modulePath

Describe 'Convert-LsmXmlToAgentEvent' {
    It 'maps a UserData event 21 and splits DOMAIN\user' {
        $xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>21</EventID>
    <TimeCreated SystemTime="2026-08-21T11:00:00.0000000Z" />
    <EventRecordID>1234</EventRecordID>
    <Channel>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</Channel>
  </System>
  <UserData>
    <EventXML xmlns="Event_NS">
      <User>EXAMPLE\alice</User>
      <SessionID>7</SessionID>
      <Address>192.0.2.10</Address>
    </EventXML>
  </UserData>
</Event>
'@
        $event = Convert-LsmXmlToAgentEvent -XmlText $xml -IncludeLocalSessions $false
        $event.type | Should -Be 'LOGON'
        $event.record_id | Should -Be 1234
        $event.session_id | Should -Be 7
        $event.domain | Should -Be 'EXAMPLE'
        $event.username | Should -Be 'alice'
    }

    It 'supports EventData Data-Name payloads' {
        $xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>25</EventID>
    <TimeCreated SystemTime="2026-08-21T11:01:00.0000000Z" />
    <EventRecordID>1235</EventRecordID>
    <Channel>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</Channel>
  </System>
  <EventData>
    <Data Name="User">EXAMPLE\alice</Data>
    <Data Name="SessionID">7</Data>
    <Data Name="Address">192.0.2.10</Data>
  </EventData>
</Event>
'@
        $event = Convert-LsmXmlToAgentEvent -XmlText $xml -IncludeLocalSessions $false
        $event.type | Should -Be 'RECONNECT'
        $event.session_id | Should -Be 7
    }

    It 'ignores LOCAL events by default' {
        $xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>24</EventID>
    <TimeCreated SystemTime="2026-08-21T11:02:00.0000000Z" />
    <EventRecordID>1236</EventRecordID>
    <Channel>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</Channel>
  </System>
  <UserData>
    <EventXML xmlns="Event_NS">
      <User>EXAMPLE\alice</User>
      <SessionID>7</SessionID>
      <Address>LOCAL</Address>
    </EventXML>
  </UserData>
</Event>
'@
        $event = Convert-LsmXmlToAgentEvent -XmlText $xml -IncludeLocalSessions $false
        $event | Should -BeNullOrEmpty
    }

    It 'accepts event 23 without an Address field' {
        $xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>23</EventID>
    <TimeCreated SystemTime="2026-08-21T11:03:00.0000000Z" />
    <EventRecordID>1237</EventRecordID>
    <Channel>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</Channel>
  </System>
  <UserData>
    <EventXML xmlns="Event_NS">
      <User>EXAMPLE\alice</User>
      <SessionID>7</SessionID>
    </EventXML>
  </UserData>
</Event>
'@
        $event = Convert-LsmXmlToAgentEvent -XmlText $xml -IncludeLocalSessions $false
        $event.type | Should -Be 'LOGOFF'
    }
}
