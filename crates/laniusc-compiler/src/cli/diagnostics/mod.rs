mod registry;
mod runtime;
mod source_pack_progress;
mod version_policy;

use self::{
    registry::{
        diagnostic_categories_json_pretty,
        diagnostic_code_json_pretty,
        diagnostic_codes_json_pretty,
    },
    runtime::{
        diagnostic_runtime_api_json_pretty,
        diagnostic_runtime_apis_json_pretty,
        diagnostic_runtime_service_apis_json_pretty,
        diagnostic_runtime_service_json_pretty,
        diagnostic_runtime_services_json_pretty,
    },
    source_pack_progress::diagnostic_source_pack_progress_json_pretty,
    version_policy::{
        diagnostic_command_discovery_json_pretty,
        diagnostic_formatter_policy_json_pretty,
        diagnostic_version_policy_json_pretty,
    },
};
use super::{
    common::{
        CliError,
        cli_args_without_diagnostic_format,
        extra_cli_argument_error,
        missing_cli_argument_error,
        unknown_cli_subcommand_error,
    },
    help::{print_diagnostics_code_help, print_diagnostics_explain_help, print_diagnostics_help},
};
use crate::compiler::{
    diagnostic_explanation_json_pretty,
    diagnostic_output_formats_json_pretty,
    diagnostic_registry_json_pretty,
};

/// Runs the no-run diagnostics metadata subcommand family.
pub(crate) fn run(args: impl IntoIterator<Item = String>) -> Result<(), CliError> {
    let args = cli_args_without_diagnostic_format(
        "laniusc diagnostics",
        args,
        "--help, registry, commands, codes, code, categories, formats, formatter, version-policy, explain, runtime-api, runtime-apis, runtime-service, runtime-service-apis, runtime-services, source-pack-progress, --diagnostic-format",
    )?;
    let mut args = args.into_iter();
    let Some(command) = args.next() else {
        print_diagnostics_help();
        return Ok(());
    };

    match command.as_str() {
        "-h" | "--help" => {
            print_diagnostics_help();
            Ok(())
        }
        "registry" => print_no_arg_json(
            "laniusc diagnostics registry",
            args,
            "serialize diagnostic registry",
            diagnostic_registry_json_pretty,
        ),
        "commands" => print_no_arg_json(
            "laniusc diagnostics commands",
            args,
            "serialize diagnostic command discovery",
            diagnostic_command_discovery_json_pretty,
        ),
        "codes" => print_no_arg_json(
            "laniusc diagnostics codes",
            args,
            "serialize diagnostic code index",
            diagnostic_codes_json_pretty,
        ),
        "code" => {
            let code = args.next().ok_or_else(|| {
                missing_cli_argument_error("laniusc diagnostics code", "a diagnostic code")
            })?;
            if matches!(code.as_str(), "-h" | "--help") {
                print_diagnostics_code_help();
                return Ok(());
            }
            reject_extra_arg("laniusc diagnostics code", args, "CODE")?;
            let json = diagnostic_code_json_pretty(&code)
                .map_err(|err| format!("serialize diagnostic code row: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "categories" => print_no_arg_json(
            "laniusc diagnostics categories",
            args,
            "serialize diagnostic categories",
            diagnostic_categories_json_pretty,
        ),
        "formats" => print_no_arg_json(
            "laniusc diagnostics formats",
            args,
            "serialize diagnostic output formats",
            diagnostic_output_formats_json_pretty,
        ),
        "formatter" => print_no_arg_json(
            "laniusc diagnostics formatter",
            args,
            "serialize formatter policy",
            diagnostic_formatter_policy_json_pretty,
        ),
        "version-policy" => print_no_arg_json(
            "laniusc diagnostics version-policy",
            args,
            "serialize version policy",
            diagnostic_version_policy_json_pretty,
        ),
        "explain" => {
            let code = args.next().ok_or_else(|| {
                missing_cli_argument_error("laniusc diagnostics explain", "a diagnostic code")
            })?;
            if matches!(code.as_str(), "-h" | "--help") {
                print_diagnostics_explain_help();
                return Ok(());
            }
            reject_extra_arg("laniusc diagnostics explain", args, "CODE")?;
            let json = diagnostic_explanation_json_pretty(&code)
                .map_err(|err| format!("serialize diagnostic explanation: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "runtime-api" => {
            let api_name = args.next().ok_or_else(|| {
                missing_cli_argument_error(
                    "laniusc diagnostics runtime-api",
                    "a stdlib API selector such as std::io::write_stdout or stdio::write_stdout",
                )
            })?;
            reject_extra_arg("laniusc diagnostics runtime-api", args, "API")?;
            let json = diagnostic_runtime_api_json_pretty(&api_name)
                .map_err(|err| format!("serialize runtime API diagnostic contract: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "runtime-apis" => print_no_arg_json(
            "laniusc diagnostics runtime-apis",
            args,
            "serialize runtime API diagnostic index",
            diagnostic_runtime_apis_json_pretty,
        ),
        "runtime-service" => {
            let service_selector = args.next().ok_or_else(|| {
                missing_cli_argument_error(
                    "laniusc diagnostics runtime-service",
                    "a runtime service id, service name, module path, capability constant, runtime probe, or qualified runtime-bound API such as std::io::write_stdout",
                )
            })?;
            reject_extra_arg("laniusc diagnostics runtime-service", args, "SERVICE")?;
            let json = diagnostic_runtime_service_json_pretty(&service_selector)
                .map_err(|err| format!("serialize runtime service diagnostic contract: {err}"))?;
            println!("{json}");
            Ok(())
        }
        "runtime-service-apis" => {
            let service_selector = args.next().ok_or_else(|| {
                missing_cli_argument_error(
                    "laniusc diagnostics runtime-service-apis",
                    "a runtime service id, service name, module path, capability constant, runtime probe, or qualified runtime-bound API such as std::io::write_stdout",
                )
            })?;
            reject_extra_arg("laniusc diagnostics runtime-service-apis", args, "SERVICE")?;
            let json =
                diagnostic_runtime_service_apis_json_pretty(&service_selector).map_err(|err| {
                    format!("serialize runtime service API diagnostic contract: {err}")
                })?;
            println!("{json}");
            Ok(())
        }
        "runtime-services" => print_no_arg_json(
            "laniusc diagnostics runtime-services",
            args,
            "serialize runtime service diagnostic index",
            diagnostic_runtime_services_json_pretty,
        ),
        "source-pack-progress" => {
            let json = diagnostic_source_pack_progress_json_pretty(args)?;
            println!("{json}");
            Ok(())
        }
        other => Err(unknown_cli_subcommand_error(
            "laniusc diagnostics",
            other,
            "registry, commands, codes, code, categories, formats, formatter, version-policy, explain, runtime-api, runtime-apis, runtime-service, runtime-service-apis, runtime-services, source-pack-progress",
        )),
    }
}

fn print_no_arg_json(
    command: &str,
    args: impl Iterator<Item = String>,
    serialize_context: &str,
    build_json: fn() -> Result<String, serde_json::Error>,
) -> Result<(), CliError> {
    reject_extra_arg(command, args, "no options")?;
    let json = build_json().map_err(|err| format!("{serialize_context}: {err}"))?;
    println!("{json}");
    Ok(())
}

fn reject_extra_arg(
    command: &str,
    mut args: impl Iterator<Item = String>,
    expected: &str,
) -> Result<(), CliError> {
    if let Some(extra) = args.next() {
        return Err(extra_cli_argument_error(command, &extra, expected));
    }
    Ok(())
}
