mod report;
mod slangc;

use super::{
    common::{CliError, cli_args_without_diagnostic_format, extra_cli_argument_error},
    help::print_doctor_help,
};

pub(crate) fn run(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args = cli_args_without_diagnostic_format(
        "laniusc doctor",
        args,
        "--help, --skip-slangc-probe, --diagnostic-format",
    )?;
    let mut skip_slangc_probe = false;
    for arg in args {
        match arg.as_str() {
            "-h" | "--help" => {
                print_doctor_help();
                return Ok(());
            }
            "--skip-slangc-probe" => {
                skip_slangc_probe = true;
            }
            other => {
                return Err(extra_cli_argument_error(
                    "laniusc doctor",
                    other,
                    "--help, --skip-slangc-probe, --diagnostic-format",
                ));
            }
        }
    }

    let json = report::json_pretty(skip_slangc_probe)?;
    println!("{json}");
    Ok(())
}
