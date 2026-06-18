use super::*;

/// Fully prepare a target-specific artifact build using default shard limits.
pub fn prepare_artifact_build_for_target(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError> {
    prepare_artifact_build(
        artifact_root,
        limits,
        batch_limits,
        SourcePackBuildShardLimits::default(),
        target,
    )
}

/// Prepare the next chunk of library schedule pages from stored source
/// metadata.
pub fn prepare_library_schedule_chunk(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<FilesystemLibrarySchedulePrepareStepResult, CompileError> {
    let max_new_libraries = max_new_libraries.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    prepare_schedule_chunk_from_metadata(&store, target, limits, max_new_libraries)
}

/// Prepare the next chunk of artifact-reference pages from the library
/// schedule.
pub fn prepare_artifact_refs_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
) -> Result<FilesystemArtifactRefPrepareStepResult, CompileError> {
    let max_new_libraries = max_new_libraries.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_artifact_ref_pages_from_schedule_chunk(&store, &schedule_index, max_new_libraries)
}

/// Prepare the next chunk of job-batch pages from the library schedule.
pub fn prepare_job_batches_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<FilesystemJobBatchPrepareStepResult, CompileError> {
    let max_new_batches = max_new_batches.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_build_job_batch_pages_from_schedule_chunk(
        &store,
        &schedule_index,
        batch_limits,
        max_new_batches,
    )
}

/// Prepare the next chunk of reverse job-batch dependency pages.
pub fn prepare_job_dependents_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_batches: usize,
) -> Result<FilesystemJobBatchDependentsPrepareStepResult, CompileError> {
    let max_new_batches = max_new_batches.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let job_batch_index = store.load_build_job_batch_page_index_for_target(target)?;
    store_job_batch_dependents_pages_from_batch_chunk(
        &store,
        target,
        &job_batch_index,
        max_new_batches,
    )
}

/// Prepare the next chunk of artifact execution shards and progress directory
/// pages.
pub fn prepare_artifact_shards_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    shard_limits: SourcePackBuildShardLimits,
    max_new_batches: usize,
) -> Result<FilesystemArtifactShardPrepareStepResult, CompileError> {
    let max_new_batches = max_new_batches.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;
    store_build_artifact_shards_from_metadata_chunk(
        &store,
        target,
        shard_limits,
        &schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
        &library_partition_index,
        max_new_batches,
    )
}

/// Prepare the next chunk of link-batch input pages.
pub fn prepare_link_batches_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<FilesystemLinkBatchPrepareStepResult, CompileError> {
    let max_new_batches = max_new_batches.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    store_build_link_batch_pages_from_artifact_refs_chunk(
        &store,
        target,
        &schedule_index,
        &artifact_ref_index,
        batch_limits,
        max_new_batches,
    )
}

/// Prepare the next chunk of hierarchical link leaf groups.
pub fn prepare_link_leaf_groups_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_partitions: usize,
) -> Result<FilesystemHierarchicalLinkLeafPrepareStepResult, CompileError> {
    let max_new_partitions = max_new_partitions.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_link_leaf_group_chunk(&store, &schedule_index, batch_limits, max_new_partitions)
}

/// Prepare the next chunk of hierarchical link reduce groups.
pub fn prepare_link_reduce_groups_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    batch_limits: SourcePackJobBatchLimits,
    max_new_reduce_groups: usize,
) -> Result<FilesystemHierarchicalLinkPlanPrepareStepResult, CompileError> {
    let max_new_reduce_groups =
        max_new_reduce_groups.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    store_link_reduce_group_chunk(&store, &schedule_index, batch_limits, max_new_reduce_groups)
}

/// Prepare the next chunk of hierarchical link execution pages.
pub fn prepare_link_execution_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_groups: usize,
) -> Result<FilesystemHierarchicalLinkExecutionPrepareStepResult, CompileError> {
    let max_new_groups = max_new_groups.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let link_plan_index = store.load_hierarchical_link_plan_index_for_target(target)?;
    store_hierarchical_link_execution_from_schedule_chunk(
        &store,
        &link_plan_index,
        &schedule_index,
        &artifact_ref_index,
        max_new_groups,
    )
}

/// Prepare the next chunk of claimable work-queue item pages.
pub fn prepare_work_queue_pages_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<FilesystemWorkQueuePrepareStepResult, CompileError> {
    let max_new_items = max_new_items.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let schedule_index = store.load_library_schedule_index_for_target(target)?;
    let link_plan_index = store.load_hierarchical_link_plan_index_for_target(target)?;
    store_work_queue_pages_from_schedule_chunk(
        &store,
        &schedule_index,
        &link_plan_index,
        max_new_items,
    )
}

/// Prepare the next chunk of initial work-queue progress pages.
pub fn prepare_work_queue_progress_chunk(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    page_size: usize,
    max_new_pages: usize,
) -> Result<FilesystemWorkQueueProgressPrepareStepResult, CompileError> {
    let max_new_pages = max_new_pages.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let work_queue_index = store.load_work_queue_index_for_target(target)?;
    store_initial_progress_chunk(&store, &work_queue_index, page_size, max_new_pages)
}
