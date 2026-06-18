use super::*;

mod inputs;
pub use inputs::{
    EntrySourceRoots,
    load_entry_path_manifest_with_source_root,
    load_entry_path_manifest_with_source_root_and_optional_stdlib,
    load_entry_path_manifest_with_source_root_and_stdlib,
    load_entry_path_manifest_with_source_roots,
    load_entry_path_manifest_with_stdlib,
    load_entry_with_source_root,
    load_entry_with_source_root_and_optional_stdlib,
    load_entry_with_source_root_and_stdlib,
    load_entry_with_source_roots,
    load_entry_with_stdlib,
    load_explicit_source_libraries_from_paths,
    load_explicit_source_pack_manifest_from_paths,
    load_explicit_source_pack_path_manifest_from_paths,
};

mod compact_manifest;
pub(super) use compact_manifest::compact_manifest_from_dependency_streams;
pub use compact_manifest::{
    plan_dependency_streams_compact_manifest,
    plan_dependency_streams_compact_manifest_for_target,
    plan_library_streams_compact_manifest,
    plan_library_streams_compact_manifest_for_target,
    plan_source_pack_streams_compact_manifest,
    plan_source_pack_streams_compact_manifest_for_target,
};

mod build_plan;
pub use build_plan::{
    plan_libraries_artifacts_from_paths,
    plan_libraries_frontend_from_paths,
    plan_pack_artifacts_from_paths,
    plan_pack_frontend_from_paths,
};

mod artifact_store_build;
pub use artifact_store_build::execute_pack_paths_store_build;

mod library_filesystem_build;
pub use library_filesystem_build::*;

mod filesystem_artifact_build;
pub use filesystem_artifact_build::*;

mod filesystem_metadata;
pub use filesystem_metadata::{
    prepare_dependency_stream_metadata,
    prepare_dependency_stream_metadata_for_target,
    prepare_library_path_metadata,
    prepare_library_path_metadata_for_target,
    prepare_metadata_chunk_for_target,
    prepare_ordered_library_path_metadata,
    prepare_ordered_library_path_metadata_for_target,
    prepare_pack_path_stream_metadata,
    prepare_pack_path_stream_metadata_for_target,
    prepare_pack_paths_metadata,
    prepare_pack_paths_metadata_for_target,
    resume_metadata_chunk_for_target,
};

mod artifact_build_stages;
pub use artifact_build_stages::{
    prepare_artifact_build_for_target,
    prepare_artifact_refs_chunk,
    prepare_artifact_shards_chunk,
    prepare_job_batches_chunk,
    prepare_job_dependents_chunk,
    prepare_library_schedule_chunk,
    prepare_link_batches_chunk,
    prepare_link_execution_chunk,
    prepare_link_leaf_groups_chunk,
    prepare_link_reduce_groups_chunk,
    prepare_work_queue_pages_chunk,
    prepare_work_queue_progress_chunk,
};

