mod entry;
mod package;
mod source_pack;

use std::path::{Path, PathBuf};

use super::{
    args::CompileRequest,
    common::{CliError, missing_cli_argument_error},
    depfile,
    output::{CliEmission, CliOutputError, write_cli_emission},
};
use crate::{
    compiler::{EntrySourceRoots, NativeLinkOptions, load_entry_path_manifest_and_dependencies},
    gpu::device,
};

/// Runs a validated compile/check request.
///
/// This selects source-pack versus in-memory compile paths, persists the GPU
/// pipeline cache after compile work, and writes target output unless the
/// request is diagnostics-only.
pub(crate) fn run(request: CompileRequest) -> Result<(), CliError> {
    let CompileRequest {
        inputs,
        stdlib_paths,
        stdlib_root,
        source_roots,
        package_manifest,
        package_lockfile,
        output,
        depfile,
        emit,
        check_only,
        native_link,
        source_pack,
        uses_source_pack,
        shared_daemon: _,
    } = request;

    let emitted = match source_pack::dispatch(
        &emit,
        &stdlib_paths,
        &inputs,
        package_manifest.as_deref(),
        package_lockfile.as_deref(),
        &source_pack,
        uses_source_pack,
    )? {
        source_pack::Action::Done => return Ok(()),
        source_pack::Action::Emit(emitted) => emitted,
        source_pack::Action::NotRequested => {
            let emitted = compile_non_source_pack(
                &inputs,
                stdlib_root.as_deref(),
                &source_roots,
                package_manifest.as_deref(),
                package_lockfile.as_deref(),
                check_only,
                &emit,
                native_link.as_ref(),
            );
            // Debug dumps and dispatch captures are written even when the
            // compile failed: a failing compile is usually why they were asked for.
            if let Ok(gpu) = device::global_result() {
                crate::gpu::passes_core::debug_dump_buffers(&gpu.device, &gpu.queue, &emit);
                crate::gpu::passes_core::debug_write_capture(&gpu.device, &gpu.queue);
            }
            emitted?
        }
    };

    device::persist_created_pipelines();
    if !check_only {
        write_cli_emission(emitted, output.clone(), &emit)?;
    }
    if let Some(depfile) = depfile {
        write_depfile(
            &depfile,
            output.as_deref().filter(|_| !check_only),
            &inputs,
            stdlib_root.as_deref(),
            &source_roots,
            native_link.as_ref(),
        )?;
    }
    Ok(())
}

/// Writes the dependency file of a compile that ran in this process. The
/// compile entry points return only the output, so import discovery runs
/// once more here. A compile in the daemon records the list during its one
/// discovery.
fn write_depfile(
    depfile: &Path,
    output: Option<&Path>,
    inputs: &[PathBuf],
    stdlib_root: Option<&Path>,
    source_roots: &[PathBuf],
    native_link: Option<&NativeLinkOptions>,
) -> Result<(), CliError> {
    let input = required_entry_input(inputs, "laniusc --depfile")?;
    let roots = EntrySourceRoots {
        stdlib_root: stdlib_root.map(Path::to_path_buf),
        user_roots: source_roots.to_vec(),
    };
    let (_, sources) = load_entry_path_manifest_and_dependencies(input, &roots)
        .map_err(CliError::from_compile_error)?;
    depfile::write(depfile, output, &sources, native_link).map_err(CliOutputError::from)?;
    Ok(())
}

fn compile_non_source_pack(
    inputs: &[PathBuf],
    stdlib_root: Option<&Path>,
    source_roots: &[PathBuf],
    package_manifest: Option<&Path>,
    package_lockfile: Option<&Path>,
    check_only: bool,
    emit: &str,
    native_link: Option<&NativeLinkOptions>,
) -> Result<CliEmission, CliError> {
    if let Some(package_manifest) = package_manifest {
        package::compile_manifest(package_manifest, check_only, emit, native_link)
    } else if let Some(package_lockfile) = package_lockfile {
        package::compile_lockfile(package_lockfile, check_only, emit, native_link)
    } else if let Some(native_link) = native_link {
        let input = required_entry_input(inputs, "laniusc native linking")?;
        let roots = EntrySourceRoots {
            stdlib_root: stdlib_root.map(Path::to_path_buf),
            user_roots: source_roots.to_vec(),
        };
        entry::compile_native(input, &roots, native_link)
    } else if !source_roots.is_empty() {
        let input = required_entry_input(inputs, "laniusc --source-root")?;
        let roots = EntrySourceRoots {
            stdlib_root: stdlib_root.map(Path::to_path_buf),
            user_roots: source_roots.to_vec(),
        };
        entry::compile_source_root(input, &roots, check_only, emit)
    } else if let Some(stdlib_root) = stdlib_root {
        let input = required_entry_input(inputs, "laniusc --stdlib-root")?;
        entry::compile_stdlib_root(input, stdlib_root, check_only, emit)
    } else if let Some(input) = inputs.first() {
        entry::compile_single_file(input, check_only, emit)
    } else {
        entry::compile_default_demo(emit)
    }
}

fn required_entry_input<'a>(inputs: &'a [PathBuf], command: &str) -> Result<&'a Path, CliError> {
    inputs
        .first()
        .map(PathBuf::as_path)
        .ok_or_else(|| missing_cli_argument_error(command, "exactly one entry input file"))
}
