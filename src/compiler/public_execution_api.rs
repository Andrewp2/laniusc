use super::*;

pub fn execute_explicit_source_libraries_filesystem_artifact_build<P, E>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build<I, P, E>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits<
    I,
    P,
    E,
>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_for_target<I, P, E>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_ordered_explicit_source_libraries_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target(
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

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target(
        path_streams,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target(
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

pub fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPaths<P>>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target(
        path_streams,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
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
    .await
}

pub async fn execute_ordered_explicit_source_libraries_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let path_streams = path_streams_from_library_paths(libraries);
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
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
    .await
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build<I, PI, P, E>(
    libraries: I,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_for_target<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_ordered_explicit_source_library_path_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target(
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

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
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
    execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target(
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

pub fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathStream<PI>>,
    PI: IntoIterator<Item = P>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let dependency_streams = dependency_streams_from_path_streams(libraries);
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
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
    execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
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
    .await
}

pub async fn execute_ordered_explicit_source_library_path_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
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
    execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target(
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

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_for_target<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target<
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
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_with_shard_limits_for_target(
        libraries,
        &artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target(
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

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
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
    execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target(
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

pub fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_worker_run_with_shard_limits_and_path_artifacts_for_target<
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
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let prepare_chunk_limit = source_pack_limit_artifact_worker_run_batches(max_batches).max(1);
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
    execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target(
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
    .await
}

pub async fn execute_ordered_explicit_source_library_path_dependency_streams_filesystem_artifact_build_work_queue_worker_run_async_with_shard_limits_and_path_artifacts_for_target<
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
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
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
    execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target(
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

pub fn execute_explicit_source_libraries_filesystem_artifact_build_for_target<P, E>(
    libraries: Vec<ExplicitSourceLibraryPaths<P>>,
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    P: AsRef<Path>,
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    prepare_explicit_source_libraries_filesystem_artifact_build_for_target(
        libraries,
        &artifact_root,
        limits,
        batch_limits,
        target,
    )?;
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        target,
        executor,
    )
}

pub(super) fn prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_for_target(
    prepared_pages: SourcePackPreparedLibrarySchedulePages,
    store: &SourcePackFilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target(
        prepared_pages,
        store,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

pub(super) fn prepare_explicit_source_prepared_library_pages_filesystem_artifact_build_with_shard_limits_for_target(
    prepared_pages: SourcePackPreparedLibrarySchedulePages,
    store: &SourcePackFilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactPrepareResult, CompileError> {
    validate_source_pack_library_partition_index(&prepared_pages.library_partition_index, target)?;
    validate_source_pack_library_schedule_index(&prepared_pages.library_schedule_index, target)?;

    for _ in 0..SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT {
        let step =
            prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target(
                store.root(),
                limits,
                batch_limits,
                shard_limits,
                target,
                SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
            )?;
        if step.complete {
            return step.prepared.ok_or_else(|| {
                source_pack_artifact_shard_contract_error(
                    "completed prepared-library-pages artifact build prepare did not return prepared result",
                )
            });
        }
    }

    Err(CompileError::GpuFrontend(format!(
        "prepared-library-pages artifact build prepare did not complete within {SOURCE_PACK_FILESYSTEM_ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT} bounded chunk steps; keep calling prepare_source_pack_filesystem_artifact_build_from_metadata_chunk_with_shard_limits_for_target to continue persisted preparation"
    )))
}

pub fn execute_source_pack_filesystem_artifact_manifest_build<E>(
    artifact_root: impl Into<PathBuf>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_build_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_build_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBuildExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let now_unix_nanos = Some(source_pack_build_now_unix_nanos()?);
    let mut progress = source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
        &artifact_root,
        0,
        target,
        now_unix_nanos,
    )?;
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_manifest_full_build_batches(usize::MAX);

    for _ in 0..step_limit {
        if progress.complete {
            break;
        }
        let step =
            execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target_at(
                &artifact_root,
                target,
                "source-pack-build",
                None,
                0,
                now_unix_nanos,
                executor,
            )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        progress = step.progress;
        if !progress.complete && step.claimed_batch_index.is_none() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack filesystem artifact build stopped before completion after executing {executed_batch_count} batches"
            )));
        }
    }
    if !progress.complete {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack filesystem artifact build did not complete within {step_limit} bounded batches; keep calling execute_source_pack_filesystem_artifact_manifest_worker_run_for_target or execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target to continue persisted execution"
        )));
    }

    let linked_output_key = progress.linked_output_key.ok_or_else(|| {
        CompileError::GpuFrontend(
            "source-pack filesystem artifact build completed without a linked output key".into(),
        )
    })?;
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let linked_output_path = progress
        .linked_output_path
        .unwrap_or(store.path_for_key(&linked_output_key)?);
    Ok(SourcePackFilesystemArtifactBuildExecutionResult {
        linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}

pub fn execute_source_pack_filesystem_artifact_manifest_batch<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_batch_for_target(
        artifact_root,
        batch_index,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_batch_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_execution_shard_batch_for_target(
        artifact_root,
        batch_index,
        target,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub(super) fn execute_source_pack_filesystem_artifact_execution_shard_batch_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let mut store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(&store, target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if source_pack_execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(store.load_link_input_shard_index_for_target(target)?)
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(source_pack_execution_shard_batch_result(
                &execution_shard,
                batch_index,
            )?)
        } else {
            if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is claimed by another worker; use claimed-batch execution"
                )));
            }
            if !source_pack_progress_batch_is_ready_unclaimed_from_locator(
                &store,
                target,
                batch_index,
                now_unix_nanos,
            )? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is not ready in its persisted progress shard"
                )));
            }
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_source_pack_build_artifact_execution_shard_batch_paged(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )?
    };

    let build_state_path = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is claimed by another worker; use claimed-batch execution"
                )));
            }
            if !source_pack_progress_batch_is_ready_unclaimed_from_locator(
                &store,
                target,
                batch_index,
                now_unix_nanos,
            )? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is not ready in its persisted progress shard"
                )));
            }
        }
        progress.record_batch_result(&result)?;
        store.store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            source_pack_update_ready_frontier_after_batch_completion_bounded(
                &store,
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store.load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        let build_state_path = store.store_build_state_marker_for_target(target, &state_marker)?;
        build_state_path
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;
    Ok(SourcePackFilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactBatchClaimResult, CompileError> {
    source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
    )
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactBatchClaimResult, CompileError> {
    source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactBatchClaimResult, CompileError> {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let _state_lock = store.try_lock_build_state_for_target(target)?;

    let worker_id = worker_id.into();
    let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let claimed_batch_index = if summary.is_complete() {
        None
    } else {
        let claimed_batch_index =
            source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary(
                &store,
                target,
                &summary,
                now_unix_nanos,
            )?;
        if let Some(batch_index) = claimed_batch_index {
            let locator = store.load_build_batch_shard_locator_for_target(target, batch_index)?;
            let progress_shard =
                store.load_build_artifact_shard_for_target(target, locator.shard_index)?;
            if progress_shard.kind != SourcePackBuildArtifactShardKind::JobBatches
                || !progress_shard.batch_indices.contains(&batch_index)
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "batch {batch_index} locator points to shard {} with kind {:?} batches {:?}",
                    progress_shard.shard_index, progress_shard.kind, progress_shard.batch_indices
                )));
            }
            let mut progress =
                store.load_or_init_build_progress_shard_for_target(target, &progress_shard)?;
            progress.prune_inactive_batch_claims(now_unix_nanos)?;
            progress.record_batch_claim(
                batch_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            store.store_build_progress_shard(&progress)?;
        }
        claimed_batch_index
    };

    let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let build_state = source_pack_build_state_from_progress_summary(&summary)?;
    validate_source_pack_progress_summary_complete_output(&store, &summary)?;
    let build_state_path = store.store_build_state_marker_for_target(target, &build_state)?;
    Ok(SourcePackFilesystemArtifactBatchClaimResult {
        claimed_batch_index,
        worker_id,
        completed_batch_count: summary.completed_batch_count,
        claimed_batch_count: summary.claimed_batch_count,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_progress(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
) -> Result<SourcePackFilesystemArtifactBatchClaimProgressResult, CompileError> {
    source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_batches,
    )
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
) -> Result<SourcePackFilesystemArtifactBatchClaimProgressResult, CompileError> {
    source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_batches,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactBatchClaimProgressResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);

    let worker_id = worker_id.into();
    let claimed_batch_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
        if summary.is_complete() {
            None
        } else {
            let claimed_batch_index =
                source_pack_build_progress_first_ready_unclaimed_batch_index_from_summary(
                    &store,
                    target,
                    &summary,
                    now_unix_nanos,
                )?;
            if let Some(batch_index) = claimed_batch_index {
                let locator =
                    store.load_build_batch_shard_locator_for_target(target, batch_index)?;
                let mut progress =
                    store.load_build_progress_shard_for_target(target, locator.shard_index)?;
                progress.prune_inactive_batch_claims(now_unix_nanos)?;
                progress.record_batch_claim(
                    batch_index,
                    worker_id.clone(),
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
                store.store_build_progress_shard(&progress)?;
            }
            claimed_batch_index
        }
    };

    let progress = source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
        &artifact_root,
        max_ready_batches,
        target,
        now_unix_nanos,
    )?;
    Ok(SourcePackFilesystemArtifactBatchClaimProgressResult {
        claimed_batch_index,
        worker_id,
        progress,
    })
}

