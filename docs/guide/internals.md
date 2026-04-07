# Engine Internals (How Things Work)

Athanor and Quicksilver orchestrate reactive dataflows by utilizing an event-driven control plane and isolated Rust runtime workers.

## Control-Plane Execution Flow

### 1. Parsing & IR Generation
When a Starlark DSL script is submitted to **Athanor**, the Elixir application invokes the `athanor_parser` library (written in Rust using Rustler).
- The DSL is evaluated in a constrained Starlark environment.
- Processes are instantiated with bound inputs/outputs but are **not executed**.
- A deterministic Intermediate Representation (IR) is returned back to Elixir.

### 2. Channels and State Machine
Athanor translates the IR into its internal domain model (`Workflow`, `Process`, `Channel`, `ArtifactRef`).
- **Channels** are append-only streams of data.
- **Subscribers** (downstream processes) maintain read cursors.
- A process becomes **runnable** only when its input channels receive items at its current cursor, decoupling logical completion from execution readiness.

### 3. Reactive Scheduling
The OTP scheduler manages state transitions using supervised agents.
- When inputs arrive, Athanor generates a `TaskFingerprint` based on the IR (image + command + inputs + resources) and content hashes of the `ArtifactRef`.
- If the fingerprint exists in the cache, the process is skipped.
- Otherwise, a **Signed Job Voucher** is issued and placed onto the runnable queue.

## Data-Plane Execution Flow

### 4. Quicksilver Workers
**Quicksilver** Rust agents lease runnable task vouchers via long-polling or heartbeats.
- The worker isolates the task within a Container or Firecracker microVM.
- Data staging occurs directly between the storage layer (S3, GS, NFS) and the worker node.
- **Crucial**: The actual payload data never traverses Athanor's control plane.

### 5. Dynamic Fan-Out and Glob Resolution
If a process generates a dynamic number of outputs (e.g. `outputs=["./chunks/*.fa"]`), Quicksilver acts after the command completes:
- It scans the working directory for matching files.
- Each file is pushed to object storage.
- An array of generated `ArtifactRefs` is sent to Athanor.
- Athanor pushes these to the downstream channels, triggering parallel fan-out executions instantly.