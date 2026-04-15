# **Azoth Implementation Plan**

## **Overview**

This document outlines the implementation plan for the Azoth project, comprising the **Athanor** (control-plane) and **Quicksilver** (data-plane) components. The strategy prioritizes a local control plane and gRPC contract before final worker implementation.

## **Key Constraints**

* **Determinism:** The DSL must produce stable plans and consistent hashes.  
* **Payload Separation:** The control-plane (Athanor) must never carry data payloads.  
* **Resumability:** Correctness is prioritized over execution speed.  
* **Fault-First Design:** The system must handle worker loss, partial uploads, and retries natively.  
* **Incremental Scope:** A local runner is required before introducing distributed complexity.  
* **Immutable Streams:** Channels are append-only; subscribers hold cursors and never destroy items.

## **Risk Areas**

* Over-building distributed logic before a stable deterministic planner exists.  
* Tight coupling between the parser and the scheduler without a stable Intermediate Representation (IR).  
* Cache key incompleteness resulting in false cache hits.  
* Introducing Firecracker or complex virtualization before the core ops burden is understood.  
* Subscriber cursor loss during control-plane restarts leading to duplicate fan-out dispatches.

## **Milestone 1: Local Deterministic Planner (Athanor)**

* **Stable IR Definition:** Define the schema for tasks, jobs, and channels.  
* **Deterministic Planning:** Implement a planner in Elixir that generates stable hashes for execution graphs.  
* **Channel Implementation:** Develop the append-only channel logic with cursor-based subscription management.  
* **Fingerprint Model:** Create the logic for cache keys to ensure execution skipping works reliably.  
* **In-Memory Workflow State:**  
  * **Task Monitor:** Tracks worker heartbeats and task status.  
  * **Dispatcher:** Forwards IR plans to the data-plane.  
  * **Scheduler:** Manages the dispatcher, artifact representations, and retry logic.  
  * **Instance Supervisor:** Manages the lifecycle of workflow subprocesses.

## **Milestone 2: Parser and IR Stability**

* **DSL Specification:** Finalize the syntax and semantics for the genomic pipeline.  
* **Parser Implementation:** Build the parser that generates the IR defined in Milestone 1\.  
* **Validation Suite:** Create a test suite to ensure IR stability and cross-version determinism.  
* **Separation of Concerns:** Audit the boundary between the parser, scheduler, and executor.

## **Milestone 3: Execution Guarantees**

* **Retry Logic:** Implement exponential backoff for transient failures within Athanor.  
* **Idempotency Checks:** Ensure task execution can be safely restarted without side effects.  
* **Concurrency Control:** Implement backpressure and limits on task dispatching to prevent worker saturation.

## **Milestone 4: Communication Contract (The Interface)**

* **Protocol Buffers:** Define the messages for task assignment, heartbeats, and artifact metadata.  
* **gRPC Service:** Implement the service definitions for the control-to-data plane bridge.  
* **Athanor Stubs:** Build the Elixir gRPC server to handle incoming worker requests.

## **Milestone 5: Quicksilver Implementation (Data-plane)**

* **Rust Worker Core:** Implement the gRPC client stubs in Quicksilver.  
* **Execution Environment:** Develop the Docker-based task runner.  
* **Artifact Management:** \* Implement logic for content-addressable storage (CAS) interactions.  
  * Build the upload/download mechanism that bypasses the control plane.  
* **Local Failure Handling:** Implement worker-side retries for environment-specific issues.

## **Milestone 6: Boundary Security**

* **Job Vouchers:** Implement cryptographically signed vouchers for task authorization.  
* **Signature Verification:** Ensure Quicksilver validates all incoming IR plans.  
* **Identity Management:** Implement mTLS or token-based registration for new workers.

## **Milestone 7: Structured Logging**

* **Log Schema:** Define a unified structure for logs across Elixir and Rust components.  
* **Sink Implementation:** Build the log ingestion sink within Athanor.  
* **Log Streaming:** Implement real-time log forwarding from Quicksilver to Athanor.

## **Milestone 8: Durable State Storage**

* **Persistence Strategy:** Define the schema for persisting workflow state transitions.  
* **Crash Recovery:** Implement logic to reload state from storage and resume workflows from the last valid cursor.  
* **Storage Backend:** Select and implement the persistence layer (e.g., PostgreSQL or a specialized KV store).

## **Milestone 9: Observability**

* **Metric Collection:** Instrument Athanor with Telemetry for pipeline throughput and scheduler latency.  
* **Worker Health:** Implement Quicksilver metrics for CPU, memory usage, and task execution time.  
* **Tracing:** Integrate OpenTelemetry to track a single task across the control and data plane boundary.

## **Milestone 10: Interface and Tooling**

* **CLI Utility:** Build a command-line tool for submitting pipelines and checking status.  
* **Status Dashboard:** Develop a lightweight web interface to visualize the execution graph and channel states.  
* **Inspection Tools:** Create utilities to inspect the content of append-only channels and cursor positions.