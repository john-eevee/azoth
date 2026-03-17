use sha2::Digest;
use sha2::Sha256;

use crate::ir::WorkflowPlan;

/// Serialise a [`WorkflowPlan`] to compact, deterministic JSON.
///
/// Determinism is guaranteed by:
/// - `serde_json` serialises struct fields in declaration order (which we
///   control) and map keys in iteration order.
/// - All maps in the IR use `BTreeMap`, which iterates in sorted key order.
/// - No pretty-printing — no insignificant whitespace.
pub fn to_canonical_json(plan: &WorkflowPlan) -> String {
    // serde_json::to_string never fails on well-formed types; unwrap is safe.
    serde_json::to_string(plan).expect("IR serialisation must not fail")
}

/// Compute the SHA-256 fingerprint of a [`WorkflowPlan`].
///
/// The hash is over the canonical JSON, not the binary struct, so it is
/// stable across Rust versions and serialisation libraries.
pub fn fingerprint(plan: &WorkflowPlan) -> String {
    let json = to_canonical_json(plan);
    let hash = Sha256::digest(json.as_bytes());
    hex::encode(hash)
}
