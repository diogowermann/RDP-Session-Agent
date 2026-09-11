# Installation and configuration

This guide describes how to install **RDP Session Agent** on a Windows Server and how to repeat the process safely across multiple servers.

The examples are intentionally generic. Replace them locally with your real values, but do **not** commit API URLs, server IDs, secrets, internal hostnames, or private network information to this repository.

## 1. Requirements

- Windows Server 2012 through Windows Server 2022 target.
- Windows PowerShell 3.0 or newer.
- Local Administrator rights for installation.
- `Microsoft-Windows-TerminalServices-LocalSessionManager/Operational` available.
- Native Windows Terminal Services API (`wtsapi32.dll`).
- Outbound HTTPS connectivity to RDP Session API.
- TLS trust for the API certificate chain.
- A unique `server_id` and Agent secret created by RDP Session API.

No inbound Agent port, WinRM, SMB, or remote WMI access is required by this project.

## 2. Register the Windows server in the API first

Every monitored Windows server must be registered independently in the companion API.

On the API host, the administrator runs a command similar to:

```bash
.venv/bin/python scripts/register_server.py --hostname SRV-RDS01
```

The API returns:

- a unique `server_id`;
- a one-time Agent secret.

Store the secret securely during initial installation. The API stores only its hash, so the original plaintext value cannot be recovered later.

Do not reuse the same Agent secret or `server_id` on another Windows server.

## 3. Obtain the Agent source

Clone or otherwise copy the repository to a local administrative working directory on the Windows server.

Example with Git:

```powershell
git clone https://github.com/diogowermann/RDP-Session-Agent.git
Set-Location .\RDP-Session-Agent
```

The checkout directory is not the runtime location. The installer copies runtime files to `C:\ProgramData\RdpSessionAgent`.

## 4. Run the preflight

Open **Windows PowerShell as Administrator** and run:

```powershell
.\scripts\Test-Prerequisites.ps1 `
    -ApiBaseUrl 'https://rdp-api.example.com/api/v1'
```

The preflight validates:

- supported PowerShell version;
- LocalSessionManager Event Log availability;
- WTS API enumeration;
- API health over HTTPS.

The API check must report contract `v1` without disabling certificate validation.

If HTTPS fails with a trust error, install the correct issuing CA certificate in the Windows trust store rather than bypassing TLS validation.

## 5. Install the Agent

Use `Install-Agent.ps1` for first installation, credential rotation, or repair that intentionally rewrites Agent configuration/credential material.

From an elevated PowerShell prompt:

```powershell
.\scripts\Install-Agent.ps1 `
    -ApiBaseUrl 'https://rdp-api.example.com/api/v1' `
    -ServerId '00000000-0000-0000-0000-000000000000' `
    -AgentSecret 'replace-with-the-secret-returned-by-the-api'
```

Default installation directory:

```text
C:\ProgramData\RdpSessionAgent\
```

The installer:

- copies the Agent runtime;
- writes `config.json`;
- protects the Agent secret with DPAPI `LocalMachine` scope in `credential.dat`;
- creates `spool` and `logs` directories;
- preserves existing operational state on reinstall;
- restricts the installation directory ACL to `SYSTEM` and local Administrators;
- creates a Scheduled Task named `RDP Session Agent`;
- configures the task to run every minute as `SYSTEM` with highest privileges.

To install the files without creating the Scheduled Task:

```powershell
.\scripts\Install-Agent.ps1 `
    -ApiBaseUrl 'https://rdp-api.example.com/api/v1' `
    -ServerId '00000000-0000-0000-0000-000000000000' `
    -AgentSecret 'replace-with-secret' `
    -SkipScheduledTask
```

## 6. Validate the installed files

Expected layout:

```text
C:\ProgramData\RdpSessionAgent\
├── config.json
├── credential.dat
├── state.json              # created/updated at runtime
├── VERSION
├── logs\
├── spool\
├── rollback\              # created by Update-Agent.ps1 when needed
└── src\
```

`credential.dat` contains the DPAPI-protected secret, not the plaintext value.

## 7. Validate the Scheduled Task

Inspect the task:

```powershell
schtasks.exe /Query /TN "RDP Session Agent" /V /FO LIST
```

The task should run as `SYSTEM` and execute once per minute.

Trigger it immediately:

```powershell
schtasks.exe /Run /TN "RDP Session Agent"
```

## 8. Run a manual validation

A manual execution is useful for immediate diagnostics:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File 'C:\ProgramData\RdpSessionAgent\src\Agent.ps1'
```

Typical successful messages include:

```text
No new RDP session events.
```

or:

```text
Collected 2 event(s); spool=...
Sending spool batch ...
API accepted=2 duplicates=0
```

When WTS reconciliation is due:

```text
WTS snapshot observed=1 created=0 updated=1 closed=0
```

## 9. Validate local logs and state

Recent log lines:

```powershell
Get-Content `
  "C:\ProgramData\RdpSessionAgent\logs\agent-$(Get-Date -Format yyyyMMdd).log" `
  -Tail 50