pub fn execute_source_pack_filesystem_artifact_manifest_claimed_batch<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    worker_id: impl AsRef<str>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target(
        artifact_root,
        batch_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at(
        artifact_root,
        batch_index,
        target,
        worker_id,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_claimed_batch_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at(
        artifact_root,
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref();
    let mut store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(&store, target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if source_pack_execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(store.load_link_input_shard_index_for_target(target)?)
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(source_pack_execution_shard_batch_result(
                &execution_shard,
                batch_index,
            )?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_source_pack_build_artifact_execution_shard_batch(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )?
    };

    let build_state_path = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            source_pack_update_ready_frontier_after_batch_completion_bounded(
                &store,
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store.load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        let build_state_path = store.store_build_state_marker_for_target(target, &state_marker)?;
        build_state_path
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;
    Ok(SourcePackFilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_store_for_target_at(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
}

pub fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactPathStore::new(&artifact_root);
    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_store_for_target_at(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
}

pub async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
    .await
}

pub async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactPathStore::new(&artifact_root);
    execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
    .await
}

pub(super) async fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_store_for_target_at<
    E,
    S,
>(
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore
        + SourcePackFilesystemExecutionShardLoader
        + AsRef<SourcePackFilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref();
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(store.as_ref(), target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if source_pack_execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(
                store
                    .as_ref()
                    .load_link_input_shard_index_for_target(target)?,
            )
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(source_pack_execution_shard_batch_result(
                &execution_shard,
                batch_index,
            )?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_source_pack_build_artifact_execution_shard_batch_paged_async(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )
        .await?
    };

    let build_state_path = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.as_ref().store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            source_pack_update_ready_frontier_after_batch_completion_bounded(
                store.as_ref(),
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store
            .as_ref()
            .load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        store
            .as_ref()
            .store_build_state_marker_for_target(target, &state_marker)?
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.as_ref().path_for_key(key))
        .transpose()?;
    let store = store.as_ref();
    Ok(SourcePackFilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub(super) fn execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_store_for_target_at<
    E,
    S,
>(
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<SourcePackFilesystemArtifactBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore
        + SourcePackFilesystemExecutionShardLoader
        + AsRef<SourcePackFilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref();
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(store.as_ref(), target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if source_pack_execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(
                store
                    .as_ref()
                    .load_link_input_shard_index_for_target(target)?,
            )
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(source_pack_execution_shard_batch_result(
                &execution_shard,
                batch_index,
            )?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_source_pack_build_artifact_execution_shard_batch_paged(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )?
    };

    let build_state_path = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.as_ref().store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            source_pack_update_ready_frontier_after_batch_completion_bounded(
                store.as_ref(),
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store
            .as_ref()
            .load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        store
            .as_ref()
            .store_build_state_marker_for_target(target, &state_marker)?
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.as_ref().path_for_key(key))
        .transpose()?;
    let store = store.as_ref();
    Ok(SourcePackFilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_step_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;

    source_pack_filesystem_artifact_manifest_worker_step_result(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;

    source_pack_filesystem_artifact_manifest_worker_step_result(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_step_async_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = if let Some(batch_index) = claim.claimed_batch_index {
        Some(
            execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_for_target_at(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
            .await?,
        )
    } else {
        None
    };

    source_pack_filesystem_artifact_manifest_worker_step_result(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_step_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = if let Some(batch_index) = claim.claimed_batch_index {
        Some(
            execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
            .await?,
        )
    } else {
        None
    };

    source_pack_filesystem_artifact_manifest_worker_step_result(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_progress<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_batches,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_batches,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerStepProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_artifact_manifest_claim_ready_batch_progress_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_batches,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = if executed_batch.is_some() {
        source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
            &artifact_root,
            max_ready_batches,
            target,
            now_unix_nanos,
        )?
    } else {
        claim.progress
    };

    Ok(
        SourcePackFilesystemArtifactWorkerStepProgressExecutionResult {
            worker_id,
            claimed_batch_index: claim.claimed_batch_index,
            executed_batch,
            progress,
        },
    )
}

pub(super) fn source_pack_filesystem_artifact_manifest_worker_step_result(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: String,
    claimed_batch_index: Option<usize>,
    executed_batch: Option<SourcePackFilesystemArtifactBatchExecutionResult>,
    _now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactWorkerStepExecutionResult, CompileError> {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let build_state = source_pack_build_state_from_progress_summary(&summary)?;
    validate_source_pack_progress_summary_complete_output(&store, &summary)?;
    let complete = summary.is_complete();
    let linked_output_path = build_state
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;

    Ok(SourcePackFilesystemArtifactWorkerStepExecutionResult {
        worker_id,
        claimed_batch_index,
        executed_batch,
        completed_batch_count: summary.completed_batch_count,
        ready_batch_count: summary.ready_batch_count,
        linked_output_key: build_state.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_progress<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        max_ready_batches,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        max_ready_batches,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_progress_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunProgressExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_batches = source_pack_limit_ready_state_batches(max_ready_batches);
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut last_progress = None;

    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_artifact_manifest_worker_step_progress_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                max_ready_batches,
                now_unix_nanos,
                executor,
            )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.progress.complete || step.claimed_batch_index.is_none();
        last_progress = Some(step.progress);
        if should_stop {
            break;
        }
    }

    let progress = match last_progress {
        Some(progress) => progress,
        None => source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
            &artifact_root,
            max_ready_batches,
            target,
            now_unix_nanos,
        )?,
    };

    Ok(
        SourcePackFilesystemArtifactWorkerRunProgressExecutionResult {
            worker_id,
            executed_batch_count,
            progress,
        },
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step = execute_source_pack_filesystem_artifact_manifest_worker_step_for_target_at(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            now_unix_nanos,
            executor,
        )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => source_pack_filesystem_artifact_manifest_worker_step_result(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(SourcePackFilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_worker_run_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_artifact_manifest_worker_step_with_path_artifacts_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
                executor,
            )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => source_pack_filesystem_artifact_manifest_worker_step_result(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(SourcePackFilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_artifact_manifest_worker_step_async_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
                executor,
            )
            .await?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => source_pack_filesystem_artifact_manifest_worker_step_result(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(SourcePackFilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
    .await
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_async_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
    .await
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_artifact_manifest_worker_step_async_with_path_artifacts_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
                executor,
            )
            .await?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => source_pack_filesystem_artifact_manifest_worker_step_result(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(SourcePackFilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
    .await
}

pub async fn execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_worker_run_async_with_path_artifacts_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        executor,
    )
    .await
}

pub fn execute_source_pack_filesystem_artifact_manifest_ready_batches<E>(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactResumeExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target(
        artifact_root,
        max_batches,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

pub fn execute_source_pack_filesystem_artifact_manifest_ready_batches_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<SourcePackFilesystemArtifactResumeExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let now_unix_nanos = Some(source_pack_build_now_unix_nanos()?);
    let initial_summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    validate_source_pack_progress_summary_complete_output(&store, &initial_summary)?;
    let max_batches = source_pack_limit_artifact_worker_run_batches(max_batches);
    let mut executed_batch_count = 0usize;

    if !initial_summary.is_complete() && max_batches != 0 {
        let ready_batch_indices =
            source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
                &store,
                target,
                &initial_summary,
                now_unix_nanos,
                Some(max_batches),
            )?;
        if ready_batch_indices.is_empty() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack build state has no unclaimed ready batches and is incomplete; completed {} batches; claimed {} batches",
                initial_summary.completed_batch_count, initial_summary.claimed_batch_count
            )));
        }
        validate_source_pack_ready_batch_dependency_artifacts_from_execution_shards(
            &store,
            initial_summary.job_batch_count,
            target,
            &ready_batch_indices,
        )?;
        for batch_index in ready_batch_indices {
            execute_source_pack_filesystem_artifact_execution_shard_batch_for_target(
                &artifact_root,
                batch_index,
                target,
                now_unix_nanos,
                executor,
            )?;
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
    }

    let final_summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let final_state = source_pack_build_state_from_progress_summary(&final_summary)?;
    validate_source_pack_progress_summary_complete_output(&store, &final_summary)?;
    let complete = final_summary.is_complete();
    let linked_output_path = final_state
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;

    Ok(SourcePackFilesystemArtifactResumeExecutionResult {
        executed_batch_count,
        completed_batch_count: final_summary.completed_batch_count,
        ready_batch_count: final_summary.ready_batch_count,
        linked_output_key: final_state.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}

pub fn source_pack_filesystem_artifact_manifest_ready_batches(
    artifact_root: impl Into<PathBuf>,
    completed_batch_indices: &[usize],
) -> Result<Vec<usize>, CompileError> {
    source_pack_filesystem_artifact_manifest_ready_batches_for_target(
        artifact_root,
        completed_batch_indices,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_ready_batches_for_target(
    artifact_root: impl Into<PathBuf>,
    completed_batch_indices: &[usize],
    target: SourcePackArtifactTarget,
) -> Result<Vec<usize>, CompileError> {
    if !completed_batch_indices.is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-pack ready-batch queries must use persisted progress state; caller-provided completed-batch arrays are not bounded".into(),
        ));
    }
    source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target(
        artifact_root,
        SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT,
        target,
    )
}

pub fn source_pack_filesystem_artifact_manifest_build_state(
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackBuildState, CompileError> {
    source_pack_filesystem_artifact_manifest_build_state_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_build_state_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildState, CompileError> {
    SourcePackFilesystemArtifactStore::new(artifact_root)
        .load_or_init_build_state_for_target(target)
}

pub fn source_pack_filesystem_artifact_manifest_progress_summary(
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackBuildProgressSummary, CompileError> {
    source_pack_filesystem_artifact_manifest_progress_summary_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_progress_summary_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildProgressSummary, CompileError> {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    store.load_build_progress_summary_for_target(target)
}

pub fn source_pack_filesystem_artifact_manifest_progress_snapshot(
    artifact_root: impl Into<PathBuf>,
    max_ready_batches: usize,
) -> Result<SourcePackFilesystemArtifactProgressSnapshot, CompileError> {
    source_pack_filesystem_artifact_manifest_progress_snapshot_for_target(
        artifact_root,
        max_ready_batches,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_progress_snapshot_for_target(
    artifact_root: impl Into<PathBuf>,
    max_ready_batches: usize,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactProgressSnapshot, CompileError> {
    source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
        artifact_root,
        max_ready_batches,
        target,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_artifact_manifest_progress_snapshot_for_target_at(
    artifact_root: impl Into<PathBuf>,
    max_ready_batches: usize,
    target: SourcePackArtifactTarget,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactProgressSnapshot, CompileError> {
    let max_ready_batches = source_pack_limit_ready_state_batches(max_ready_batches);
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let ready_batch_indices = if summary.is_complete() || max_ready_batches == 0 {
        Vec::new()
    } else {
        source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
            &store,
            target,
            &summary,
            now_unix_nanos,
            Some(max_ready_batches),
        )?
    };
    let linked_output_path = summary
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;
    let complete = summary.is_complete();

    Ok(SourcePackFilesystemArtifactProgressSnapshot {
        target,
        job_batch_count: summary.job_batch_count,
        completed_batch_count: summary.completed_batch_count,
        ready_batch_count: summary.ready_batch_count,
        claimed_batch_count: summary.claimed_batch_count,
        ready_claimed_batch_count: summary.ready_claimed_batch_count,
        earliest_claim_lease_expires_unix_nanos: summary.earliest_claim_lease_expires_unix_nanos,
        first_ready_batch_index: summary.first_ready_batch_index,
        ready_batch_indices,
        linked_output_key: summary.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
        progress_summary_path: store.build_progress_summary_path_for_target(target),
    })
}

pub fn source_pack_filesystem_artifact_manifest_progress_page(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
) -> Result<SourcePackFilesystemArtifactProgressPage, CompileError> {
    source_pack_filesystem_artifact_manifest_progress_page_for_target(
        artifact_root,
        shard_index,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_progress_page_for_target(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactProgressPage, CompileError> {
    source_pack_filesystem_artifact_manifest_progress_page_for_target_at(
        artifact_root,
        shard_index,
        target,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_artifact_manifest_progress_page_for_target_at(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
    target: SourcePackArtifactTarget,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemArtifactProgressPage, CompileError> {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let shard = store.load_build_artifact_shard_for_target(target, shard_index)?;
    if shard.kind != SourcePackBuildArtifactShardKind::JobBatches {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "progress page shard {shard_index} has non-job kind {:?}",
            shard.kind
        )));
    }
    let progress = store.load_or_init_build_progress_shard_for_target(target, &shard)?;
    source_pack_validate_progress_shard_matches_artifact_shard(&progress, &shard)?;
    let claimed_batch_indices = progress.claimed_batch_indices(now_unix_nanos)?;
    let claimed_batches = progress
        .claimed_batches
        .iter()
        .filter(|claim| {
            !progress
                .completed_batch_indices
                .contains(&claim.batch_index)
                && !claim.is_expired(now_unix_nanos)
        })
        .cloned()
        .collect::<Vec<_>>();

    Ok(SourcePackFilesystemArtifactProgressPage {
        target,
        shard_index,
        batch_indices: progress.batch_indices,
        completed_batch_indices: progress.completed_batch_indices,
        ready_batch_indices: progress.ready_batch_indices,
        claimed_batch_indices,
        claimed_batches,
        linked_output_key: progress.linked_output_key,
        progress_shard_path: store.build_progress_shard_path_for_target(target, shard_index),
        progress_summary_path: store.build_progress_summary_path_for_target(target),
    })
}

pub fn source_pack_filesystem_work_queue_progress_snapshot(
    artifact_root: impl Into<PathBuf>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
    source_pack_filesystem_work_queue_progress_snapshot_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        max_ready_items,
    )
}

pub fn source_pack_filesystem_work_queue_progress_snapshot_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
    source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        artifact_root,
        target,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let index = store.load_work_queue_progress_index_for_target(target)?;
    source_pack_filesystem_work_queue_progress_snapshot_from_index(
        &store,
        target,
        &index,
        max_ready_items,
        now_unix_nanos,
    )
}

pub(super) fn source_pack_filesystem_work_queue_progress_snapshot_from_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemWorkQueueProgressSnapshot, CompileError> {
    let max_ready_items = source_pack_limit_ready_state_items(max_ready_items);
    validate_source_pack_work_queue_progress_index(index, target)?;
    let complete = index.completed_item_count == index.work_item_count;
    let ready_item_indices = if complete || max_ready_items == 0 {
        Vec::new()
    } else {
        source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
            store,
            target,
            index,
            now_unix_nanos,
            Some(max_ready_items),
        )?
    };
    Ok(SourcePackFilesystemWorkQueueProgressSnapshot {
        target,
        work_item_count: index.work_item_count,
        completed_item_count: index.completed_item_count,
        ready_item_count: index.ready_item_count,
        claimed_item_count: index.claimed_item_count,
        first_ready_item_index: index.first_ready_item_index,
        ready_item_indices,
        complete,
        work_queue_index_path: store.work_queue_index_path_for_target(target),
        progress_index_path: store.work_queue_progress_index_path_for_target(target),
    })
}

pub(super) fn source_pack_work_queue_singleton_artifact_batch_index_for_item(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<usize>, CompileError> {
    let Some(batch_index) = item.artifact_batch_index else {
        return Ok(None);
    };
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(store, target, batch_index)?;
    let batch = source_pack_execution_shard_job_batch(&execution_shard, batch_index)?;
    if batch.job_indices.as_slice() != [item.job_index] {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "work queue item {} maps to artifact batch {} with jobs {:?}, expected singleton job {}",
            item.item_index, batch_index, batch.job_indices, item.job_index
        )));
    }
    let job = source_pack_execution_shard_job(&execution_shard, item.job_index)?;
    let expected_kind = match job.phase {
        SourcePackJobPhase::LibraryFrontend => SourcePackWorkQueueItemKind::LibraryFrontend,
        SourcePackJobPhase::Codegen => SourcePackWorkQueueItemKind::Codegen,
        SourcePackJobPhase::Link => {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "work queue item {} maps to artifact link job {}; hierarchical link items are not singleton artifact jobs",
                item.item_index, job.job_index
            )));
        }
    };
    if item.kind != expected_kind {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "work queue item {} kind {:?} maps to artifact job phase {:?}",
            item.item_index, item.kind, job.phase
        )));
    }
    Ok(Some(batch_index))
}

pub(super) fn source_pack_work_queue_item_output_key_for_release(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<(String, &'static str)>, CompileError> {
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let Some(batch_index) = source_pack_work_queue_singleton_artifact_batch_index_for_item(
                store, target, item,
            )?
            else {
                return Ok(None);
            };
            let execution_shard =
                source_pack_execution_shard_for_batch_locator(store, target, batch_index)?;
            let job_manifest =
                source_pack_execution_shard_job_artifact(&execution_shard, item.job_index)?;
            let (kind, label) = match item.kind {
                SourcePackWorkQueueItemKind::LibraryFrontend => (
                    SourcePackArtifactKind::LibraryInterface,
                    "library interface",
                ),
                SourcePackWorkQueueItemKind::Codegen => {
                    (SourcePackArtifactKind::CodegenObject, "codegen object")
                }
                SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
                    unreachable!()
                }
            };
            let output = single_output_artifact_ref(job_manifest, kind)?;
            Ok(Some((output.key.clone(), label)))
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let group_index = item.link_group_index.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "source-pack link work item {} has no link group index",
                    item.item_index
                ))
            })?;
            let page =
                store.load_hierarchical_link_execution_page_for_target(target, group_index)?;
            let expected_item_kind = match page.kind {
                SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
                SourcePackHierarchicalLinkGroupKind::Reduce => {
                    SourcePackWorkQueueItemKind::LinkReduce
                }
            };
            if item.kind != expected_item_kind || item.job_index != page.job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "source-pack link work item {} kind {:?} job {} does not match execution page group {} kind {:?} job {}",
                    item.item_index,
                    item.kind,
                    item.job_index,
                    page.group_index,
                    page.kind,
                    page.job_index
                )));
            }
            if page.final_output {
                Ok(None)
            } else {
                Ok(Some((page.output_key, "partial link output")))
            }
        }
    }
}

#[allow(dead_code)]
pub(super) fn source_pack_for_each_work_queue_dependency_item<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<bool, CompileError>,
{
    validate_source_pack_work_queue_page(item, target, Some(item.item_index))?;
    if !item.dependency_item_indices.is_empty() {
        for &dependency_item_index in &item.dependency_item_indices {
            if !visit(dependency_item_index)? {
                return Ok(());
            }
        }
        for range in &item.dependency_item_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue item {} dependency range starting at {} overflows",
                    item.item_index, range.first_job_index
                )));
            };
            for dependency_item_index in indices {
                if !visit(dependency_item_index)? {
                    return Ok(());
                }
            }
        }
        return Ok(());
    }

    let mut seen_dependency_count = 0usize;
    for page_index in 0..item.dependency_page_count {
        let page = store.load_work_queue_dependencies_page_for_target(
            target,
            item.item_index,
            page_index,
        )?;
        seen_dependency_count = seen_dependency_count.saturating_add(page.dependency_count);
        for &dependency_item_index in &page.dependency_item_indices {
            if !visit(dependency_item_index)? {
                return Ok(());
            }
        }
    }
    if seen_dependency_count != item.dependency_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue item {} iterated {} dependencies but expected {}",
            item.item_index, seen_dependency_count, item.dependency_item_count
        )));
    }
    for range in &item.dependency_item_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue item {} dependency range starting at {} overflows",
                item.item_index, range.first_job_index
            )));
        };
        for dependency_item_index in indices {
            if !visit(dependency_item_index)? {
                return Ok(());
            }
        }
    }
    Ok(())
}

