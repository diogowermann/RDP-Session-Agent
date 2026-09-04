# Phase 2 RDP client origin capture

Agent 0.3.0 adds optional client-origin evidence to the existing v1 event and snapshot payloads.

## Event Log source

Terminal Services LocalSessionManager events already expose an `Address` field on relevant lifecycle records. Agent 0.3.0 normalizes this field for LOGON and RECONNECT and sends it as `source_ip` when it is a usable IPv4/IPv6 address.

Invalid, partial, loopback, unspecified or `LOCAL` values become null and never invalidate the lifecycle event.

## WTS source

Snapshots query `WTSClientAddress` through `WTSQuerySessionInformation`. For `AF_INET`, the IPv4 value is read from the documented two-byte offset inside `WTS_CLIENT_ADDRESS.Address`. For `AF_INET6`, the first 16 raw address bytes are decoded.

A failed WTS address query returns null and does not fail the snapshot.

Microsoft documents `WTSClientAddress` with a minimum supported server of Windows Server 2008. Windows Server 2008 R2 is nevertheless treated as a legacy compatibility canary in this project rather than as the primary support floor.

## Evidence limitations

`WTSClientAddress` is reported by the RDP client and can differ from the network peer seen by the server when NAT, Remote Desktop Gateway or VPN is involved. It is telemetry evidence, not an authentication or device-identity mechanism.

## Rollout gate

1. Deploy RDP Session API 0.3.0 first.
2. Confirm all existing Agent 0.2.0 instances remain healthy.
3. Upgrade one Windows Server 2022 canary to Agent 0.3.0.
4. Exercise LOGON, DISCONNECT, RECONNECT and LOGOFF, including reconnect from another client when practical.
5. Confirm event `source_ip`, session `initial_source_ip`/`last_source_ip`, spool and snapshot behavior.
6. Only then upgrade the Windows Server 2008 R2 legacy canary.
7. Expand in small batches after both canaries are stable.

No source port is emitted by Agent 0.3.0 because neither current Event Log parsing nor `WTSClientAddress` provides a reliable client source port. The API field remains optional for future evidence sources.
