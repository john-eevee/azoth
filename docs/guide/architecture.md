# Azoth Architecture

This document defines the intended direction for Azoth — a distributed reactive workflow platform composed of two sub-systems:

- `Athanor`: the control-plane for parsing workflows, maintaining state, scheduling work, and exposing UI/API surfaces.
- `Quicksilver`: the worker and data-plane for staging inputs, executing jobs, streaming logs, and publishing task results.

## Goals

### Product Goals

- Deliver a reactive workflow system over a traditional batch scheduler.
- Execute tasks reactively as data becomes available through channels.
- Make resumability and cache correctness first-class features.
- Keep the control-plane lightweight even for very large datasets.
- Support multiple execution backends without changing workflow definitions.

### Engineering Goals

- Use Elixir and OTP for orchestration, retries, supervision, and visibility.
- Use deterministic workflow definitions via KDL (Keyword Document Language).
- Use Rust for performance-sensitive worker, hashing, and runtime integration paths.
- Use gRPC for strongly typed control-plane to worker communication.
- Design for failure as a normal operating condition.

## Non-Goals For Early Versions

- Full multi-cloud feature parity on day one.
- Perfect abstraction for every scheduler or storage backend.
- General-purpose arbitrary scripting in the workflow DSL.

## Architecture Overview

```mermaid
flowchart TB
    subgraph CP["Control-Plane: Athanor (Elixir/OTP)"]
        direction TB
        Parser["DSL.Parser\nRust NIF → WorkflowPlan IR"]
        GlobRes["Storage.GlobResolver\nExpands input path channels"]
        AppSup["Athanor.Application\nTop-level Supervisor + ETS owner"]
        WfSup["Workflow.Supervisor\nDynamicSupervisor"]
        subgraph Instance["Workflow.Instance (one_for_all, per workflow_id)"]
            TMReg["TaskMonitor.Registry\nElixir Registry — fingerprint→PID"]
            Reg["Workflow.Registry\nETS-backed definition store"]
            TM["Workflow.TaskMonitor\nPID monitor + crash escalation"]
            Sched["Workflow.Scheduler\nIndexedBuffer · cursors · zip · CAS · queue"]
        end
        Disp["Workflow.Dispatcher\nBehaviour (StubDispatcher → gRPC)"]
    end

    subgraph DP["Data-Plane: Quicksilver (Rust)"]
        Agent["Worker Agent\ngRPC client"]
        Stage["Data Staging\nDirect pull from object store"]
        Exec["Executor Adapter\nDocker / Firecracker"]
        GlobScan["Output Glob Scanner\nPost-execution output discovery"]
        Logs["Log Streamer\nstdout/stderr → Athanor"]
    end

    subgraph Store["Object Storage"]
        S3[(S3 / GCS / NFS)]
    end

    User["User Workflow\n(KDL source)"] -->|"submit source"| Parser
    Parser -->|"WorkflowPlan IR"| AppSup
    AppSup -->|"resolve input path channels"| GlobRes
    GlobRes -->|"seed ArtifactRefs"| Sched
    AppSup -->|"start_child"| WfSup
    WfSup -->|"spawn Instance"| Instance
    Reg -->|"ETS read: channels + subscriptions"| Sched
    Sched -->|"build_voucher + dispatch"| Disp
    Disp -->|"job voucher (gRPC)"| Agent
    Agent --> Stage
    Stage -->|"pull inputs"| S3
    Stage --> Exec
    Exec --> GlobScan
    GlobScan -->|"upload matched files"| S3
    Exec --> Logs
    Logs -->|"heartbeats + logs"| Sched
    GlobScan -->|"publish ArtifactRefs"| Sched
    Sched -->|"unregister on complete/fail"| TM
    TM -->|"monitor PID"| TMReg

    classDef elixir fill:#4e2a8e,stroke:#fff,color:#fff;
    classDef rust fill:#dea584,stroke:#2b2b2b,color:#2b2b2b;
    classDef storage fill:#2b5a3e,stroke:#fff,color:#fff;
    class Parser,GlobRes,AppSup,WfSup,TMReg,Reg,TM,Sched,Disp elixir;
    class Agent,Stage,Exec,GlobScan,Logs rust;
    class S3 storage;
```

## Core Pillars

### 1. Dataflow Over Static DAG Execution

