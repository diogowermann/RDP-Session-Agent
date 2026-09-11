# Phase 9 Windows rollout

Phase 9 expands the Windows Agent with source-IP support in controlled batches while preserving the operational state and per-server credential already installed on each server.

The rollout must not require recovery or re-entry of the existing plaintext Agent secret. The central API stores only the secret hash, so routine code updates use `scripts/Update-Agent.ps1` rather than `Install-Agent.ps1`.

## Release scope

Version `0.3.1` adds the credential-safe runtime updater and rollout documentation. It does not change the event contract introduced by `0.3.0`.

The updater replaces only:

- `src/`
- `VERSION`

It preserves:

- `config.json`
- `credential.dat`
- `state.json`
- `spool/`
- `logs/`

Before replacement, the currently installed runtime and version are copied to a timestamped directory under:

```text
C:\ProgramData\RdpSessionAgent\rollback\
```

The backup deliberately excludes credentials, configuration, session state, spool and logs because those paths remain in place and are not part of the code rollback unit.

## Preconditions

Run from an elevated Windows PowerShell prompt.

Before updating a server, record:

```powershell
$Root = 'C:\ProgramData\RdpSessionAgent'
Get-Content (Join-Path $Root 'VERSION')
schtasks.exe /Query /TN 'RDP Session Agent' /V /FO LIST
Get-ChildItem (Join-Path $Root 'spool') -File |
    Measure-Object -Property Length -Sum
Get-Content (Join-Path $Root "logs\agent-$(Get-Date -Format yyyyMMdd).log") -Tail 30
```

The server is ready when the Scheduled Task is healthy, API `last_seen` is current and spool is not growing continuously.

## Zero-dependency updater self-test

The Phase 9 updater validation must run with the Windows/PowerShell components already required by the Agent. It does not require Pester or any other external PowerShell module.

From the repository checkout:

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass `
    -File '.\tests\UpdateAgent.SelfTest.ps1'
```

The self-test uses an isolated temporary installation tree, invokes `Update-Agent.ps1` with Scheduled Task control disabled, verifies runtime replacement and rollback creation, and confirms that configuration, protected credential, state, spool and logs remain unchanged. It also validates the matching-version no-op path.

A successful run ends with:

```text
SELF-TEST PASSED: Update-Agent.ps1 requires no external PowerShell modules for this validation.
```

This test does not modify the production Agent installation.

## Update procedure

Update the approved source checkout first:

```powershell
git switch main
git pull --ff-only
Get-Content .\VERSION
```

Then execute:

```powershell
.\scripts\Update-Agent.ps1
```

The updater validates the existing installation, stages the new runtime, creates the rollback copy, temporarily disables/ends the Scheduled Task, swaps the runtime, validates the installed version and restores the original enabled state of the task.

`-SkipScheduledTaskControl` exists only for isolated test execution. Do not use it during a production rollout.

## Immediate post-update validation

Confirm the installed version and task state:

```powershell
Get-Content 'C:\ProgramData\RdpSessionAgent\VERSION'
schtasks.exe /Query /TN 'RDP Session Agent' /V /FO LIST
```

Trigger one run:

```powershell
schtasks.exe /Run /TN 'RDP Session Agent'
Start-Sleep -Seconds 10
Get-Content "C:\ProgramData\RdpSessionAgent\logs\agent-$(Get-Date -Format yyyyMMdd).log" -Tail 50
```

Validate centrally that:

- API `last_seen` advances;
- no unexpected authentication failure appears;
- spool is stable or decreasing;
- WTS reconciliation continues normally;
- source IP is present when Windows provides usable RDP origin evidence.

## Per-server lifecycle gate

For at least one connection on each initial canary, validate:

```text
LOGON -> ACTIVE
DISCONNECT -> DISCONNECTED
RECONNECT -> ACTIVE
LOGOFF -> CLOSED
```

The gate passes when the session is not duplicated, `initial_source_ip` remains stable, `last_source_ip` follows valid reconnection evidence, and the absence of an IP does not invalidate the session.

## Rollback

If the new runtime is unhealthy, first contain collection without deleting evidence:

```powershell
schtasks.exe /Change /TN 'RDP Session Agent' /DISABLE
```

Identify the rollback directory printed by the updater. Restore only `src` and `VERSION` from that directory to the installation root, preserving `config.json`, `credential.dat`, `state.json`, `spool` and `logs`.

After restoration:

```powershell
schtasks.exe /Change /TN 'RDP Session Agent' /ENABLE
schtasks.exe /Run /TN 'RDP Session Agent'
```

Then confirm API `last_seen`, lifecycle collection and spool replay.

The updater also attempts an automatic runtime restore if failure occurs after replacement begins.

## Controlled batch strategy

Use small batches and stop expansion whenever a gate fails.

Recommended order:

1. one modern Windows Server canary with meaningful RDP usage;
2. one Windows Server 2012 canary to retain the lower compatibility boundary;
3. one or two servers per batch, prioritizing higher RDP usage;
4. remaining compatible Windows servers after each previous batch has remained healthy.

Between batches, inspect:

- installed version distribution;
- API `last_seen`;
- spool count and oldest item age;
- event duplicate count;
- session reconciliation behavior;
- source-IP coverage;
- any authentication, TLS or WTS errors.

## Phase 9 Windows gate

Windows rollout is complete when:

- all intended Windows servers run the approved version;
- every server keeps its original identity and machine-protected credential;
- no rollout-induced spool backlog remains;
- lifecycle and WTS reconciliation remain healthy;
- source-IP telemetry is observed where Windows exposes it;
- rollback evidence exists and no server required destructive state reset or credential copying.
