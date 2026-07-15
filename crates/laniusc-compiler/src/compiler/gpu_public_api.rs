use super::*;

#[cfg(test)]
/// Builds a path-backed source-pack manifest for test assertions.
pub(super) fn source_pack_path_build_manifest(
    manifest: &ExplicitSourcePackPathManifest,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    artifacts: SourcePackBuildArtifactManifest,
) -> SourcePackPathBuildManifest {
    SourcePackPathBuildManifest {
        version: SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION,
        source_file_count: manifest.files.len(),
        source_byte_count: manifest.files.iter().map(|file| file.byte_len).sum(),
        source_line_count: manifest
            .files
            .iter()
            .map(|file| file.line_count.unwrap_or(0))
            .sum(),
        source_files: manifest.files.clone(),
        library_dependencies: manifest.library_dependencies.clone(),
        limits,
        batch_limits,
        artifacts,
    }
}

/// Reads explicit source paths into source strings with path-labeled errors.
pub(super) fn read_explicit_source_paths<P: AsRef<Path>>(
    label: &str,
    paths: &[P],
) -> Result<Vec<String>, CompileError> {
    let mut sources = Vec::with_capacity(paths.len());
    for (i, path) in paths.iter().enumerate() {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            input_read_failed_error(
                path,
                format!("read explicit {label} source file {i}"),
                "could not read this explicit source file",
                err,
                "create the source file or pass a readable .lani input path",
            )
        })?;
        sources.push(source);
    }
    Ok(sources)
}

/// Reads file metadata for one explicit source path.
pub(super) fn read_explicit_source_path_metadata(
    label: &str,
    path_index: usize,
    library_id: u32,
    path: &Path,
) -> Result<ExplicitSourcePathFile, CompileError> {
    let metadata = fs::metadata(path).map_err(|err| {
        input_read_failed_error(
            path,
            format!("stat explicit {label} source file {path_index}"),
            "could not read metadata for this source file",
            err,
            "create the source file or pass a readable regular .lani input path",
        )
    })?;
    if !metadata.is_file() {
        return Err(input_path_invalid_error(
            path,
            format!("stat explicit {label} source file {path_index}"),
            "this source input is not a regular file",
            "source input path is not a regular file",
            "pass a readable regular .lani file",
        ));
    }
    let byte_len = usize::try_from(metadata.len()).map_err(|_| {
        source_pack_input_limit_exceeded(
            &format!("stat explicit {label} source file {path_index}"),
            format!(
                "source file {} is too large for this target",
                path.display()
            ),
            "file byte length does not fit the host target",
            Some(DiagnosticLabel::primary(
                path,
                1,
                1,
                1,
                None,
                "this source file is too large for this target",
            )),
        )
    })?;
    let modified_unix_nanos = source_file_modified_unix_nanos(&metadata);
    Ok(ExplicitSourcePathFile {
        library_id,
        path: path.to_path_buf(),
        byte_len,
        modified_unix_nanos,
        line_count: None,
    })
}

/// Converts file modification time to Unix nanoseconds when the platform exposes it.
pub(super) fn source_file_modified_unix_nanos(metadata: &fs::Metadata) -> Option<u128> {
    metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos())
}

/// Validates that one source file still matches its planned path metadata.
pub(super) fn validate_explicit_source_path_file_metadata(
    label: &str,
    path_index: usize,
    file: &ExplicitSourcePathFile,
) -> Result<(), CompileError> {
    let metadata = fs::metadata(&file.path).map_err(|err| {
        input_read_failed_error(
            &file.path,
            format!("stat explicit {label} source file {path_index}"),
            "could not read metadata for this source file",
            err,
            "restore the source file or regenerate the source-pack manifest",
        )
    })?;
    if !metadata.is_file() {
        return Err(input_path_invalid_error(
            &file.path,
            format!("stat explicit {label} source file {path_index}"),
            "this planned source input is not a regular file",
            "planned source input path is not a regular file",
            "restore the source file or regenerate the source-pack manifest",
        ));
    }
    let current_byte_len = usize::try_from(metadata.len()).map_err(|_| {
        source_pack_input_limit_exceeded(
            &format!("stat explicit {label} source file {path_index}"),
            format!(
                "planned source file {} is too large for this target",
                file.path.display()
            ),
            "file byte length does not fit the host target",
            Some(DiagnosticLabel::primary(
                &file.path,
                1,
                1,
                1,
                None,
                "this planned source file is too large for this target",
            )),
        )
    })?;
    if current_byte_len != file.byte_len {
        return Err(explicit_source_pack_manifest_invalid_at_path(
            &file.path,
            format!(
                "explicit {label} source file {path_index} changed since manifest was planned: byte_len was {}, now {}",
                file.byte_len, current_byte_len
            ),
            "this source file changed since the manifest was planned",
        ));
    }
    let current_modified_unix_nanos = source_file_modified_unix_nanos(&metadata);
    if file.modified_unix_nanos.is_some() && current_modified_unix_nanos != file.modified_unix_nanos
    {
        return Err(explicit_source_pack_manifest_invalid_at_path(
            &file.path,
            format!(
                "explicit {label} source file {path_index} changed since manifest was planned: modified_unix_nanos was {:?}, now {:?}",
                file.modified_unix_nanos, current_modified_unix_nanos
            ),
            "this source file changed since the manifest was planned",
        ));
    }
    Ok(())
}