```

Important locations:

```text
C:\ProgramData\RdpSessionAgent\logs\
C:\ProgramData\RdpSessionAgent\state.json
C:\ProgramData\RdpSessionAgent\spool\
```

### `state.json`

Tracks the acknowledged Event Log checkpoint and the last successful WTS snapshot time.

### `spool\`

Contains event batches that were persisted locally before delivery. A failed HTTP request leaves the batch in place for retry.

## 10. Validate from the API side

After the Agent has executed successfully, query the central API and confirm that the server record is populated.

Expected server metadata includes:

- hostname;
- FQDN when available;
- Windows version;
- Agent version;
- last seen time;
- last WTS snapshot time;
- current active/disconnected/open session counts.

## 11. Validate a normal RDP lifecycle

A recommended first validation sequence is:

1. create a new RDP logon;
2. allow the Agent to collect the event;
3. disconnect without logging off;
4. reconnect;
5. perform a full logoff.

Expected logical transitions:

```text
LOGON -> ACTIVE
DISCONNECT -> DISCONNECTED
RECONNECT -> ACTIVE
LOGOFF -> CLOSED
```

## 12. WTS reconciliation behavior

Event Log is the primary lifecycle source. WTS is a secondary current-state source.

By default:

- Event Log collection is attempted every Scheduled Task run (one minute).
- WTS reconciliation runs every five minutes.

The interval is stored in `config.json` as:

```json
{
  "snapshot_interval_minutes": 5
}
```

WTS can:

- create an observed current session missing from consolidated state;
- correct an open session between `ACTIVE` and `DISCONNECTED`;
- close an API session no longer observed locally with `end_reason=RECONCILIATION`.

## 13. Failure and retry behavior

### Event delivery failure

Event batches are saved to local spool **before** transmission.

If the API request fails:

1. the Agent exits non-zero;
2. the spool file remains on disk;
3. the Event Log checkpoint is not advanced for that batch;
4. the next execution sends pending spool before collecting newer events.

API event ingestion is idempotent, so replay is safe.

### WTS snapshot failure

Snapshots represent current state and are not persisted in the event spool.

If a snapshot request fails, its timestamp is not advanced. A later Scheduled Task run builds and sends a new current-state snapshot.

## 14. Install on additional servers

Repeat these steps for each new Windows Server:

1. register a new server in RDP Session API;
2. receive a unique `server_id` and Agent secret;
3. clone/copy the Agent repository to that server;
4. run the preflight;
5. run `Install-Agent.ps1` with that server's unique values;
6. validate the Scheduled Task and logs;
7. confirm the new server appears separately in the API.

Do **not** copy `credential.dat`, `config.json`, or `state.json` from another monitored server.

## 15. Update an existing installation

Routine code updates use `Update-Agent.ps1` and do **not** require the plaintext Agent secret.

Update the source checkout:

```powershell
git switch main
git pull --ff-only
Get-Content .\VERSION
```

Then run from an elevated prompt:

```powershell
.\scripts\Update-Agent.ps1
```

The updater:

- verifies that an existing installation is present;
- stages the repository runtime before changing production files;
- creates a timestamped rollback copy of the currently installed `src` and `VERSION`;
- temporarily disables/ends the Scheduled Task during the runtime swap;
- replaces only `src` and `VERSION`;
- preserves `config.json`, `credential.dat`, `state.json`, `spool` and `logs`;
- restores the original enabled state of the Scheduled Task;
- attempts automatic runtime restoration if replacement fails.

The normal production command does not accept or need `AgentSecret`.

After the update:

```powershell
Get-Content 'C:\ProgramData\RdpSessionAgent\VERSION'
schtasks.exe /Run /TN 'RDP Session Agent'
Start-Sleep -Seconds 10
Get-Content "C:\ProgramData\RdpSessionAgent\logs\agent-$(Get-Date -Format yyyyMMdd).log" -Tail 50
```

Confirm API `last_seen`, WTS reconciliation and spool health. For Phase 9 rollout procedure and batch gates, see [Phase 9 Windows rollout](phase9-windows-rollout.md).

`git pull` alone does not update the installed runtime.

## 16. Credential rotation

Credential rotation is intentionally separate from routine code updates.

If the API administrator rotates a server credential, immediately rerun `Install-Agent.ps1` for that server with the newly returned secret. The previous token can no longer authenticate.

Do not use another server's secret and do not copy `credential.dat` between machines.

## 17. Troubleshooting checklist

### Preflight fails on API health

Check:

- DNS resolution;
- outbound TCP/443 connectivity;
- TLS certificate trust;
- reverse-proxy availability;
- API health endpoint.

### Event Log collection fails

Check that this channel exists and is readable:

```text
Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
```

### Events remain in spool

Check:

- HTTPS connectivity;
- server ID and Agent secret pairing;
- API service logs;
- reverse-proxy status.

### WTS snapshot fails

Re-run:

```powershell
.\scripts\Test-Prerequisites.ps1 `
    -ApiBaseUrl 'https://rdp-api.example.com/api/v1'
```

Then inspect the Agent log for WTS-specific errors.

### Update-Agent.ps1 refuses to run

Do not bypass its installation checks. Confirm that the server already has:

- `C:\ProgramData\RdpSessionAgent\src`;
- `VERSION`;
- `config.json`;
- `credential.dat`.

If configuration or credential material is genuinely missing/corrupt, treat it as installation repair rather than a routine code update.

## 18. Current limitations

The project does not currently provide:

- automatic Agent self-update;
- Windows service packaging;
- dedicated Event Log reset/gap recovery beyond the existing reconciliation behavior.