#[allow(dead_code)]
pub(super) fn source_pack_for_each_work_queue_dependent_item<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<bool, CompileError>,
{
    validate_source_pack_work_queue_page(item, target, Some(item.item_index))?;
    if !item.dependent_item_indices.is_empty() {
        for &dependent_item_index in &item.dependent_item_indices {
            if !visit(dependent_item_index)? {
                return Ok(());
            }
        }
        for range in &item.dependent_item_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue item {} dependent range starting at {} overflows",
                    item.item_index, range.first_job_index
                )));
            };
            for dependent_item_index in indices {
                if !visit(dependent_item_index)? {
                    return Ok(());
                }
            }
        }
        return Ok(());
    }

    let mut seen_dependent_count = 0usize;
    for page_index in 0..item.dependent_page_count {
        let page = store.load_work_queue_dependents_page_for_target(
            target,
            item.item_index,
            page_index,
        )?;
        seen_dependent_count = seen_dependent_count.saturating_add(page.dependent_count);
        for &dependent_item_index in &page.dependent_item_indices {
            if !visit(dependent_item_index)? {
                return Ok(());
            }
        }
    }
    if seen_dependent_count != item.dependent_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue item {} iterated {} dependents but expected {}",
            item.item_index, seen_dependent_count, item.dependent_item_count
        )));
    }
    for range in &item.dependent_item_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue item {} dependent range starting at {} overflows",
                item.item_index, range.first_job_index
            )));
        };
        for dependent_item_index in indices {
            if !visit(dependent_item_index)? {
                return Ok(());
            }
        }
    }
    Ok(())
}

