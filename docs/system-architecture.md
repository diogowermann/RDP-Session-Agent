# RDP Session Agent — system architecture

> Technical reference for the Windows collector. The code remains the authority when implementation and documentation differ.

## 1. Purpose

RDP Session Agent runs locally on a monitored Windows Server and forwards Remote Desktop Services session telemetry to RDP Session API.

The design combines two Windows data sources:

- **LocalSessionManager Event Log** for lifecycle transitions;
- **Windows Terminal Services (WTS) API** for periodic current-state reconciliation.

## 2. Repository boundary

| Repository | Responsibility |
|---|---|
| `RDP-Session-Agent` | Windows collection, local persistence, retry behavior, WTS reconciliation, Scheduled Task installation |
| `RDP-Session-API` | Central authentication, ingestion, state consolidation, database persistence and queries |

## 3. Context view

```mermaid
flowchart LR
    User["RDP user activity"] --> Windows["Windows Server"]

    subgraph Windows
        EventLog["LocalSessionManager Event Log"]
        WTS["Windows WTS API"]
        Agent["RDP Session Agent"]
        Local["state.json + spool + logs"]
    end

    EventLog --> Agent
    WTS --> Agent
    Agent <--> Local
    Agent -->|"Outbound HTTPS only"| API["RDP Session API"]
```

## 4. Data sources

### 4.1 LocalSessionManager Event Log

The Agent reads:

```text
Microsoft-Windows-TerminalServices-LocalSessionManager/Operational
```

Relevant events:

| Event ID | Normalized type | Meaning |
|---|---|---|
| 21 | `LOGON` | New session |
| 23 | `LOGOFF` | Session ended |
| 24 | `DISCONNECT` | Session remains open but disconnected |
| 25 | `RECONNECT` | Existing disconnected session is active again |

Event Log is the primary source for lifecycle chronology.

### 4.2 WTS API

The Agent calls native `wtsapi32.dll` functions to enumerate current local Terminal Services sessions.

Only relevant RDP sessions in current `ACTIVE` or `DISCONNECTED` state are included in the snapshot sent to the API.

WTS is the secondary current-state source used to correct drift.

## 5. Scheduled execution

```mermaid
flowchart TB
    Task["Windows Scheduled Task\nevery minute"] --> Agent["Agent.ps1\nruns as SYSTEM"]
    Agent --> Pending["Send pending spool"]
    Pending --> Collect["Collect new Event Log records"]
    Collect --> Events{"New lifecycle events?"}
    Events -- Yes --> Persist["Persist batch in spool"]
    Persist --> Post["POST /agent/events"]
    Post --> Ack{"API acknowledged?"}
    Ack -- Yes --> Checkpoint["Advance checkpoint\nremove spool"]
    Ack -- No --> Keep["Keep spool for retry"]
    Events -- No --> Snapshot
    Checkpoint --> Snapshot{"WTS snapshot due?"}
    Keep --> End["Exit non-zero"]
    Snapshot -- Yes --> WTS["Enumerate WTS sessions"]
    WTS --> PostSnapshot["POST /agent/snapshot"]
    PostSnapshot --> EndOk["Persist snapshot time\nexit"]
    Snapshot -- No --> EndOk
```

## 6. Local persistence

Default runtime path:

```text
C:\ProgramData\RdpSessionAgent\
```

```mermaid
flowchart LR
    Config["config.json"] --> Agent["Agent runtime"]
    Credential["credential.dat\nDPAPI LocalMachine"] --> Agent
    State["state.json"] <--> Agent
    Spool["spool/*.json"] <--> Agent
    Logs["logs/*.log"] <-- Agent
```

### `config.json`

Stores non-secret runtime configuration such as API base URL, server ID, Event Log channel, batch size, and snapshot interval.

### `credential.dat`

Stores the Agent secret encrypted using Windows DPAPI machine scope.

### `state.json`

Stores the Event Log checkpoint and the last successful WTS snapshot timestamp.

### `spool\`

Stores event batches durably before transmission.

## 7. Event delivery reliability

