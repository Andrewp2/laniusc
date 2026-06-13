mod entry;
mod package;
mod source_pack;

use std::path::{Path, PathBuf};

use laniusc::{compiler::EntrySourceRoots, gpu::device};

use super::{
    args::CompileRequest,
    common::{CliError, missing_cli_argument_error},
    output::{CliEmission, write_cli_emission},
};

pub(crate) fn run(request: CompileRequest) -> Result<(), CliError> {
    let CompileRequest {
        inputs,
        stdlib_paths,
        stdlib_root,
        source_roots,
        package_manifest,
        package_lockfile,
        output,
        emit,
        check_only,
        source_pack,
        uses_source_pack,
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
        source_pack::Action::NotRequested => compile_non_source_pack(
            &inputs,
            stdlib_root.as_deref(),
            &source_roots,
            package_manifest.as_deref(),
            package_lockfile.as_deref(),
            check_only,
            &emit,
        )?,
    };

    device::persist_pipeline_cache();
    if check_only {
        return Ok(());
    }
    write_cli_emission(emitted, output, &emit)?;
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
) -> Result<CliEmission, CliError> {
    if let Some(package_manifest) = package_manifest {
        package::compile_manifest(package_manifest, check_only, emit)
    } else if let Some(package_lockfile) = package_lockfile {
        package::compile_lockfile(package_lockfile, check_only, emit)
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
