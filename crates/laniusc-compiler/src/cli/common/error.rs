use crate::compiler::{CompileError, Diagnostic};

#[derive(Debug)]
pub(crate) enum CliError {
    Diagnostic(Diagnostic),
    Message(String),
}

impl CliError {
    pub(crate) fn from_compile_error(err: CompileError) -> Self {
        match err {
            CompileError::Diagnostic(diagnostic) => CliError::Diagnostic(diagnostic),
            err => CliError::Message(err.to_string()),
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
            CliError::Message(message) => f.write_str(message),
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

pub(crate) fn missing_cli_option_value_error(
    option: &str,
    expected: impl Into<String>,
) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0023", "missing CLI option value")
            .with_note(format!("{option} requires {}", expected.into())),
    )
}

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

pub(crate) fn missing_cli_argument_error(command: &str, expected: &str) -> CliError {
    CliError::Diagnostic(
        Diagnostic::error("LNC0026", "missing CLI argument")
            .with_note(format!("{command} requires {expected}"))
            .with_help(format!(
                "run `{command} --help` or pass the required argument: {expected}"
            )),
    )
}

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
