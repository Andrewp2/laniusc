use super::*;

#[cfg(test)]
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

pub(super) fn read_explicit_source_paths<P: AsRef<Path>>(
    label: &str,
    paths: &[P],
) -> Result<Vec<String>, CompileError> {
    let mut sources = Vec::with_capacity(paths.len());
    for (i, path) in paths.iter().enumerate() {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read explicit {label} source file {i} ({}): {err}",
                path.display()
            ))
        })?;
        sources.push(source);
    }
    Ok(sources)
}

pub(super) fn read_explicit_source_path_metadata(
    label: &str,
    path_index: usize,
    library_id: u32,
    path: &Path,
) -> Result<ExplicitSourcePathFile, CompileError> {
    let metadata = fs::metadata(path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): {err}",
            path.display()
        ))
    })?;
    if !metadata.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): not a regular file",
            path.display()
        )));
    }
    let byte_len = usize::try_from(metadata.len()).map_err(|_| {
        CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): file is too large for this target",
            path.display()
        ))
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

pub(super) fn source_file_modified_unix_nanos(metadata: &fs::Metadata) -> Option<u128> {
    metadata
        .modified()
        .ok()
        .and_then(|modified| modified.duration_since(UNIX_EPOCH).ok())
        .map(|duration| duration.as_nanos())
}

pub(super) fn validate_explicit_source_path_file_metadata(
    label: &str,
    path_index: usize,
    file: &ExplicitSourcePathFile,
) -> Result<(), CompileError> {
    let metadata = fs::metadata(&file.path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): {err}",
            file.path.display()
        ))
    })?;
    if !metadata.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): not a regular file",
            file.path.display()
        )));
    }
    let current_byte_len = usize::try_from(metadata.len()).map_err(|_| {
        CompileError::GpuFrontend(format!(
            "stat explicit {label} source file {path_index} ({}): file is too large for this target",
            file.path.display()
        ))
    })?;
    if current_byte_len != file.byte_len {
        return Err(CompileError::GpuFrontend(format!(
            "explicit {label} source file {path_index} ({}) changed since manifest was planned: byte_len was {}, now {}",
            file.path.display(),
            file.byte_len,
            current_byte_len
        )));
    }
    let current_modified_unix_nanos = source_file_modified_unix_nanos(&metadata);
    if file.modified_unix_nanos.is_some() && current_modified_unix_nanos != file.modified_unix_nanos
    {
        return Err(CompileError::GpuFrontend(format!(
            "explicit {label} source file {path_index} ({}) changed since manifest was planned: modified_unix_nanos was {:?}, now {:?}",
            file.path.display(),
            file.modified_unix_nanos,
            current_modified_unix_nanos
        )));
    }
    Ok(())
}

pub(super) fn validate_explicit_source_path_files_metadata(
    label: &str,
    files: &[ExplicitSourcePathFile],
) -> Result<(), CompileError> {
    for (i, file) in files.iter().enumerate() {
        validate_explicit_source_path_file_metadata(label, i, file)?;
    }
    Ok(())
}

pub(super) fn read_explicit_source_path_files(
    label: &str,
    files: &[ExplicitSourcePathFile],
) -> Result<Vec<String>, CompileError> {
    validate_explicit_source_path_files_metadata(label, files)?;
    let mut sources = Vec::with_capacity(files.len());
    for (i, file) in files.iter().enumerate() {
        let source = fs::read_to_string(&file.path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read explicit {label} source file {i} ({}): {err}",
                file.path.display()
            ))
        })?;
        sources.push(source);
    }
    Ok(sources)
}

pub(super) fn prepare_source_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

pub(super) fn prepare_source_for_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

pub(super) fn prepare_source_for_gpu_type_check(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

pub(super) fn prepare_source_for_gpu_type_check_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

pub(super) fn global_gpu_compiler_for(
    compiler: &'static OnceLock<Result<GpuCompiler<'static>, String>>,
    backends: GpuCompilerBackends,
    label: &'static str,
) -> Result<&'static GpuCompiler<'static>, CompileError> {
    compiler
        .get_or_init(|| {
            pollster::block_on(GpuCompiler::new_with_device_and_backends(
                device::global(),
                backends,
            ))
            .map_err(|err| err.to_string())
        })
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize {label} GPU compiler: {err}")))
}

pub(super) fn global_frontend_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError>
{
    static GPU_FRONTEND_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(
        &GPU_FRONTEND_COMPILER,
        GpuCompilerBackends::frontend_only(),
        "frontend",
    )
}

pub(super) fn global_wasm_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_WASM_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_WASM_COMPILER, GpuCompilerBackends::wasm_only(), "WASM")
}

