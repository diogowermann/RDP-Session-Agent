# RDP Session Agent documentation

This directory contains the public technical documentation for RDP Session Agent.

## Main documents

- [Installation and configuration](installation.md) — server registration prerequisites, preflight, installation, Scheduled Task validation, lifecycle tests, WTS reconciliation, multi-server rollout, updates and troubleshooting.
- [System architecture](system-architecture.md) — Event Log and WTS sources, local persistence, spool reliability, authentication, TLS, Scheduled Task execution and deployment model.

## Companion project

Central ingestion, persistence, reconciliation, query endpoints and Grafana integration are implemented by [RDP-Session-API](https://github.com/diogowermann/RDP-Session-API).

## Public documentation policy

Examples in this repository must remain infrastructure-agnostic. Do not add production API URLs, real server IDs, Agent secrets, internal DNS names, private IP addresses, certificates, or logs containing private environment data.