/// Reconstructs a completed preparation summary from persisted indexes.
pub(super) fn artifact_prepare_result_from_indexes(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let library_schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let artifact_shard_index = store.load_build_artifact_shard_index_for_target(target)?;
    let hierarchical_link_plan_index =
        store.load_hierarchical_link_plan_index_for_target(target)?;
    let hierarchical_link_execution_index =
        store.load_hierarchical_link_execution_index_for_target(target)?;
    let work_queue_index = store.load_work_queue_index_for_target(target)?;
    let work_queue_progress_index = store.load_work_queue_progress_index_for_target(target)?;
    let build_progress_summary = store.load_build_progress_summary_for_target(target)?;
    let build_manifest = store.load_path_build_manifest_for_target(target)?;
    let artifact_manifest = store.load_build_artifact_manifest_for_target(target)?;
    validate_path_manifest(&build_manifest)?;
    validate_artifact_manifest(&artifact_manifest)?;
    if build_manifest.artifacts.target != target || artifact_manifest.target != target {
        return Err(artifact_shard_contract_error(format!(
            "stored build manifests target {:?}/{:?} do not match requested target {:?}",
            build_manifest.artifacts.target, artifact_manifest.target, target
        )));
    }
    if artifact_manifest.artifact_count != artifact_ref_index.artifact_count
        || artifact_manifest.job_batch_count != job_batch_page_index.batch_count
        || artifact_manifest.job_count != library_schedule_index.job_count
    {
        return Err(artifact_shard_contract_error(format!(
            "stored artifact manifest jobs/batches/artifacts {}/{}/{} do not match indexes {}/{}/{}",
            artifact_manifest.job_count,
            artifact_manifest.job_batch_count,
            artifact_manifest.artifact_count,
            library_schedule_index.job_count,
            job_batch_page_index.batch_count,
            artifact_ref_index.artifact_count
        )));
    }
    let build_state_path = store.build_state_path_for_target(target);
    if !build_state_path.is_file() {
        return Err(artifact_shard_contract_error(format!(
            "prepared source-pack build state is missing at {}",
            build_state_path.display()
        )));
    }
    Ok(PrepareResult {
        target,
        artifact_root: store.root().to_path_buf(),
        source_file_count: library_partition_index.source_file_count,
        source_byte_count: library_partition_index.source_byte_count,
        source_line_count: library_partition_index.source_line_count,
        library_count: library_partition_index.partition_count,
        artifact_count: artifact_ref_index.artifact_count,
        scheduled_job_count: library_schedule_index.job_count,
        batch_count: job_batch_page_index.batch_count,
        initial_ready_batch_count: build_progress_summary.ready_batch_count,
        first_ready_batch_index: build_progress_summary.first_ready_batch_index,
        build_manifest_path: store.build_manifest_path_for_target(target),
        library_partition_index_path: store.library_partition_index_path_for_target(target),
        library_partition_count: library_partition_index.partition_count,
        library_source_file_page_count: library_partition_index.partition_count,
        library_build_unit_page_count: library_schedule_index.partition_count,
        library_schedule_index_path: store.library_schedule_index_path_for_target(target),
        library_schedule_page_count: library_schedule_index.partition_count,
        hierarchical_link_plan_index_path: store
            .hierarchical_link_plan_index_path_for_target(target),
        hierarchical_link_group_count: hierarchical_link_plan_index.link_group_count,
        hierarchical_link_execution_index_path: store
            .hierarchical_link_execution_index_path_for_target(target),
        hierarchical_link_execution_group_count: hierarchical_link_execution_index.link_group_count,
        work_queue_index_path: store.work_queue_index_path_for_target(target),
        work_queue_item_count: work_queue_index.work_item_count,
        work_queue_progress_index_path: store.work_queue_progress_index_path_for_target(target),
        work_queue_progress_page_count: work_queue_progress_index.page_count,
        initial_ready_work_item_count: work_queue_progress_index.ready_item_count,
        first_ready_work_item_index: work_queue_progress_index.first_ready_item_index,
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        artifact_shard_index_path: store.artifact_shard_index_path_for_target(target),
        artifact_shard_count: artifact_shard_index.shard_count(),
        build_state_path,
    })
}

/// Stores compact build manifests after all planning indexes have been prepared.
pub(super) fn store_compact_build_manifests_from_indexes(
    store: &FilesystemArtifactStore,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
) -> Result<(PathBuf, PathBuf), CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    let library_schedule_index = store.load_library_schedule_index_for_target(target)?;
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;
    let path_build_manifest = compact_path_build_manifest_from_stored_indexes(
        limits,
        batch_limits,
        target,
        &library_schedule_index,
        &artifact_ref_index,
        &job_batch_page_index,
        &link_batch_page_index,
        library_partition_index.source_file_count,
        library_partition_index.source_byte_count,
        library_partition_index.source_line_count,
    );
    let artifact_manifest_path =
        store.store_build_artifact_manifest(&path_build_manifest.artifacts)?;
    let build_manifest_path = store.store_compact_path_build_manifest(&path_build_manifest)?;
    Ok((build_manifest_path, artifact_manifest_path))
}

