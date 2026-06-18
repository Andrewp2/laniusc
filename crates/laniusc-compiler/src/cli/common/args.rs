use super::{
    constants::LANIUS_DIAGNOSTIC_FORMATS,
    diagnostic_format::validate_diagnostic_format,
    error::{CliError, missing_cli_option_value_error, unknown_cli_option_error},
};

/// Removes `--diagnostic-format` selectors from subcommand-local argument lists.
pub(crate) fn cli_args_without_diagnostic_format(
    command: &str,
    args: impl IntoIterator<Item = String>,
    accepted: &str,
) -> Result<Vec<String>, CliError> {
    let mut filtered = Vec::new();
    let mut args = args.into_iter();
    while let Some(arg) = args.next() {
        if arg == "--diagnostic-format" {
            let value = args.next().ok_or_else(|| {
                missing_cli_option_value_error(
                    "--diagnostic-format",
                    format!("one of: {LANIUS_DIAGNOSTIC_FORMATS}"),
                )
            })?;
            validate_diagnostic_format(&value)?;
        } else if let Some(value) = arg.strip_prefix("--diagnostic-format=") {
            validate_diagnostic_format(value)?;
        } else if arg.starts_with("--diagnostic-format") {
            return Err(unknown_cli_option_error(command, &arg, accepted));
        } else {
            filtered.push(arg);
        }
    }
    Ok(filtered)
}
