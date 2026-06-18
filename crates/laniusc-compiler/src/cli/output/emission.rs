use std::{
    fs,
    path::{Path, PathBuf},
};

use super::{
    CliOutputError,
    contract::read_linked_output_contract_descriptor,
    diagnostics::output_write_diagnostic,
    stream::write_stdout_bytes,
};

/// Output produced by a compile/source-pack command before final CLI writing.
pub(crate) enum CliEmission {
    /// In-memory target bytes.
    Bytes(Vec<u8>),
    /// Path to a linked-output contract descriptor produced by source-pack mode.
    ContractDescriptorFile(PathBuf),
}

/// Writes CLI emission to `-o/--out` or stdout.
pub(crate) fn write_cli_emission(
    emitted: CliEmission,
    output: Option<PathBuf>,
    emit: &str,
) -> Result<(), CliOutputError> {
    match emitted {
        CliEmission::Bytes(bytes) => {
            if let Some(output) = output {
                fs::write(&output, bytes).map_err(|err| {
                    output_write_diagnostic(&output, emit, "write target bytes", err)
                })?;
                mark_output_executable_if_needed(&output, emit)?;
            } else {
                write_stdout_bytes(emit, "write target bytes", &bytes)?;
            }
        }
        CliEmission::ContractDescriptorFile(path) => {
            let bytes = read_linked_output_contract_descriptor(&path, emit)?;
            if let Some(output) = output {
                fs::write(&output, bytes).map_err(|err| {
                    output_write_diagnostic(
                        &output,
                        emit,
                        "write linked-output contract descriptor",
                        err,
                    )
                })?;
            } else {
                write_stdout_bytes(
                    emit,
                    format!(
                        "stream linked-output contract descriptor {}",
                        path.display()
                    ),
                    &bytes,
                )?;
            }
        }
    }
    Ok(())
}

fn mark_output_executable_if_needed(output: &Path, emit: &str) -> Result<(), CliOutputError> {
    #[cfg(unix)]
    if emit != "wasm" {
        use std::os::unix::fs::PermissionsExt;
        let mut permissions = fs::metadata(output)
            .map_err(|err| output_write_diagnostic(output, emit, "stat output file", err))?
            .permissions();
        permissions.set_mode(0o755);
        fs::set_permissions(output, permissions)
            .map_err(|err| output_write_diagnostic(output, emit, "mark output executable", err))?;
    }
    #[cfg(not(unix))]
    let _ = (output, emit);
    Ok(())
}
