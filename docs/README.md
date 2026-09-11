# RDP Session Agent documentation

This directory contains the public technical documentation for RDP Session Agent.

## Main documents

- [Installation and configuration](installation.md) — server registration prerequisites, preflight, installation, Scheduled Task validation, lifecycle tests, WTS reconciliation, multi-server rollout, updates and troubleshooting.
- [Operational runbook](runbook.md) — routine health checks, incident triage, safe containment, upgrades, credential rotation, rollback and recovery gate.
- [System architecture](system-architecture.md) — Event Log and WTS sources, local persistence, spool reliability, authentication, TLS, Scheduled Task execution and deployment model.
- [Phase 0 baseline capture](phase0-baseline.md) — pre-expansion per-server evidence, spool/task health and readiness gate.
- [Phase 2 RDP client origin capture](phase2-origin-capture.md) — Event Log/WTS source IP collection, normalization, limitations and modern/legacy canary rollout.
- [Phase 9 Windows rollout](phase9-windows-rollout.md) — credential-safe runtime update, per-server canary checks, rollback evidence and controlled batch expansion.
- [Phase 9 Windows canary evidence](phase9-windows-canary-evidence.md) — infrastructure-agnostic record of the approved legacy/modern Windows canary gate before batch rollout.

## Companion project

Central ingestion, persistence, reconciliation, query endpoints and Grafana integration are implemented by [RDP-Session-API](https://github.com/diogowermann/RDP-Session-API).

## Public documentation policy

Examples in this repository must remain infrastructure-agnostic. Do not add production API URLs, real server IDs, Agent secrets, internal DNS names, private IP addresses, certificates, or logs containing private environment data.
