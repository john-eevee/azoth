mod error;
mod ir;
mod parser;
mod channel_ref;
mod serializer;
mod validator;

use rustler::Atom;
use rustler::NifResult;

// Re-export atoms for ok/error tuples.
rustler::atoms! {
    ok,
    error,
}

/// NIF: parse Starlark DSL source into canonical JSON.
///
/// Returns `{:ok, json_string}` on success or `{:error, errors}` on
/// any parse or validation failure.
///
/// For parse-time errors, returns a single error message string.
/// For validation errors, returns a list of error message strings.
#[rustler::nif(schedule = "DirtyCpu")]
fn parse_workflow(source: String) -> NifResult<(Atom, String)> {
    match parser::parse(&source) {
        Ok(plan) => {
            // Validate the plan
            match validator::validate_workflow(&plan) {
                Ok(_) => {
                    let json = serializer::to_canonical_json(&plan);
                    Ok((ok(), json))
                }
                Err(validation_errors) => {
                    // Combine all errors into a single string, one per line
                    let error_msg = validation_errors
                        .iter()
                        .map(|e| e.to_string())
                        .collect::<Vec<_>>()
                        .join("\n");
                    Ok((error(), error_msg))
                }
            }
        }
        Err(e) => {
            // Parse-time error — return as single string
            Ok((error(), e.to_string()))
        }
    }
}

/// NIF: compute the SHA-256 fingerprint of a canonical JSON string.
///
/// This is a pure function — same input always yields the same hex string.
#[rustler::nif(schedule = "DirtyCpu")]
fn fingerprint_json(json: String) -> NifResult<(Atom, String)> {
    // Re-parse to guarantee we're hashing a normalised representation,
    // not whatever string the caller happened to pass.
    match serde_json::from_str::<ir::WorkflowPlan>(&json) {
        Ok(plan) => Ok((ok(), serializer::fingerprint(&plan))),
        Err(e) => Ok((error(), format!("invalid IR JSON: {e}"))),
    }
}

rustler::init!("Elixir.Athanor.DSL.Parser.Native");
