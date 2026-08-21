# Installation and first validation

This guide is intentionally generic. Do not add real API URLs, server IDs, Agent secrets, internal hostnames, or private network information to this repository.

## Requirements

- Windows Server 2012 through Windows Server 2022 target.
- Windows PowerShell 3.0 or newer.
- Administrator rights for installation and DPAPI machine-scope credential creation.
- `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` available.
- Outbound HTTPS access to the RDP Session API.
- A server ID and Agent secret created by RDP Session API.

The current release does not create a Scheduled Task. It is intended for manual one-shot validation first.

## 1. Preflight

From an elevated Windows PowerShell prompt in the repository checkout:

```powershell
.\scripts\Test-Prerequisites.ps1 -ApiBaseUrl 'https://api.example.com/api/v1'
```

The API health check must report contract `v1`.

## 2. Install files and credential

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
- restricts the installation directory to `SYSTEM` and local Administrators.

It does not create a service or Scheduled Task yet.

## 3. First manual run

From an elevated prompt:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File 'C:\ProgramData\RdpSessionAgent\src\Agent.ps1'
```

On first execution the Agent inspects recent lifecycle events using the configured lookback window. If no recent matching events exist, it records the latest relevant Event Record ID as its baseline and does not backfill older history.

## 4. Generate a real test event

After the first run, create a normal RDP session lifecycle action (for example a new RDP logon) and execute the Agent again.

The Agent should:

1. read new LocalSessionManager events;
2. normalize IDs 21/23/24/25;
3. write the batch to the local spool before transmission;
4. POST the batch to `/api/v1/agent/events`;
5. update `state.json` only after the API acknowledges the batch;
6. remove the acknowledged spool file.

Inspect:

```text
C:\ProgramData\RdpSessionAgent\logs\
C:\ProgramData\RdpSessionAgent\state.json
C:\ProgramData\RdpSessionAgent\spool\
```

Then validate the server summary and active/history endpoints on RDP Session API.

## Failure behavior

If the HTTP request fails, the Agent exits non-zero and keeps the JSON batch in `spool`. The next run sends pending spool batches before collecting newer events. Replays are safe because the API implements idempotent event ingestion.

## Current limitations

This first increment intentionally does not yet include:

- Scheduled Task installation;
- WTS session snapshot reconciliation;
- Event Log reset/gap recovery;
- automatic update;
- Windows service packaging.

Those capabilities are added only after real event collection has been validated.

### Note about event 23

LocalSessionManager event 23 does not include a source address. The Agent forwards a valid event 23 when it contains a user and session ID; the API only changes consolidated state when it matches an existing open session. WTS reconciliation in the next increment becomes the authoritative source for current remote-session state.
