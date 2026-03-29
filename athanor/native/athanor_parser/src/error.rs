use thiserror::Error;

/// Validation errors collected in a single pass before returning to Elixir.
///
/// All variants carry enough context for the Elixir layer to format a
/// human-readable diagnostic without additional lookups.
#[derive(Debug, Clone, PartialEq, Error)]
pub enum ValidationError {
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

    /// A resource value is zero or negative.
    #[error("process '{process_id}': resource '{resource}' must be > 0, got {value}")]
    NonPositiveResource {
        process_id: String,
        resource: &'static str,
        value: f64,
    },

    /// The Starlark source could not be parsed or evaluated.
    #[error("starlark evaluation failed: {message}")]
    StarlarkError { message: String },

    /// The `workflow()` call was not found in `main()`.
    #[error("no workflow() call found — main() must return workflow(...)")]
    NoWorkflowFound,

    /// Two processes in the same workflow share the same name.
    #[error(
        "workflow '{workflow_name}': duplicate process name '{name}' \
         (process names must be unique within a workflow)"
    )]
    DuplicateProcessName { workflow_name: String, name: String },

    /// Channel type mismatch between what a process expects and what it receives.
    #[error(
        "process '{process_id}': type mismatch on input channel \
         (expected format '{expected}', but channel provides '{got}')"
    )]
    TypeMismatch {
        process_id: String,
        expected: String,
        got: String,
    },
}

/// Convenience alias.
pub type ValidationErrors = Vec<ValidationError>;