/// Returns whether job-batch dependent preparation has reached the final batch.
pub(super) fn job_batch_dependents_complete(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<bool, CompileError> {
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    if !path.is_file() {
        return Ok(false);
    }
    let progress = load_job_batch_dependents_prepare_progress(store, target, batch_count)?;
    Ok(progress.next_batch_index == batch_count)
}

/// Returns whether hierarchical link leaf-group preparation has completed.
pub(super) fn hierarchical_link_leaf_groups_complete(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<bool, CompileError> {
    let progress_path =
        store.hierarchical_link_plan_prepare_progress_path_for_target(schedule_index.target);
    if !progress_path.is_file() {
        return Ok(false);
    }
    let progress = load_link_plan_prepare_progress(
        store,
        schedule_index.target,
        schedule_index.partition_count,
        batch_limits.normalized(),
    )?;
    Ok(progress.next_partition_index == schedule_index.partition_count)
}

/// Builds an incomplete artifact-preparation step result.
pub(super) fn artifact_prepare_step(
    target: SourcePackArtifactTarget,
    stage: BuildPrepareStage,
    next_stage: BuildPrepareStage,
    new_item_count: usize,
) -> BuildPrepareStepResult {
    BuildPrepareStepResult {
        target,
        complete: false,
        stage,
        next_stage,
        new_item_count,
        prepared: None,
    }
}

/// Advance persisted artifact-build preparation by a bounded number of new
/// items and report the current preparation stage.
pub fn prepare_artifact_build_chunk(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<BuildPrepareStepResult, CompileError> {
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact build chunk max_new_items must be greater than zero".into(),
        ));
    }
    let max_new_items = max_new_items.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let _state_lock = store.try_lock_build_state_for_target(target)?;
    if store.build_state_path_for_target(target).is_file() {
        let prepared = artifact_prepare_result_from_indexes(&store, target)?;
        return Ok(BuildPrepareStepResult {
            target,
            complete: true,
            stage: BuildPrepareStage::Complete,
            next_stage: BuildPrepareStage::Complete,
            new_item_count: 0,
            prepared: Some(prepared),
        });
    }

    if !store
        .library_schedule_job_locator_index_path_for_target(target)
        .is_file()
    {
        let step = prepare_schedule_chunk_from_metadata(&store, target, limits, max_new_items)?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::LibrarySchedule,
            if step.complete {
                BuildPrepareStage::ArtifactRefs
            } else {
                BuildPrepareStage::LibrarySchedule
            },
            step.new_library_build_unit_page_count
                .saturating_add(step.new_library_schedule_page_count),
        ));
    }
    let schedule_index = store.load_library_schedule_index_for_target(target)?;

    if !store
        .build_artifact_ref_index_path_for_target(target)
        .is_file()
    {
        let step =
            store_artifact_ref_pages_from_schedule_chunk(&store, &schedule_index, max_new_items)?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::ArtifactRefs,
            if step.complete {
                BuildPrepareStage::JobBatches
            } else {
                BuildPrepareStage::ArtifactRefs
            },
            step.new_library_count,
        ));
    }
    let artifact_ref_index = store.load_build_artifact_ref_index_for_target(target)?;

    if !store
        .build_job_batch_index_path_for_target(target)
        .is_file()
    {
        let step = store_build_job_batch_pages_from_schedule_chunk(
            &store,
            &schedule_index,
            batch_limits,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::JobBatches,
            if step.complete {
                BuildPrepareStage::LinkBatches
            } else {
                BuildPrepareStage::JobBatches
            },
            step.new_batch_count,
        ));
    }
    let job_batch_page_index = store.load_build_job_batch_page_index_for_target(target)?;

    if !store
        .build_link_batch_index_path_for_target(target)
        .is_file()
    {
        let step = store_build_link_batch_pages_from_artifact_refs_chunk(
            &store,
            target,
            &schedule_index,
            &artifact_ref_index,
            batch_limits,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::LinkBatches,
            if step.complete {
                BuildPrepareStage::JobBatchDependents
            } else {
                BuildPrepareStage::LinkBatches
            },
            step.new_batch_count,
        ));
    }
    let link_batch_page_index = store.load_build_link_batch_page_index_for_target(target)?;

    if !job_batch_dependents_complete(&store, target, job_batch_page_index.batch_count)? {
        let step = store_job_batch_dependents_pages_from_batch_chunk(
            &store,
            target,
            &job_batch_page_index,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::JobBatchDependents,
            if step.complete {
                BuildPrepareStage::ArtifactShards
            } else {
                BuildPrepareStage::JobBatchDependents
            },
            step.new_batch_count,
        ));
    }

    if !store.artifact_shard_index_path_for_target(target).is_file() {
        let library_partition_index = store.load_library_partition_index_for_target(target)?;
        let step = store_build_artifact_shards_from_metadata_chunk(
            &store,
            target,
            shard_limits,
            &schedule_index,
            &artifact_ref_index,
            &job_batch_page_index,
            &link_batch_page_index,
            &library_partition_index,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::ArtifactShards,
            if step.complete {
                BuildPrepareStage::HierarchicalLinkLeafGroups
            } else {
                BuildPrepareStage::ArtifactShards
            },
            step.new_input_batch_count
                .saturating_add(step.new_progress_directory_page_count)
                .saturating_add(step.new_progress_directory_index_page_count),
        ));
    }

    if !store
        .hierarchical_link_plan_index_path_for_target(target)
        .is_file()
        && !hierarchical_link_leaf_groups_complete(&store, &schedule_index, batch_limits)?
    {
        let step =
            store_link_leaf_group_chunk(&store, &schedule_index, batch_limits, max_new_items)?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::HierarchicalLinkLeafGroups,
            if step.complete {
                BuildPrepareStage::HierarchicalLinkPlanReduceGroups
            } else {
                BuildPrepareStage::HierarchicalLinkLeafGroups
            },
            step.new_leaf_group_count,
        ));
    }

    if !store
        .hierarchical_link_plan_index_path_for_target(target)
        .is_file()
    {
        let step =
            store_link_reduce_group_chunk(&store, &schedule_index, batch_limits, max_new_items)?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::HierarchicalLinkPlanReduceGroups,
            if step.complete {
                BuildPrepareStage::HierarchicalLinkExecution
            } else {
                BuildPrepareStage::HierarchicalLinkPlanReduceGroups
            },
            step.new_reduce_group_count,
        ));
    }
    let hierarchical_link_plan_index =
        store.load_hierarchical_link_plan_index_for_target(target)?;

    if !store
        .hierarchical_link_execution_index_path_for_target(target)
        .is_file()
    {
        let step = store_hierarchical_link_execution_from_schedule_chunk(
            &store,
            &hierarchical_link_plan_index,
            &schedule_index,
            &artifact_ref_index,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::HierarchicalLinkExecution,
            if step.complete {
                BuildPrepareStage::WorkQueuePages
            } else {
                BuildPrepareStage::HierarchicalLinkExecution
            },
            step.new_execution_page_count,
        ));
    }

    if !store.work_queue_index_path_for_target(target).is_file() {
        let step = store_work_queue_pages_from_schedule_chunk(
            &store,
            &schedule_index,
            &hierarchical_link_plan_index,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::WorkQueuePages,
            if step.complete {
                BuildPrepareStage::WorkQueueProgress
            } else {
                BuildPrepareStage::WorkQueuePages
            },
            step.new_work_item_count,
        ));
    }

    if !store
        .work_queue_progress_index_path_for_target(target)
        .is_file()
    {
        let work_queue_index = store.load_work_queue_index_for_target(target)?;
        let step = store_initial_progress_chunk(
            &store,
            &work_queue_index,
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
            max_new_items,
        )?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::WorkQueueProgress,
            if step.complete {
                BuildPrepareStage::BuildManifests
            } else {
                BuildPrepareStage::WorkQueueProgress
            },
            step.new_progress_page_count,
        ));
    }

    if !store.build_manifest_path_for_target(target).is_file()
        || !store.artifact_manifest_path_for_target(target).is_file()
    {
        store_compact_build_manifests_from_indexes(&store, limits, batch_limits, target)?;
        return Ok(artifact_prepare_step(
            target,
            BuildPrepareStage::BuildManifests,
            BuildPrepareStage::BuildState,
            2,
        ));
    }

    let build_state_path =
        store.store_build_state_for_target(target, &SourcePackBuildState::new())?;
    if !build_state_path.is_file() {
        return Err(artifact_shard_contract_error(format!(
            "source-pack build state was not stored at {}",
            build_state_path.display()
        )));
    }
    let prepared = artifact_prepare_result_from_indexes(&store, target)?;
    Ok(BuildPrepareStepResult {
        target,
        complete: true,
        stage: BuildPrepareStage::BuildState,
        next_stage: BuildPrepareStage::Complete,
        new_item_count: 1,
        prepared: Some(prepared),
    })
}

