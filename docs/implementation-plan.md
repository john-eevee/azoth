# Azoth Implementation Plan

## Overview

Phase-by-phase plan for Azoth (Athanor control-plane + Quicksilver data-plane) to deliver a production-grade reactive workflow engine with deterministic DSL, resumability, and distribution.

## Key Constraints

- Determinism: DSL produces stable plans and stable hashes
- Control-plane should not carry data payloads
- Resumability correctness over speed
- Fault-first design (worker loss, partial uploads, retries)
- Incremental scope: local runner before distributed complexity

## Risk Areas

- Over-building distributed parts before nailing local deterministic planner
- Tight coupling between parser/scheduler/executor without stable IR boundary
- Cache key incompleteness causing false cache hits
- Schema churn if task/job state machine not formalized first
- Firecracker introduced too early (ops burden + nested virt constraints)

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
- Unit tests (DSL/planner)
- Integration tests (runner)
- Fault tests (retry/heartbeat)

**Exit Criteria**: Canonical model + lifecycle docs + executable test skeleton

---

## Phase 1 — DSL Parser + Deterministic Plan IR

### AZ-101: Starlark Parser Boundary
- Implement parser layer and AST validation
- Handle `process`, `channel`, `workflow` primitives from DSL spec

### AZ-102: Canonical IR Serializer
- Build order-stable IR for deterministic hashing
- JSON or Protobuf encoding for reproducible fingerprints

### AZ-103: DSL Linting & Validation
- Required fields, resource schema, command placeholder validation
- Error messages and recovery

### AZ-104: Golden Tests
- Same input produces byte-identical IR/hash
- Regression tests for parser behavior

**Exit Criteria**: Parse `dsl.md` examples into stable IR with deterministic snapshots

---

## Phase 2 — Local Runner (MVP Execution)

### AZ-201: Process Launcher
- Bounded concurrency executor
- Captures stdout/stderr/exit codes

### AZ-202: Run Metadata Persistence
- Store status, logs, exit codes, timestamps
- Simple local DB or file-based storage

### AZ-203: DAG Executor
- Dependency-aware execution (ready tasks → running → completed)
- Transition handling and error propagation

### AZ-204: Retry Policy
- Max attempts, backoff strategies, retryable failure detection

**Exit Criteria**: Multi-step local workflow executes with logs and retry behavior

---

## Phase 3 — Reactive Channel Scheduler

### AZ-301: Channel Materialization
- Events for channel readiness and data arrival
- Task activation based on channel state

### AZ-302: Fan-out/Fan-in & Backpressure
- Map over channels, partitioning, merge semantics
- Backpressure rules and bounded queueing

### AZ-303: Idempotent Event Ingestion
- Dedupe keys and event ordering guarantees
- Exactly-once-ish semantics

### AZ-304: Deterministic Replay Tests
- Scheduler can replay event log deterministically
- Tests for ordering and idempotency

**Exit Criteria**: Readiness driven by channel arrivals, not only static DAG completion

---

## Phase 4 — Resumability + Cache Correctness

### AZ-401: TaskFingerprint Implementation
- Hash of process + inputs + image + command + runtime/env policy
- Stable fingerprint generation

### AZ-402: Cache Index Schema
- CAS index design and lookup API
- Fast lookup of cached results

### AZ-403: Cache Hit/Miss Engine
- Decision logic with explicit invalidation reasons
- Audit trail for cache decisions

### AZ-404: Resume-After-Crash Flow
- Recovery after control-plane restart
- Replay safety tests

**Exit Criteria**: Interrupted run can resume correctly with explainable cache decisions

---

## Phase 5 — Control/Data Plane Split (Quicksilver Protocol)

### AZ-501: Protobuf Contracts
- Job voucher, heartbeat, status stream, completion payload
- gRPC service definitions

### AZ-502: Athanor Dispatch Service
- Worker registration and task dispatch
- Voucher signing and verification

### AZ-503: Worker Heartbeat Monitor
- Lease expiry handling and worker health tracking
- Failover strategies

### AZ-504: Exactly-once-ish Completion
- Idempotent finalization and dedupe
- Duplicate event handling

**Exit Criteria**: Remote worker can receive tasks and stream state safely

---

## Phase 6 — Data Staging + Artifact Handling

### AZ-601: ArtifactRef Abstraction
- `s3://`, `gs://`, `nfs://`, local paths
- URI parsing and protocol adapters

### AZ-602: Worker-Side Staging Pipeline
- Pull inputs via URI/mount
- Publish outputs without control-plane proxy

### AZ-603: Multipart Upload/Retry
- Large file handling with checksums
- Retry strategy for partial failures

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

## Phase 8 — Observability + API/UI

### AZ-801: Query API
- Run/task/event queries
- Filtering and pagination

### AZ-802: Log Streaming
- Real-time logs to UI/API consumers
- Backpressure and buffering

### AZ-803: Explainability Endpoints
- Scheduler and cache decision explanations
- Debugging APIs

### AZ-804: SLO Dashboards
- Queue latency, retry rates, worker health, cache hit ratio
- Metrics and alerting

**Exit Criteria**: Operators can diagnose failures without digging into worker nodes

---

## Phase 9 — Hardening + v1 Gate

### AZ-901: Chaos/Fault Injection
- Worker death, network flap, partial upload scenarios
- Automated fault testing

### AZ-902: Security Hardening
- Voucher signing/verification, mTLS, authz boundaries
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

---

## Execution Order

1. **Phases 0-4** before serious distributed work (local-first recommended)
2. **Phase 5** only after state machine + fingerprint semantics stable
3. Firecracker as optional until container path hardened

## Success Criteria (v1)

- Users can define deterministic workflows in Starlark
- Athanor can schedule reactive execution based on input readiness
- Quicksilver can execute jobs remotely and report status reliably
- Cached tasks resume correctly after interruption or restart
- Data movement happens directly between storage and workers
