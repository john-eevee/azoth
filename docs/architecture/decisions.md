# Key Design Decisions

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