Athanor should behave like a dataflow engine. Instead of only evaluating fixed task-to-task edges, tasks should become runnable when the required inputs arrive on their channels.

Traditional DAG schedulers fail for bioinformatics workloads because genomic tools frequently generate a dynamic number of output files — splitting a genome into chromosome chunks, for example, yields an unpredictable count of `.fa` files that cannot be hardcoded into a static output declaration. Azoth solves this by delegating output discovery to Quicksilver at runtime and modelling channels as append-only streams.

Implications:

- The scheduler must be event-driven.
- Runtime state must track channel materialization, not only task completion.
- Parallelism is discovered at runtime, not planned at parse time.
- Process `outputs` declarations may be glob patterns; Quicksilver resolves them after execution.
- Channels are **append-only streams**, not queues — items are never consumed or destroyed.

### 2. Deterministic Workflow Logic

The workflow definition layer should be embedded and constrained. KDL (Keyword Document Language) fits because it is deterministic, familiar, and safer than unconstrained scripting. The KDL source is parsed by a Rust NIF (`athanor_parser` via Rustler) that produces a stable JSON Intermediate Representation (`WorkflowPlan`), which is then decoded into Elixir data structures.

Implications:

- Workflow parsing should produce a stable execution plan with a deterministic SHA-256 fingerprint.
- The DSL should describe processes, inputs, outputs, resources, and runtime hints.
- Parsing work is isolated from scheduler-sensitive paths via the NIF boundary.

### 3. Control-Plane / Data-Plane Separation

Large datasets should never flow through the control-plane. Athanor dispatches intent; Quicksilver performs the heavy lifting.

Implications:

- Athanor sends signed job vouchers, not payload-heavy work packets.
- Quicksilver pulls data directly from object stores or shared filesystems.
- Logs, heartbeats, and status updates return asynchronously.

### Channel Materialization Detail

```mermaid
graph TB
    subgraph "Athanor: Reactive Control Plane"
        Sched["Workflow.Scheduler\nIndexedBuffer per channel"]
        CAS["CAS Index\nMapSet of fingerprints"]
        ETS["Workflow.Registry\nETS :athanor_workflows"]
        Disp["Workflow.Dispatcher\nbehaviour (StubDispatcher → gRPC)"]
    end

    subgraph "Data Plane: Quicksilver"
        QW["Worker Agent"]
        GlobScan["Output Glob Scanner\npost-execution output scan"]
        S3[(Storage: S3/GCS/NFS)]
    end

    %% Flow 1: Materialization
    QW -- "1. Publish ArtifactRefs (gRPC callback)" --> Sched
    Sched -- "2. do_append → IndexedBuffer.append" --> Sched
    Sched -- "3. evaluate_zips (zip channel sync)" --> Sched
    ETS -- "ETS direct read: get_subscriptions" --> Sched
    Sched -- "4. fan_out → advance cursors" --> CAS

    %% Flow 2: Dispatch
    CAS -- "5. enqueue_if_new (CAS dedup)" --> Sched
    Sched -- "6. do_dispatch_next → build_voucher" --> Disp
    Disp -- "7. dispatch job voucher (gRPC)" --> QW

    %% Flow 3: Data Locality
    S3 -- "8. Direct pull (inputs)" --> QW
    QW -- "9. Execute in isolation" --> GlobScan
    GlobScan -- "10. Upload matched files" --> S3

    classDef elixir fill:#4e2a8e,stroke:#fff,color:#fff;
    classDef rust fill:#dea584,stroke:#2b2b2b,color:#2b2b2b;
    class Sched,CAS,ETS,Disp elixir;
    class QW,GlobScan rust;
```

## Per-Workflow Supervision Tree

Athanor implements each workflow as an isolated OTP supervision tree via `Athanor.Workflow.Supervisor` (DynamicSupervisor). Each workflow instance has its own `Athanor.Workflow.Instance` (`:one_for_all` Supervisor) containing four children started in dependency order:

1. **TaskMonitor.Registry** — Elixir `Registry` (`:unique` keyed by fingerprint). Must start first; used by `TaskMonitor` for O(1) PID lookups.
2. **Workflow.Registry** — GenServer with ETS backing (`:athanor_workflows` table). Stores channels, processes, subscriptions, and a name index. All reads bypass the GenServer mailbox and go directly to ETS.
3. **Workflow.TaskMonitor** — GenServer that monitors running task PIDs via `Process.monitor/1`. On unexpected crash (reason ≠ `:normal`), calls `Scheduler.fail_task/2` to transition the task to failed state and free the concurrency slot.
4. **Workflow.Scheduler** — GenServer that maintains reactive state: per-channel `IndexedBuffer`s, per-subscription cursors, zip channel state, a FIFO task queue, a CAS deduplication index (`MapSet` of fingerprints), and the running tasks map.

