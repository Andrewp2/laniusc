use std::path::Path;

use super::error::CliError;
use crate::compiler::CompileError;

/// Adds package metadata selector context to a compiler error.
pub(crate) fn package_metadata_cli_error(flag: &str, path: &Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic.with_note(
            format!("package metadata context: {flag} {}", path.display()),
        )),
        err => CliError::Diagnostic(err.into_public_diagnostic().with_note(format!(
            "package metadata context: {flag} {}",
            path.display()
        ))),
    }
}

/// Adds package compile selector context to a compiler error.
pub(crate) fn package_compile_cli_error(flag: &str, path: &Path, err: CompileError) -> CliError {
    match err {
        CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(
            diagnostic.with_note(format!("package context: {flag} {}", path.display())),
        ),
        err => CliError::Diagnostic(
            err.into_public_diagnostic()
                .with_note(format!("package context: {flag} {}", path.display())),
        ),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::compiler::Diagnostic;

    #[test]
    fn package_metadata_adapter_preserves_structured_diagnostics() {
        let cli_error = package_metadata_cli_error(
            "--package-manifest",
            Path::new("lanius.package.json"),
            CompileError::Diagnostic(
                Diagnostic::error("LNC0037", "package metadata invalid")
                    .with_note("manifest entry path is outside declared roots"),
            ),
        );

        match cli_error {
            CliError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0037");
                assert!(
                    diagnostic.notes.iter().any(|note| {
                        note.contains("package metadata context: --package-manifest")
                    })
                );
                assert!(diagnostic.notes.iter().any(|note| {
                    note.contains("manifest entry path is outside declared roots")
                }));
            }
            CliError::Message(message) => {
                panic!("package metadata diagnostics should stay structured: {message}")
            }
        }
    }

    #[test]
    fn package_metadata_adapter_sanitizes_raw_phase_errors() {
        let cli_error = package_metadata_cli_error(
            "--package-manifest",
            Path::new("lanius.package.json"),
            CompileError::GpuFrontend("GPU LL(1) parser rejected token: 4".into()),
        );

        match cli_error {
            CliError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0057");
                assert_eq!(diagnostic.message, "compiler execution failed");
                assert!(
                    diagnostic.notes.iter().any(|note| {
                        note.contains("package metadata context: --package-manifest")
                    })
                );

                let rendered = diagnostic.render();
                assert!(!rendered.contains("GPU"));
                assert!(!rendered.contains("LL(1)"));
                assert!(!rendered.contains("parser rejected token"));
                assert!(!rendered.contains("frontend error:"));
            }
            CliError::Message(message) => {
                panic!("raw compiler errors should lower to diagnostics: {message}")
            }
        }
    }
}