/// Validates that all source files still match their planned path metadata.
pub(super) fn validate_explicit_source_path_files_metadata(
    label: &str,
    files: &[ExplicitSourcePathFile],
) -> Result<(), CompileError> {
    for (i, file) in files.iter().enumerate() {
        validate_explicit_source_path_file_metadata(label, i, file)?;
    }
    Ok(())
}

/// Validates and reads explicit source-path file records.
pub(super) fn read_explicit_source_path_files(
    label: &str,
    files: &[ExplicitSourcePathFile],
) -> Result<Vec<String>, CompileError> {
    validate_explicit_source_path_files_metadata(label, files)?;
    let mut sources = Vec::with_capacity(files.len());
    for (i, file) in files.iter().enumerate() {
        let source = fs::read_to_string(&file.path).map_err(|err| {
            input_read_failed_error(
                &file.path,
                format!("read explicit {label} source file {i}"),
                "could not read this planned source file",
                err,
                "restore the source file or regenerate the source-pack manifest",
            )
        })?;
        sources.push(source);
    }
    Ok(sources)
}

/// Initializes or returns a process-global GPU compiler for one backend set.
pub(super) fn global_gpu_compiler_for(
    compiler: &'static OnceLock<Result<GpuCompiler<'static>, CompileError>>,
    backends: GpuCompilerBackends,
) -> Result<&'static GpuCompiler<'static>, CompileError> {
    compiler
        .get_or_init(|| {
            let compiler = pollster::block_on(GpuCompiler::new_with_backends(backends));
            if compiler.is_ok() {
                device::persist_pipeline_cache();
            }
            compiler
        })
        .as_ref()
        .map_err(Clone::clone)
}

/// Returns the process-global frontend-only GPU compiler.
pub(super) fn global_frontend_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError>
{
    static GPU_FRONTEND_COMPILER: OnceLock<Result<GpuCompiler<'static>, CompileError>> =
        OnceLock::new();
    global_gpu_compiler_for(&GPU_FRONTEND_COMPILER, GpuCompilerBackends::frontend_only())
}

/// Returns the process-global WASM GPU compiler.
pub(super) fn global_wasm_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_WASM_COMPILER: OnceLock<Result<GpuCompiler<'static>, CompileError>> =
        OnceLock::new();
    global_gpu_compiler_for(&GPU_WASM_COMPILER, GpuCompilerBackends::wasm_only())
}

/// Returns the process-global x86 GPU compiler.
pub(super) fn global_x86_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_X86_COMPILER: OnceLock<Result<GpuCompiler<'static>, CompileError>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_X86_COMPILER, GpuCompilerBackends::x86_only())
}

/// Validates that an in-memory source pack fits the default bounded codegen unit.
pub(super) fn validate_in_memory_source_pack_fits_default_codegen_unit<S: AsRef<str>>(
    operation: &str,
    sources: &[S],
) -> Result<(), CompileError> {
    let limits = CodegenUnitLimits::default().normalized();
    if sources.len() > limits.max_source_files {
        return Err(source_pack_input_limit_exceeded(
            operation,
            format!("received {} in-memory source files", sources.len()),
            format!(
                "bounded codegen-unit source-file limit: {}",
                limits.max_source_files
            ),
            None,
        ));
    }

    let mut total_source_bytes = 0usize;
    for (source_index, source) in sources.iter().enumerate() {
        let source_bytes = source.as_ref().len();
        if source_bytes > limits.max_source_bytes {
            return Err(source_pack_input_limit_exceeded(
                operation,
                format!("source file {source_index} has {source_bytes} bytes"),
                format!(
                    "bounded codegen-unit byte limit: {}",
                    limits.max_source_bytes
                ),
                Some(source_pack_input_limit_label(
                    source_index,
                    "this in-memory source file exceeds the bounded codegen-unit byte limit",
                )),
            ));
        }
        total_source_bytes = total_source_bytes
            .checked_add(source_bytes)
            .ok_or_else(|| {
                source_pack_input_limit_exceeded(
                    operation,
                    "in-memory source-pack byte count overflowed",
                    "bounded codegen-unit byte limit could not be checked",
                    None,
                )
            })?;
        if total_source_bytes > limits.max_source_bytes {
            return Err(source_pack_input_limit_exceeded(
                operation,
                format!("received {total_source_bytes} total in-memory source bytes"),
                format!(
                    "bounded codegen-unit byte limit: {}",
                    limits.max_source_bytes
                ),
                None,
            ));
        }
    }
    Ok(())
}