pub(super) fn global_x86_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_X86_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_X86_COMPILER, GpuCompilerBackends::x86_only(), "x86")
}

pub(super) fn reject_raw_source_pack_paths_for_gpu_descriptor_worker<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<(), CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    if !stdlib_paths.is_empty() || !user_paths.is_empty() {
        return Err(CompileError::GpuCodegen(
            "source-pack GPU descriptor workers require prepared artifact records; raw stdlib/user path inputs are not accepted"
                .to_string(),
        ));
    }
    Ok(())
}

pub(super) fn validate_in_memory_source_pack_fits_default_codegen_unit<S: AsRef<str>>(
    operation: &str,
    sources: &[S],
) -> Result<(), CompileError> {
    let limits = CodegenUnitLimits::default().normalized();
    if sources.len() > limits.max_source_files {
        return Err(CompileError::GpuFrontend(format!(
            "{operation} received {} in-memory source files, exceeding the bounded codegen-unit limit {}; use persisted source-pack descriptor work queues for larger codebases",
            sources.len(),
            limits.max_source_files
        )));
    }

    let mut total_source_bytes = 0usize;
    for (source_index, source) in sources.iter().enumerate() {
        let source_bytes = source.as_ref().len();
        if source_bytes > limits.max_source_bytes {
            return Err(CompileError::GpuFrontend(format!(
                "{operation} source file {source_index} has {source_bytes} bytes, exceeding the bounded codegen-unit limit {}; use persisted source-pack descriptor work queues for larger codebases",
                limits.max_source_bytes
            )));
        }
        total_source_bytes = total_source_bytes.checked_add(source_bytes).ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "{operation} in-memory source-pack byte count overflowed; use persisted source-pack descriptor work queues for larger codebases"
            ))
        })?;
        if total_source_bytes > limits.max_source_bytes {
            return Err(CompileError::GpuFrontend(format!(
                "{operation} received {total_source_bytes} total in-memory source bytes, exceeding the bounded codegen-unit limit {}; use persisted source-pack descriptor work queues for larger codebases",
                limits.max_source_bytes
            )));
        }
    }
    Ok(())
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>(
    sources: &[S],
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_pack(sources)
        .await
}

pub async fn type_check_source_pack_manifest_with_gpu(
    source_pack: &ExplicitSourcePack,
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_source_pack_manifest(source_pack)
        .await
}

pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_with_gpu_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn type_check_source_pack_with_gpu_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    compiler.type_check_source_pack(sources).await
}

pub async fn type_check_source_pack_manifest_with_gpu_using(
    source_pack: &ExplicitSourcePack,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    compiler.type_check_source_pack_manifest(source_pack).await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(sources)
        .await
}

pub async fn compile_source_pack_manifest_to_wasm_with_gpu_codegen(
    source_pack: &ExplicitSourcePack,
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_manifest_to_wasm(source_pack)
        .await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_wasm(sources).await
}

pub async fn compile_source_pack_manifest_to_wasm_with_gpu_codegen_using(
    source_pack: &ExplicitSourcePack,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler
        .compile_source_pack_manifest_to_wasm(source_pack)
        .await
}

pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let source_pack = load_explicit_source_pack_manifest_from_paths(stdlib_paths, user_paths)?;
    global_wasm_gpu_compiler()?
        .compile_source_pack_manifest_to_wasm(&source_pack)
        .await
}

#[deprecated(
    note = "compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen whole-loads source files; use prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target plus submit_gpu_descriptor_work_queue_step_using for scalable builds"
)]
pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen(
        stdlib_paths,
        user_paths,
    )
    .await
}

pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    let source_pack = load_explicit_source_libraries_from_paths(libraries)?;
    global_wasm_gpu_compiler()?
        .compile_source_pack_manifest_to_wasm(&source_pack)
        .await
}

