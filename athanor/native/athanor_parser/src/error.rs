use thiserror::Error;

/// Validation errors collected in a single pass before returning to Elixir.
///
/// All variants carry enough context for the Elixir layer to format a
/// human-readable diagnostic without additional lookups.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum ValidationError {
    // ── Process field errors ────────────────────────────────────────────────
    /// A required field is absent on the given process.
    #[error("process '{process_id}': missing required field '{field}'")]
    MissingField {
        process_id: String,
        field: &'static str,
    },

    /// A field that must be a non-empty string is empty.
    #[error("process '{process_id}': field '{field}' must be a non-empty string")]
    EmptyField {
        process_id: String,
        field: &'static str,
    },

    /// A command placeholder `{name}` cannot be resolved from declared inputs,
    /// outputs, or resources.
    #[error(
        "process '{process_id}': command placeholder '{{{placeholder}}}' cannot be resolved \
         (not in inputs, outputs, or resources)"
    )]
    UnresolvablePlaceholder {
        process_id: String,
        placeholder: String,
    },

    /// An output URI uses an unsupported scheme.
    #[error(
        "process '{process_id}': output '{key}' has unsupported URI scheme \
         (got '{scheme}', expected s3://, gs://, nfs://, or a relative path)"
    )]
    InvalidOutputScheme {
        process_id: String,
        key: String,
        scheme: String,
    },

    /// A resource value is not a number.
    #[error(
        "process '{process_id}': resource '{resource}' must be a number, \
         got a string or other non-numeric value"
    )]
    NonNumericResource {
        process_id: String,
        resource: &'static str,
    },

    /// A resource value is zero or negative.
    #[error("process '{process_id}': resource '{resource}' must be > 0, got {value}")]
    NonPositiveResource {
        process_id: String,
        resource: &'static str,
        value: f64,
    },

    // ── Parse-time errors ───────────────────────────────────────────────────
    /// The Starlark source could not be parsed or evaluated.
    #[error("starlark evaluation failed: {message}")]
    StarlarkError { message: String },

    /// The `workflow()` call was not found in `main()`.
    #[error("no workflow() call found — main() must return workflow(...)")]
    NoWorkflowFound,

    /// The `workflow()` call is missing a required keyword.
    #[error("workflow() is missing required keyword '{keyword}'")]
    WorkflowMissingKeyword { keyword: &'static str },

    /// An internal extraction invariant was violated.
    #[error("internal extraction error: {message}")]
    ExtractionError { message: String },
}

/// Convenience alias.
pub type ValidationErrors = Vec<ValidationError>;