pub(super) struct SourcePackWorkQueueProgressChangedPageBatch {
    pub(super) pages: Vec<SourcePackWorkQueueProgressPage>,
    pub(super) page_limit: usize,
}

impl SourcePackWorkQueueProgressChangedPageBatch {
    pub(super) fn new(page_limit: usize) -> Self {
        Self {
            pages: Vec::new(),
            page_limit: page_limit.max(1),
        }
    }

    pub(super) fn page_for_item_mut(
        &mut self,
        store: &SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
        item_index: usize,
    ) -> Result<&mut SourcePackWorkQueueProgressPage, CompileError> {
        let page_index = source_pack_work_queue_progress_page_index_for_item(index, item_index)?;
        self.page_for_index_mut(store, target, index, page_index)
    }

    pub(super) fn page_for_index_mut(
        &mut self,
        store: &SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
        page_index: usize,
    ) -> Result<&mut SourcePackWorkQueueProgressPage, CompileError> {
        validate_source_pack_work_queue_progress_index(index, target)?;
        if page_index >= index.page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {page_index} exceeds page count {}",
                index.page_count
            )));
        }
        if let Some(position) = self
            .pages
            .iter()
            .position(|page| page.page_index == page_index)
        {
            return Ok(&mut self.pages[position]);
        }
        if self.pages.len() >= self.page_limit {
            self.flush(store, target, index)?;
        }
        self.pages
            .push(store.load_work_queue_progress_page_for_target(target, page_index)?);
        let position = self.pages.len() - 1;
        Ok(&mut self.pages[position])
    }

    pub(super) fn flush(
        &mut self,
        store: &SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
    ) -> Result<(), CompileError> {
        if self.pages.is_empty() {
            return Ok(());
        }
        source_pack_work_queue_progress_refresh_index_from_pages(
            store,
            target,
            index,
            &self.pages,
        )?;
        for page in &self.pages {
            store.store_work_queue_progress_page(page)?;
        }
        self.pages.clear();
        Ok(())
    }
}

pub(super) fn source_pack_work_queue_item_has_no_remaining_dependents(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    item: &SourcePackWorkQueuePage,
) -> Result<bool, CompileError> {
    let page_index = source_pack_work_queue_progress_page_index_for_item(index, item.item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    if source_pack_work_queue_progress_page_item_has_remaining_dependents(&page, item.item_index) {
        return Ok(false);
    }
    if source_pack_work_queue_page_dependent_count(item) == 0 {
        return Ok(true);
    }
    Err(source_pack_library_partition_contract_error(format!(
        "work queue progress page {} has no remaining dependent counter for item {} with {} dependents",
        page.page_index,
        item.item_index,
        source_pack_work_queue_page_dependent_count(item)
    )))
}

pub(super) fn source_pack_work_queue_record_dependent_dependency_completed(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    dependent_item_index: usize,
) -> Result<Option<bool>, CompileError> {
    let (page_changed, became_ready) = {
        let dependent_progress_page =
            changed_page_batch.page_for_item_mut(store, target, index, dependent_item_index)?;
        source_pack_work_queue_progress_page_record_dependency_completed(
            dependent_progress_page,
            dependent_item_index,
        )?
    };
    if page_changed {
        let dependent_progress_page =
            changed_page_batch.page_for_item_mut(store, target, index, dependent_item_index)?;
        let is_ready = source_pack_work_queue_progress_page_item_is_ready(
            dependent_progress_page,
            dependent_item_index,
        );
        Ok(Some(became_ready && is_ready))
    } else {
        Ok(None)
    }
}

pub(super) fn source_pack_work_queue_record_dependent_range_dependency_completed(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    dependent_range: &SourcePackJobIndexRange,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    if dependent_range.is_empty() {
        return Ok(0);
    }
    let Some(range_end) = dependent_range.end_job_index() else {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent range starting at {} overflows",
            dependent_range.first_job_index
        )));
    };
    if range_end > index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent range {}..{} exceeds work item count {}",
            dependent_range.first_job_index, range_end, index.work_item_count
        )));
    }

    let start_page_index = source_pack_work_queue_progress_page_index_for_item(
        index,
        dependent_range.first_job_index,
    )?;
    let last_item_index = range_end - 1;
    let end_page_index =
        source_pack_work_queue_progress_page_index_for_item(index, last_item_index)?;
    let mut newly_ready_item_count = 0usize;
    for page_index in start_page_index..=end_page_index {
        let progress_page =
            changed_page_batch.page_for_index_mut(store, target, index, page_index)?;
        let page_end = progress_page
            .first_item_index
            .checked_add(progress_page.item_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "work queue progress page {} item range overflows",
                    progress_page.page_index
                ))
            })?;
        let update_start = dependent_range
            .first_job_index
            .max(progress_page.first_item_index);
        let update_end = range_end.min(page_end);
        if update_start >= update_end {
            continue;
        }
        let (_page_changed, page_newly_ready_item_count) =
            source_pack_work_queue_progress_page_record_dependency_range_completed(
                progress_page,
                update_start,
                update_end - update_start,
            )?;
        newly_ready_item_count = newly_ready_item_count.saturating_add(page_newly_ready_item_count);
    }
    Ok(newly_ready_item_count)
}

pub(super) fn source_pack_work_queue_record_work_item_dependents_dependency_completed(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    work_item: &SourcePackWorkQueuePage,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_page(work_item, target, Some(work_item.item_index))?;
    let mut newly_ready_item_count = 0usize;
    if !work_item.dependent_item_indices.is_empty() {
        for &dependent_item_index in &work_item.dependent_item_indices {
            let Some(became_ready) = source_pack_work_queue_record_dependent_dependency_completed(
                store,
                target,
                index,
                changed_page_batch,
                dependent_item_index,
            )?
            else {
                continue;
            };
            if became_ready {
                newly_ready_item_count = newly_ready_item_count.saturating_add(1);
            }
        }
    } else {
        let mut seen_dependent_count = 0usize;
        for page_index in 0..work_item.dependent_page_count {
            let page = store.load_work_queue_dependents_page_for_target(
                target,
                work_item.item_index,
                page_index,
            )?;
            seen_dependent_count = seen_dependent_count.saturating_add(page.dependent_count);
            for &dependent_item_index in &page.dependent_item_indices {
                let Some(became_ready) =
                    source_pack_work_queue_record_dependent_dependency_completed(
                        store,
                        target,
                        index,
                        changed_page_batch,
                        dependent_item_index,
                    )?
                else {
                    continue;
                };
                if became_ready {
                    newly_ready_item_count = newly_ready_item_count.saturating_add(1);
                }
            }
        }
        if seen_dependent_count != work_item.dependent_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue item {} iterated {} dependents but expected {}",
                work_item.item_index, seen_dependent_count, work_item.dependent_item_count
            )));
        }
    }
    for dependent_range in &work_item.dependent_item_ranges {
        newly_ready_item_count = newly_ready_item_count.saturating_add(
            source_pack_work_queue_record_dependent_range_dependency_completed(
                store,
                target,
                index,
                changed_page_batch,
                dependent_range,
            )?,
        );
    }
    Ok(newly_ready_item_count)
}

pub(super) fn source_pack_work_queue_record_dependent_completed_for_release_candidate(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    item_index: usize,
) -> Result<bool, CompileError> {
    let no_remaining_dependents = {
        let page = changed_page_batch.page_for_item_mut(store, target, index, item_index)?;
        source_pack_work_queue_progress_page_record_dependent_completed(page, item_index)?
    };
    Ok(no_remaining_dependents)
}

