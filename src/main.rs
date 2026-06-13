mod cli;

fn main() -> std::process::ExitCode {
    cli::run_from_env()
}