fn source_pack_input_limit_exceeded(
    operation: &str,
    observed: impl Into<String>,
    limit: impl Into<String>,
    primary_label: Option<DiagnosticLabel>,
) -> CompileError {
    let mut diagnostic = Diagnostic::error("LNC0048", "source-pack input limit exceeded")
        .with_note(format!("operation: {operation}"))
        .with_note(observed)
        .with_note(limit)
        .with_note("use persisted source-pack descriptor work queues for larger codebases");
    if let Some(label) = primary_label {
        diagnostic = diagnostic.with_primary_label(label);
    }
    CompileError::Diagnostic(diagnostic)
}

fn source_pack_input_limit_label(source_index: usize, message: &str) -> DiagnosticLabel {
    DiagnosticLabel::primary(
        format!("<source pack file {source_index}>"),
        1,
        1,
        1,
        None,
        message,
    )
}

/// Compile one in-memory source string to WASM with the process-global GPU
/// compiler.
pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu(src)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

/// Type-check one in-memory source string with the process-global frontend GPU
/// compiler.
pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu(src)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

/// Type-check an in-memory source pack with the process-global frontend GPU
/// compiler.
pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>(
    sources: &[S],
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_pack(sources)
        .await
}

/// Type-checks one bounded library against complete dependency semantic
/// interfaces using the process-global frontend compiler.
pub async fn type_check_source_pack_with_dependency_interfaces_with_gpu<S: AsRef<str>>(
    library_id: u32,
    sources: &[S],
    dependency_interfaces: &[GpuSemanticInterfaceArtifact],
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_pack_with_dependencies(library_id, sources, dependency_interfaces)
        .await
}

/// Type-checks one bounded library source pack and returns its complete
/// canonical public semantic interface from the process-global frontend.
pub async fn semantic_interface_for_source_pack_with_gpu<S: AsRef<str>>(
    library_id: u32,
    sources: &[S],
) -> Result<GpuSemanticInterfaceArtifact, CompileError> {
    global_frontend_gpu_compiler()?
        .semantic_interface_for_source_pack(library_id, sources)
        .await
}

/// Type-checks one bounded library against persisted dependency interfaces and
/// returns its complete canonical public semantic interface.
pub async fn semantic_interface_for_source_pack_with_dependencies_with_gpu<S: AsRef<str>>(
    library_id: u32,
    sources: &[S],
    dependency_interfaces: &[GpuSemanticInterfaceArtifact],
) -> Result<GpuSemanticInterfaceArtifact, CompileError> {
    global_frontend_gpu_compiler()?
        .semantic_interface_for_source_pack_with_dependencies(
            library_id,
            sources,
            dependency_interfaces,
        )
        .await
}

/// Type-check an explicit in-memory source-pack manifest with the global
/// frontend GPU compiler.
pub async fn type_check_source_pack_manifest_with_gpu(
    source_pack: &ExplicitSourcePack,
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_pack_manifest(source_pack)
        .await
}

/// Load an entry file plus standard-library root into a source pack and
/// type-check it with the global frontend GPU compiler.
pub async fn type_check_entry_with_stdlib<EP, RP>(
    entry_path: EP,
    stdlib_root: RP,
) -> Result<(), CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_with_stdlib(entry_path, stdlib_root)?;
    global_frontend_gpu_compiler()?
        .type_check_source_pack_manifest(&source_pack)
        .await
}

/// Load an entry file plus one user source root into a source pack and
/// type-check it with the global frontend GPU compiler.
pub async fn type_check_entry_with_source_root<EP, RP>(
    entry_path: EP,
    source_root: RP,
) -> Result<(), CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_with_source_root(entry_path, source_root)?;
    global_frontend_gpu_compiler()?
        .type_check_source_pack_manifest(&source_pack)
        .await
}

