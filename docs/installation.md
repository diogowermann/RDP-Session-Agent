# Installation and validation

This guide is intentionally generic. Do not add real API URLs, server IDs, Agent secrets, internal hostnames, or private network information to this repository.

## Requirements

- Windows Server 2012 through Windows Server 2022 target.
- Windows PowerShell 3.0 or newer.
- Administrator rights for installation, Task Scheduler configuration and DPAPI machine-scope credential creation.
- `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` available.
- Windows Terminal Services API (`wtsapi32.dll`), included with supported Windows Server versions.
- Outbound HTTPS access to the RDP Session API.
- A server ID and Agent secret created by RDP Session API.

## 1. Preflight

From an elevated Windows PowerShell prompt in the repository checkout:

```powershell
.\scripts\Test-Prerequisites.ps1 -ApiBaseUrl 'https://api.example.com/api/v1'
```

The API health check must report contract `v1`.

## 2. Install or update the Agent

Run the installer from an elevated Windows PowerShell prompt:

```powershell
.\scripts\Install-Agent.ps1 `
    -ApiBaseUrl 'https://api.example.com/api/v1' `
    -ServerId '00000000-0000-0000-0000-000000000000' `
    -AgentSecret 'replace-with-the-secret-returned-by-the-api'
```

Default destination:

```text
C:\ProgramData\RdpSessionAgent\
```

The installer:

- copies the Agent runtime;
- writes `config.json`;
- protects the Agent secret with DPAPI `LocalMachine` scope in `credential.dat`;
- creates `spool` and `logs` directories;
- restricts the installation directory to `SYSTEM` and local Administrators;
- creates a Scheduled Task named `RDP Session Agent`;
- runs the task every minute as `SYSTEM` with highest privileges.

To install without creating the task, add `-SkipScheduledTask`.

### Updating an existing installation

The Agent executes from `C:\ProgramData\RdpSessionAgent`, not directly from the Git checkout. After updating the repository, always re-run the installer:

```powershell
git pull
.\scripts\Install-Agent.ps1 `
    -ApiBaseUrl 'https://api.example.com/api/v1' `
    -ServerId '00000000-0000-0000-0000-000000000000' `
    -AgentSecret 'replace-with-the-existing-secret'
```

Re-running the installer replaces the runtime files and Scheduled Task while preserving `state.json`, logs and pending spool data.

## 3. Manual validation

Even with the Scheduled Task installed, a manual run is useful for immediate validation:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\RdpSessionAgent\src\Agent.ps1'
```

The Agent first delivers pending event spool files, then collects new LocalSessionManager lifecycle events. A WTS current-state snapshot is sent when the configured snapshot interval is due.

Default timing:

- Event Log collection: every Scheduled Task run (one minute).
- WTS reconciliation: every five minutes.

The WTS interval is stored in `config.json` as `snapshot_interval_minutes`.

## 4. WTS reconciliation behavior

The Agent enumerates local Terminal Services sessions using the native Windows WTS API and forwards only RDP sessions in `ACTIVE` or `DISCONNECTED` state.

Event Log remains the primary lifecycle source. The WTS snapshot acts as a secondary source of truth for current state:

- an observed session missing from API state can be created by reconciliation;
- an existing open session can be corrected between `ACTIVE` and `DISCONNECTED`;
- an API session no longer observed by WTS can be closed with `end_reason=RECONCILIATION`.

This makes the system recover from missed Event Log records or temporary Agent/API unavailability.

## 5. Validate the Scheduled Task

Inspect the task:

```powershell
schtasks.exe /Query /TN "RDP Session Agent" /V /FO LIST
```

Trigger it immediately if desired:

```powershell
schtasks.exe /Run /TN "RDP Session Agent"
```

Inspect Agent output in:

```text
C:\ProgramData\RdpSessionAgent\logs\
C:\ProgramData\RdpSessionAgent\state.json
C:\ProgramData\RdpSessionAgent\spool\
```

A successful WTS cycle logs a line similar to:

```text
WTS snapshot observed=1 created=0 updated=1 closed=0
```

The API server record should also populate `last_snapshot_at`, hostname, FQDN and OS version.

## Failure behavior

If an event HTTP request fails, the Agent exits non-zero and keeps the JSON event batch in `spool`. The next run sends pending spool batches before collecting newer events. Replays are safe because the API implements idempotent event ingestion.

If a WTS snapshot request fails, the snapshot timestamp is not advanced. The next Scheduled Task run retries using a new current-state snapshot.

## Current limitations

This increment does not yet include:

- Event Log reset/gap recovery;
- automatic Agent update;
- Windows service packaging.

### Note about event 23

LocalSessionManager event 23 does not include a source address. The Agent forwards a valid event 23 when it contains a user and session ID; the API only changes consolidated state when it matches an existing open session. WTS reconciliation independently verifies the current remote-session state.