```mermaid
sequenceDiagram
    participant Agent
    participant Disk as Local spool
    participant API

    Agent->>Disk: write event batch
    Agent->>API: POST /agent/events
    alt success
        API-->>Agent: accepted / duplicates
        Agent->>Agent: save checkpoint
        Agent->>Disk: delete acknowledged batch
    else network/API failure
        API--xAgent: request fails
        Agent->>Disk: leave batch intact
        Note over Agent,Disk: next run replays pending spool first
    end
```

The checkpoint advances only after API acknowledgement. This prevents an event batch from being forgotten after a failed request.

The API implements idempotent ingestion, so replaying an already accepted event is safe.

## 8. WTS reconciliation

```mermaid
sequenceDiagram
    participant Task as Scheduled Task
    participant Agent
    participant WTS as Windows WTS API
    participant API

    Task->>Agent: run
    Agent->>Agent: check snapshot interval
    alt snapshot due
        Agent->>WTS: enumerate sessions
        WTS-->>Agent: ACTIVE / DISCONNECTED sessions
        Agent->>API: POST /agent/snapshot
        API-->>Agent: observed / created / updated / closed
        Agent->>Agent: persist successful snapshot time
    else not due
        Agent-->>Task: finish without snapshot
    end
```

WTS allows the central state to recover when:

- an expected Event Log lifecycle record was missed;
- the Agent or API was temporarily unavailable;
- an API session remains open but no longer exists locally.

A missing open session can be closed by the API with:

```text
end_reason=RECONCILIATION
```

## 9. Lifecycle model

The Agent reports transitions; the API owns the consolidated state machine.

```mermaid
stateDiagram-v2
    [*] --> ACTIVE: Event 21 / LOGON
    ACTIVE --> DISCONNECTED: Event 24 / DISCONNECT
    DISCONNECTED --> ACTIVE: Event 25 / RECONNECT
    ACTIVE --> CLOSED: Event 23 / LOGOFF
    DISCONNECTED --> CLOSED: Event 23 / LOGOFF
```

WTS snapshots can independently correct the current `ACTIVE` / `DISCONNECTED` state or cause a missing session to be reconciled closed by the API.

## 10. Authentication and secret handling

```mermaid
flowchart LR
    Secret["One-time Agent secret"] --> Install["Install-Agent.ps1"]
    Install --> DPAPI["credential.dat\nDPAPI LocalMachine"]
    DPAPI --> Agent["Agent runtime as SYSTEM"]
    Config["server_id in config.json"] --> Agent
    Agent -->|"X-Server-ID + Bearer secret"| API["RDP Session API"]
```

Security properties:

- one credential per monitored server;
- plaintext secret is not written to `config.json`;
- installed directory ACL is restricted;
- runtime executes as `SYSTEM`;
- no query API key is stored by the Agent;
- no inbound Agent service is exposed.

## 11. TLS and network model

```mermaid
flowchart LR
    Agent["Windows Server"] -->|"HTTPS :443"| Proxy["API reverse proxy"]
    Proxy --> API["RDP Session API"]
```

The Agent expects the Windows certificate trust store to validate the API endpoint normally. Production deployment should not require certificate-validation bypasses.

## 12. Multi-server deployment

One Agent instance is installed independently on each Windows Server.

```mermaid
flowchart TB
    API["RDP Session API"]
    S1["Server A\nunique server_id + secret"] --> API
    S2["Server B\nunique server_id + secret"] --> API
    S3["Server C\nunique server_id + secret"] --> API
```

Do not clone one server's installed `config.json`, `credential.dat`, or `state.json` to another server. Register and install each server independently.

## 13. Upgrade model

The Git repository checkout and installed runtime are intentionally separate.

```mermaid
flowchart LR
    Git["Git checkout"] -->|"Install-Agent.ps1"| Runtime["C:\\ProgramData\\RdpSessionAgent"]
    Runtime --> Task["Scheduled Task"]
```

After `git pull`, the installer must be run again to refresh the installed runtime and Scheduled Task.

## 14. Current limitations

The current design does not include:

- automatic Agent self-update;
- Windows service packaging;
- a dedicated Event Log reset/gap recovery mechanism beyond WTS reconciliation.
