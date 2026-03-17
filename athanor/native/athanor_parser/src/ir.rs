use std::collections::BTreeMap;

use serde::Deserialize;
use serde::Serialize;

/// A single declared process in a workflow.
///
/// BTreeMap is used for `inputs` so iteration order is deterministic,
/// which is required for stable SHA-256 fingerprinting.
///
/// `id` is the UUID7 canonical identity used for all internal routing.
/// `name` is a cosmetic label for UI and logging; it must be unique within
/// a workflow but carries no semantic weight in the scheduler.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ProcessDescriptor {
    pub id: String,
    /// Human-readable label. Extracted from the Starlark function name, or
    /// overridden by an explicit `name=` kwarg in the `process()` call.
    /// Format: `[a-zA-Z0-9_.]{1,120}`.
    pub name: String,
    pub image: String,
    pub command: String,
    /// Sorted map of input-name → ArtifactRef URI / channel item placeholder.
    pub inputs: BTreeMap<String, String>,
    pub outputs: OutputDef,
    pub resources: ResourceDef,
}

/// How a process declares its output artifacts.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "type", content = "value")]
pub enum OutputDef {
    /// Named URI templates known at parse time  (e.g. `{"output": "s3://…/{reads.stem}.bam"}`).
    Static(BTreeMap<String, String>),
    /// Glob patterns resolved by Quicksilver at runtime (e.g. `["./chunks/*.fa"]`).
    Glob(Vec<String>),
}

/// Resource requirements for a process.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ResourceDef {
    pub cpu: f64,
    pub mem: f64,
    pub disk: f64,
}

/// A named channel in the workflow graph.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct ChannelDef {
    pub id: String,
    pub channel_type: ChannelType,
    pub source: ChannelSource,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ChannelType {
    Path,
    Result,
    Literal,
}

/// Where the channel's items originate.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case", tag = "kind")]
pub enum ChannelSource {
    /// `channel.from_path("glob")` — one item per matching path.
    FromPath { glob: String },
    /// `channel.literal("value")` — a single static item.
    Literal { value: String },
    /// Implicit result channel produced by a process.
    Result { process_id: String },
}

/// The top-level parsed workflow plan.
///
/// `version` is embedded so the deserialiser can detect schema migrations.
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
pub struct WorkflowPlan {
    pub version: u32,
    pub name: String,
    pub processes: Vec<ProcessDescriptor>,
    pub channels: Vec<ChannelDef>,
}
