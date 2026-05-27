use super::*;

pub async fn run_ordered_path_stream_artifact_worker_async<I, PI, P, E>(
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
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepare_chunk_limit = limit_work_queue_worker_run_items(max_items).max(1);
    let prepared = prepare_dependency_stream_work_queue_chunk(
        dependency_streams,
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

pub fn execute_dependency_stream_artifact_build<I, PI, DI, P, E>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_dependency_streams_for_target_with_shards(
        libraries,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_artifact_manifest_build_for_target(artifact_root, target, executor)
}

pub fn run_dependency_stream_artifact_worker<I, PI, DI, P, E>(
    libraries: I,
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
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    run_dependency_stream_artifact_worker_with_shards(
        libraries,
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

pub fn run_dependency_stream_artifact_worker_with_shards<I, PI, DI, P, E>(
    libraries: I,
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
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared = prepare_dependency_stream_work_queue_chunk(
        libraries,
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

pub fn run_dependency_stream_path_artifact_worker<I, PI, DI, P, E>(
    libraries: I,
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
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    run_dependency_stream_path_artifact_worker_with_shards(
        libraries,
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

pub fn run_dependency_stream_path_artifact_worker_with_shards<I, PI, DI, P, E>(
    libraries: I,
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
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = limit_artifact_worker_run_batches(max_batches).max(1);
    let prepared = prepare_dependency_stream_work_queue_chunk(
        libraries,
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

pub(in crate::compiler) fn prepare_library_pages_artifact_build(
    prepared_pages: PreparedLibrarySchedulePages,
    store: &FilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError> {
    prepare_library_pages_artifact_build_with_shards(
        prepared_pages,
        store,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub(in crate::compiler) fn prepare_library_pages_artifact_build_with_shards(
    prepared_pages: PreparedLibrarySchedulePages,
    store: &FilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError> {
    validate_library_partition_index(&prepared_pages.library_partition_index, target)?;
    validate_library_schedule_index(&prepared_pages.library_schedule_index, target)?;

    for _ in 0..ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT {
        let step = prepare_artifact_build_chunk(
            store.root(),
            limits,
            batch_limits,
            shard_limits,
            target,
            ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
        if step.complete {
            return step.prepared.ok_or_else(|| {
                artifact_shard_contract_error(
                    "completed prepared-library-pages artifact build prepare did not return prepared result",
                )
            });
        }
    }

    Err(CompileError::GpuFrontend(format!(
        "prepared-library-pages artifact build prepare did not complete within {ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT} bounded chunk steps; keep calling prepare_artifact_build_chunk to continue persisted preparation"
    )))
}
