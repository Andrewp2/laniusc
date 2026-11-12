use std::io::IsTerminal;

use super::{
    args::{self, Command},
    common::{CliError, DiagnosticFormat, diagnostic_format_from_args},
    compile,
    daemon,
    diagnostics,
    doctor,
    fmt,
    help,
    lsp,
    package,
    test_command,
};

/// Parses raw CLI arguments and routes the resulting command to its owner.
pub(super) fn run(raw_args: Vec<String>) -> Result<(), CliError> {
    let text_diagnostics =
        matches!(diagnostic_format_from_args(raw_args.iter().cloned()), DiagnosticFormat::Text);
    match args::parse_args(raw_args)? {
        Command::Help => {
            help::print_help();
            Ok(())
        }
        Command::Version => {
            help::print_version();
            Ok(())
        }
        Command::Fmt(args) => fmt::run(args),
        Command::Doctor(args) => doctor::run(args),
        Command::Daemon(args) => daemon::run(args),
        Command::Test(args) => test_command::run(args),
        Command::Package(args) => package::run(args),
        Command::Lsp(args) => lsp::run(args),
        Command::Diagnostics(args) => diagnostics::run(args),
        Command::Compile(request) => {
            // A one-shot compile creates every GPU pipeline again; the resident
            // compiler pays that once and then compiles in tens of milliseconds.
            // The hint is for a person at a terminal. A piped or JSON stderr
            // carries only diagnostics.
            if text_diagnostics && std::io::stderr().is_terminal() {
                eprintln!(
                    "laniusc: warning: this one-shot compile starts the GPU compiler from scratch; use `laniusc daemon` (one resident compiler) for repeated compiles"
                );
            }
            compile::run(request)
        }
    }
}