```mermaid
graph TB
    subgraph AppSup["Athanor.Application (one_for_one)"]
        WfReg["Elixir Registry\nAthanor.Workflow.Registry\n(process name lookup)"]
        DynSup["Athanor.Workflow.Supervisor\n(DynamicSupervisor)"]
    end

    subgraph Instance["Athanor.Workflow.Instance (one_for_all, per workflow_id)"]
        TMReg["1. TaskMonitor.Registry\nElixir Registry :unique\nfingerprint → PID"]
        Reg["2. Workflow.Registry\nGenServer + ETS :athanor_workflows\nchannels · processes · subscriptions · names_index"]
        TM["3. Workflow.TaskMonitor\nGenServer\nProcess.monitor + crash escalation"]
        Sched["4. Workflow.Scheduler\nGenServer\nIndexedBuffer · cursors · zip · CAS · queue"]
    end

    User["User / API"] -->|"DynamicSupervisor.start_child\n{Instance, workflow_id: id}"| DynSup
    DynSup -->|"spawn"| Instance
    TMReg -.->|"Registry.lookup (O(1))"| TM
    Reg -->|"ETS direct read"| Sched
    TM -->|"cast: fail_task on :DOWN"| Sched
    Sched -->|"cast: unregister on complete/fail"| TM

    classDef sup fill:#f9d0c4,stroke:#333,stroke-width:2px;
    classDef genserver fill:#d4edda,stroke:#333,stroke-width:2px;
    classDef registry fill:#cce5ff,stroke:#333,stroke-width:2px;

    class DynSup,AppSup,Instance sup;
    class Reg,TM,Sched genserver;
    class WfReg,TMReg registry;
```

**Isolation**: One workflow crash or high concurrency spike does not affect others. Each Instance is independently supervised and can be stopped/restarted.

**Registration**: All GenServer names use `{:global, "string_name"}` instead of dynamic atoms to avoid atom table exhaustion. This is critical for systems that manage many workflows.

**Fingerprinting**: Each task is uniquely identified by `Workflow.Fingerprinting.fingerprint/1` — a SHA-256 of the process image, command, output search patterns, and sorted input artifact URIs/hashes. The Scheduler uses a CAS index (`MapSet` of fingerprints) to prevent duplicate task dispatch if the same inputs are published multiple times.

## Channel Semantics: Streams, Not Queues

Channels are **append-only streams of immutable `ArtifactRef` values** backed by `Athanor.IndexedBuffer`. This distinction is critical:

- **Publishers** (Quicksilver workers) append items to the tail of a channel.
- **Subscribers** (downstream processes) maintain a cursor — an index of the last item they have seen. They read items without removing them.
- Multiple downstream processes can subscribe to the same channel independently. Each holds its own cursor and processes every item at its own pace.

This means a downstream process can never "starve" a sibling by consuming shared data. If Process B and Process C both subscribe to the output of Process A, each receives all items regardless of ordering or speed.

```
Channel (IndexedBuffer — append-only stream)
  index 0: ArtifactRef(chr1.fa)   ← Process B cursor: 3 (done)
  index 1: ArtifactRef(chr2.fa)       Process C cursor: 1 (in progress)
  index 2: ArtifactRef(chr3.fa)
  ...
```

### Zip Channels

A `zip` channel synchronises multiple upstream channels into a single tuple stream. The Scheduler evaluates zip readiness in `evaluate_zips/2` after every `publish`. A zipped item is emitted only when all upstream channels have an item at the current zip cursor. Cascading zips (a zip depending on another zip) are handled via recursion.

## Dynamic Pub/Sub Lifecycle

Because genomic tools generate an unpredictable number of output files, Athanor cannot resolve output paths at parse time. Instead, output discovery is delegated to Quicksilver at runtime using glob patterns.

### Lifecycle Steps

