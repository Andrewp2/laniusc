use std::path::Path;

use laniusc::compiler::{CompileError, Diagnostic};

use super::error::CliError;

pub(crate) fn package_metadata_cli_error(flag: &str, path: &Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic.with_note(
            format!("package metadata context: {flag} {}", path.display()),
        )),
        CompileError::GpuFrontend(message) => package_metadata_invalid_error(flag, path, message),
        err => package_metadata_invalid_error(flag, path, err.to_string()),
    }
}

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
