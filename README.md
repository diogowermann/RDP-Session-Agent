# RDP Session Agent

RDP Session Agent is a lightweight Windows PowerShell collector for Remote Desktop Services session lifecycle events.

It is designed to work with the separate RDP Session API project and to remain infrastructure-agnostic. The repository does not contain environment-specific hostnames, credentials, network addresses, or deployment configuration.

## Current scope

- Windows Server 2012 through Windows Server 2022 compatibility target.
- PowerShell 3.0-compatible runtime code.
- Event IDs 21, 23, 24 and 25 from `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational`.
- Local DPAPI protection for the per-server Agent secret.
- Durable local spool before HTTP delivery.
- Idempotent replay support through the API contract.
- Local checkpoint updated only after API acknowledgement.
- Manual one-shot execution for the first validation phase.

## Event mapping

| Windows event | Agent event |
| --- | --- |
| 21 | `LOGON` |
| 23 | `LOGOFF` |
| 24 | `DISCONNECT` |
| 25 | `RECONNECT` |

## Installation

See [docs/installation.md](docs/installation.md).

The first release is intentionally installed and executed manually. Scheduled Tasks and WTS snapshot reconciliation will be added after event collection is validated on real Windows Server versions.

## Security

The Agent secret is never stored in plaintext by the installed Agent. `Install-Agent.ps1` protects it with Windows DPAPI using machine scope and restricts the installation directory ACL to `SYSTEM` and local Administrators.

Do not commit real API URLs, server IDs, secrets, internal hostnames, or production configuration.
