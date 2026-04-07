# Workflow Engine Internals

This document details the internal architecture of `Athanor.Workflow`, the per-workflow supervision and scheduling system.

## Module Overview

The workflow module consists of five cooperating components:

| Module | Role |
|--------|------|
| `Instance` | Per-workflow `Supervisor` (`:one_for_all`) that bootstraps the entire subtree |
| `Registry` | Workflow definition store (channels, processes, subscriptions) backed by ETS |
| `Scheduler` | Reactive core — maintains buffers, cursors, queue, and dispatch loop |
| `TaskMonitor` | Crash detection via `Process.monitor/1`, escalates failures to Scheduler |
| `Dispatcher` | Pluggable behaviour for sending job vouchers to workers (stub → gRPC) |

## Supervision Tree

```mermaid
graph TB
    subgraph "DynamicSupervisor (Athanor.Workflow.Supervisor)"
        subgraph "Instance (one_for_all)"
            TMReg["Elixir Registry\n:unique keys"]
            Reg["Registry GenServer\nETS-backed definition store"]
            TM["TaskMonitor GenServer\nPID crash detection"]
            Sched["Scheduler GenServer\nreactive queue + dispatch"]
        end
    end

    TMReg -.-> TM

    classDef supervisor fill:#f9d0c4,stroke:#333,stroke-width:2px;
    classDef genserver fill:#d4edda,stroke:#333,stroke-width:2px;
    classDef registry fill:#cce5ff,stroke:#333,stroke-width:2px;

    class TMReg registry;
    class Reg,Sched,TM genserver;
```

## Message Passing Architecture

### Communication Patterns

The system uses three message-passing mechanisms:

| Pattern | Direction | Purpose |
|---------|-----------|---------|
| `GenServer.call` | External → Registry | Register workflow definition (only sync call) |
| `GenServer.cast` | Any → Scheduler / TaskMonitor | Async operations (publish, subscribe, dispatch, monitor) |
| `handle_info` | OTP → TaskMonitor | `:DOWN` messages when task processes crash |

### Full Message Flow Diagram

```mermaid
sequenceDiagram
    participant Ext as External API
    participant Reg as Registry
    participant Sched as Scheduler
    participant TM as TaskMonitor
    participant Disp as Dispatcher
    participant Worker as Quicksilver Worker

    rect rgb(240, 248, 255)
    note over Ext,Reg: Phase 1: Workflow Registration
    Ext->>Reg: call: register_workflow(channels, processes)
    Reg->>Reg: derive_subscriptions from process.input
    Reg->>Reg: write to ETS :athanor_workflows
    end

    rect rgb(255, 248, 240)
    note over Ext,Sched: Phase 2: Process & Subscription Setup
    Ext->>Sched: cast: register_process(process_id, process)
    Sched->>Sched: store in state.processes
    Ext->>Sched: cast: subscribe(channel_id, process_id)
    Sched->>Sched: create subscription with cursor at buffer length
    end

    rect rgb(240, 255, 240)
    note over Ext,Worker: Phase 3: Reactive Execution Loop
    Ext->>Sched: cast: publish(channel_id, artifacts)
    Sched->>Sched: do_append — add to IndexedBuffer
    Sched->>Sched: evaluate_zips — check zip channel readiness
    Sched->>Sched: fan_out — collect new items per subscriber cursor
    Sched->>Sched: enqueue_if_new — CAS dedup via fingerprint

    loop dispatch_next (demand-driven)
        Sched->>Sched: dequeue task from :queue
        Sched->>Disp: build_voucher(workflow_id, task, process)
        Sched->>Disp: dispatch(voucher)
        Disp-->>Worker: job voucher (async, future gRPC)
        Disp-->>Sched: {:ok, fingerprint}
        Sched->>TM: cast: register(fingerprint, task_pid, scheduler)
        TM->>TM: Process.monitor(task_pid)
        TM->>TM: Registry.register(fingerprint, pid)
    end
    end

    rect rgb(255, 240, 245)
    note over Worker,TM: Phase 4: Task Completion
    Ext->>Sched: cast: complete_task(fingerprint, output_artifacts)
    Sched->>Sched: remove from running_tasks
    Sched->>TM: cast: unregister(fingerprint)
    TM->>TM: Process.demonitor(ref, [:flush])
    Sched->>Sched: publish outputs to output_channel
    Sched->>Sched: triggers fan_out for downstream subscribers
    Sched->>Sched: dispatch_next(1)
    end

    rect rgb(255, 250, 240)
    note over Worker,TM: Phase 5: Task Failure (Two Paths)
    Note over Sched,TM: Path A — Clean failure
    Ext->>Sched: cast: fail_task(fingerprint)
    Sched->>Sched: remove from running_tasks + cas_index
    Sched->>TM: cast: unregister(fingerprint)
    Sched->>Sched: dispatch_next(1)

    Note over OTP,TM: Path B — Crash escalation
    Worker--xTM: task process crashes
    OTP-->>TM: handle_info {:DOWN, ref, :process, pid, reason}
    TM->>TM: Registry.unregister(fingerprint)
    alt reason != :normal
        TM->>Sched: cast: fail_task(fingerprint)
    end
    end
```