1. **Subscription (Athanor)**: During workflow registration, `Workflow.Registry` derives that Process B subscribes to the output channel of Process A. No file counts or paths are assumed. The Scheduler sets Process B's cursor to the current channel length so only future arrivals trigger tasks.
2. **Execution (Quicksilver)**: Quicksilver runs Process A. The tool may generate any number of output files (e.g., `chr1.fa … chr24.fa`).
3. **Publication (Quicksilver)**: After the container exits, Quicksilver scans the working directory against the declared output glob (e.g., `./chunks/*.fa`). It uploads matching files to object storage, computes content hashes, and publishes an array of `ArtifactRef` values back to Athanor over gRPC.
4. **Fan-out (Athanor)**: The Scheduler appends the new `ArtifactRef` items via `do_append`, runs `evaluate_zips`, then `fan_out`. Fan-out detects that Process B subscribes to this channel and enqueues one `Task` per new item (deduped by CAS fingerprint). `do_dispatch_next` dispatches tasks up to the concurrency gate.

This keeps Athanor entirely ignorant of filesystem layout; all path resolution stays in the data-plane.

```mermaid
sequenceDiagram
    participant A as Athanor (Scheduler)
    participant Q1 as Quicksilver (Process A)
    participant C as Channel (IndexedBuffer)
    participant Q2 as Quicksilver (Process B)

    A->>Q1: Dispatch job voucher (output_search_patterns: ["./chunks/*.fa"])
    Note over Q1: Tool generates N dynamic files
    Q1->>A: Publish [chr1.fa, chr2.fa, chr3.fa] as ArtifactRefs
    A->>C: do_append → IndexedBuffer.append (3 items at indices 0–2)
    Note over A,C: Process B subscribed at cursor 0
    A->>A: evaluate_zips (no zip dependency here)
    A->>A: fan_out → advance Process B cursor to 3, enqueue 3 tasks
    A->>A: do_dispatch_next → CAS dedup, build_voucher, dispatch
    A->>Q2: Dispatch TaskRun (chr1.fa)
    A->>Q2: Dispatch TaskRun (chr2.fa)
    A->>Q2: Dispatch TaskRun (chr3.fa)
```

## Design Choices

### Elixir and OTP for Athanor

- Good fit for supervision trees, retries, and distributed state management.
- Can model many concurrent task coordinators efficiently.
- Supports UI/API integration well through Phoenix-style patterns.

Primary risk:

- Long-running native work must not starve schedulers.

### KDL for the DSL

- Deterministic and constrained — stable hashes across re-runs.
- Human-readable with familiar block syntax.
- Parsed by a Rust NIF (`athanor_parser` via Rustler), returning a JSON `WorkflowPlan` IR that is decoded into Elixir data structures.
- The IR is independently fingerprinted (SHA-256) before any execution state is attached.

Primary risk:

- Complex parsing or evaluation paths must be offloaded from latency-sensitive orchestration loops. The NIF boundary already isolates this.

### Rust for Quicksilver and Low-Level Services

- Strong fit for hashing, file operations, worker agents, and runtime integration.
- Gives predictable performance for staging and executor control.
- Works well for building gRPC services and isolation adapters.
- The `athanor_parser` NIF is already implemented in Rust.

### Firecracker as a Premium Isolation Path

- Strong isolation boundary for messy scientific tooling.
- Fast startup relative to traditional virtual machines.
- Clear fit for secure task execution.

Primary risk:

- Requires KVM or nested virtualization support.
- Introduces operational complexity around networking, image distribution, and host permissions.

### gRPC Between Planes

- Enforces typed contracts.
- Suitable for status streams, heartbeats, and task dispatch.
- Easier to evolve than ad hoc payload protocols.
- The `Dispatcher` behaviour abstracts the transport: `StubDispatcher` is used during development and testing; the real gRPC implementation is swapped in via `Application.get_env(:athanor, :dispatcher_impl)` without changing any Scheduler code.

### Metadata Storage

- Start local with SQLite or DuckDB.
- Optimize for fast task history and cache lookup queries.
- Leave room for a later multi-node metadata backend if scale requires it.

## Reference Task Flow

