use crate::compiler::Diagnostic;

/// Builds the shared fallback diagnostic for CLI/tooling failures that have
/// not yet been mapped to a more specific diagnostic code.
pub(crate) fn cli_operation_failed_diagnostic(detail: impl Into<String>) -> Diagnostic {
    Diagnostic::error("LNC0067", "CLI operation failed")
        .with_note("the CLI stopped before it could map this failure to a more specific diagnostic")
        .with_note(format!("tooling detail: {}", detail.into()))
        .with_help(
            "rerun the command after fixing the reported CLI/tooling issue; if this is a serialization, protocol, or output failure, report a compiler bug",
        )
}