pub(super) fn release_source_pack_work_queue_dependency_item_after_item_completion(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    release_candidate_index: usize,
) -> Result<usize, CompileError> {
    let release_candidate =
        store.load_work_queue_page_for_target(target, release_candidate_index)?;
    if source_pack_work_queue_record_dependent_completed_for_release_candidate(
        store,
        target,
        index,
        changed_page_batch,
        release_candidate_index,
    )? {
        if let Some(key) =
            release_source_pack_work_queue_item_output(store, target, &release_candidate)?
        {
            drop(key);
            return Ok(1);
        }
    }
    Ok(0)
}

pub(super) fn release_source_pack_work_queue_dependency_range_after_item_completion(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut SourcePackWorkQueueProgressChangedPageBatch,
    dependency_range: &SourcePackJobIndexRange,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    if dependency_range.is_empty() {
        return Ok(0);
    }
    let Some(range_end) = dependency_range.end_job_index() else {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependency range starting at {} overflows",
            dependency_range.first_job_index
        )));
    };
    if range_end > index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependency range {}..{} exceeds work item count {}",
            dependency_range.first_job_index, range_end, index.work_item_count
        )));
    }

    let start_page_index = source_pack_work_queue_progress_page_index_for_item(
        index,
        dependency_range.first_job_index,
    )?;
    let last_item_index = range_end - 1;
    let end_page_index =
        source_pack_work_queue_progress_page_index_for_item(index, last_item_index)?;
    let mut released_count = 0usize;
    for page_index in start_page_index..=end_page_index {
        let progress_page =
            changed_page_batch.page_for_index_mut(store, target, index, page_index)?;
        let page_end = progress_page
            .first_item_index
            .checked_add(progress_page.item_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "work queue progress page {} item range overflows",
                    progress_page.page_index
                ))
            })?;
        let update_start = dependency_range
            .first_job_index
            .max(progress_page.first_item_index);
        let update_end = range_end.min(page_end);
        if update_start >= update_end {
            continue;
        }
        let (_page_changed, no_remaining_dependent_item_indices) =
            source_pack_work_queue_progress_page_record_dependent_range_completed(
                progress_page,
                update_start,
                update_end - update_start,
            )?;
        for release_candidate_index in no_remaining_dependent_item_indices {
            let release_candidate =
                store.load_work_queue_page_for_target(target, release_candidate_index)?;
            if let Some(key) =
                release_source_pack_work_queue_item_output(store, target, &release_candidate)?
            {
                drop(key);
                released_count = released_count.saturating_add(1);
            }
        }
    }
    Ok(released_count)
}

pub(super) fn release_source_pack_work_queue_item_output(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<String>, CompileError> {
    let Some((key, label)) =
        source_pack_work_queue_item_output_key_for_release(store, target, item)?
    else {
        return Ok(None);
    };
    remove_source_pack_filesystem_artifact(store.root(), &key, label)?;
    Ok(Some(key))
}

pub(super) fn release_source_pack_work_queue_consumed_outputs_after_item_completion(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    completed_item: &SourcePackWorkQueuePage,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_page(completed_item, target, Some(completed_item.item_index))?;
    let mut released_count = 0usize;
    let mut changed_page_batch = SourcePackWorkQueueProgressChangedPageBatch::new(
        SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT,
    );
    if !completed_item.dependency_item_indices.is_empty() {
        for &release_candidate_index in &completed_item.dependency_item_indices {
            released_count = released_count.saturating_add(
                release_source_pack_work_queue_dependency_item_after_item_completion(
                    store,
                    target,
                    index,
                    &mut changed_page_batch,
                    release_candidate_index,
                )?,
            );
        }
    } else {
        let mut seen_dependency_count = 0usize;
        for page_index in 0..completed_item.dependency_page_count {
            let page = store.load_work_queue_dependencies_page_for_target(
                target,
                completed_item.item_index,
                page_index,
            )?;
            seen_dependency_count = seen_dependency_count.saturating_add(page.dependency_count);
            for &release_candidate_index in &page.dependency_item_indices {
                released_count = released_count.saturating_add(
                    release_source_pack_work_queue_dependency_item_after_item_completion(
                        store,
                        target,
                        index,
                        &mut changed_page_batch,
                        release_candidate_index,
                    )?,
                );
            }
        }
        if seen_dependency_count != completed_item.dependency_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue item {} iterated {} dependencies but expected {}",
                completed_item.item_index,
                seen_dependency_count,
                completed_item.dependency_item_count
            )));
        }
    }
    for dependency_range in &completed_item.dependency_item_ranges {
        released_count = released_count.saturating_add(
            release_source_pack_work_queue_dependency_range_after_item_completion(
                store,
                target,
                index,
                &mut changed_page_batch,
                dependency_range,
            )?,
        );
    }
    changed_page_batch.flush(store, target, index)?;
    {
        let release_candidate =
            store.load_work_queue_page_for_target(target, completed_item.item_index)?;
        if source_pack_work_queue_item_has_no_remaining_dependents(
            store,
            target,
            index,
            &release_candidate,
        )? {
            if let Some(key) =
                release_source_pack_work_queue_item_output(store, target, &release_candidate)?
            {
                drop(key);
                released_count = released_count.saturating_add(1);
            }
        }
    }
    Ok(released_count)
}

pub(super) fn source_pack_work_queue_first_ready_unclaimed_artifact_item(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
) -> Result<Option<(usize, usize)>, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    if index.ready_item_count == 0
        || index.artifact_item_count == 0
        || index.ready_artifact_item_count == 0
    {
        return Ok(None);
    }
    let Some(start_item_index) = index.first_ready_artifact_item_index else {
        return Ok(None);
    };
    let start_page_index =
        source_pack_work_queue_progress_page_index_for_item(index, start_item_index)?;
    let mut seen_ready_artifact_item_count = 0usize;
    let first_directory_page_index =
        source_pack_work_queue_progress_directory_page_index_for_progress_page(start_page_index);
    let first_directory_index_page_index =
        source_pack_work_queue_progress_directory_index_page_index_for_directory_page(
            first_directory_page_index,
        );
    let directory_index_page_count =
        source_pack_work_queue_progress_directory_index_page_count(index)?;
    for directory_index_page_index in first_directory_index_page_index..directory_index_page_count {
        let directory_index_page =
            source_pack_work_queue_progress_directory_index_page_from_changes_or_store(
                store,
                target,
                index,
                &[],
                directory_index_page_index,
            )?;
        if directory_index_page.ready_artifact_directory_page_count == 0 {
            continue;
        }
        if source_pack_work_queue_progress_directory_index_ready_artifact_pages_are_claimed(
            &directory_index_page,
            now_unix_nanos,
        ) {
            continue;
        }
        let directory_start = directory_index_page
            .first_ready_artifact_directory_page_index
            .unwrap_or(directory_index_page.first_directory_page_index)
            .max(first_directory_page_index);
        let directory_end = directory_index_page
            .first_directory_page_index
            .saturating_add(directory_index_page.directory_page_count);
        for directory_page_index in directory_start..directory_end {
            let directory_page =
                source_pack_work_queue_progress_directory_page_from_changes_or_store(
                    store,
                    target,
                    index,
                    &[],
                    directory_page_index,
                )?;
            let directory_page_end = directory_page
                .first_progress_page_index
                .saturating_add(directory_page.progress_page_count);
            if directory_page.ready_artifact_page_count == 0 {
                continue;
            }
            if source_pack_work_queue_progress_directory_ready_artifact_pages_are_claimed(
                &directory_page,
                now_unix_nanos,
            ) {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_artifact_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_artifact_page_count = 0usize;
            while page_index < directory_page_end {
                let summary = source_pack_work_queue_progress_page_summary_from_index_or_store(
                    store, target, index, page_index,
                )?;
                if summary.ready_artifact_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_artifact_page_count = seen_ready_artifact_page_count.saturating_add(1);
                if source_pack_work_queue_progress_page_ready_artifact_items_are_claimed(
                    &summary,
                    now_unix_nanos,
                ) {
                    seen_ready_artifact_item_count = seen_ready_artifact_item_count
                        .saturating_add(summary.ready_artifact_item_count);
                    if seen_ready_artifact_item_count >= index.ready_artifact_item_count {
                        return Ok(None);
                    }
                    if seen_ready_artifact_page_count >= directory_page.ready_artifact_page_count {
                        break;
                    }
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
                for &item_index in &page.ready_artifact_item_indices {
                    if item_index < start_item_index {
                        continue;
                    }
                    seen_ready_artifact_item_count =
                        seen_ready_artifact_item_count.saturating_add(1);
                    if source_pack_work_queue_progress_page_item_is_completed(&page, item_index)
                        || !source_pack_work_queue_progress_page_item_is_ready(&page, item_index)
                        || !source_pack_work_queue_progress_page_item_is_artifact_backed(
                            &page, item_index,
                        )
                        || source_pack_work_queue_progress_page_item_is_claimed(
                            &page,
                            item_index,
                            now_unix_nanos,
                        )
                    {
                        continue;
                    }
                    let work_item = store.load_work_queue_page_for_target(target, item_index)?;
                    let Some(batch_index) =
                        source_pack_work_queue_singleton_artifact_batch_index_for_item(
                            store, target, &work_item,
                        )?
                    else {
                        return Err(source_pack_library_partition_contract_error(format!(
                            "ready artifact work queue item {item_index} has no singleton artifact batch"
                        )));
                    };
                    return Ok(Some((item_index, batch_index)));
                }
                if seen_ready_artifact_item_count >= index.ready_artifact_item_count {
                    return Ok(None);
                }
                if seen_ready_artifact_page_count >= directory_page.ready_artifact_page_count {
                    break;
                }
                page_index = page_index.saturating_add(1);
            }
        }
    }
    Ok(None)
}

pub(super) fn source_pack_work_queue_record_artifact_batch_claim(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    worker_id: &str,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let execution_shard =
        source_pack_execution_shard_for_batch_locator(store, target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let mut progress = store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
    progress.prune_inactive_batch_claims(now_unix_nanos)?;
    if !progress.is_batch_completed(batch_index) {
        if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            return Ok(());
        }
        if !source_pack_progress_batch_is_ready_unclaimed_from_locator(
            store,
            target,
            batch_index,
            now_unix_nanos,
        )? {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack artifact batch {batch_index} is not ready for work-queue item claim"
            )));
        }
        progress.record_batch_claim(
            batch_index,
            worker_id.to_string(),
            lease_expires_unix_nanos,
            now_unix_nanos,
        )?;
        store.store_build_progress_shard(&progress)?;
    }
    Ok(())
}