/// Repeatedly prepare persisted artifact-build chunks until preparation
/// completes or the full-prepare step limit is reached.
pub fn prepare_artifact_build(
    artifact_root: impl Into<PathBuf>,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
) -> Result<PrepareResult, CompileError> {
    let artifact_root = artifact_root.into();
    for _ in 0..ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT {
        let step = prepare_artifact_build_chunk(
            &artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
        )?;
        if step.complete {
            return step.prepared.ok_or_else(|| {
                artifact_shard_contract_error(
                    "completed source-pack artifact build prepare did not return prepared result",
                )
            });
        }
    }
    Err(CompileError::GpuFrontend(format!(
        "source-pack artifact build prepare did not complete within {ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT} bounded chunk steps; keep calling prepare_artifact_build_chunk to continue persisted preparation"
    )))
}

/// Advances metadata and artifact preparation for dependency-stream inputs.
pub(super) fn prepare_dependency_stream_work_queue_chunk<I, PI, DI, P>(
    libraries: I,
    artifact_root: &Path,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<bool, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work-queue preparation chunk max_new_items must be greater than zero"
                .into(),
        ));
    }
    let max_new_items = max_new_items.min(ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT);
    let store = FilesystemArtifactStore::new(artifact_root);
    if !store
        .library_partition_index_path_for_target(target)
        .is_file()
    {
        let metadata =
            prepare_metadata_chunk_for_target(libraries, artifact_root, target, max_new_items)?;
        if !metadata.complete {
            return Ok(false);
        }
    }
    if !store.build_state_path_for_target(target).is_file() {
        let build = prepare_artifact_build_chunk(
            artifact_root,
            limits,
            batch_limits,
            shard_limits,
            target,
            max_new_items,
        )?;
        return Ok(build.complete);
    }
    Ok(true)
}

#[allow(clippy::too_many_arguments)]
/// Advances metadata and artifact preparation for stdlib/user path streams.
pub(super) fn prepare_path_stream_work_queue_chunk<'a, SI, UI, P>(
    stdlib_source_file_count: usize,
    stdlib_paths: SI,
    user_source_file_count: usize,
    user_paths: UI,
    artifact_root: &Path,
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    shard_limits: SourcePackBuildShardLimits,
    target: SourcePackArtifactTarget,
    max_new_items: usize,
) -> Result<bool, CompileError>
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
    prepare_dependency_stream_work_queue_chunk(
        libraries,
        artifact_root,
        limits,
        batch_limits,
        shard_limits,
        target,
        max_new_items,
    )
}

mod work_queue_prepare;
pub(super) use work_queue_prepare::work_queue_not_prepared_error;
