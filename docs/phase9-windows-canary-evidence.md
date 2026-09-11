# Phase 9 Windows canary evidence

This document records the public, infrastructure-agnostic evidence used to close the Windows canary gate for Phase 9.

No production hostnames, usernames, private IP addresses, API keys, Agent secrets, certificates or internal URLs are included here.

## Date

2026-09-11

## Scope

The canary gate validated the credential-safe update path introduced in version `0.3.1` before controlled multi-server rollout.

The validation covered:

- native PowerShell self-test with no external modules;
- an installed Windows Server 2012 canary upgraded from `0.3.0` to `0.3.1`;
- an additional modern Windows Server canary;
- preservation of Agent configuration, DPAPI-protected credential, state, spool and logs;
- Scheduled Task continuity;
- runtime rollback creation;
- API ingestion after upgrade;
- WTS reconciliation;
- RDP session lifecycle visibility in the Portal;
- source-IP visibility when Windows supplied usable origin evidence;
- duplicate protection and spool health.

A Windows Server 2008 host also passed the native updater self-test as supplementary evidence. Windows Server 2008 is not part of the formal compatibility baseline and this result does not extend the documented support matrix.

## Native self-test result

`tests/UpdateAgent.SelfTest.ps1` passed without Pester, PSGallery or any other external PowerShell module.

The self-test verified that a simulated `0.3.0` installation could be upgraded to `0.3.1` while preserving:

- `config.json`;
- `credential.dat`;
- `state.json`;
- `spool/`;
- `logs/`.

It also verified creation of a runtime rollback copy and no-op behavior when the installed version already matched the repository version.

## Windows Server 2012 production canary

Before upgrade:

- installed Agent version was `0.3.0`;
- the Scheduled Task was enabled and running as `SYSTEM`;
- the previous task result was successful;
- spool was empty;
- state checkpoints were advancing;
- WTS reconciliation was healthy.

Upgrade result:

- `Update-Agent.ps1` upgraded the installed runtime to `0.3.1`;
- the existing configuration and protected credential remained in place;
- a timestamped `0.3.0` runtime rollback copy was created;
- the Scheduled Task remained enabled and could be triggered successfully;
- the Agent continued writing normal logs after the update;
- spool remained empty after successful delivery.

Lifecycle result:

- real RDP activity was collected after the upgrade;
- API ingestion accepted the generated events with zero reported duplicates in the observed test batches;
- WTS reconciliation continued to observe the active session;
- the Agent state checkpoint advanced after the test activity;
- the Portal displayed the resulting remote-session history and details correctly.

## Modern Windows Server canary

A second canary on a modern supported Windows Server completed the same operational gate without errors. The updater, Agent execution, ingestion, spool behavior and Portal validation all remained healthy.

The exact production server identity is intentionally omitted from the public repository.

## Gate decision

**APPROVED** — the Windows canary gate is closed.

Version `0.3.1` is approved for controlled rollout to the remaining intended Windows servers in batches of one or two servers at a time.

Expansion must stop if any batch shows:

- Agent authentication regression;
- Scheduled Task failure;
- continuously growing spool;
- unexpected duplicate growth;
- WTS/session reconciliation regression;
- source-IP regression relative to available Windows evidence;
- loss or mutation of the existing per-server credential/state.

Rollback remains runtime-only: restore the previous `src/` and `VERSION` while preserving configuration, credential, state, spool and logs.