pub fn source_pack_filesystem_work_queue_claim_ready_item(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    source_pack_filesystem_work_queue_claim_ready_item_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
    )
}

pub fn source_pack_filesystem_work_queue_claim_ready_item_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let claimed_item_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let claimed_item_index = if index.completed_item_count == index.work_item_count {
            None
        } else {
            source_pack_work_queue_progress_first_ready_unclaimed_item_index(
                &store,
                target,
                &index,
                now_unix_nanos,
            )?
        };
        if let Some(item_index) = claimed_item_index {
            let page_index =
                source_pack_work_queue_progress_page_index_for_item(&index, item_index)?;
            let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
            source_pack_work_queue_progress_page_prune_inactive_claims(&mut page, now_unix_nanos);
            source_pack_work_queue_progress_page_record_item_claim(
                &mut page,
                item_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let changed_pages = [page];
            source_pack_work_queue_progress_refresh_index_from_pages(
                &store,
                target,
                &mut index,
                &changed_pages,
            )?;
            store.store_work_queue_progress_page(&changed_pages[0])?;
            store.store_work_queue_progress_index(&index)?;
        }
        claimed_item_index
    };
    let progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;
    Ok(SourcePackFilesystemWorkQueueItemClaimResult {
        claimed_item_index,
        worker_id,
        progress,
    })
}

pub fn source_pack_filesystem_work_queue_claim_ready_artifact_item(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
    )
}

pub fn source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_work_queue_claim_ready_artifact_item_for_target_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemWorkQueueItemClaimResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let claimed_item_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let claimed = if index.completed_item_count == index.work_item_count {
            None
        } else {
            source_pack_work_queue_first_ready_unclaimed_artifact_item(
                &store,
                target,
                &index,
                now_unix_nanos,
            )?
        };
        if let Some((item_index, batch_index)) = claimed {
            source_pack_work_queue_record_artifact_batch_claim(
                &store,
                target,
                batch_index,
                &worker_id,
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let page_index =
                source_pack_work_queue_progress_page_index_for_item(&index, item_index)?;
            let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
            source_pack_work_queue_progress_page_prune_inactive_claims(&mut page, now_unix_nanos);
            source_pack_work_queue_progress_page_record_item_claim(
                &mut page,
                item_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let changed_pages = [page];
            source_pack_work_queue_progress_refresh_index_from_pages(
                &store,
                target,
                &mut index,
                &changed_pages,
            )?;
            store.store_work_queue_progress_page(&changed_pages[0])?;
            store.store_work_queue_progress_index(&index)?;
            Some(item_index)
        } else {
            None
        }
    };
    let progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;
    Ok(SourcePackFilesystemWorkQueueItemClaimResult {
        claimed_item_index,
        worker_id,
        progress,
    })
}

pub fn source_pack_filesystem_work_queue_record_claimed_item_complete(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    worker_id: impl Into<String>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemCompletionResult, CompileError> {
    source_pack_filesystem_work_queue_record_claimed_item_complete_for_target(
        artifact_root,
        item_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_ready_items,
    )
}

pub fn source_pack_filesystem_work_queue_record_claimed_item_complete_for_target(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_ready_items: usize,
) -> Result<SourcePackFilesystemWorkQueueItemCompletionResult, CompileError> {
    source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
    )
}

pub fn source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<SourcePackFilesystemWorkQueueItemCompletionResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let (newly_completed, newly_ready_item_count) = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let page_index = source_pack_work_queue_progress_page_index_for_item(&index, item_index)?;
        let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
        let newly_completed = source_pack_work_queue_progress_page_record_item_completed(
            &mut page,
            item_index,
            &worker_id,
            now_unix_nanos,
        )?;
        let changed_pages = [page];
        source_pack_work_queue_progress_refresh_index_from_pages(
            &store,
            target,
            &mut index,
            &changed_pages,
        )?;
        store.store_work_queue_progress_page(&changed_pages[0])?;
        let mut newly_ready_item_count = 0usize;

        if newly_completed {
            let work_item = store.load_work_queue_page_for_target(target, item_index)?;
            let mut changed_page_batch = SourcePackWorkQueueProgressChangedPageBatch::new(
                SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT,
            );
            newly_ready_item_count =
                source_pack_work_queue_record_work_item_dependents_dependency_completed(
                    &store,
                    target,
                    &mut index,
                    &mut changed_page_batch,
                    &work_item,
                )?;
            changed_page_batch.flush(&store, target, &mut index)?;
            release_source_pack_work_queue_consumed_outputs_after_item_completion(
                &store, target, &mut index, &work_item,
            )?;
        }

        store.store_work_queue_progress_index(&index)?;
        (newly_completed, newly_ready_item_count)
    };
    let progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;
    Ok(SourcePackFilesystemWorkQueueItemCompletionResult {
        completed_item_index: item_index,
        worker_id,
        newly_completed,
        newly_ready_item_count,
        progress,
    })
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target(
        artifact_root,
        item_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
        &store, target, &item,
    )?
    .ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} has no singleton artifact batch execution mapping"
        ))
    })?;

    let executed_batch =
        execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_for_target_at(
            &artifact_root,
            batch_index,
            target,
            &worker_id,
            now_unix_nanos,
            executor,
        )?;
    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(SourcePackFilesystemWorkQueueArtifactItemExecutionResult {
        item_index,
        worker_id,
        executed_batch,
        completion,
    })
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target(
        artifact_root,
        item_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_artifact_item_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
        &store, target, &item,
    )?
    .ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} has no singleton artifact batch execution mapping"
        ))
    })?;

    let executed_batch =
        execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_with_path_artifacts_for_target_at(
            &artifact_root,
            batch_index,
            target,
            &worker_id,
            now_unix_nanos,
            executor,
        )?;
    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(SourcePackFilesystemWorkQueueArtifactItemExecutionResult {
        item_index,
        worker_id,
        executed_batch,
        completion,
    })
}

pub fn execute_source_pack_filesystem_work_queue_claimed_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_item_for_target(
        artifact_root,
        item_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_item_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_item_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_item_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
                &store, target, &item,
            )?
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack work item {item_index} has no singleton artifact batch execution mapping"
                ))
            })?;
            let already_completed = source_pack_filesystem_work_queue_item_completed_or_claimed_by(
                &store,
                target,
                item_index,
                &worker_id,
                now_unix_nanos,
            )?;
            if !already_completed {
                let lease_expires_unix_nanos =
                    source_pack_filesystem_work_queue_item_claim_lease_expires_by(
                        &store,
                        target,
                        item_index,
                        &worker_id,
                        now_unix_nanos,
                    )?;
                source_pack_work_queue_record_artifact_batch_claim(
                    &store,
                    target,
                    batch_index,
                    &worker_id,
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
            }
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_artifact_item_paged_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(
                    executed.executed_batch,
                ),
                completion: executed.completion,
            })
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_link_item_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(
                    executed.executed_link_group,
                ),
                completion: executed.completion,
            })
        }
    }
}

pub fn execute_source_pack_filesystem_work_queue_claimed_item_with_path_artifacts_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
                &store, target, &item,
            )?
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack work item {item_index} has no singleton artifact batch execution mapping"
                ))
            })?;
            let already_completed = source_pack_filesystem_work_queue_item_completed_or_claimed_by(
                &store,
                target,
                item_index,
                &worker_id,
                now_unix_nanos,
            )?;
            if !already_completed {
                let lease_expires_unix_nanos =
                    source_pack_filesystem_work_queue_item_claim_lease_expires_by(
                        &store,
                        target,
                        item_index,
                        &worker_id,
                        now_unix_nanos,
                    )?;
                source_pack_work_queue_record_artifact_batch_claim(
                    &store,
                    target,
                    batch_index,
                    &worker_id,
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
            }
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_artifact_item_with_path_artifacts_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(
                    executed.executed_batch,
                ),
                completion: executed.completion,
            })
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_link_item_with_path_artifacts_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(
                    executed.executed_link_group,
                ),
                completion: executed.completion,
            })
        }
    }
}

pub fn execute_source_pack_filesystem_work_queue_claimed_link_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_link_item_for_target(
        artifact_root,
        item_index,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_link_item_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_claimed_link_item_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_link_item_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    execute_source_pack_filesystem_work_queue_claimed_link_item_with_store_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
        store,
    )
}

pub fn execute_source_pack_filesystem_work_queue_claimed_link_item_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactPathStore::new(&artifact_root);
    execute_source_pack_filesystem_work_queue_claimed_link_item_with_store_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
        store,
    )
}

pub(super) fn execute_source_pack_filesystem_work_queue_claimed_link_item_with_store_for_target_at<
    E,
    S,
