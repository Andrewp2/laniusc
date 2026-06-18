use std::path::Path;

use super::CliOutputError;
use crate::compiler::{Diagnostic, DiagnosticLabel};

/// Builds the stable diagnostic for invalid linked-output contract files.
pub(super) fn linked_output_contract_descriptor_diagnostic(path: &Path, emit: &str) -> Diagnostic {
    Diagnostic::error("LNC0022", "linked-output contract descriptor")
        .with_primary_label(DiagnosticLabel::primary(
            path,
            1,
            1,
            1,
            None,
            "linked-output contract descriptor here",
        ))
        .with_note(format!(
            "expected linked-output JSON contract descriptor for --emit {emit}"
        ))
}

/// Converts a failed output-file write into the CLI's stable diagnostic form.
pub(super) fn output_write_diagnostic(
    output: &Path,
    emit: &str,
    operation: &str,
    err: std::io::Error,
) -> CliOutputError {
    CliOutputError::Diagnostic(
        Diagnostic::error("LNC0034", "output write failed")
            .with_primary_label(DiagnosticLabel::primary(
                output,
                1,
                1,
                1,
                None,
                "requested output path here",
            ))
            .with_help("choose a writable output path or omit -o/--out to write bytes to stdout")
            .with_note(format!("{operation} for --emit {emit} failed: {err}")),
    )
}

/// Converts stdout or stderr write failures into the CLI's stable diagnostic form.
pub(super) fn output_stream_write_diagnostic(
    stream: &str,
    emit: &str,
    operation: impl Into<String>,
    err: std::io::Error,
) -> CliOutputError {
    let operation = operation.into();
    let error_kind = format!("{:?}", err.kind());
    CliOutputError::Diagnostic(
        Diagnostic::error("LNC0035", "output stream write failed")
            .with_help("keep the output stream open or pass -o/--out to write to a file")
            .with_note(format!("output stream: {stream}"))
            .with_note(format!("operation: {operation}"))
            .with_note(format!("emit mode: {emit}"))
            .with_note(format!("I/O error kind: {error_kind}"))
            .with_note(format!("I/O error: {err}")),
    )
}
