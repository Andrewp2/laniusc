use std::path::Path;

use super::error::CliError;
use crate::compiler::{CompileError, Diagnostic};

/// Adds package metadata selector context to a compiler error.
pub(crate) fn package_metadata_cli_error(flag: &str, path: &Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic.with_note(
            format!("package metadata context: {flag} {}", path.display()),
        )),
        CompileError::GpuFrontend(message) => package_metadata_invalid_error(flag, path, message),
        err => package_metadata_invalid_error(flag, path, err.to_string()),
    }
}

/// Adds package compile selector context to a compiler error.
pub(crate) fn package_compile_cli_error(flag: &str, path: &Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(
            diagnostic.with_note(format!("package context: {flag} {}", path.display())),
        ),
        err => package_metadata_cli_error(flag, path, err),
    }
}

fn package_metadata_invalid_error(flag: &str, path: &Path, message: String) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0037", "package metadata invalid")
            .with_note(format!("package metadata selector: {flag}"))
            .with_note(format!("package metadata path: {}", path.display()))
            .with_note(message)
            .with_help(
                "fix the package manifest or regenerate the package lockfile before compiling",
            ),
    )
}