>(
    artifact_root: PathBuf,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: SourcePackPathHierarchicalLinkArtifactStore
        + SourcePackFilesystemExecutionShardLoader
        + AsRef<SourcePackFilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref().to_string();
    let item = store
        .as_ref()
        .load_work_queue_page_for_target(target, item_index)?;
    if !matches!(
        item.kind,
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce
    ) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is {:?}, not a link item",
            item.kind
        )));
    }
    let group_index = item.link_group_index.ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "source-pack link work item {item_index} has no link group index"
        ))
    })?;
    let page = store
        .as_ref()
        .load_hierarchical_link_execution_page_for_target(target, group_index)?;
    let expected_item_kind = match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
        SourcePackHierarchicalLinkGroupKind::Reduce => SourcePackWorkQueueItemKind::LinkReduce,
    };
    if item.kind != expected_item_kind || item.job_index != page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-pack link work item {} kind {:?} job {} does not match execution page group {} kind {:?} job {}",
            item.item_index, item.kind, item.job_index, page.group_index, page.kind, page.job_index
        )));
    }

    let already_completed = source_pack_filesystem_work_queue_item_completed_or_claimed_by(
        store.as_ref(),
        target,
        item_index,
        &worker_id,
        now_unix_nanos,
    )?;
    if !already_completed {
        execute_source_pack_hierarchical_link_execution_page(&page, executor, &mut store)?;
    }

    let output_path = store.as_ref().path_for_key(&page.output_key)?;
    let linked_output_key = page.final_output.then(|| page.output_key.clone());
    let linked_output_path = page.final_output.then(|| output_path.clone());
    let executed_link_group = SourcePackFilesystemHierarchicalLinkGroupExecutionResult {
        group_index: page.group_index,
        job_index: page.job_index,
        kind: page.kind,
        input_interface_count: source_pack_hierarchical_link_execution_input_interface_count(&page),
        input_object_count: source_pack_hierarchical_link_execution_input_object_count(&page),
        input_group_count: source_pack_hierarchical_link_execution_input_group_count(&page),
        output_key: page.output_key.clone(),
        output_path,
        final_output: page.final_output,
        linked_output_key,
        linked_output_path,
    };
    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(SourcePackFilesystemWorkQueueLinkItemExecutionResult {
        item_index,
        worker_id,
        executed_link_group,
        completion,
    })
}

pub(super) fn source_pack_filesystem_work_queue_item_completed_or_claimed_by(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<bool, CompileError> {
    let index = store.load_work_queue_progress_index_for_target(target)?;
    let page_index = source_pack_work_queue_progress_page_index_for_item(&index, item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    if source_pack_work_queue_progress_page_item_is_completed(&page, item_index) {
        return Ok(true);
    }
    source_pack_work_queue_progress_page_require_item_claimed_by(
        &page,
        item_index,
        worker_id,
        now_unix_nanos,
    )?;
    Ok(false)
}

pub(super) fn source_pack_filesystem_work_queue_item_claim_lease_expires_by(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<Option<u128>, CompileError> {
    let index = store.load_work_queue_progress_index_for_target(target)?;
    let page_index = source_pack_work_queue_progress_page_index_for_item(&index, item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    source_pack_work_queue_progress_page_item_claim_lease_expires_by(
        &page,
        item_index,
        worker_id,
        now_unix_nanos,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_step<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_step_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_step_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_step_for_target_at(
        artifact_root,
        target,
        worker_id,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_step_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_items,
        now_unix_nanos,
    )?;
    let executed_item = claim
        .claimed_item_index
        .map(|item_index| {
            execute_source_pack_filesystem_work_queue_claimed_item_for_target_at(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = executed_item
        .as_ref()
        .map(|execution| execution.completion.progress.clone())
        .unwrap_or_else(|| claim.progress.clone());
    Ok(SourcePackFilesystemWorkQueueWorkerStepExecutionResult {
        worker_id,
        claimed_item_index: claim.claimed_item_index,
        executed_item,
        progress,
    })
}

pub fn execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_items,
        now_unix_nanos,
    )?;
    let executed_item = claim
        .claimed_item_index
        .map(|item_index| {
            execute_source_pack_filesystem_work_queue_claimed_item_with_path_artifacts_for_target_at(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = executed_item
        .as_ref()
        .map(|execution| execution.completion.progress.clone())
        .unwrap_or_else(|| claim.progress.clone());
    Ok(SourcePackFilesystemWorkQueueWorkerStepExecutionResult {
        worker_id,
        claimed_item_index: claim.claimed_item_index,
        executed_item,
        progress,
    })
}

pub fn execute_source_pack_filesystem_work_queue_worker_run<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_run_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_run_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_items = source_pack_limit_ready_state_items(max_ready_items);
    let step_limit = source_pack_limit_work_queue_worker_run_items(max_items);
    let mut executed_item_count = 0usize;
    let mut executed_artifact_batch_count = 0usize;
    let mut executed_link_group_count = 0usize;
    let mut progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;

    for _ in 0..step_limit {
        let step = execute_source_pack_filesystem_work_queue_worker_step_for_target_at(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            max_ready_items,
            now_unix_nanos,
            executor,
        )?;
        progress = step.progress;
        let Some(executed_item) = step.executed_item else {
            break;
        };
        executed_item_count = executed_item_count.saturating_add(1);
        match executed_item.executed {
            SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(_) => {
                executed_artifact_batch_count = executed_artifact_batch_count.saturating_add(1);
            }
            SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(_) => {
                executed_link_group_count = executed_link_group_count.saturating_add(1);
            }
        }
        if progress.complete {
            break;
        }
    }

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let (linked_output_key, linked_output_path) =
        source_pack_filesystem_work_queue_final_linked_output_for_progress(
            &store, target, &progress,
        )?;
    Ok(SourcePackFilesystemWorkQueueWorkerRunExecutionResult {
        worker_id,
        executed_item_count,
        executed_artifact_batch_count,
        executed_link_group_count,
        linked_output_key,
        linked_output_path,
        progress,
    })
}

pub fn execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
}

pub fn execute_source_pack_filesystem_work_queue_worker_run_with_path_artifacts_for_target_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_items = source_pack_limit_ready_state_items(max_ready_items);
    let step_limit = source_pack_limit_work_queue_worker_run_items(max_items);
    let mut executed_item_count = 0usize;
    let mut executed_artifact_batch_count = 0usize;
    let mut executed_link_group_count = 0usize;
    let mut progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;

    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_work_queue_worker_step_with_path_artifacts_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                max_ready_items,
                now_unix_nanos,
                executor,
            )?;
        progress = step.progress;
        let Some(executed_item) = step.executed_item else {
            break;
        };
        executed_item_count = executed_item_count.saturating_add(1);
        match executed_item.executed {
            SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(_) => {
                executed_artifact_batch_count = executed_artifact_batch_count.saturating_add(1);
            }
            SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(_) => {
                executed_link_group_count = executed_link_group_count.saturating_add(1);
            }
        }
        if progress.complete {
            break;
        }
    }

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let (linked_output_key, linked_output_path) =
        source_pack_filesystem_work_queue_final_linked_output_for_progress(
            &store, target, &progress,
        )?;
    Ok(SourcePackFilesystemWorkQueueWorkerRunExecutionResult {
        worker_id,
        executed_item_count,
        executed_artifact_batch_count,
        executed_link_group_count,
        linked_output_key,
        linked_output_path,
        progress,
    })
}

pub async fn execute_source_pack_filesystem_work_queue_claimed_artifact_item_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
        &store, target, &item,
    )?
    .ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} has no singleton artifact batch execution mapping"
        ))
    })?;

    let executed_batch =
        execute_source_pack_filesystem_artifact_execution_shard_claimed_batch_paged_async_with_path_artifacts_for_target_at(
            &artifact_root,
            batch_index,
            target,
            &worker_id,
            now_unix_nanos,
            executor,
        )
        .await?;
    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(SourcePackFilesystemWorkQueueArtifactItemExecutionResult {
        item_index,
        worker_id,
        executed_batch,
        completion,
    })
}

pub async fn execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = SourcePackFilesystemArtifactPathStore::new(&artifact_root);
    execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_store_for_target_at(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
        store,
    )
    .await
}

pub(super) async fn execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_store_for_target_at<
    E,
    S,
>(
    artifact_root: PathBuf,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<SourcePackFilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: SourcePackPathHierarchicalLinkArtifactStore
        + SourcePackFilesystemExecutionShardLoader
        + AsRef<SourcePackFilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref().to_string();
    let item = store
        .as_ref()
        .load_work_queue_page_for_target(target, item_index)?;
    if !matches!(
        item.kind,
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce
    ) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is {:?}, not a link item",
            item.kind
        )));
    }
    let group_index = item.link_group_index.ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "source-pack link work item {item_index} has no link group index"
        ))
    })?;
    let page = store
        .as_ref()
        .load_hierarchical_link_execution_page_for_target(target, group_index)?;
    let expected_item_kind = match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
        SourcePackHierarchicalLinkGroupKind::Reduce => SourcePackWorkQueueItemKind::LinkReduce,
    };
    if item.kind != expected_item_kind || item.job_index != page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-pack link work item {} kind {:?} job {} does not match execution page group {} kind {:?} job {}",
            item.item_index, item.kind, item.job_index, page.group_index, page.kind, page.job_index
        )));
    }

    let already_completed = source_pack_filesystem_work_queue_item_completed_or_claimed_by(
        store.as_ref(),
        target,
        item_index,
        &worker_id,
        now_unix_nanos,
    )?;
    if !already_completed {
        execute_source_pack_hierarchical_link_execution_page_async(&page, executor, &mut store)
            .await?;
    }

    let output_path = store.as_ref().path_for_key(&page.output_key)?;
    let linked_output_key = page.final_output.then(|| page.output_key.clone());
    let linked_output_path = page.final_output.then(|| output_path.clone());
    let executed_link_group = SourcePackFilesystemHierarchicalLinkGroupExecutionResult {
        group_index: page.group_index,
        job_index: page.job_index,
        kind: page.kind,
        input_interface_count: source_pack_hierarchical_link_execution_input_interface_count(&page),
        input_object_count: source_pack_hierarchical_link_execution_input_object_count(&page),
        input_group_count: source_pack_hierarchical_link_execution_input_group_count(&page),
        output_key: page.output_key.clone(),
        output_path,
        final_output: page.final_output,
        linked_output_key,
        linked_output_path,
    };
    let completion = source_pack_filesystem_work_queue_record_claimed_item_complete_for_target_at(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(SourcePackFilesystemWorkQueueLinkItemExecutionResult {
        item_index,
        worker_id,
        executed_link_group,
        completion,
    })
}

