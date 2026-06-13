use super::{
    constants::LANIUS_DIAGNOSTIC_FORMATS,
    error::{CliError, unsupported_cli_option_value_error},
};

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(crate) enum DiagnosticFormat {
    Text,
    Json,
    LspJson,
}

pub(crate) fn diagnostic_format_from_args(
    args: impl IntoIterator<Item = String>,
) -> DiagnosticFormat {
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--diagnostic-format" {
            return match args.next().as_deref() {
                Some(value) => {
                    diagnostic_format_from_value(value).unwrap_or(DiagnosticFormat::Text)
                }
                _ => DiagnosticFormat::Text,
            };
        }
        if let Some(value) = arg.strip_prefix("--diagnostic-format=") {
            return diagnostic_format_from_value(value).unwrap_or(DiagnosticFormat::Text);
        }
    }
    DiagnosticFormat::Text
}

pub(crate) fn validate_diagnostic_format(value: &str) -> Result<(), CliError> {
    if diagnostic_format_from_value(value).is_some() {
        Ok(())
    } else {
        Err(unsupported_cli_option_value_error(
            "--diagnostic-format",
            value,
            LANIUS_DIAGNOSTIC_FORMATS,
            None,
        ))
    }
}

fn diagnostic_format_from_value(value: &str) -> Option<DiagnosticFormat> {
    match value {
        "text" => Some(DiagnosticFormat::Text),
        "json" => Some(DiagnosticFormat::Json),
        "lsp-json" => Some(DiagnosticFormat::LspJson),
        _ => None,
    }
}
