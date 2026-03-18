# Azoth Implementation Plan

## Overview

Phase-by-phase plan for Azoth (Athanor control-plane + Quicksilver data-plane) to deliver a production-grade reactive workflow engine with deterministic DSL, resumability, and distribution.

## Key Constraints

- Determinism: DSL produces stable plans and stable hashes
- Control-plane should not carry data payloads
- Resumability correctness over speed
- Fault-first design (worker loss, partial uploads, retries)
- Incremental scope: local runner before distributed complexity
- Validate execution model before investing in parser surface
- Channels are append-only streams; subscribers hold cursors and must never destroy items

## Risk Areas

- Over-building distributed parts before nailing local deterministic planner
- Tight coupling between parser/scheduler/executor without stable IR boundary
- Cache key incompleteness causing false cache hits
- Schema churn if task/job state machine not formalized first
- Firecracker introduced too early (ops burden + nested virt constraints)
- Reactive channel semantics designed without fingerprint model in place
- Security trust boundary for control/data split left implicit until too late
- Dynamic output glob resolution: partial publication on worker failure must not corrupt channel state
- Subscriber cursor durability: cursors lost on control-plane restart cause duplicate or missed fan-out dispatches

---

## Phase 0 — Foundation + Contracts

### AZ-001: Define Domain Model
- Workflow, Process, Channel, TaskRun, ArtifactRef, TaskFingerprint
- Determine data structures and validation rules

### AZ-002: Task Lifecycle State Machine
- Define valid transitions (pending → running → succeeded/failed → retrying → cancelled)
- Document lifecycle guarantees and idempotency rules

### AZ-003: Architecture Decision Records
- Persistence choice (SQLite first, Postgres-ready schema)
- Hashing scope and cache validity
- Dispatch model (pull-based leasing recommended)

### AZ-004: Test Strategy
- Unit tests (planner/state machine)
- Integration tests (runner)
- Fault tests (retry/heartbeat)
- Event log and replay harness design: the append-only event log is the
  foundational test mechanism for Phase 3 (reactive scheduler) and Phase 9
  (chaos injection); the harness shape must be decided here even if the
  implementation lands later

**Exit Criteria**: Canonical model + lifecycle docs + executable test skeleton + replay harness design doc

---

## Phase 1 — Local Runner (MVP Execution)

Build the execution core first. The runner is the load-bearing invariant of
the whole system. Validating concurrency, retry, and state transitions against
a simple JSON/YAML manifest costs far less than discovering execution model
problems after the Starlark parser is already in place.

### AZ-101: Process Launcher
- Bounded concurrency executor
- Captures stdout/stderr/exit codes

### AZ-102: Run Metadata Persistence
- Store status, logs, exit codes, timestamps
- SQLite-backed local store (Postgres-ready schema)

### AZ-103: Structured Log Streaming
- Emit structured events (task started, stdout line, task completed/failed)
  to a local append-only event log
- Provide a basic read-path: tail-follow and query by run/task ID
- This is the minimum observability surface needed to develop and debug all
  subsequent phases; full API and dashboards come later in Phase 8

### AZ-104: DAG Executor
- Dependency-aware execution (ready tasks → running → completed)
- Transition handling and error propagation

### AZ-105: Retry Policy
- Max attempts, backoff strategies, retryable failure detection

**Exit Criteria**: Multi-step local workflow defined in JSON/YAML executes with
structured logs, retry behavior, and a queryable event log

**Status**: ✅ COMPLETE (2026-03-16)

**Implementation Details**:
- **Supervision Tree**: Each workflow spawned via `Athanor.Workflow.Supervisor` DynamicSupervisor gets an isolated Instance (one_for_all Supervisor) containing Registry, Scheduler, and TaskMonitor.
- **Registration**: All GenServer names use `{:global, "string_name"}` to prevent atom table exhaustion with many workflows.
- **Reactive Scheduler**: `Workflow.Scheduler` GenServer implements fan-out on channel append. Enqueues one task per artifact per subscriber, deduplicates via CAS (content-addressable storage) index keyed by fingerprint, gates concurrency via max_concurrency, and drains queue on task completion.
- **Dispatcher**: `Workflow.Dispatcher` behaviour with `StubDispatcher` implementation for Phase 1. Logs full job voucher (image, command, inputs, output_search_patterns, resources, fingerprint) and returns `{:ok, fingerprint}` synchronously. Real gRPC dispatch comes in Phase 5.
- **Task Monitor**: `Workflow.TaskMonitor` wraps Elixir Registry (keyed by fingerprint) and monitors running task PIDs. On crash, auto-calls `Scheduler.fail_task/2` for recovery.
- **Fingerprinting**: Fixed crypto pipeline bug in `Fingerprinting.fingerprint/1`; now uses `then(&:crypto.hash(:sha256, &1))` instead of pipe syntax.
- **Tests**: 73 tests total (13 doctests + 60 unit tests), all passing, zero warnings. Coverage includes fan-out with multiple artifacts/subscribers, CAS deduplication, concurrency gating, task transitions, downstream publish chain, and multi-subscriber independence.