#[deprecated(
    note = "compile_explicit_source_libraries_to_wasm_with_gpu_codegen whole-loads source files; use ordered path dependency streams plus filesystem work-queue descriptor submission for scalable builds"
)]
pub async fn compile_explicit_source_libraries_to_wasm_with_gpu_codegen<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen(libraries).await
}

pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_legacy_in_memory_to_wasm(stdlib_paths, user_paths)
        .await
}

#[deprecated(
    note = "compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen_using whole-loads source files; use prepared source-pack filesystem work queues for scalable builds"
)]
pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compile_explicit_source_pack_paths_legacy_in_memory_to_wasm_with_gpu_codegen_using(
        stdlib_paths,
        user_paths,
        compiler,
    )
    .await
}

pub async fn compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen_using<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compiler
        .compile_explicit_source_libraries_legacy_in_memory_to_wasm(libraries)
        .await
}

#[deprecated(
    note = "compile_explicit_source_libraries_to_wasm_with_gpu_codegen_using whole-loads source files; use prepared source-pack filesystem work queues for scalable builds"
)]
pub async fn compile_explicit_source_libraries_to_wasm_with_gpu_codegen_using<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compile_explicit_source_libraries_legacy_in_memory_to_wasm_with_gpu_codegen_using(
        libraries, compiler,
    )
    .await
}

pub async fn type_check_source_with_gpu_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(sources)
        .await
}

pub async fn compile_source_pack_manifest_to_x86_64_with_gpu_codegen(
    source_pack: &ExplicitSourcePack,
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_manifest_to_x86_64(source_pack)
        .await
}

pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let source_pack = load_explicit_source_pack_manifest_from_paths(stdlib_paths, user_paths)?;
    global_x86_gpu_compiler()?
        .compile_source_pack_manifest_to_x86_64(&source_pack)
        .await
}

#[deprecated(
    note = "compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen whole-loads source files; use prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target plus submit_gpu_descriptor_work_queue_step_using for scalable builds"
)]
pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen(
        stdlib_paths,
        user_paths,
    )
    .await
}

pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    let source_pack = load_explicit_source_libraries_from_paths(libraries)?;
    global_x86_gpu_compiler()?
        .compile_source_pack_manifest_to_x86_64(&source_pack)
        .await
}

#[deprecated(
    note = "compile_explicit_source_libraries_to_x86_64_with_gpu_codegen whole-loads source files; use ordered path dependency streams plus filesystem work-queue descriptor submission for scalable builds"
)]
pub async fn compile_explicit_source_libraries_to_x86_64_with_gpu_codegen<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen(libraries).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_x86_64(sources).await
}

pub async fn compile_source_pack_manifest_to_x86_64_with_gpu_codegen_using(
    source_pack: &ExplicitSourcePack,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler
        .compile_source_pack_manifest_to_x86_64(source_pack)
        .await
}

pub async fn compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64(stdlib_paths, user_paths)
        .await
}

#[deprecated(
    note = "compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen_using whole-loads source files; use prepared source-pack filesystem work queues for scalable builds"
)]
pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compile_explicit_source_pack_paths_legacy_in_memory_to_x86_64_with_gpu_codegen_using(
        stdlib_paths,
        user_paths,
        compiler,
    )
    .await
}

pub async fn compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen_using<
    P,
>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compiler
        .compile_explicit_source_libraries_legacy_in_memory_to_x86_64(libraries)
        .await
}