/// Load an entry file plus explicit source roots into a source pack and
/// type-check it with the global frontend GPU compiler.
pub async fn type_check_entry_with_source_roots<EP>(
    entry_path: EP,
    roots: &EntrySourceRoots,
) -> Result<(), CompileError>
where
    EP: AsRef<Path>,
{
    let source_pack = load_entry_with_source_roots(entry_path, roots)?;
    global_frontend_gpu_compiler()?
        .type_check_source_pack_manifest(&source_pack)
        .await
}

/// Read one source file from disk and type-check it with path-labeled
/// diagnostics.
pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_from_path(path)
        .await
}

/// Compile an in-memory source pack to WASM with the process-global GPU
/// compiler.
pub async fn compile_source_pack_to_wasm_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(sources)
        .await
}

/// Compile an explicit in-memory source-pack manifest to WASM with the
/// process-global GPU compiler.
pub async fn compile_source_pack_manifest_to_wasm_with_gpu_codegen(
    source_pack: &ExplicitSourcePack,
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_manifest_to_wasm(source_pack)
        .await
}

/// Compile a path-backed source-pack manifest to Wasm, automatically using
/// bounded persisted units when one resident job would exceed unit limits.
pub async fn compile_source_pack_path_manifest_to_wasm_with_gpu_codegen(
    source_pack: &ExplicitSourcePackPathManifest,
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_path_manifest_to_wasm(source_pack)
        .await
}

/// Load an entry file plus standard-library root into a source pack and compile
/// it to WASM.
pub async fn compile_entry_to_wasm_with_stdlib<EP, RP>(
    entry_path: EP,
    stdlib_root: RP,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_stdlib(entry_path, stdlib_root)?;
    compile_path_manifest_to_wasm(&source_pack).await
}

/// Load an entry file plus one user source root into a source pack and compile
/// it to WASM.
pub async fn compile_entry_to_wasm_with_source_root<EP, RP>(
    entry_path: EP,
    source_root: RP,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_source_root(entry_path, source_root)?;
    compile_path_manifest_to_wasm(&source_pack).await
}

/// Load an entry file plus explicit source roots into a source pack and compile
/// it to WASM.
pub async fn compile_entry_to_wasm_with_source_roots<EP>(
    entry_path: EP,
    roots: &EntrySourceRoots,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_source_roots(entry_path, roots)?;
    compile_path_manifest_to_wasm(&source_pack).await
}

/// Read one source file from disk and compile it to WASM with path-labeled
/// diagnostics.
pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_to_wasm_from_path(path)
        .await
}

/// Compile one in-memory source string to x86_64 output with the process-global
/// GPU compiler.
pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu(src)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

/// Read one source file from disk and compile it to x86_64 output with
/// path-labeled diagnostics.
pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_to_x86_64_from_path(path)
        .await
}

/// Compile an in-memory source pack to x86_64 output with the process-global
/// GPU compiler.
pub async fn compile_source_pack_to_x86_64_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(sources)
        .await
}

/// Compile an explicit in-memory source-pack manifest to x86_64 output with the
/// process-global GPU compiler.
pub async fn compile_source_pack_manifest_to_x86_64_with_gpu_codegen(
    source_pack: &ExplicitSourcePack,
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_manifest_to_x86_64(source_pack)
        .await
}

/// Compile a path-backed source-pack manifest to x86_64, automatically using
/// bounded persisted units when one resident job would exceed unit limits.
pub async fn compile_source_pack_path_manifest_to_x86_64_with_gpu_codegen(
    source_pack: &ExplicitSourcePackPathManifest,
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_path_manifest_to_x86_64(source_pack)
        .await
}

/// Load an entry file plus standard-library root into a source pack and compile
/// it to x86_64 output.
pub async fn compile_entry_to_x86_64_with_stdlib<EP, RP>(
    entry_path: EP,
    stdlib_root: RP,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_stdlib(entry_path, stdlib_root)?;
    compile_path_manifest_to_x86_64(&source_pack).await
}

/// Load an entry file plus one user source root into a source pack and compile
/// it to x86_64 output.
pub async fn compile_entry_to_x86_64_with_source_root<EP, RP>(
    entry_path: EP,
    source_root: RP,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
    RP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_source_root(entry_path, source_root)?;
    compile_path_manifest_to_x86_64(&source_pack).await
}