**Files Created/Modified**:
- `lib/athanor/workflow.ex` — stripped nested Scheduler, added module docs with supervision and messaging diagrams
- `lib/athanor/workflow/scheduler.ex` — 340 lines, promoted from nested module, fixed bugs, complete fan-out implementation
- `lib/athanor/workflow/registry.ex` — 165 lines, workflow entity store + subscription derivation
- `lib/athanor/workflow/dispatcher.ex` — 80 lines, Dispatcher behaviour + StubDispatcher
- `lib/athanor/workflow/task_monitor.ex` — 170 lines, Elixir Registry wrapper + PID monitor
- `lib/athanor/workflow/instance.ex` — 45 lines, thin one_for_all Supervisor
- `lib/athanor/application.ex` — added DynamicSupervisor for workflows
- `test/athanor/workflow/scheduler_test.exs` — 400+ lines, 60 comprehensive tests

---

## Phase 2 — DSL Parser + Deterministic Plan IR

Now that the execution model is validated, introduce the Starlark parser as an
input surface that compiles down to the IR the runner already understands. The
parser's only job is to produce a stable, correct plan; the runner does not
change.

### AZ-201: Starlark Parser Boundary
- Implement parser layer and AST validation
- Handle `process`, `channel`, `workflow` primitives from DSL spec

### AZ-202: Canonical IR Serializer
- Build order-stable IR for deterministic hashing
- JSON encoding for reproducible fingerprints (Protobuf can replace it later
  when the wire format is needed for gRPC in Phase 6)

### AZ-203: DSL Linting & Validation
- Required fields, resource schema, command placeholder validation
- Error messages and recovery

### AZ-204: Golden Tests
- Same input produces byte-identical IR/hash
- Regression tests for parser behavior

**Exit Criteria**: Parse `dsl.md` examples into stable IR; runner executes
Starlark-defined workflows end-to-end with deterministic snapshots

**Status**: ✅ COMPLETE

**Implementation Details**:
- **AZ-201 (Starlark Parser):** Integrated `rustler` with the `starlark` Rust crate. Added parsing for `process`, `channel_literal`, `channel_from_path` and `workflow` declarations. Replaced declarative lists with programmatic data-flow graph generation (processes return `ChannelRef`).
- **AZ-202 (Canonical IR Serializer):** Configured deterministic JSON generation over the Rust IR via `serde_json`, allowing stable hashing. Extended `ProcessDescriptor` so `image` supports a struct containing `tag` and `checksum`.
- **AZ-203 (DSL Linting & Validation):** Validates resources (`cpu`, `mem`, `disk` > 0), URI schemes (s3, gs, nfs, local), process duplicate names, and strict template placeholder enforcement.
- **AZ-204 (Golden Tests):** `genomics_pipeline` and `dynamic_split_align` have JSON snapshot tests and end-to-end Elixir integration tests validating runtime workflow registration.
- **Glob Resolution:** Built `Athanor.Storage.GlobResolver` and `LocalGlobResolver` to expand input `channel.from_path(...)` patterns before workflow execution begins.

**Dependencies**: Phase 1 (AZ-101–105) must be complete and passing all tests before beginning Phase 2.

---

## Phase 3 — Resumability + Cache Correctness

Cache correctness must be established before reactive channel semantics.
Fan-out over a channel produces many tasks; without fingerprinting and
idempotency already in place, partial resumption after a crash is undefined
behavior. AZ-301 (TaskFingerprint) is a prerequisite of Phase 4's idempotent
event ingestion (AZ-403).

### AZ-301: TaskFingerprint Implementation
- Hash of process + inputs + image + command + runtime/env policy
- Stable fingerprint generation anchored to the canonical IR from Phase 2

