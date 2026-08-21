# RDP Session Agent

RDP Session Agent is a lightweight Windows PowerShell collector for Remote Desktop Services session lifecycle events.

It is designed to work with the separate RDP Session API project and to remain infrastructure-agnostic. The repository does not contain environment-specific hostnames, credentials, network addresses, or deployment configuration.

## Current scope

- Windows Server 2012 through Windows Server 2022 compatibility target.
- PowerShell 3.0-compatible runtime code.
- Event IDs 21, 23, 24 and 25 from `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`.
- Native Windows Terminal Services (WTS) session snapshots for reconciliation.
- Event collection every minute through Windows Task Scheduler.
- WTS reconciliation every five minutes by default.
- Scheduled Task runs as `SYSTEM`; no inbound management port is required.
- Local DPAPI protection for the per-server Agent secret.
- Durable local spool before HTTP event delivery.
- Idempotent replay support through the API contract.
- Local checkpoint updated only after API acknowledgement.

## Event mapping

| Windows event | Agent event |
| --- | --- |
| 21 | `LOGON` |
| 23 | `LOGOFF` |
| 24 | `DISCONNECT` |
| 25 | `RECONNECT` |

Event Log remains the primary lifecycle source. WTS snapshots are a secondary current-state source used to correct drift when an event is missed or the Agent was temporarily unavailable.

## Installation

See [docs/installation.md](docs/installation.md).

After updating an existing checkout with `git pull`, re-run `Install-Agent.ps1`. The runtime executes from the installed copy under `C:\ProgramData\RdpSessionAgent`; updating the repository alone does not update that installed copy.

## Security

The Agent secret is never stored in plaintext by the installed Agent. `Install-Agent.ps1` protects it with Windows DPAPI using machine scope and restricts the installation directory ACL to `SYSTEM` and local Administrators.

The Scheduled Task runs locally as `SYSTEM` and the Agent only requires outbound HTTPS connectivity to the RDP Session API.

Do not commit real API URLs, server IDs, secrets, internal hostnames, or production configuration.