#[deprecated(
    note = "compile_explicit_source_libraries_to_x86_64_with_gpu_codegen_using whole-loads source files; use prepared source-pack filesystem work queues for scalable builds"
)]
pub async fn compile_explicit_source_libraries_to_x86_64_with_gpu_codegen_using<P>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    P: AsRef<Path>,
{
    compile_explicit_source_libraries_legacy_in_memory_to_x86_64_with_gpu_codegen_using(
        libraries, compiler,
    )
    .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
    global_wasm_gpu_compiler()?
        .execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors(
            artifact_root,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_step_to_wasm_with_gpu_descriptors(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
    global_wasm_gpu_compiler()?
        .execute_prepared_source_pack_filesystem_work_queue_worker_step_to_wasm_with_gpu_descriptors(
            artifact_root,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors_using(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
    compiler
        .execute_prepared_source_pack_filesystem_work_queue_worker_run_to_wasm_with_gpu_descriptors(
            artifact_root,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_step_to_wasm_with_gpu_descriptors_using(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
    compiler
        .execute_prepared_source_pack_filesystem_work_queue_worker_step_to_wasm_with_gpu_descriptors(
            artifact_root,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
    global_x86_gpu_compiler()?
        .execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
            artifact_root,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
    global_x86_gpu_compiler()?
        .execute_prepared_source_pack_filesystem_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
            artifact_root,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors_using(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError> {
    compiler
        .execute_prepared_source_pack_filesystem_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
            artifact_root,
            worker_id,
            max_items,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

pub async fn execute_prepared_source_pack_filesystem_work_queue_worker_step_to_x86_64_with_gpu_descriptors_using(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError> {
    compiler
        .execute_prepared_source_pack_filesystem_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
            artifact_root,
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
        )
        .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors<
    I,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors_using<
    I,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors<
    I,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors_using<
    I,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors_using<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors_using<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors_using<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors_using<
    I,
    PI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors_using<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_wasm_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors_using<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors_using<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    global_x86_gpu_compiler()?
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors_using<
    I,
    PI,
    DI,
    P,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    compiler
        .execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    global_wasm_gpu_compiler()?
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    compiler
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_wasm_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    global_wasm_gpu_compiler()?
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    compiler
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_wasm_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    global_x86_gpu_compiler()?
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    compiler
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_to_x86_64_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    global_x86_gpu_compiler()?
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors_using<
    SP,
    UP,
>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    compiler: &GpuCompiler<'_>,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    reject_raw_source_pack_paths_for_gpu_descriptor_worker(stdlib_paths, user_paths)?;
    compiler
        .execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_to_x86_64_with_gpu_descriptors(
            stdlib_paths,
            user_paths,
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

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        path_streams,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepare_chunk_limit = source_pack_limit_work_queue_worker_run_items(max_items).max(1);
    let prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            dependency_streams,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_work_queue_worker_run_items(max_items).max(1);
    let prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            libraries,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_work_queue_worker_run_items(max_items).max(1);
    let prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            prepare_chunk_limit,
        )?;
    if !prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                prepare_chunk_limit,
            ),
        );
    }
    execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_run_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        path_streams,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let work_queue_prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            dependency_streams,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared.submit_path_artifact_work_queue_step(
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let work_queue_prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            libraries,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared.submit_path_artifact_work_queue_step(
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let work_queue_prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared.submit_path_artifact_work_queue_step(
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        path_streams,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let work_queue_prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            dependency_streams,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared
        .submit_path_artifact_work_queue_step_async(
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
        .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<
    I,
    PI,
    DI,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let work_queue_prepared =
        prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            libraries,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared
        .submit_path_artifact_work_queue_step_async(
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
        .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target<
    'a,
    SI,
    UI,
    P,
    E,
>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let work_queue_prepared =
        prepare_explicit_source_pack_path_streams_filesystem_work_queue_chunk_with_shard_limits_for_target(
            stdlib_source_file_count,
            stdlib_paths,
            user_source_file_count,
            user_paths,
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
    if !work_queue_prepared {
        return Err(
            source_pack_work_queue_not_prepared_after_bounded_chunk_error(
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            ),
        );
    }
    let prepared = SourcePackFilesystemPreparedArtifactBuild::new(&artifact_root, target);
    prepared
        .submit_path_artifact_work_queue_step_async(
            worker_id,
            lease_expires_unix_nanos,
            max_ready_items,
            executor,
        )
        .await
}

#[allow(clippy::too_many_arguments)]
pub async fn execute_explicit_source_pack_paths_filesystem_artifact_build_work_queue_worker_step_async_with_path_artifacts_for_target<
    'a,
    SP,
    UP,
    E,
>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_explicit_source_pack_path_streams_filesystem_artifact_build_work_queue_worker_step_async_with_shard_limits_and_path_artifacts_for_target(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}