pub async fn execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let batch_index = source_pack_work_queue_singleton_artifact_batch_index_for_item(
                &store, target, &item,
            )?
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack work item {item_index} has no singleton artifact batch execution mapping"
                ))
            })?;
            let already_completed = source_pack_filesystem_work_queue_item_completed_or_claimed_by(
                &store,
                target,
                item_index,
                &worker_id,
                now_unix_nanos,
            )?;
            if !already_completed {
                let lease_expires_unix_nanos =
                    source_pack_filesystem_work_queue_item_claim_lease_expires_by(
                        &store,
                        target,
                        item_index,
                        &worker_id,
                        now_unix_nanos,
                    )?;
                source_pack_work_queue_record_artifact_batch_claim(
                    &store,
                    target,
                    batch_index,
                    &worker_id,
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
            }
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_artifact_item_async_with_path_artifacts_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )
                .await?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(
                    executed.executed_batch,
                ),
                completion: executed.completion,
            })
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let executed =
                execute_source_pack_filesystem_work_queue_claimed_link_item_async_with_path_artifacts_for_target_at(
                    &artifact_root,
                    item_index,
                    target,
                    &worker_id,
                    max_ready_items,
                    now_unix_nanos,
                    executor,
                )
                .await?;
            Ok(SourcePackFilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(
                    executed.executed_link_group,
                ),
                completion: executed.completion,
            })
        }
    }
}

pub async fn execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = source_pack_filesystem_work_queue_claim_ready_item_for_target_at(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_items,
        now_unix_nanos,
    )?;
    let executed_item = if let Some(item_index) = claim.claimed_item_index {
        Some(
            execute_source_pack_filesystem_work_queue_claimed_item_async_with_path_artifacts_for_target_at(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
            .await?,
        )
    } else {
        None
    };
    let progress = executed_item
        .as_ref()
        .map(|execution| execution.completion.progress.clone())
        .unwrap_or_else(|| claim.progress.clone());
    Ok(SourcePackFilesystemWorkQueueWorkerStepExecutionResult {
        worker_id,
        claimed_item_index: claim.claimed_item_index,
        executed_item,
        progress,
    })
}

pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target_at<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_items = source_pack_limit_ready_state_items(max_ready_items);
    let step_limit = source_pack_limit_work_queue_worker_run_items(max_items);
    let mut executed_item_count = 0usize;
    let mut executed_artifact_batch_count = 0usize;
    let mut executed_link_group_count = 0usize;
    let mut progress = source_pack_filesystem_work_queue_progress_snapshot_for_target_at(
        &artifact_root,
        target,
        max_ready_items,
        now_unix_nanos,
    )?;
    for _ in 0..step_limit {
        let step =
            execute_source_pack_filesystem_work_queue_worker_step_async_with_path_artifacts_for_target_at(
                &artifact_root,
                target,
                worker_id.clone(),
                lease_expires_unix_nanos,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
            .await?;
        progress = step.progress;
        let Some(executed_item) = step.executed_item else {
            break;
        };
        executed_item_count = executed_item_count.saturating_add(1);
        match executed_item.executed {
            SourcePackFilesystemWorkQueueExecutedItem::ArtifactBatch(_) => {
                executed_artifact_batch_count = executed_artifact_batch_count.saturating_add(1);
            }
            SourcePackFilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(_) => {
                executed_link_group_count = executed_link_group_count.saturating_add(1);
            }
        }
        if progress.complete {
            break;
        }
    }

    let store = SourcePackFilesystemArtifactStore::new(&artifact_root);
    let (linked_output_key, linked_output_path) =
        source_pack_filesystem_work_queue_final_linked_output_for_progress(
            &store, target, &progress,
        )?;
    Ok(SourcePackFilesystemWorkQueueWorkerRunExecutionResult {
        worker_id,
        executed_item_count,
        executed_artifact_batch_count,
        executed_link_group_count,
        linked_output_key,
        linked_output_path,
        progress,
    })
}

pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target<
    E,
>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target_at(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(source_pack_build_now_unix_nanos()?),
        executor,
    )
    .await
}

pub async fn execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts<E>(
    artifact_root: impl Into<PathBuf>,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<SourcePackFilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath,
            CodegenObjectArtifact = SourcePackFilesystemArtifactPath,
            LinkedOutputArtifact = SourcePackFilesystemArtifactPath,
            PartialLinkArtifact = SourcePackFilesystemArtifactPath,
        >,
{
    execute_source_pack_filesystem_work_queue_worker_run_async_with_path_artifacts_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        executor,
    )
    .await
}

pub fn release_source_pack_filesystem_artifact_manifest_link_input_shard(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
) -> Result<SourcePackFilesystemArtifactLinkInputReleaseResult, CompileError> {
    release_source_pack_filesystem_artifact_manifest_link_input_shard_for_target(
        artifact_root,
        shard_index,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn release_source_pack_filesystem_artifact_manifest_link_input_shard_for_target(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackFilesystemArtifactLinkInputReleaseResult, CompileError> {
    let mut store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let link_input_index = store.load_link_input_shard_index_for_target(target)?;
    let summary = store.load_build_progress_summary_for_target(target)?;
    if !summary.is_complete() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack link input shard {shard_index} cannot be released before build completion; completed {} of {} batches",
            summary.completed_batch_count, summary.job_batch_count
        )));
    }
    let linked_output_key = summary.linked_output_key.clone().ok_or_else(|| {
        CompileError::GpuFrontend(
            "source-pack complete progress summary has no linked output key".into(),
        )
    })?;
    let linked_output_path = store.path_for_key(&linked_output_key)?;
    if !linked_output_path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack linked output {linked_output_key:?} is missing at {}",
            linked_output_path.display()
        )));
    }

    let expected_kind = if source_pack_link_input_shard_index_contains_kind(
        &link_input_index,
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
        shard_index,
    ) {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches
    } else if source_pack_link_input_shard_index_contains_kind(
        &link_input_index,
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
        shard_index,
    ) {
        SourcePackBuildArtifactShardKind::LinkObjectBatches
    } else {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "shard {shard_index} is not listed in the link-input shard index"
        )));
    };

    let execution_shard =
        store.load_build_artifact_execution_shard_for_target(target, shard_index)?;
    validate_source_pack_build_artifact_execution_shard(&execution_shard, target)?;
    if execution_shard.shard.kind != expected_kind {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "execution shard {shard_index} is {:?}, expected {:?} from link-input shard index",
            execution_shard.shard.kind, expected_kind
        )));
    }
    let (released_interface_count, released_object_count) =
        release_source_pack_link_input_artifacts_from_execution_shard(
            &execution_shard,
            &mut store,
        )?;

    Ok(SourcePackFilesystemArtifactLinkInputReleaseResult {
        target,
        shard_index,
        shard_kind: execution_shard.shard.kind,
        released_interface_count,
        released_object_count,
        linked_output_key,
        linked_output_path,
        artifact_shard_index_path: store.artifact_shard_index_path_for_target(target),
        artifact_execution_shard_path: store
            .artifact_execution_shard_path_for_target(target, shard_index),
    })
}

pub fn source_pack_filesystem_artifact_manifest_ready_state_batches(
    artifact_root: impl Into<PathBuf>,
) -> Result<Vec<usize>, CompileError> {
    source_pack_filesystem_artifact_manifest_ready_state_batches_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_ready_state_batches_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<Vec<usize>, CompileError> {
    source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target(
        artifact_root,
        SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT,
        target,
    )
}

pub fn source_pack_filesystem_artifact_manifest_ready_state_batches_limited(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
) -> Result<Vec<usize>, CompileError> {
    source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target(
        artifact_root,
        max_batches,
        SourcePackArtifactTarget::Generic,
    )
}

pub fn source_pack_filesystem_artifact_manifest_ready_state_batches_limited_for_target(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    target: SourcePackArtifactTarget,
) -> Result<Vec<usize>, CompileError> {
    let max_batches = source_pack_limit_ready_state_batches(max_batches);
    let store = SourcePackFilesystemArtifactStore::new(artifact_root);
    let summary = source_pack_build_progress_summary_for_frontier_bounded(&store, target)?;
    let now_unix_nanos = Some(source_pack_build_now_unix_nanos()?);
    let ready_batch_indices = if summary.is_complete() || max_batches == 0 {
        Vec::new()
    } else {
        source_pack_build_progress_ready_unclaimed_batch_indices_from_summary_limited(
            &store,
            target,
            &summary,
            now_unix_nanos,
            Some(max_batches),
        )?
    };
    validate_source_pack_ready_batch_dependency_artifacts_from_execution_shards(
        &store,
        summary.job_batch_count,
        target,
        &ready_batch_indices,
    )?;
    Ok(ready_batch_indices)
}