### AZ-302: Cache Index Schema
- CAS index design and lookup API
- Fast lookup of cached results

### AZ-303: Cache Hit/Miss Engine
- Decision logic with explicit invalidation reasons
- Audit trail for cache decisions surfaced through the event log (AZ-103)

### AZ-304: Resume-After-Crash Flow
- Recovery after control-plane restart
- Replay safety tests using the harness designed in AZ-004

**Exit Criteria**: Interrupted run resumes correctly with explainable cache
decisions visible in the event log

---

## Phase 4 — Reactive Channel Scheduler

With the fingerprint model and idempotency semantics established, the reactive
scheduler can be built on a solid footing. AZ-401 (Query API) is introduced
here because cache decisions and channel state transitions are opaque without
a read-path; debugging reactive behavior requires querying scheduler state.

### AZ-401: Channel Materialization
- Events for channel readiness and data arrival
- Task activation based on channel state
- Persist subscriber cursors durably so control-plane restarts do not lose progress or trigger duplicate fan-out

### AZ-402: Fan-out/Fan-in & Backpressure
- Map over channels, partitioning, merge semantics
- Backpressure rules and bounded queueing
- Dynamic fan-out: handle variable-cardinality publications from glob-resolved outputs (N items appended atomically)

### AZ-403: Idempotent Event Ingestion
- Dedupe keys and event ordering guarantees
- Exactly-once-ish semantics; relies on TaskFingerprint from AZ-301
- Treat multi-item glob publication as a single atomic event to prevent partial fan-out on re-delivery

### AZ-404: Query API (minimal)
- Run/task/event queries with filtering and pagination
- Expose cache decision audit trail and channel state
- Full dashboards and SLO metrics remain in Phase 8; this is the minimum
  read-path needed to develop and validate the reactive scheduler

### AZ-405: Deterministic Replay Tests
- Scheduler replays event log deterministically using harness from AZ-004
- Tests for ordering, idempotency, and channel-triggered task activation

**Exit Criteria**: Readiness driven by channel arrivals, cache-correct, and
queryable via the minimal API

---

## Phase 5 — Control/Data Plane Split (Quicksilver Protocol)

The first phase that introduces a network boundary. The security trust model
for this boundary — worker registration, voucher verification, and transport
security — must be designed here even if full hardening lands in Phase 9.
Deferring the mTLS and authz interface design until after the protocol
solidifies forces breaking changes later.

### AZ-501: Protobuf Contracts
- Job voucher, heartbeat, status stream, completion payload
- gRPC service definitions

### AZ-502: Athanor Dispatch Service
- Worker registration and task dispatch
- Voucher signing (Ed25519, short TTL + nonce) and verification

### AZ-503: Trust Boundary Design
- Define the mTLS and authz model for the control/data plane interface
- Worker identity: certificate-based or token-based registration
- Authz scope: what a worker is permitted to claim, report, and read
- This is a design and interface commitment, not full hardening; hardening
  lands in AZ-902

### AZ-504: Worker Heartbeat Monitor
- Lease expiry handling and worker health tracking
- Failover strategies

### AZ-505: Exactly-once-ish Completion
- Idempotent finalization and dedupe
- Duplicate event handling

**Exit Criteria**: Remote worker can receive tasks and stream state safely
over a defined and documented trust boundary

---

## Phase 6 — Data Staging + Artifact Handling

### AZ-601: ArtifactRef Abstraction
- `s3://`, `gs://`, `nfs://`, local paths
- URI parsing and protocol adapters

### AZ-602: Worker-Side Staging Pipeline
- Pull inputs via URI/mount
- Publish outputs without control-plane proxy
- Implement glob output resolution: after container exits, scan working directory against declared glob patterns, upload all matching files, and publish the full `ArtifactRef` array atomically to Athanor

### AZ-603: Multipart Upload/Retry
- Large file handling with checksums
- Retry strategy for partial failures
- Glob resolution must be idempotent: a retry after partial upload must not publish duplicate `ArtifactRef` entries

### AZ-604: Data Locality Tests
- Verify no control-plane data proxying
- End-to-end data flow verification

**Exit Criteria**: End-to-end remote run moves bulk data directly via worker/storage

---

## Phase 7 — Isolation Backends

### AZ-701: Executor Interface
- Pluggable executors: local, container, firecracker
- Interface definition and adapter pattern

