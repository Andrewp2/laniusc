use std::path::Path;

use crate::{
    cli::fallback::cli_operation_failed_diagnostic,
    compiler::{CompileError, Diagnostic},
};

/// CLI error wrapper that preserves structured compiler diagnostics when
/// possible.
#[derive(Debug)]
pub(crate) enum CliError {
    /// Structured diagnostic that can render as text, JSON, or LSP JSON.
    Diagnostic(Diagnostic),
    /// Plain control-plane error string.
    Message(String),
}

impl CliError {
    /// Converts compiler errors while preserving diagnostic payloads.
    pub(crate) fn from_compile_error(err: CompileError) -> Self {
        CliError::Diagnostic(err.into_public_diagnostic())
    }

    /// Converts this CLI error into a public diagnostic payload.
    ///
    /// `CliError::Message` is kept as a temporary control-plane carrier, but
    /// every renderer should lower it before producing user-visible output.
    pub(crate) fn into_public_diagnostic(self) -> Diagnostic {
        match self {
            CliError::Diagnostic(diagnostic) => diagnostic,
            CliError::Message(message) => cli_operation_failed_diagnostic(message),
        }
    }
}

impl From<String> for CliError {
    fn from(value: String) -> Self {
        CliError::Message(value)
    }
}

impl From<&str> for CliError {
    fn from(value: &str) -> Self {
        CliError::Message(value.to_string())
    }
}

impl std::fmt::Display for CliError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CliError::Diagnostic(diagnostic) => write!(f, "{diagnostic}"),
            CliError::Message(message) => {
                write!(f, "{}", cli_operation_failed_diagnostic(message.as_str()))
            }
        }
    }
}

impl From<crate::cli::output::CliOutputError> for CliError {
    fn from(value: crate::cli::output::CliOutputError) -> Self {
        match value {
            crate::cli::output::CliOutputError::Diagnostic(diagnostic) => {
                Self::Diagnostic(diagnostic)
            }
            crate::cli::output::CliOutputError::Message(message) => Self::Message(message),
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn compile_error_conversion_preserves_structured_diagnostic() {
        let cli_error = CliError::from_compile_error(CompileError::Diagnostic(
            Diagnostic::error("LNC0026", "missing CLI argument")
                .with_note("compile-error conversion should preserve diagnostics"),
        ));

        match cli_error {
            CliError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0026");
                assert_eq!(diagnostic.message, "missing CLI argument");
                assert!(
                    diagnostic
                        .notes
                        .iter()
                        .any(|note| note.contains("preserve"))
                );
            }
            CliError::Message(message) => {
                panic!(
                    "structured compiler diagnostics should not become plain messages: {message}"
                )
            }
        }
    }

    #[test]
    fn compile_error_conversion_lowers_raw_phase_errors_for_json_rendering() {
        let cli_error = CliError::from_compile_error(CompileError::GpuFrontend(
            "GPU LL(1) parser rejected token: 4".into(),
        ));

        let diagnostic = match cli_error {
            CliError::Diagnostic(diagnostic) => diagnostic,
            CliError::Message(message) => {
                panic!("raw compiler errors should lower to diagnostics, got message: {message}")
            }
        };
        assert_eq!(diagnostic.code, "LNC0057");
        assert_eq!(diagnostic.message, "compiler execution failed");
        assert!(diagnostic.primary_label.is_none());

        let json = diagnostic
            .render_json_pretty()
            .expect("fallback diagnostic JSON should serialize");
        assert!(json.contains("\"code\": \"LNC0057\""));
        assert!(json.contains("\"message\": \"compiler execution failed\""));
        assert!(!json.contains("GPU"));
        assert!(!json.contains("LL(1)"));
        assert!(!json.contains("parser rejected token"));
    }

    #[test]
    fn plain_cli_messages_can_lower_to_structured_diagnostics() {
        let diagnostic =
            CliError::from("serialize doctor report: broken pipe").into_public_diagnostic();

        assert_eq!(diagnostic.code, "LNC0067");
        assert_eq!(diagnostic.message, "CLI operation failed");
        assert_eq!(diagnostic.category, "tooling");
        assert!(diagnostic.primary_label.is_none());
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note.contains("serialize doctor report: broken pipe"))
        );

        let json = diagnostic
            .render_json_pretty()
            .expect("plain CLI fallback diagnostic JSON should serialize");
        assert!(json.contains("\"code\": \"LNC0067\""));
        assert!(json.contains("\"message\": \"CLI operation failed\""));
    }

    #[test]
    fn plain_cli_message_display_uses_structured_diagnostic() {
        let rendered = CliError::from("serialize doctor report: broken pipe").to_string();

        assert!(rendered.contains("error[LNC0067]: CLI operation failed"));
        assert!(rendered.contains("tooling detail: serialize doctor report: broken pipe"));
        assert!(!rendered.starts_with("laniusc:"));
    }

    #[test]
    fn plain_output_messages_convert_to_shared_cli_fallback_diagnostic() {
        let diagnostic = CliError::from(crate::cli::output::CliOutputError::from(
            "copy linked output: broken pipe".to_string(),
        ))
        .into_public_diagnostic();

        assert_eq!(diagnostic.code, "LNC0067");
        assert_eq!(diagnostic.message, "CLI operation failed");
        assert_eq!(diagnostic.category, "tooling");
        assert!(
            diagnostic
                .notes
                .iter()
                .any(|note| note == "tooling detail: copy linked output: broken pipe")
        );
        assert!(
            diagnostic
                .help
                .as_deref()
                .is_some_and(|help| help.contains("serialization, protocol, or output failure"))
        );
    }
}

