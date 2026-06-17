use std::{env, process::ExitCode};

use super::{
    common::{CliError, DiagnosticFormat, diagnostic_format_from_args},
    dispatch,
};

pub fn run_from_env() -> ExitCode {
    let args = env::args().skip(1).collect::<Vec<_>>();
    let diagnostic_format = diagnostic_format_from_args(args.iter().cloned());
    match dispatch::run(args) {
        Ok(()) => ExitCode::SUCCESS,
        Err(err) => {
            report_error(diagnostic_format, err);
            ExitCode::FAILURE
        }
    }
}

fn report_error(diagnostic_format: DiagnosticFormat, err: CliError) {
    match (diagnostic_format, err) {
        (DiagnosticFormat::Json, CliError::Diagnostic(diagnostic)) => {
            match diagnostic.render_json_pretty() {
                Ok(json) => eprintln!("{json}"),
                Err(err) => eprintln!("laniusc: failed to serialize diagnostic JSON: {err}"),
            }
        }
        (DiagnosticFormat::LspJson, CliError::Diagnostic(diagnostic)) => {
            match diagnostic.render_lsp_json_pretty() {
                Ok(json) => eprintln!("{json}"),
                Err(err) => eprintln!("laniusc: failed to serialize LSP diagnostic JSON: {err}"),
            }
        }
        (_, err) => eprintln!("laniusc: {err}"),
    }
}
