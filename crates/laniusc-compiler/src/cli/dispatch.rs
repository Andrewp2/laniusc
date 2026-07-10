use super::{
    args::{self, Command},
    common::CliError,
    compile,
    daemon,
    diagnostics,
    doctor,
    fmt,
    help,
    lsp,
    package,
};

/// Parses raw CLI arguments and routes the resulting command to its owner.
pub(super) fn run(raw_args: Vec<String>) -> Result<(), CliError> {
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
        Command::Package(args) => package::run(args),
        Command::Lsp(args) => lsp::run(args),
        Command::Diagnostics(args) => diagnostics::run(args),
        Command::Compile(request) => compile::run(request),
    }
}