```mermaid
sequenceDiagram
    participant U as User
    participant P as DSL.Parser (Rust NIF)
    participant GR as Storage.GlobResolver
    participant A as Athanor (Scheduler)
    participant D as Workflow.Dispatcher
    participant Q as Quicksilver (Worker)
    participant S as Object Storage
    participant R as Isolation Runtime

    U->>P: Submit KDL workflow source
    P->>P: parse_workflow/1 → WorkflowPlan IR (JSON)
    P-->>A: Decoded IR (channels, processes, subscriptions)
    A->>GR: Resolve input path channels (glob URIs)
    GR-->>A: Seed ArtifactRefs for input channels
    A->>A: Register workflow (Registry + ETS), derive subscriptions
    A->>A: publish seed artifacts → fan_out → enqueue tasks
    A->>A: Check CAS fingerprint index (skip cached tasks)
    A->>D: build_voucher(workflow_id, task, process)
    D->>Q: Dispatch signed job voucher (gRPC)
    Q->>S: Pull inputs by URI (direct — never via Athanor)
    Q->>R: Start isolated task (Docker / Firecracker)
    R-->>Q: Stream stdout and stderr
    Q-->>A: Heartbeats and log lines
    R->>Q: Task exits
    Q->>Q: Resolve output_search_patterns against working directory
    Q->>S: Upload matched files, compute content hashes
    Q-->>A: Publish ArtifactRefs for all resolved outputs
    A->>A: do_append → evaluate_zips → fan_out → dispatch downstream tasks
    A-->>U: Update UI and downstream readiness
```

## Data-Plane Interaction Graph

This graph shows the full control-plane / data-plane boundary and every data movement path. The key invariant: Athanor only ever sees URIs and content hashes (`ArtifactRef`). Bulk data — input files, output files, log payloads — never traverses the control-plane.

```mermaid
flowchart TB
    subgraph CP["Control-Plane: Athanor (Elixir/OTP)"]
        Sched["Workflow.Scheduler\nfan-out · CAS · queue"]
        Disp["Workflow.Dispatcher\n(StubDispatcher → gRPC)"]
        GlobRes["Storage.GlobResolver\ninput channel seeding"]
    end

    subgraph DP["Data-Plane: Quicksilver (Rust)"]
        Agent["Worker Agent\ngRPC client"]
        Staging["Data Staging\ndirect pull"]
        Runtime["Isolation Runtime\nDocker / Firecracker"]
        GlobScan["Output Glob Scanner\npost-execution"]
        LogStreamer["Log Streamer\nstdout/stderr"]
    end

    subgraph Store["Object Storage"]
        InputStore[(Input Artifacts\nS3 / GCS / NFS)]
        OutputStore[(Output Artifacts\nS3 / GCS / NFS)]
    end

    %% ① Control path — voucher only, never payload
    Sched -->|"① job voucher\nimage · command · input URIs\noutput patterns · fingerprint"| Disp
    Disp -->|"② dispatch (gRPC)"| Agent

    %% ③ Data pull — bypasses control-plane entirely
    Agent --> Staging
    Staging -->|"③ pull inputs by URI"| InputStore

    %% ④ Execution
    Staging -->|"④ stage inputs"| Runtime

    %% ⑤⑥ Log streaming — metadata only, not payload
    Runtime -->|"⑤ stdout/stderr"| LogStreamer
    LogStreamer -->|"⑥ heartbeats + log lines"| Sched

    %% ⑦⑧⑨ Output discovery
    Runtime -->|"⑦ task exits"| GlobScan
    GlobScan -->|"⑧ upload matched files + compute hashes"| OutputStore
    GlobScan -->|"⑨ ArtifactRefs (URIs + hashes only)"| Sched

    %% ⑩ Input seeding — URIs only, no payload through control-plane
    GlobRes -->|"⑩ seed ArtifactRefs (URIs only)"| Sched
    InputStore -.->|"backing store"| GlobRes

    classDef cp fill:#4e2a8e,stroke:#fff,color:#fff;
    classDef dp fill:#dea584,stroke:#2b2b2b,color:#2b2b2b;
    classDef store fill:#2b5a3e,stroke:#fff,color:#fff;
    class Sched,Disp,GlobRes cp;
    class Agent,Staging,Runtime,GlobScan,LogStreamer dp;
    class InputStore,OutputStore store;
```

## Reactive Scheduler Execution Flow

The Scheduler implements a pull-based task dispatch model. Every `publish` call triggers a four-stage synchronous pipeline inside the GenServer:

1. **`do_append`**: Appends new `ArtifactRef` items to the target channel's `IndexedBuffer`. Indices are stable and never reused.

