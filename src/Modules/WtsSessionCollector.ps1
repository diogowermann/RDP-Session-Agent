function Initialize-WtsNativeTypes {
    if ('RdpSessionAgent.WtsNativeMethods' -as [type]) {
        return
    }

    $source = @'
using System;
using System.Runtime.InteropServices;

namespace RdpSessionAgent
{
    public enum WTS_CONNECTSTATE_CLASS
    {
        WTSActive = 0,
        WTSConnected = 1,
        WTSConnectQuery = 2,
        WTSShadow = 3,
        WTSDisconnected = 4,
        WTSIdle = 5,
        WTSListen = 6,
        WTSReset = 7,
        WTSDown = 8,
        WTSInit = 9
    }

    public enum WTS_INFO_CLASS
    {
        WTSInitialProgram = 0,
        WTSApplicationName = 1,
        WTSWorkingDirectory = 2,
        WTSOEMId = 3,
        WTSSessionId = 4,
        WTSUserName = 5,
        WTSWinStationName = 6,
        WTSDomainName = 7,
        WTSConnectState = 8,
        WTSClientAddress = 14
    }

    [StructLayout(LayoutKind.Sequential)]
    public struct WTS_SESSION_INFO
    {
        public Int32 SessionID;
        public IntPtr pWinStationName;
        public WTS_CONNECTSTATE_CLASS State;
    }

    public static class WtsNativeMethods
    {
        [DllImport("wtsapi32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool WTSEnumerateSessions(
            IntPtr hServer,
            Int32 Reserved,
            Int32 Version,
            out IntPtr ppSessionInfo,
            out Int32 pCount);

        [DllImport("wtsapi32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        public static extern bool WTSQuerySessionInformation(
            IntPtr hServer,
            Int32 sessionId,
            WTS_INFO_CLASS wtsInfoClass,
            out IntPtr ppBuffer,
            out Int32 pBytesReturned);

        [DllImport("wtsapi32.dll")]
        public static extern void WTSFreeMemory(IntPtr pMemory);

        public static int WtsSessionInfoSize
        {
            get { return Marshal.SizeOf(typeof(WTS_SESSION_INFO)); }
        }

        public static WTS_SESSION_INFO PtrToSessionInfo(IntPtr pointer)
        {
            return (WTS_SESSION_INFO)Marshal.PtrToStructure(pointer, typeof(WTS_SESSION_INFO));
        }
    }
}
'@

    Add-Type -TypeDefinition $source -ErrorAction Stop
}

function Get-WtsSessionString {
    param(
        [Parameter(Mandatory=$true)][int]$SessionId,
        [Parameter(Mandatory=$true)]$InfoClass
    )

    $buffer = [IntPtr]::Zero
    $bytes = 0
    try {
        $ok = [RdpSessionAgent.WtsNativeMethods]::WTSQuerySessionInformation(
            [IntPtr]::Zero,
            $SessionId,
            $InfoClass,
            [ref]$buffer,
            [ref]$bytes
        )
        if (-not $ok -or $buffer -eq [IntPtr]::Zero) {
            return ''
        }
        return [Runtime.InteropServices.Marshal]::PtrToStringUni($buffer)
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [RdpSessionAgent.WtsNativeMethods]::WTSFreeMemory($buffer)
        }
    }
}

function Convert-WtsClientAddressBytesToIp {
    param(
        [Parameter(Mandatory=$true)][int]$AddressFamily,
        [Parameter(Mandatory=$true)][byte[]]$Address
    )

    $ip = $null
    if ($AddressFamily -eq [int][System.Net.Sockets.AddressFamily]::InterNetwork) {
        if ($Address.Length -lt 6) {
            return $null
        }
        $text = '{0}.{1}.{2}.{3}' -f $Address[2], $Address[3], $Address[4], $Address[5]
        if (-not [System.Net.IPAddress]::TryParse($text, [ref]$ip)) {
            return $null
        }
    }
    elseif ($AddressFamily -eq [int][System.Net.Sockets.AddressFamily]::InterNetworkV6) {
        if ($Address.Length -lt 16) {
            return $null
        }
        $ipv6Bytes = New-Object byte[] 16
        [Array]::Copy($Address, 0, $ipv6Bytes, 0, 16)
        $ip = New-Object System.Net.IPAddress -ArgumentList (,$ipv6Bytes)
    }
    else {
        return $null
    }

    if ($null -eq $ip -or [System.Net.IPAddress]::IsLoopback($ip)) {
        return $null
    }
    if ($ip.Equals([System.Net.IPAddress]::Any) -or $ip.Equals([System.Net.IPAddress]::IPv6Any)) {
        return $null
    }
    return $ip.ToString()
}

function Get-WtsClientAddress {
    param([Parameter(Mandatory=$true)][int]$SessionId)

    $buffer = [IntPtr]::Zero
    $bytes = 0
    try {
        $ok = [RdpSessionAgent.WtsNativeMethods]::WTSQuerySessionInformation(
            [IntPtr]::Zero,
            $SessionId,
            [RdpSessionAgent.WTS_INFO_CLASS]::WTSClientAddress,
            [ref]$buffer,
            [ref]$bytes
        )
        if (-not $ok -or $buffer -eq [IntPtr]::Zero -or $bytes -lt 24) {
            return $null
        }

        $addressFamily = [Runtime.InteropServices.Marshal]::ReadInt32($buffer, 0)
        $addressBytes = New-Object byte[] 20
        [Runtime.InteropServices.Marshal]::Copy([IntPtr]::Add($buffer, 4), $addressBytes, 0, 20)
        return Convert-WtsClientAddressBytesToIp -AddressFamily $addressFamily -Address $addressBytes
    }
    catch {
        return $null
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [RdpSessionAgent.WtsNativeMethods]::WTSFreeMemory($buffer)
        }
    }
}

