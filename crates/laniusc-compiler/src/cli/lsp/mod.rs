mod capabilities;
mod document;
mod protocol;
mod session;

/// Language identifier used by the LSP surface.
pub(super) const LSP_LANGUAGE_ID: &str = "lanius";

/// Returns the LSP error-data contract metadata used by no-run diagnostics.
pub(crate) fn error_data_contract_metadata() -> serde_json::Value {
    protocol::error_data_contract_metadata()
}

use super::{
    common::{
        CliError,
        cli_args_without_diagnostic_format,
        extra_cli_argument_error,
        unknown_cli_subcommand_error,
    },
    help::print_lsp_help,
};

/// Runs the LSP capability or stdio-server subcommand.
pub(crate) fn run(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args = cli_args_without_diagnostic_format(
        "laniusc lsp",
        args,
        "--help, capabilities, serve, --stdio, --diagnostic-format",
    )?;
    let mut args = args.into_iter();
    let Some(command) = args.next() else {
        print_lsp_help();
        return Ok(());
    };

    match command.as_str() {
        "-h" | "--help" => {
            print_lsp_help();
            Ok(())
        }
        "capabilities" => {
            if let Some(extra) = args.next() {
                return Err(extra_cli_argument_error(
                    "laniusc lsp capabilities",
                    &extra,
                    "no options",
                ));
            }
            let document = capabilities::capabilities_document();
            let json = serde_json::to_string_pretty(&document)
                .map_err(|err| format!("serialize lsp capabilities: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "serve" => session::run_serve(args),
        other => Err(unknown_cli_subcommand_error(
            "laniusc lsp",
            other,
            "capabilities, serve",
        )),
    }
}