## Scheduler Internal Pipeline

When `publish/3` is called, the scheduler executes a four-stage pipeline:

```mermaid
flowchart LR
    A["publish(channel_id, artifacts)"] --> B["do_append/3\nAdd to channel IndexedBuffer"]
    B --> C["evaluate_zips/2\nCheck zip channels for ready tuples"]
    C --> D["fan_out/2\nCollect new items per subscriber cursor"]
    D --> E["do_dispatch_next/2\nDrain queue up to demand"]

    C -.->|"recursive"| C
    E -->|"on dispatch error"| F["re-enqueue + remove from CAS"]
    E -->|"on success"| G["add to running_tasks\nregister with TaskMonitor"]

    classDef stage fill:#d4edda,stroke:#333,stroke-width:2px;
    classDef error fill:#f8d7da,stroke:#333,stroke-width:2px;
    classDef success fill:#cce5ff,stroke:#333,stroke-width:2px;

    class A,B,C,D,E stage;
    class F error;
    class G success;
```

## Data Flow: Artifact Publication to Task Dispatch

```mermaid
flowchart TB
    subgraph "Input"
        Pub["Quicksilver publishes ArtifactRefs"]
    end

    subgraph "Scheduler State"
        Buf["IndexedBuffer\nper-channel append-only buffer"]
        Subs["Subscriptions\nchannel → [{process_id, cursor}]"]
        Queue[":queue\nFIFO task queue"]
        CAS["CAS Index\nMapSet of fingerprints"]
        Running["running_tasks\nfingerprint → task"]
    end

    subgraph "Output"
        Voucher["Job Voucher"]
        Monitor["TaskMonitor registration"]
    end

    Pub -->|"append"| Buf
    Buf -->|"scan new items since cursor"| Subs
    Subs -->|"for each new item"| Dedup{"fingerprint\nin CAS?"}
    Dedup -->|"no"| Queue
    Dedup -->|"yes"| Skip["skip (idempotent)"]
    Queue -->|"drain up to demand"| Dispatch["build_voucher + dispatch"]
    Dispatch -->|"on success"| Voucher
    Dispatch -->|"on success"| Monitor
    Dispatch -->|"on error"| Queue
    Dispatch -->|"on success"| Running
```

## Zip Channel Evaluation

Zip channels synchronize multiple upstream channels into a single tuple stream:

```mermaid
flowchart TD
    A["evaluate_zips/2"] --> B{"any zip channel\nhas all upstreams ready\nat current cursor?"}
    B -->|"no"| C["return"]
    B -->|"yes"| D["pull one item from each upstream"]
    D --> E["create zipped tuple"]
    E --> F["append to zip channel buffer"]
    F --> G["trigger fan_out on zip channel"]
    G --> H["recursive evaluate_zips\n(cascading zips)"]
    H --> A
```

## Key Design Decisions

### Read-Optimized Registry

The Registry uses `GenServer.call` for the single write operation (`register_workflow`) but **direct ETS reads** for all reads (`get_subscriptions`, `get_process`, `get_channels`). This eliminates the GenServer mailbox as a bottleneck for read-heavy workloads.

### CAS Deduplication

Tasks are fingerprinted via SHA-256 of their process definition + inputs. The fingerprint is added to a `MapSet` before queuing. If the same fingerprint already exists, the task is skipped — providing idempotent execution even if inputs are published multiple times.

### Cursor-Based Fan-Out

Each subscriber to a channel maintains an independent cursor. When artifacts are appended, the scheduler collects only items the subscriber hasn't seen yet (items at or after the cursor). This ensures:

- No lost messages — every artifact reaches every subscriber
- No double-processing — each item is delivered exactly once per subscriber
- Independent pacing — slow subscribers don't block fast ones

### Crash Escalation

The TaskMonitor uses `Process.monitor/1` on each task PID. If a task crashes unexpectedly (reason ≠ `:normal`), the `:DOWN` message triggers automatic escalation: the TaskMonitor calls `Scheduler.fail_task/2`, which removes the task from running state and allows the next queued task to dispatch.

### Pluggable Dispatcher

The Dispatcher is a behaviour with a stub implementation. The real gRPC implementation is swapped in via application config (`Application.get_env(:athanor, :dispatcher_impl)`) without changing any scheduler code.
