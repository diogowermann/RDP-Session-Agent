$eventCollectorPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Modules\EventCollector.ps1'
$wtsCollectorPath = Join-Path (Split-Path -Parent $PSScriptRoot) 'src\Modules\WtsSessionCollector.ps1'
. $eventCollectorPath
. $wtsCollectorPath

Describe 'RDP client origin capture' {
    It 'captures IPv4 from LOGON Event Log Address' {
        $xml = @'
<Event xmlns="http://schemas.microsoft.com/win/2004/08/events/event">
  <System>
    <EventID>21</EventID>
    <TimeCreated SystemTime="2026-09-04T12:00:00.0000000Z" />
    <EventRecordID>4001</EventRecordID>
    <Channel>Microsoft-Windows-TerminalServices-LocalSessionManager/Operational</Channel>
  </System>
  <UserData><EventXML xmlns="Event_NS">
    <User>EXAMPLE\alice</User><SessionID>7</SessionID><Address>192.0.2.10</Address>
  </EventXML></UserData>
</Event>
'@
        $event = Convert-LsmXmlToAgentEvent -XmlText $xml -IncludeLocalSessions $false
        $event.source_ip | Should -Be '192.0.2.10'
    }

    It 'normalizes IPv6 and tolerates invalid or loopback values' {
        (ConvertTo-RdpSourceIp '2001:0db8:0:0::1') | Should -Be '2001:db8::1'
        (ConvertTo-RdpSourceIp '127.0.0.1') | Should -BeNullOrEmpty
        (ConvertTo-RdpSourceIp '::1') | Should -BeNullOrEmpty
        (ConvertTo-RdpSourceIp '192.168.1') | Should -BeNullOrEmpty
        (ConvertTo-RdpSourceIp 'not-an-ip') | Should -BeNullOrEmpty
    }

    It 'decodes WTS IPv4 with the documented two-byte offset' {
        $address = New-Object byte[] 20
        $address[2] = 192; $address[3] = 0; $address[4] = 2; $address[5] = 44
        $result = Convert-WtsClientAddressBytesToIp -AddressFamily ([int][System.Net.Sockets.AddressFamily]::InterNetwork) -Address $address
        $result | Should -Be '192.0.2.44'
    }

    It 'decodes WTS IPv6 raw bytes' {
        $address = New-Object byte[] 20
        $ipv6 = [System.Net.IPAddress]::Parse('2001:db8::44').GetAddressBytes()
        [Array]::Copy($ipv6, 0, $address, 0, 16)
        $result = Convert-WtsClientAddressBytesToIp -AddressFamily ([int][System.Net.Sockets.AddressFamily]::InterNetworkV6) -Address $address
        $result | Should -Be '2001:db8::44'
    }

    It 'returns null for WTS loopback, unspecified and unsupported families' {
        $v4 = New-Object byte[] 20
        $v4[2] = 127; $v4[3] = 0; $v4[4] = 0; $v4[5] = 1
        (Convert-WtsClientAddressBytesToIp -AddressFamily 2 -Address $v4) | Should -BeNullOrEmpty

        $empty = New-Object byte[] 20
        (Convert-WtsClientAddressBytesToIp -AddressFamily 2 -Address $empty) | Should -BeNullOrEmpty
        (Convert-WtsClientAddressBytesToIp -AddressFamily 0 -Address $empty) | Should -BeNullOrEmpty
    }
}