2. **`evaluate_zips`**: Checks whether any zip channel depending on the updated channel has all upstream channels ready at the current zip cursor. If so, pulls one item from each upstream, emits a zipped tuple, appends it to the zip channel buffer, and recurses to handle cascading zip dependencies.

3. **`fan_out`**: For each subscriber to the channel, reads items since the subscription cursor via `IndexedBuffer.from_cursor/2`. For each new item, calls `enqueue_if_new`: computes the task fingerprint, skips if the CAS index already contains it, otherwise appends to the FIFO queue and adds to the CAS index. Advances the cursor.

4. **`do_dispatch_next`**: Dequeues tasks and dispatches them via `Dispatcher.build_voucher/3` + `Dispatcher.dispatch/1` until demand is met or the queue is empty. On success, adds to `running_tasks` and registers with `TaskMonitor`. On error, re-enqueues at the back and removes from the CAS index so the task can be re-fingerprinted.

```mermaid
sequenceDiagram
    participant Q as Quicksilver (Process A)
    participant Sched as Workflow.Scheduler
    participant IB as IndexedBuffer (per channel)
    participant Subs as Subscriptions (cursors)
    participant CAS as CAS Index (MapSet)
    participant Disp as Workflow.Dispatcher
    participant TM as Workflow.TaskMonitor

    Q->>Sched: cast: publish(channel_id, [ArtifactRef])
    Sched->>IB: do_append → IndexedBuffer.append
    Sched->>Sched: evaluate_zips (zip channel readiness check)
    Sched->>Subs: fan_out → from_cursor(buf, cursor) per subscriber
    loop for each new item per subscriber
        Sched->>CAS: fingerprint in CAS? → skip if yes
        CAS-->>Sched: no → :queue.snoc(task) + MapSet.put(fingerprint)
    end
    Sched->>Disp: do_dispatch_next → build_voucher + dispatch
    Disp-->>Q: job voucher (async)
    Disp-->>Sched: {:ok, fingerprint}
    Sched->>TM: cast: register(fingerprint, task_pid, scheduler_pid)
    TM->>TM: Process.monitor(task_pid)
    TM->>TM: Registry.register(fingerprint, pid)

    Note over Q,TM: Path A — clean completion
    Q->>Sched: cast: complete_task(fingerprint, [output ArtifactRefs])
    Sched->>TM: cast: unregister(fingerprint)
    TM->>TM: Process.demonitor(ref, [:flush])
    Sched->>IB: do_append(output_channel_id, output_artifacts)
    Sched->>Sched: evaluate_zips + fan_out (trigger downstream)
    Sched->>Sched: do_dispatch_next(1)

    Note over Q,TM: Path B — unexpected crash
    Q--xTM: task process crashes
    TM->>TM: handle_info {:DOWN, ref, :process, pid, reason}
    alt reason != :normal
        TM->>Sched: cast: fail_task(fingerprint)
        Sched->>Sched: remove from running_tasks
        Sched->>Sched: do_dispatch_next(1)
    end
```

## Milestones

```mermaid
gantt
    title Azoth to v1.0
    dateFormat  YYYY-MM-DD
    axisFormat  %b
    section Foundation
    Runner                :done, m1, 2026-03-01, 14d
    DAG Scheduling        :active, m2, after m1, 21d
    section Resumability
    Content Hashing       :m3, after m2, 30d
    Cache Lookup          :m4, after m3, 21d
    section Distribution
    Remote Workers        :m5, after m4, 45d
    Heartbeats and Retry  :m6, after m5, 21d
    section Data Plane
    Cloud Staging         :m7, after m6, 45d
    Runtime Isolation     :m8, after m7, 30d
```

## Hard Problems To Design For

- Cache invalidation across code, inputs, and runtime versions.
- Worker discovery and health tracking.
- Fast log streaming without overloading the control-plane.
- Large image distribution and cold start latency.
- Partial failures such as disk exhaustion, transient network loss, and interrupted uploads.
- Firecracker infrastructure constraints such as KVM availability and nested virtualization support.
- Dynamic output cardinality: glob resolution on the worker must be atomic with the upload step to avoid partial publications on failure.
- Cursor management for channel subscribers: cursors must be durable and recoverable after control-plane restart.
- Zip channel cursor durability: zip cursors live in Scheduler in-memory state and are lost on restart.