/// Builds the stable diagnostic for an unsupported option value.
pub(crate) fn unsupported_cli_option_value_error(
    option: &str,
    value: &str,
    accepted: &str,
    detail: Option<String>,
) -> CliError {
    let mut diagnostic = Diagnostic::error("LNC0018", "unsupported CLI option value")
        .with_note(format!("{option} value {value:?} is not supported"))
        .with_note(format!("accepted {option} values: {accepted}"));
    if let Some(detail) = detail {
        diagnostic = diagnostic.with_note(detail);
    }
    CliError::Diagnostic(diagnostic)
}

/// Builds the stable diagnostic for a missing option value.
pub(crate) fn missing_cli_option_value_error(
    option: &str,
    expected: impl Into<String>,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0023", "missing CLI option value")
            .with_note(format!("{option} requires {}", expected.into())),
    )
}

/// Builds the stable diagnostic for an unknown option flag.
pub(crate) fn unknown_cli_option_error(command: &str, flag: &str, accepted: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0020", "unknown CLI option")
            .with_note(format!("{command} option {flag:?} is not recognized"))
            .with_note(format!("accepted {command} options: {accepted}"))
            .with_help(
                "remove the unrecognized option or use an accepted option listed in the notes",
            ),
    )
}

/// Builds the stable diagnostic for an unknown subcommand.
pub(crate) fn unknown_cli_subcommand_error(
    command: &str,
    subcommand: &str,
    accepted: &str,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0039", "unknown CLI subcommand")
            .with_note(format!(
                "{command} subcommand {subcommand:?} is not recognized"
            ))
            .with_note(format!("accepted {command} subcommands: {accepted}"))
            .with_help(format!(
                "run `{command} --help` or choose one of the accepted subcommands listed in the notes"
            )),
    )
}

/// Builds the stable diagnostic for a missing subcommand.
pub(crate) fn missing_cli_subcommand_error(command: &str, accepted: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0025", "missing CLI subcommand")
            .with_note(format!("{command} requires a subcommand"))
            .with_note(format!("accepted {command} subcommands: {accepted}"))
            .with_help(format!(
                "run `{command} --help` or choose one of the accepted subcommands listed in the notes"
            )),
    )
}

/// Builds the stable diagnostic for a missing positional argument.
pub(crate) fn missing_cli_argument_error(command: &str, expected: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0026", "missing CLI argument")
            .with_note(format!("{command} requires {expected}"))
            .with_help(format!(
                "run `{command} --help` or pass the required argument: {expected}"
            )),
    )
}

/// Builds an option or positional diagnostic for an unexpected argument.
pub(crate) fn extra_cli_argument_error(command: &str, argument: &str, accepted: &str) -> CliError {
    if argument.starts_with('-') {
        unknown_cli_option_error(command, argument, accepted)
    } else {
        CliError::Diagnostic(
            Diagnostic::error("LNC0031", "unexpected CLI argument")
                .with_note(format!(
                    "{command} does not accept extra argument {argument:?}"
                ))
                .with_note(format!("accepted {command} arguments/options: {accepted}")),
        )
    }
}

/// Builds the stable diagnostic for an invalid positional-argument count.
pub(crate) fn invalid_cli_argument_count_error(
    command: &str,
    requirement: &str,
    actual: impl Into<String>,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0031", "unexpected CLI argument")
            .with_note(format!("{command} requires {requirement}"))
            .with_note(actual),
    )
}

/// Builds the stable diagnostic for incompatible option combinations.
pub(crate) fn incompatible_cli_options_error(
    command: &str,
    option: &str,
    incompatible_with: &str,
    remediation: &str,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0032", "incompatible CLI options")
            .with_note(format!(
                "{command} cannot combine {option} with {incompatible_with}"
            ))
            .with_note(remediation.to_string()),
    )
}

/// Builds the stable diagnostic for an explicit source-pack manifest contract
/// failure surfaced by CLI-only manifest readers.
pub(crate) fn explicit_source_pack_manifest_invalid_error(reason: impl Into<String>) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0049", "explicit source-pack manifest invalid")
            .with_note(reason)
            .with_note(
                "each explicit source-pack library must appear once, declare at least one source file, depend only on present libraries, and report counts that match the streamed paths and dependencies",
            )
            .with_help(
                "fix the source-pack library manifest or path-list file, then rerun the preparation command with the same artifact root",
            ),
    )
}

/// Builds the stable diagnostic for a CLI path that must resolve to a
/// directory.
pub(crate) fn invalid_cli_directory_path_error(
    label: &str,
    path: &Path,
    reason: impl Into<String>,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0040", "input read failed")
            .with_primary_label(crate::compiler::DiagnosticLabel::primary(
                path,
                1,
                1,
                1,
                None,
                format!("{label} path cannot be used"),
            ))
            .with_note(format!("{label}: {}", path.display()))
            .with_note(reason)
            .with_help(format!("pass an existing directory path for {label}")),
    )
}

/// Builds the stable diagnostic for source-pack artifact-store consistency
/// failures detected by CLI-only descriptor validation.
pub(crate) fn source_pack_artifact_store_cli_error(message: impl Into<String>) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0059", "source-pack artifact store failed")
            .with_note(message)
            .with_note(
                "source-pack artifact stores require canonical artifact identities, normal relative artifact keys, and readable or writable artifact files under the selected artifact root",
            )
            .with_help(
                "regenerate the source-pack artifact root or remove stale artifact files before resuming the build",
            ),
    )
}