function Get-WtsRdpSessions {
    Initialize-WtsNativeTypes

    $buffer = [IntPtr]::Zero
    $count = 0
    $sessions = @()

    try {
        $ok = [RdpSessionAgent.WtsNativeMethods]::WTSEnumerateSessions(
            [IntPtr]::Zero,
            0,
            1,
            [ref]$buffer,
            [ref]$count
        )
        if (-not $ok) {
            $errorCode = [Runtime.InteropServices.Marshal]::GetLastWin32Error()
            throw (New-Object ComponentModel.Win32Exception($errorCode))
        }

        $infoSize = [RdpSessionAgent.WtsNativeMethods]::WtsSessionInfoSize

        for ($index = 0; $index -lt $count; $index++) {
            $current = [IntPtr]::Add($buffer, ($index * $infoSize))
            $info = [RdpSessionAgent.WtsNativeMethods]::PtrToSessionInfo($current)

            $state = $null
            if ([int]$info.State -eq 0) {
                $state = 'ACTIVE'
            }
            elseif ([int]$info.State -eq 4) {
                $state = 'DISCONNECTED'
            }
            else {
                continue
            }

            $station = Get-WtsSessionString -SessionId $info.SessionID -InfoClass ([RdpSessionAgent.WTS_INFO_CLASS]::WTSWinStationName)
            if ([string]::IsNullOrWhiteSpace($station) -or -not $station.StartsWith('RDP-', [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }

            $username = Get-WtsSessionString -SessionId $info.SessionID -InfoClass ([RdpSessionAgent.WTS_INFO_CLASS]::WTSUserName)
            if ([string]::IsNullOrWhiteSpace($username)) {
                continue
            }

            $domain = Get-WtsSessionString -SessionId $info.SessionID -InfoClass ([RdpSessionAgent.WTS_INFO_CLASS]::WTSDomainName)
            if ([string]::IsNullOrWhiteSpace($domain)) {
                $domain = $null
            }

            $sourceIp = Get-WtsClientAddress -SessionId $info.SessionID

            $sessions += [PSCustomObject][ordered]@{
                session_id = [int]$info.SessionID
                username = $username
                domain = $domain
                state = $state
                logon_at = $null
                source_ip = $sourceIp
            }
        }
    }
    finally {
        if ($buffer -ne [IntPtr]::Zero) {
            [RdpSessionAgent.WtsNativeMethods]::WTSFreeMemory($buffer)
        }
    }

    return @($sessions)
}

function Get-AgentHostMetadata {
    $hostname = [string]$env:COMPUTERNAME
    $domainName = [System.Net.NetworkInformation.IPGlobalProperties]::GetIPGlobalProperties().DomainName
    $fqdn = $null
    if (-not [string]::IsNullOrWhiteSpace($domainName)) {
        $fqdn = $hostname + '.' + $domainName
    }

    $os = Get-WmiObject -Class Win32_OperatingSystem -ErrorAction Stop
    $osVersion = ('{0} {1} build {2}' -f $os.Caption, $os.Version, $os.BuildNumber).Trim()
    if ($osVersion.Length -gt 128) {
        $osVersion = $osVersion.Substring(0, 128)
    }

    return [PSCustomObject]@{
        hostname = $hostname
        fqdn = $fqdn
        os_version = $osVersion
    }
}
