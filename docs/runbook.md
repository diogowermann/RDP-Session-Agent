# Operational runbook

This runbook covers routine operation, incident containment, upgrade and recovery of RDP Session Agent on Windows Server.

## Runtime inventory

| Item | Value |
|---|---|
| Scheduled Task | `RDP Session Agent` |
| Runtime root | `C:\ProgramData\RdpSessionAgent` |
| Entry point | `C:\ProgramData\RdpSessionAgent\src\Agent.ps1` |
| Configuration | `C:\ProgramData\RdpSessionAgent\config.json` |
| Protected credential | `C:\ProgramData\RdpSessionAgent\credential.dat` |
| State | `C:\ProgramData\RdpSessionAgent\state.json` |
| Logs | `C:\ProgramData\RdpSessionAgent\logs` |
| Durable event spool | `C:\ProgramData\RdpSessionAgent\spool` |
| Runtime rollback copies | `C:\ProgramData\RdpSessionAgent\rollback` |

Run commands from an elevated Windows PowerShell prompt. Do not expose `credential.dat`, production configuration, usernames or session payloads in public tickets.

## Routine health check

```powershell
$Root = 'C:\ProgramData\RdpSessionAgent'
Get-Content (Join-Path $Root 'VERSION')
schtasks.exe /Query /TN 'RDP Session Agent' /V /FO LIST
Get-Content (Join-Path $Root "logs\agent-$(Get-Date -Format yyyyMMdd).log") -Tail 50
Get-ChildItem (Join-Path $Root 'spool') -File | Select-Object Name, Length, LastWriteTime
```

Healthy operation means the task is enabled, executes as `SYSTEM`, recent logs show successful delivery or `No new RDP session events`, WTS snapshots succeed, spool does not grow continuously, and API `last_seen` advances.

Trigger and inspect one run:

```powershell
schtasks.exe /Run /TN 'RDP Session Agent'
Start-Sleep -Seconds 10
Get-Content "C:\ProgramData\RdpSessionAgent\logs\agent-$(Get-Date -Format yyyyMMdd).log" -Tail 50
```

For synchronous diagnostics:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File 'C:\ProgramData\RdpSessionAgent\src\Agent.ps1'
```

## Incident triage

### Task missing, disabled or failing

1. Query the task and its last result.
2. Run the installed entry point manually as Administrator.
3. Inspect the current Agent log and installed `VERSION`.
4. Re-run `scripts\Install-Agent.ps1` from an approved checkout only when the task definition, configuration or credential itself must be repaired.

Routine code upgrades should use `scripts\Update-Agent.ps1`, which preserves the existing machine identity, protected credential, state, logs and spool.

### Events accumulating in spool

Spool is recoverable telemetry. Do not delete it during ordinary troubleshooting. Check, in order:

1. DNS and outbound TCP/443 access;
2. API certificate-chain trust;
3. API v1 health from the server;
4. the `server_id` and machine-specific secret pairing;
5. reverse-proxy and API logs;
6. free disk space and runtime-root ACLs.

After repair, run the Agent once. Pending spool is replayed before newer records and API ingestion is idempotent.

### API returns 401 or 403

The server identity is disabled or its ID and secret do not match. Never copy credentials from another server. Rotate/register the credential centrally and reinstall this Agent with the returned secret.

### TLS failure

Install or repair the issuing CA in the Windows machine trust store. Never bypass certificate validation.

### Event Log collection failure

```powershell
Get-WinEvent -ListLog 'Microsoft-Windows-TerminalServices-LocalSessionManager/Operational' |
    Select-Object LogName, IsEnabled, RecordCount
```

Do not reset `state.json` merely to force replay; preserve it for diagnosis.

### WTS snapshot failure

Verify local WTS enumeration with `scripts\Test-Prerequisites.ps1`. A failed snapshot does not remove the event spool and is retried on a later run.

## Upgrade

Routine upgrades of an existing healthy installation must not require the plaintext Agent secret.

1. Record installed `VERSION`, task state and spool count.
2. Update the approved source checkout.
3. Run the release tests and preflight.
4. Run `scripts\Update-Agent.ps1` from an elevated PowerShell prompt.
5. Confirm the new installed `VERSION`.
6. Trigger one task run and verify logs, spool replay, WTS reconciliation and API `last_seen`.
7. For rollout canaries, validate `LOGON -> DISCONNECT -> RECONNECT -> LOGOFF` and source-IP behavior.

`Update-Agent.ps1` replaces only `src` and `VERSION`. It preserves `config.json`, `credential.dat`, `state.json`, logs and spool, and creates a runtime rollback copy before replacement.

Do not use `Install-Agent.ps1` as the normal upgrade path. The installer requires an Agent secret and is reserved for first installation, credential rotation or repair that genuinely requires rewriting installation configuration/credential material.

`git pull` alone does not upgrade the installed runtime.

See [Phase 9 Windows rollout](phase9-windows-rollout.md) for batch order, canary gates and rollback evidence.

## Containment and rollback

Stop collection without deleting evidence:

```powershell
schtasks.exe /Change /TN 'RDP Session Agent' /DISABLE
```

Re-enable after correction:

```powershell
schtasks.exe /Change /TN 'RDP Session Agent' /ENABLE
schtasks.exe /Run /TN 'RDP Session Agent'
```

For code rollback after a Phase 9 update, restore only `src` and `VERSION` from the rollback directory created by `Update-Agent.ps1`. Preserve `config.json`, `credential.dat`, `state.json`, logs and spool.

If no updater rollback copy exists, check out the last approved release and use a controlled recovery procedure. Never copy operational state or credentials between servers.

## Credential rotation

1. Rotate the server token through the API administration procedure.
2. Reinstall the Agent immediately using `Install-Agent.ps1` with the new secret.
3. Trigger a run and confirm acknowledgement.
4. Verify no new spool backlog appears.

Credential rotation is intentionally separate from routine code updates.

## Escalation evidence

Collect hostname and version, task status/last result, sanitized recent logs, spool count/oldest timestamp/total size, last successful acknowledgement and snapshot time, and relevant HTTP status. Never collect secrets or full session payloads.

## Post-recovery gate

- task enabled and executing as `SYSTEM`;
- manual or scheduled run succeeds;
- pending spool is stable or decreasing;
- API `last_seen` advances;
- one controlled lifecycle reaches `LOGON -> DISCONNECT -> RECONNECT -> LOGOFF`;
- no credentials or sensitive telemetry were exposed.
