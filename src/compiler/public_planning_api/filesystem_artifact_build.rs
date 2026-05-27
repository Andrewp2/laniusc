use super::*;

pub fn prepare_pack_path_streams<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_pack_path_streams_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_path_streams_with_shards<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<PrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_pack_path_streams_for_target_with_shards(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_path_streams_for_target<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    prepare_pack_path_streams_for_target_with_shards(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_pack_path_streams_for_target_with_shards<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
{
    let has_stdlib_sources = stdlib_source_file_count != 0;
    let stdlib_library = has_stdlib_sources.then(|| ExplicitSourceLibraryPathDependencyStream {
        library_id: 0,
        source_file_count: stdlib_source_file_count,
        paths: Box::new(stdlib_paths.into_iter()) as Box<dyn Iterator<Item = P> + 'a>,
        dependency_library_count: 0,
        dependency_library_ids: Vec::new(),
    });
    let user_library = (user_source_file_count != 0).then(|| {
        let dependency_library_ids = if has_stdlib_sources {
            vec![0]
        } else {
            Vec::new()
        };
        ExplicitSourceLibraryPathDependencyStream {
            library_id: 1,
            source_file_count: user_source_file_count,
            paths: Box::new(user_paths.into_iter()) as Box<dyn Iterator<Item = P> + 'a>,
            dependency_library_count: dependency_library_ids.len(),
            dependency_library_ids,
        }
    });
    let libraries = stdlib_library.into_iter().chain(user_library);
    prepare_dependency_streams_for_target_with_shards(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn prepare_pack_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<PrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_pack_paths_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_paths_with_shards<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
) -> Result<PrepareResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    prepare_pack_paths_for_target_with_shards(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn prepare_pack_paths_for_target<'a, SP, UP>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_pack_paths_for_target_with_shards(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub fn prepare_pack_paths_for_target_with_shards<'a, SP, UP>(
    stdlib_paths: &'a [SP],
    user_paths: &'a [UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
{
    prepare_pack_path_streams_for_target_with_shards(
        stdlib_paths.len(),
        stdlib_paths.iter().map(|path| path.as_ref()),
        user_paths.len(),
        user_paths.iter().map(|path| path.as_ref()),
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )
}

pub fn execute_pack_paths<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_paths_for_target(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_pack_path_streams<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_path_streams_for_target(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_pack_path_streams_with_shards<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_path_streams_for_target_with_shards(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_pack_path_streams_for_target<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_path_streams_for_target_with_shards(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn run_pack_path_stream_worker<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    run_pack_path_stream_worker_with_shards(
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
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_pack_path_streams_for_target_with_shards<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_pack_path_streams_for_target_with_shards(
        stdlib_source_file_count,
        stdlib_paths,
        user_source_file_count,
        user_paths,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_artifact_manifest_build_for_target(artifact_root, target, executor)
}

pub fn run_pack_path_stream_worker_with_shards<'a, SI, UI, P, E>(
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared = prepare_path_stream_work_queue_chunk(
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
        return Err(work_queue_not_prepared_error(target, prepare_chunk_limit));
    }
    run_artifact_manifest_worker(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn run_pack_path_stream_path_worker<'a, SI, UI, P, E>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    run_pack_path_stream_path_worker_with_shards(
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
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn run_pack_path_stream_path_worker_with_shards<'a, SI, UI, P, E>(
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared = prepare_path_stream_work_queue_chunk(
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
        return Err(work_queue_not_prepared_error(target, prepare_chunk_limit));
    }
    run_path_artifact_manifest_worker(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub async fn run_pack_path_stream_work_queue_async<'a, SI, UI, P, E>(
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
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    run_pack_path_stream_work_queue_with_shards_async(
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
    .await
}

pub async fn run_pack_path_stream_work_queue_with_shards_async<'a, SI, UI, P, E>(
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
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SI: IntoIterator<Item = P> + 'a,
    UI: IntoIterator<Item = P> + 'a,
    P: AsRef<Path> + 'a,
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = limit_work_queue_worker_run_items(max_items).max(1);
    let prepared = prepare_path_stream_work_queue_chunk(
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
        return Err(work_queue_not_prepared_error(target, prepare_chunk_limit));
    }
    run_path_work_queue_async(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub async fn run_pack_paths_work_queue_async<'a, SP, UP, E>(
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
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    run_pack_paths_work_queue_with_shards_async(
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
    .await
}

pub async fn run_pack_paths_work_queue_with_shards_async<'a, SP, UP, E>(
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
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    SP: AsRef<Path> + 'a,
    UP: AsRef<Path> + 'a,
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    run_pack_path_stream_work_queue_with_shards_async(
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
    .await
}

pub fn execute_pack_paths_with_shards<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_paths_for_target_with_shards(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_pack_paths_for_target<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_pack_paths_for_target_with_shards(
        stdlib_paths,
        user_paths,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_pack_paths_for_target_with_shards<SP, UP, E>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_pack_paths_for_target_with_shards(
        stdlib_paths,
        user_paths,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_artifact_manifest_build_for_target(artifact_root, target, executor)
}