### AZ-702: Container Runtime Adapter
- Docker/containerd as default production backend
- Image pull and execution

### AZ-703: Firecracker Spike
- Capability checks and graceful fallback
- Experimental microVM isolation

### AZ-704: Failure Taxonomy
- Startup/network/teardown failures and recovery
- Runbook and debugging guidance

**Exit Criteria**: Pluggable executor works with one hardened backend

---

## Phase 8 — Observability + API/UI (Full)

The minimal observability surfaces (structured log streaming in AZ-103, query
API in AZ-404) are already in place. This phase completes the production
observability story.

### AZ-801: Log Streaming (production)
- Real-time log streaming to UI/API consumers with backpressure and buffering
- Replaces the development-grade tail-follow from AZ-103

### AZ-802: Explainability Endpoints
- Scheduler and cache decision explanations
- Debugging APIs surfacing the audit trail from AZ-303

### AZ-803: SLO Dashboards
- Queue latency, retry rates, worker health, cache hit ratio
- Metrics and alerting

**Exit Criteria**: Operators can diagnose failures without digging into worker nodes

---

## Phase 9 — Hardening + v1 Gate

### AZ-901: Chaos/Fault Injection
- Worker death, network flap, partial upload scenarios
- Automated fault testing using replay harness from AZ-004

### AZ-902: Security Hardening
- Implement mTLS and authz boundaries designed in AZ-503
- Full voucher signing/verification audit
- Security review and compliance

### AZ-903: Performance Targets
- Load test thresholds and benchmarks
- Performance regression detection

### AZ-904: v1 Readiness Checklist
- Migration notes and upgrade path
- Production-readiness evidence

**Exit Criteria**: Production-readiness evidence against documented success criteria

---

## Decision Points

| Decision | Recommended | Notes |
|----------|-------------|-------|
| Persistence | SQLite first | Postgres-ready schema |
| Scheduler Core | Event-sourced log | Append-only with projections |
| Voucher Security | Ed25519 signed claims | Short TTL + nonce |
| Worker Dispatch | Pull-based leasing | Recommended for scalability |
| Cache Storage | Metadata in DB, artifacts in object store | Strict checksum verification |
| IR Encoding | JSON (Phase 2), Protobuf (Phase 5) | Migrate to Protobuf when gRPC wire format is needed |
| Trust Boundary | mTLS + certificate-based worker identity | Designed in AZ-503, hardened in AZ-902 |
| Channel Semantics | Append-only stream with per-subscriber cursors | No item removal; enables safe multi-consumer fan-out |
| Dynamic Outputs | Glob patterns resolved by Quicksilver at runtime | Athanor never touches the filesystem; all path discovery is data-plane responsibility |
| Glob Publication | Atomic multi-item append to channel | All resolved ArtifactRefs from one execution published as a single event to prevent partial fan-out |

---

## Milestone to Phase Map

| Gantt Milestone | Engineering Phases |
|---|---|
| M1: Runner | Phase 1 (AZ-101–105) |
| M2: DAG Scheduling | Phase 1 (AZ-104) + Phase 2 (AZ-201–204) |
| M3: Content Hashing | Phase 3 (AZ-301–302) |
| M4: Cache Lookup | Phase 3 (AZ-303–304) |
| M5: Remote Workers | Phase 5 (AZ-501–505) |
| M6: Heartbeats and Retry | Phase 5 (AZ-504–505) |
| M7: Cloud Staging | Phase 6 (AZ-601–604) |
| M8: Runtime Isolation | Phase 7 (AZ-701–704) |

---

## Execution Order

1. **Phases 0–1** establish the execution model before any DSL or distribution work
2. **Phase 2** introduces the parser only after the runner is validated
3. **Phase 3** establishes fingerprint and cache correctness before reactive semantics
4. **Phase 4** builds the reactive scheduler on top of a proven fingerprint model
5. **Phase 5** is the first network boundary; define the trust model here
6. **Phases 6–7** extend capability without changing core invariants
7. **Phase 8** completes observability; minimal surfaces were introduced in Phases 1 and 4
8. **Phase 9** hardens what was designed in earlier phases — no new interfaces

## Success Criteria (v1)

- Users can define deterministic workflows in Starlark
- Athanor can schedule reactive execution based on input readiness
- Quicksilver can execute jobs remotely and report status reliably
- Cached tasks resume correctly after interruption or restart
- Data movement happens directly between storage and workers
