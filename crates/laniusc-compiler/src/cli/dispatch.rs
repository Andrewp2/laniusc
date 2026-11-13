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
#[cfg(unix)]
use super::shared_daemon;

/// How a command ended when it did not return an error.
pub(super) enum Completion {
    Success,
    /// The command failed and has already printed why.
    ReportedFailure,
}

/// Parses raw CLI arguments and routes the resulting command to its owner.
pub(super) fn run(raw_args: Vec<String>) -> Result<Completion, CliError> {
    let diagnostic_format = diagnostic_format_from_args(raw_args.iter().cloned());
    let text_diagnostics = matches!(diagnostic_format, DiagnosticFormat::Text);
    let command = args::parse_args(raw_args)?;
    // A compile that the shared daemon of this build can run goes there. The
    // daemon keeps every GPU pipeline, so the compile takes tens of
    // milliseconds, and this process creates no device.
    #[cfg(unix)]
    if let Command::Compile(request) = &command
        && let Some(completion) = shared_daemon::compile(request, diagnostic_format)
    {
        return Ok(completion);
    }
    run_in_this_process(command, text_diagnostics).map(|()| Completion::Success)
}

fn run_in_this_process(command: Command, text_diagnostics: bool) -> Result<(), CliError> {
    // A resident compiler holds its device for hours and serializes its own
    // jobs. Every other command is a one-shot process: it waits for a GPU
    // process slot if it creates a device.
    if !matches!(command, Command::Daemon(_) | Command::Lsp(_)) {
        crate::gpu::process_slot::limit_this_process();
    }
    match command {
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
            // This compile was not handed to the shared daemon, so it creates
            // every GPU pipeline again. The hint is for a person at a
            // terminal who did not ask for that. A piped or JSON stderr
            // carries only diagnostics.
            if request.shared_daemon && text_diagnostics && std::io::stderr().is_terminal() {
                eprintln!(
                    "laniusc: warning: this compile starts the GPU compiler from scratch; `laniusc --help` lists the compiles that the shared daemon runs"
                );
            }
            compile::run(request)
        }
    }
}
