# Phase 0 — Agent baseline capture

This runbook records the Windows Agent state before the Remote Session Monitoring expansion changes its payload or collection behavior.

## Capture

Run from an elevated Windows PowerShell prompt on each monitored server:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Get-Phase0Baseline.ps1
```

The script reads the installed runtime under `C:\ProgramData\RdpSessionAgent` by default and writes an evidence JSON to the current user's temporary directory.

The output contains internal hostname, server ID and API configuration. **Never commit the generated JSON to this public repository.** Archive it in the internal project workspace.

## Evidence collected

- Windows version/build and last boot time;
- PowerShell version;
- installed Agent version;
- presence of configuration, DPAPI credential and state files;
- server ID and API base URL;
- checkpoint/snapshot state;
- spool file count, size and oldest/newest timestamps;
- Agent log count and timestamps;
- Scheduled Task status, last result and next execution.

The Agent secret is never decrypted or exported.

## Per-server gate

A server is ready for the expansion only when:

- the expected Agent version is installed;
- the Scheduled Task is present and healthy;
- `credential.dat` and state are present;
- spool backlog is empty or explicitly explained;
- recent API `last_seen_at`/snapshot evidence matches the local Agent state;
- no current operational incident is attributed to the Agent.

Run this on every expected monitored Windows server. The central API capture must reconcile the list of local evidence files with the servers registered in the API.