/// Load an entry file plus explicit source roots into a source pack and compile
/// it to x86_64 output.
pub async fn compile_entry_to_x86_64_with_source_roots<EP>(
    entry_path: EP,
    roots: &EntrySourceRoots,
) -> Result<Vec<u8>, CompileError>
where
    EP: AsRef<Path>,
{
    let source_pack = load_entry_path_manifest_with_source_roots(entry_path, roots)?;
    compile_path_manifest_to_x86_64(&source_pack).await
}

async fn compile_path_manifest_to_wasm(
    source_pack: &ExplicitSourcePackPathManifest,
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_path_manifest_to_wasm(source_pack)
        .await
}

async fn compile_path_manifest_to_x86_64(
    source_pack: &ExplicitSourcePackPathManifest,
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_path_manifest_to_x86_64(source_pack)
        .await
}

/// Run descriptor work-queue items for an already prepared artifact root until
/// `max_items` is reached or no ready work remains.
pub async fn run_prepared_descriptor_worker_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
    let compiler = match target {
        SourcePackArtifactTarget::Wasm => global_wasm_gpu_compiler()?,
        SourcePackArtifactTarget::X86_64 => global_x86_gpu_compiler()?,
        SourcePackArtifactTarget::Generic => {
            return Err(source_pack_target_invalid_error(
                "run prepared descriptor worker",
                format!("{:?}", SourcePackArtifactTarget::Generic),
                "a concrete descriptor execution target: Wasm or X86_64",
            ));
        }
    };
    compiler
        .run_descriptor_work_queue(
            artifact_root,
            target,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Claim and execute at most one descriptor work-queue item for an already
/// prepared artifact root.
pub async fn step_prepared_descriptor_worker_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
    let compiler = match target {
        SourcePackArtifactTarget::Wasm => global_wasm_gpu_compiler()?,
        SourcePackArtifactTarget::X86_64 => global_x86_gpu_compiler()?,
        SourcePackArtifactTarget::Generic => {
            return Err(source_pack_target_invalid_error(
                "step prepared descriptor worker",
                format!("{:?}", SourcePackArtifactTarget::Generic),
                "a concrete descriptor execution target: Wasm or X86_64",
            ));
        }
    };
    compiler
        .step_descriptor_work_queue(
            artifact_root,
            target,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}
/// Prepare library path inputs if needed, then execute one WASM descriptor work
/// item.
pub async fn step_library_path_worker_to_wasm<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .step_library_path_worker_to_wasm(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}
/// Prepare library path inputs if needed, then execute one x86_64 descriptor
/// work item.
pub async fn step_library_path_worker_to_x86_64<I, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .step_library_path_worker_to_x86_64(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare path-stream inputs if needed, then run WASM descriptor work items
/// until `max_items` is reached or no ready work remains.
#[allow(clippy::too_many_arguments)]
pub async fn run_path_stream_worker_to_wasm<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .run_path_stream_worker_to_wasm(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare path-stream inputs if needed, then execute one WASM descriptor work
/// item.
#[allow(clippy::too_many_arguments)]
pub async fn step_path_stream_worker_to_wasm<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .step_path_stream_worker_to_wasm(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare path-stream inputs if needed, then run x86_64 descriptor work items
/// until `max_items` is reached or no ready work remains.
#[allow(clippy::too_many_arguments)]
pub async fn run_path_stream_worker_to_x86_64<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .run_path_stream_worker_to_x86_64(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare path-stream inputs if needed, then execute one x86_64 descriptor
/// work item.
#[allow(clippy::too_many_arguments)]
pub async fn step_path_stream_worker_to_x86_64<I, PI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .step_path_stream_worker_to_x86_64(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare dependency-stream inputs if needed, then run WASM descriptor work
/// items until `max_items` is reached or no ready work remains.
#[allow(clippy::too_many_arguments)]
pub async fn run_dependency_stream_worker_to_wasm<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .run_dependency_stream_worker_to_wasm(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare dependency-stream inputs if needed, then execute one WASM descriptor
/// work item.
#[allow(clippy::too_many_arguments)]
pub async fn step_dependency_stream_worker_to_wasm<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .step_dependency_stream_worker_to_wasm(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare dependency-stream inputs if needed, then run x86_64 descriptor work
/// items until `max_items` is reached or no ready work remains.
#[allow(clippy::too_many_arguments)]
pub async fn run_dependency_stream_worker_to_x86_64<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .run_dependency_stream_worker_to_x86_64(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

/// Prepare dependency-stream inputs if needed, then execute one x86_64
/// descriptor work item.
#[allow(clippy::too_many_arguments)]
pub async fn step_dependency_stream_worker_to_x86_64<I, PI, DI, P>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .step_dependency_stream_worker_to_x86_64(
            libraries,
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}
