use super::*;

mod builders;
pub(in crate::compiler) use builders::*;

/// Stage of resumable artifact-shard preparation.
///
/// Artifact-shard preparation first groups job/link batches into bounded
/// execution shards, then derives the progress directory pages workers use to
/// find ready work without scanning every shard.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) enum ArtifactShardPreparePhase {
    /// Group normal job batches into job-batch artifact shards.
    JobBatches,
    /// Group link-interface batches into link-input artifact shards.
    LinkInterfaceBatches,
    /// Group link-object batches into link-input artifact shards.
    LinkObjectBatches,
    /// Write progress-directory pages from generated job-batch shards.
    BuildProgressDirectoryPages,
    /// Write progress-directory index pages from generated directory pages.
    BuildProgressDirectoryIndexPages,
    /// Preparation is complete and compact indexes can be loaded directly.
    Complete,
}

impl ArtifactShardPreparePhase {
    /// Returns the artifact-shard kind produced by this phase, if any.
    pub(in crate::compiler) fn kind(self) -> Option<SourcePackBuildArtifactShardKind> {
        match self {
            Self::JobBatches => Some(SourcePackBuildArtifactShardKind::JobBatches),
            Self::LinkInterfaceBatches => {
                Some(SourcePackBuildArtifactShardKind::LinkInterfaceBatches)
            }
            Self::LinkObjectBatches => Some(SourcePackBuildArtifactShardKind::LinkObjectBatches),
            Self::BuildProgressDirectoryPages
            | Self::BuildProgressDirectoryIndexPages
            | Self::Complete => None,
        }
    }

    /// Returns the next phase in the artifact-shard preparation state machine.
    pub(in crate::compiler) fn next(self) -> Self {
        match self {
            Self::JobBatches => Self::LinkInterfaceBatches,
            Self::LinkInterfaceBatches => Self::LinkObjectBatches,
            Self::LinkObjectBatches => Self::BuildProgressDirectoryPages,
            Self::BuildProgressDirectoryPages => Self::BuildProgressDirectoryIndexPages,
            Self::BuildProgressDirectoryIndexPages | Self::Complete => Self::Complete,
        }
    }
}

/// Persisted cursor for resumable artifact-shard preparation.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct ArtifactShardPrepareProgress {
    /// Progress record format version.
    pub(in crate::compiler) version: u32,
    /// Artifact target whose pages are being prepared.
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    /// Normalized shard limits used for this preparation run.
    pub(in crate::compiler) limits: SourcePackBuildShardLimits,
    /// Total scheduled job count captured from the schedule index.
    pub(in crate::compiler) job_count: usize,
    /// Total normal job-batch count captured from the job-batch index.
    pub(in crate::compiler) job_batch_count: usize,
    /// Total artifact-ref count captured from the artifact-ref index.
    pub(in crate::compiler) artifact_count: usize,
    /// Total link-interface batch count captured from the link-batch index.
    pub(in crate::compiler) link_interface_batch_count: usize,
    /// Total link-object batch count captured from the link-batch index.
    pub(in crate::compiler) link_object_batch_count: usize,
    /// Current preparation phase.
    pub(in crate::compiler) phase: ArtifactShardPreparePhase,
    /// Next input batch or directory page index to process in the current phase.
    pub(in crate::compiler) next_batch_index: usize,
    /// Index that will be assigned to the next stored artifact shard.
    pub(in crate::compiler) next_shard_index: usize,
    /// Pending shard builder for phases that group input batches.
    pub(in crate::compiler) current_builder: Option<ArtifactShardBuilder>,
    /// Number of generated shards that contain normal job batches.
    pub(in crate::compiler) job_batch_shard_count: usize,
    /// Contiguous shard range containing link-interface input batches.
    pub(in crate::compiler) link_interface_shard_range: Option<SourcePackLinkInputShardRange>,
    /// Contiguous shard range containing link-object input batches.
    pub(in crate::compiler) link_object_shard_range: Option<SourcePackLinkInputShardRange>,
    /// Initial count of ready job batches across generated progress shards.
    pub(in crate::compiler) ready_batch_count: usize,
    /// Lowest initially ready job-batch index, if any batch is ready.
    pub(in crate::compiler) first_ready_batch_index: Option<usize>,
}

/// Returns the total number of input units in the current preparation phase.
pub(in crate::compiler) fn artifact_shard_prepare_phase_batch_count(
    progress: &ArtifactShardPrepareProgress,
) -> usize {
    match progress.phase {
        ArtifactShardPreparePhase::JobBatches => progress.job_batch_count,
        ArtifactShardPreparePhase::LinkInterfaceBatches => progress.link_interface_batch_count,
        ArtifactShardPreparePhase::LinkObjectBatches => progress.link_object_batch_count,
        ArtifactShardPreparePhase::BuildProgressDirectoryPages => progress
            .job_batch_shard_count
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE),
        ArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => progress
            .job_batch_shard_count
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE),
        ArtifactShardPreparePhase::Complete => 0,
    }
}

/// Returns the number of build-progress directory pages for prepared shards.
pub(in crate::compiler) fn shard_progress_directory_page_count(
    progress: &ArtifactShardPrepareProgress,
) -> usize {
    progress
        .job_batch_shard_count
        .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
}

/// Returns the number of build-progress directory index pages.
pub(in crate::compiler) fn shard_progress_directory_index_page_count(
    progress: &ArtifactShardPrepareProgress,
) -> usize {
    shard_progress_directory_page_count(progress)
        .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE)
}

/// Builds the initial progress summary represented by shard preparation state.
pub(in crate::compiler) fn progress_summary_from_shard_prepare(
    progress: &ArtifactShardPrepareProgress,
) -> SourcePackBuildProgressSummary {
    SourcePackBuildProgressSummary {
        version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
        target: progress.target,
        job_batch_count: progress.job_batch_count,
        job_batch_shard_count: progress.job_batch_shard_count,
        completed_batch_count: 0,
        ready_batch_count: progress.ready_batch_count,
        first_ready_batch_index: progress.first_ready_batch_index,
        claimed_batch_count: 0,
        ready_claimed_batch_count: 0,
        earliest_claim_lease_expires_unix_nanos: None,
        linked_output_key: None,
    }
}

/// Validates persisted artifact-shard preparation progress against source indexes.
pub(in crate::compiler) fn validate_artifact_shard_prepare_progress(
    progress: &ArtifactShardPrepareProgress,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-shard prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard prepare target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    let limits = limits.normalized();
    if progress.limits.normalized() != limits {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard prepare limits {:?} do not match requested {:?}",
            progress.limits, limits
        )));
    }
    if progress.job_count != schedule_index.job_count
        || progress.job_count != job_batch_page_index.scheduled_job_count
        || progress.job_batch_count != job_batch_page_index.batch_count
        || progress.artifact_count != artifact_ref_index.artifact_count
        || progress.link_interface_batch_count != link_batch_page_index.link_interface_batch_count
        || progress.link_object_batch_count != link_batch_page_index.link_object_batch_count
    {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard prepare shape jobs/batches/artifacts/link batches {}/{}/{}/{}/{} does not match stored indexes {}/{}/{}/{}/{}",
            progress.job_count,
            progress.job_batch_count,
            progress.artifact_count,
            progress.link_interface_batch_count,
            progress.link_object_batch_count,
            schedule_index.job_count,
            job_batch_page_index.batch_count,
            artifact_ref_index.artifact_count,
            link_batch_page_index.link_interface_batch_count,
            link_batch_page_index.link_object_batch_count
        )));
    }
    let phase_batch_count = artifact_shard_prepare_phase_batch_count(progress);
    if progress.next_batch_index > phase_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard prepare phase {:?} next batch {} exceeds phase batch count {}",
            progress.phase, progress.next_batch_index, phase_batch_count
        )));
    }
    if progress.job_batch_shard_count > progress.job_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard prepare has {} job-batch shards but only {} job batches",
            progress.job_batch_shard_count, progress.job_batch_count
        )));
    }
    if !matches!(progress.phase, ArtifactShardPreparePhase::JobBatches)
        && progress.job_batch_count != 0
        && progress.job_batch_shard_count == 0
    {
        return Err(artifact_shard_contract_error(
            "artifact-shard prepare left job-batch phase without job-batch shards",
        ));
    }
    match (progress.phase.kind(), &progress.current_builder) {
        (Some(kind), Some(builder)) if builder.kind == kind => {}
        (Some(kind), Some(builder)) => {
            return Err(artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has builder kind {:?}, expected {:?}",
                progress.phase, builder.kind, kind
            )));
        }
        (Some(kind), None) => {
            return Err(artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has no {:?} builder",
                progress.phase, kind
            )));
        }
        (None, None) => {}
        (None, Some(_)) => {
            return Err(artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has a pending shard builder",
                progress.phase
            )));
        }
    }
    let progress_summary = progress_summary_from_shard_prepare(progress);
    validate_build_progress_summary(&progress_summary)?;
    validate_link_input_shard_range(progress.link_interface_shard_range.as_ref(), "interface")?;
    validate_link_input_shard_range(progress.link_object_shard_range.as_ref(), "object")?;
    Ok(())
}

/// Creates a shard builder for one input batch in a shard-producing phase.
pub(in crate::compiler) fn artifact_shard_builder_for_phase_batch(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    phase: ArtifactShardPreparePhase,
    batch_index: usize,
) -> Result<ArtifactShardBuilder, CompileError> {
    match phase {
        ArtifactShardPreparePhase::JobBatches => {
            let page = store.load_build_job_batch_page_for_target(target, batch_index)?;
            job_batch_shard_builder_from_schedule_page(store, schedule_index, &page.batch)
        }
        ArtifactShardPreparePhase::LinkInterfaceBatches => {
            let page =
                store.load_build_link_interface_batch_page_for_target(target, batch_index)?;
            link_interface_batch_shard_builder_from_page(&page)
        }
        ArtifactShardPreparePhase::LinkObjectBatches => {
            let page = store.load_build_link_object_batch_page_for_target(target, batch_index)?;
            link_object_batch_shard_builder_from_page(&page)
        }
        ArtifactShardPreparePhase::BuildProgressDirectoryPages
        | ArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
            Err(artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has no shard input batch",
                phase
            )))
        }
        ArtifactShardPreparePhase::Complete => Err(artifact_shard_contract_error(
            "completed artifact-shard prepare has no input batch",
        )),
    }
}

/// Stores one completed shard and all derived execution/progress metadata.
pub(in crate::compiler) fn store_artifact_shard_from_page_metadata(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    shard: SourcePackBuildArtifactShard,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
    link_interface_shard_range: &mut Option<SourcePackLinkInputShardRange>,
    link_object_shard_range: &mut Option<SourcePackLinkInputShardRange>,
    ready_batch_count: &mut usize,
    first_ready_batch_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    store_artifact_shard_page(store, &shard)?;
    store_batch_shard_locators(store, &shard)?;
    let execution_shard = build_artifact_execution_shard_from_stored_pages(
        store,
        &shard,
        schedule_index,
        artifact_ref_index,
        job_batch_page_index,
        link_batch_page_index,
        library_partition_index,
    )?;
    store.store_build_artifact_execution_shard_with_batch_count(
        &execution_shard,
        Some(job_batch_page_index.batch_count),
    )?;

    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            let progress = initial_progress_shard_from_execution_shard(target, &execution_shard)?;
            *ready_batch_count =
                ready_batch_count.saturating_add(progress.ready_batch_indices.len());
            if let Some(shard_first_ready) = progress.ready_batch_indices.iter().copied().min() {
                if first_ready_batch_index.map_or(true, |first| shard_first_ready < first) {
                    *first_ready_batch_index = Some(shard_first_ready);
                }
            }
            store.write_build_progress_shard_file(&progress)?;
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            extend_link_input_shard_range(
                link_interface_shard_range,
                shard.shard_index,
                "interface",
            )?;
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            extend_link_input_shard_range(link_object_shard_range, shard.shard_index, "object")?;
        }
    }
    Ok(())
}

/// Flushes the pending shard builder in preparation progress, if it is complete.
pub(in crate::compiler) fn store_pending_artifact_shard_prepare_builder(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    progress: &mut ArtifactShardPrepareProgress,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<bool, CompileError> {
    let Some(builder) = progress.current_builder.take() else {
        return Ok(false);
    };
    let Some(shard) = builder.finish(progress.next_shard_index, target, limits) else {
        progress.current_builder = progress.phase.kind().map(ArtifactShardBuilder::new);
        return Ok(false);
    };
    store_artifact_shard_from_page_metadata(
        store,
        target,
        shard,
        schedule_index,
        artifact_ref_index,
        job_batch_page_index,
        link_batch_page_index,
        library_partition_index,
        &mut progress.link_interface_shard_range,
        &mut progress.link_object_shard_range,
        &mut progress.ready_batch_count,
        &mut progress.first_ready_batch_index,
    )?;
    progress.next_shard_index = progress.next_shard_index.checked_add(1).ok_or_else(|| {
        artifact_shard_contract_error("artifact-shard prepare next shard index overflows")
    })?;
    progress.current_builder = progress.phase.kind().map(ArtifactShardBuilder::new);
    Ok(true)
}

/// Stores one build-progress directory page after shard preparation.
pub(in crate::compiler) fn store_progress_directory_page_from_shard(
    store: &FilesystemArtifactStore,
    progress: &ArtifactShardPrepareProgress,
    directory_page_index: usize,
) -> Result<PathBuf, CompileError> {
    let progress_summary = progress_summary_from_shard_prepare(progress);
    validate_build_progress_summary(&progress_summary)?;
    let directory_page = directory_page_from_summaries(
        store,
        progress.target,
        &progress_summary,
        directory_page_index,
    )?;
    store.store_build_progress_directory_page_for_target(
        progress.target,
        &directory_page,
        &progress_summary,
    )
}

/// Stores one build-progress directory index page after shard preparation.
pub(in crate::compiler) fn store_progress_directory_index_from_shard(
    store: &FilesystemArtifactStore,
    progress: &ArtifactShardPrepareProgress,
    directory_index_page_index: usize,
) -> Result<PathBuf, CompileError> {
    let progress_summary = progress_summary_from_shard_prepare(progress);
    validate_build_progress_summary(&progress_summary)?;
    let directory_index_page = directory_index_page_from_pages(
        store,
        progress.target,
        &progress_summary,
        None,
        directory_index_page_index,
    )?;
    store.store_build_progress_directory_index_page_for_target(
        progress.target,
        &directory_index_page,
        &progress_summary,
    )
}

/// Advances artifact-shard preparation by a bounded number of input units.
///
/// This is the resumable entry point for converting stored job/link batch pages
/// into bounded execution shards, progress shards, progress directory pages, and
/// compact shard indexes.
pub(in crate::compiler) fn store_build_artifact_shards_from_metadata_chunk(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
    max_new_batches: usize,
) -> Result<FilesystemArtifactShardPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact-shard chunk max_new_batches must be greater than zero".into(),
        ));
    }
    let limits = limits.normalized();
    validate_library_schedule_index(schedule_index, target)?;
    validate_artifact_ref_index(artifact_ref_index, target)?;
    validate_library_partition_index(library_partition_index, target)?;
    validate_job_batch_page_index(job_batch_page_index, target)?;
    validate_link_batch_page_index(link_batch_page_index, target)?;
    if store.artifact_shard_index_path_for_target(target).is_file() {
        let index = store.load_build_artifact_shard_index_for_target(target)?;
        let progress_summary = store.load_build_progress_summary_for_target(target).ok();
        let progress_directory_page_count = progress_summary
            .as_ref()
            .and_then(|summary| directory_page_count(summary).ok())
            .unwrap_or(0);
        let progress_directory_index_page_count = progress_summary
            .as_ref()
            .and_then(|summary| directory_index_page_count(summary).ok())
            .unwrap_or(0);
        return Ok(FilesystemArtifactShardPrepareStepResult {
            target,
            complete: true,
            shard_count: index.shard_count,
            new_shard_count: 0,
            next_input_kind: None,
            next_batch_index: 0,
            new_input_batch_count: 0,
            progress_directory_page_count,
            progress_directory_index_page_count,
            next_progress_directory_page_index: progress_directory_page_count,
            next_progress_directory_index_page_index: progress_directory_index_page_count,
            new_progress_directory_page_count: 0,
            new_progress_directory_index_page_count: 0,
            job_batch_count: index.job_batch_count,
            link_interface_batch_count: index.link_interface_batch_count,
            link_object_batch_count: index.link_object_batch_count,
            job_batch_shard_count: progress_summary
                .as_ref()
                .map(|summary| summary.job_batch_shard_count)
                .unwrap_or(0),
            ready_batch_count: progress_summary
                .as_ref()
                .map(|summary| summary.ready_batch_count)
                .unwrap_or(0),
            first_ready_batch_index: progress_summary
                .as_ref()
                .and_then(|summary| summary.first_ready_batch_index),
            artifact_shard_index_path: Some(store.artifact_shard_index_path_for_target(target)),
            link_input_shard_index_path: Some(store.link_input_shard_index_path_for_target(target)),
        });
    }

    let dependents_progress = load_job_batch_dependents_prepare_progress(
        store,
        target,
        job_batch_page_index.batch_count,
    )?;
    if dependents_progress.next_batch_index != job_batch_page_index.batch_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-shard chunk requires completed job-batch dependents; next batch {} of {}",
            dependents_progress.next_batch_index, job_batch_page_index.batch_count
        )));
    }

    let progress_path = store.artifact_shard_prepare_progress_path_for_target(target);
    let mut progress = if progress_path.is_file() {
        load_artifact_shard_prepare_progress(
            store,
            target,
            limits,
            schedule_index,
            artifact_ref_index,
            job_batch_page_index,
            link_batch_page_index,
        )?
    } else {
        ArtifactShardPrepareProgress {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION,
            target,
            limits,
            job_count: schedule_index.job_count,
            job_batch_count: job_batch_page_index.batch_count,
            artifact_count: artifact_ref_index.artifact_count,
            link_interface_batch_count: link_batch_page_index.link_interface_batch_count,
            link_object_batch_count: link_batch_page_index.link_object_batch_count,
            phase: ArtifactShardPreparePhase::JobBatches,
            next_batch_index: 0,
            next_shard_index: 0,
            current_builder: Some(ArtifactShardBuilder::new(
                SourcePackBuildArtifactShardKind::JobBatches,
            )),
            job_batch_shard_count: 0,
            link_interface_shard_range: None,
            link_object_shard_range: None,
            ready_batch_count: 0,
            first_ready_batch_index: None,
        }
    };
    validate_artifact_shard_prepare_progress(
        &progress,
        target,
        limits,
        schedule_index,
        artifact_ref_index,
        job_batch_page_index,
        link_batch_page_index,
    )?;

    let mut new_input_batch_count = 0usize;
    let mut new_shard_count = 0usize;
    let mut new_progress_directory_page_count = 0usize;
    let mut new_progress_directory_index_page_count = 0usize;
    let mut new_prepare_unit_count = 0usize;
    while new_prepare_unit_count < max_new_batches
        && progress.phase != ArtifactShardPreparePhase::Complete
    {
        let phase_batch_count = artifact_shard_prepare_phase_batch_count(&progress);
        if progress.next_batch_index == phase_batch_count {
            if store_pending_artifact_shard_prepare_builder(
                store,
                target,
                limits,
                &mut progress,
                schedule_index,
                artifact_ref_index,
                job_batch_page_index,
                link_batch_page_index,
                library_partition_index,
            )? {
                new_shard_count = new_shard_count.saturating_add(1);
            }
            if progress.phase == ArtifactShardPreparePhase::JobBatches {
                progress.job_batch_shard_count = progress.next_shard_index;
            }
            progress.phase = progress.phase.next();
            progress.next_batch_index = 0;
            progress.current_builder = progress.phase.kind().map(ArtifactShardBuilder::new);
            store_artifact_shard_prepare_progress(store, &progress)?;
            continue;
        }

        match progress.phase {
            ArtifactShardPreparePhase::JobBatches
            | ArtifactShardPreparePhase::LinkInterfaceBatches
            | ArtifactShardPreparePhase::LinkObjectBatches => {
                let builder = artifact_shard_builder_for_phase_batch(
                    store,
                    target,
                    schedule_index,
                    progress.phase,
                    progress.next_batch_index,
                )?;
                let current = progress.current_builder.as_mut().ok_or_else(|| {
                    artifact_shard_contract_error("artifact-shard prepare has no current builder")
                })?;
                if current.would_exceed(&builder, limits) {
                    if store_pending_artifact_shard_prepare_builder(
                        store,
                        target,
                        limits,
                        &mut progress,
                        schedule_index,
                        artifact_ref_index,
                        job_batch_page_index,
                        link_batch_page_index,
                        library_partition_index,
                    )? {
                        new_shard_count = new_shard_count.saturating_add(1);
                    }
                }
                let current = progress.current_builder.as_mut().ok_or_else(|| {
                    artifact_shard_contract_error(
                        "artifact-shard prepare has no current builder after flush",
                    )
                })?;
                current.absorb(builder);
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        artifact_shard_contract_error(
                            "artifact-shard prepare next batch index overflows",
                        )
                    })?;
                new_input_batch_count = new_input_batch_count.checked_add(1).ok_or_else(|| {
                    artifact_shard_contract_error(
                        "artifact-shard prepare new input batch count overflows",
                    )
                })?;
            }
            ArtifactShardPreparePhase::BuildProgressDirectoryPages => {
                store_progress_directory_page_from_shard(
                    store,
                    &progress,
                    progress.next_batch_index,
                )?;
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        artifact_shard_contract_error(
                            "artifact-shard prepare progress-directory page index overflows",
                        )
                    })?;
                new_progress_directory_page_count = new_progress_directory_page_count
                    .checked_add(1)
                    .ok_or_else(|| {
                        artifact_shard_contract_error(
                            "artifact-shard prepare new progress-directory page count overflows",
                        )
                    })?;
            }
            ArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
                store_progress_directory_index_from_shard(
                    store,
                    &progress,
                    progress.next_batch_index,
                )?;
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        artifact_shard_contract_error(
                            "artifact-shard prepare progress-directory index page index overflows",
                        )
                    })?;
                new_progress_directory_index_page_count =
                    new_progress_directory_index_page_count
                        .checked_add(1)
                        .ok_or_else(|| {
                            artifact_shard_contract_error(
                                "artifact-shard prepare new progress-directory index page count overflows",
                            )
                        })?;
            }
            ArtifactShardPreparePhase::Complete => {}
        }
        new_prepare_unit_count = new_prepare_unit_count.checked_add(1).ok_or_else(|| {
            artifact_shard_contract_error("artifact-shard prepare new unit count overflows")
        })?;
        store_artifact_shard_prepare_progress(store, &progress)?;
    }

    let prepared_progress_directory_page_count = shard_progress_directory_page_count(&progress);
    let prepared_progress_directory_index_page_count =
        shard_progress_directory_index_page_count(&progress);

    let mut artifact_shard_index_path = None;
    let mut link_input_shard_index_path = None;
    if progress.phase == ArtifactShardPreparePhase::Complete {
        let progress_summary = progress_summary_from_shard_prepare(&progress);
        validate_build_progress_summary(&progress_summary)?;
        let stored_directory_page_count = directory_page_count(&progress_summary)?;
        let stored_directory_index_page_count = directory_index_page_count(&progress_summary)?;
        if prepared_progress_directory_page_count != stored_directory_page_count
            || prepared_progress_directory_index_page_count != stored_directory_index_page_count
        {
            return Err(artifact_shard_contract_error(format!(
                "artifact-shard prepare progress directory counts {}/{} do not match summary counts {}/{}",
                prepared_progress_directory_page_count,
                prepared_progress_directory_index_page_count,
                stored_directory_page_count,
                stored_directory_index_page_count
            )));
        }
        let index = SourcePackBuildArtifactShardIndex {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits,
            shard_count: progress.next_shard_index,
            job_count: progress.job_count,
            job_batch_count: progress.job_batch_count,
            artifact_count: progress.artifact_count,
            link_interface_batch_count: progress.link_interface_batch_count,
            link_object_batch_count: progress.link_object_batch_count,
        };
        validate_artifact_shard_index(&index)?;
        let link_input_index = SourcePackBuildLinkInputShardIndex {
            version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
            target,
            link_interface_shard_range: progress.link_interface_shard_range.clone(),
            link_object_shard_range: progress.link_object_shard_range.clone(),
        };
        validate_link_input_shard_index(&link_input_index, target)?;
        store_artifact_shard_compact_indexes(store, &index, &link_input_index)?;
        artifact_shard_index_path = Some(store.artifact_shard_index_path_for_target(target));
        link_input_shard_index_path = Some(store.link_input_shard_index_path_for_target(target));
        store.store_build_progress_summary(&progress_summary)?;
    }

    Ok(FilesystemArtifactShardPrepareStepResult {
        target,
        complete: artifact_shard_index_path.is_some(),
        shard_count: progress.next_shard_index,
        new_shard_count,
        next_input_kind: progress.phase.kind(),
        next_batch_index: progress.next_batch_index,
        new_input_batch_count,
        progress_directory_page_count: prepared_progress_directory_page_count,
        progress_directory_index_page_count: prepared_progress_directory_index_page_count,
        next_progress_directory_page_index: match progress.phase {
            ArtifactShardPreparePhase::BuildProgressDirectoryPages => progress.next_batch_index,
            ArtifactShardPreparePhase::BuildProgressDirectoryIndexPages
            | ArtifactShardPreparePhase::Complete => prepared_progress_directory_page_count,
            _ => 0,
        },
        next_progress_directory_index_page_index: match progress.phase {
            ArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
                progress.next_batch_index
            }
            ArtifactShardPreparePhase::Complete => prepared_progress_directory_index_page_count,
            _ => 0,
        },
        new_progress_directory_page_count,
        new_progress_directory_index_page_count,
        job_batch_count: progress.job_batch_count,
        link_interface_batch_count: progress.link_interface_batch_count,
        link_object_batch_count: progress.link_object_batch_count,
        job_batch_shard_count: progress.job_batch_shard_count,
        ready_batch_count: progress.ready_batch_count,
        first_ready_batch_index: progress.first_ready_batch_index,
        artifact_shard_index_path,
        link_input_shard_index_path,
    })
}

/// Stores the persisted artifact-shard preparation cursor.
pub(in crate::compiler) fn store_artifact_shard_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &ArtifactShardPrepareProgress,
) -> Result<PathBuf, CompileError> {
    let path = store.artifact_shard_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack artifact-shard prepare progress: {err}"
        ))
    })?;
    write_file_atomic(&path, &bytes, "source-pack artifact-shard prepare progress")?;
    Ok(path)
}

/// Loads and validates the persisted artifact-shard preparation cursor.
pub(in crate::compiler) fn load_artifact_shard_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
) -> Result<ArtifactShardPrepareProgress, CompileError> {
    let path = store.artifact_shard_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack artifact-shard prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<ArtifactShardPrepareProgress>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack artifact-shard prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_artifact_shard_prepare_progress(
        &progress,
        target,
        limits,
        schedule_index,
        artifact_ref_index,
        job_batch_page_index,
        link_batch_page_index,
    )?;
    Ok(progress)
}

/// Extends a contiguous link-input shard range with the next shard index.
pub(in crate::compiler) fn extend_link_input_shard_range(
    range: &mut Option<SourcePackLinkInputShardRange>,
    shard_index: usize,
    label: &str,
) -> Result<(), CompileError> {
    if let Some(range) = range {
        let end_shard_index = range.end_shard_index().ok_or_else(|| {
            artifact_shard_contract_error(format!("{label} link input shard range overflows"))
        })?;
        if shard_index != end_shard_index {
            return Err(artifact_shard_contract_error(format!(
                "{label} link input shard range expected shard {end_shard_index} but saw {shard_index}"
            )));
        }
        range.shard_count = range.shard_count.checked_add(1).ok_or_else(|| {
            artifact_shard_contract_error(format!("{label} link input shard range count overflows"))
        })?;
    } else {
        *range = Some(SourcePackLinkInputShardRange {
            first_shard_index: shard_index,
            shard_count: 1,
        });
    }
    Ok(())
}

/// Serializes one artifact-shard page.
pub(in crate::compiler) fn store_artifact_shard_page(
    store: &FilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
) -> Result<PathBuf, CompileError> {
    validate_artifact_shard(shard, shard.target)?;
    let path = store.artifact_shard_path_for_target(shard.target, shard.shard_index);
    let bytes = serde_json::to_vec_pretty(shard).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack build artifact shard {}: {err}",
            shard.shard_index
        ))
    })?;
    write_file_atomic(&path, &bytes, "source-pack build artifact shard")?;
    Ok(path)
}

/// Stores batch-to-shard locator pages for job-batch shards.
pub(in crate::compiler) fn store_batch_shard_locators(
    store: &FilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
) -> Result<usize, CompileError> {
    validate_artifact_shard(shard, shard.target)?;
    if shard.kind != SourcePackBuildArtifactShardKind::JobBatches {
        return Ok(0);
    }
    let mut batch_shard_locator_count = 0usize;
    for &batch_index in &shard.batch_indices {
        let locator = SourcePackBuildBatchShardLocator {
            version: SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION,
            target: shard.target,
            batch_index,
            shard_index: shard.shard_index,
        };
        let locator_path = store.batch_shard_locator_path_for_target(shard.target, batch_index);
        let bytes = serde_json::to_vec_pretty(&locator).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack batch shard locator {batch_index}: {err}"
            ))
        })?;
        write_file_atomic(&locator_path, &bytes, "source-pack batch shard locator")?;
        batch_shard_locator_count += 1;
    }
    Ok(batch_shard_locator_count)
}

/// Stores the compact shard indexes that mark shard preparation complete.
pub(in crate::compiler) fn store_artifact_shard_compact_indexes(
    store: &FilesystemArtifactStore,
    index: &SourcePackBuildArtifactShardIndex,
    link_input_index: &SourcePackBuildLinkInputShardIndex,
) -> Result<(), CompileError> {
    validate_artifact_shard_index(index)?;
    validate_link_input_shard_index(link_input_index, index.target)?;
    let index_path = store.artifact_shard_index_path_for_target(index.target);
    let link_input_index_path = store.link_input_shard_index_path_for_target(index.target);
    let index_bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack build artifact shard index: {err}"
        ))
    })?;
    let link_input_index_bytes = serde_json::to_vec_pretty(link_input_index).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack link input shard index: {err}"
        ))
    })?;
    write_file_atomic(
        &link_input_index_path,
        &link_input_index_bytes,
        "source-pack link input shard index",
    )?;
    write_file_atomic(
        &index_path,
        &index_bytes,
        "source-pack build artifact shard index",
    )?;
    Ok(())
}

/// Builds the initial progress shard for a generated execution shard.
pub(in crate::compiler) fn initial_progress_shard_from_execution_shard(
    target: SourcePackArtifactTarget,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
) -> Result<SourcePackBuildProgressShard, CompileError> {
    validate_execution_shard(execution_shard, target)?;
    let mut progress = SourcePackBuildProgressShard::new(target, &execution_shard.shard);
    for dependency in &execution_shard.batch_dependencies {
        if !dependency.has_dependencies() {
            progress.record_batch_ready(dependency.batch_index)?;
        }
    }
    Ok(progress)
}

/// Materializes an execution shard from persisted schedule, batch, and artifact pages.
pub(in crate::compiler) fn build_artifact_execution_shard_from_stored_pages(
    store: &FilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
    validate_artifact_shard(shard, shard.target)?;
    validate_library_schedule_index(schedule_index, shard.target)?;
    validate_artifact_ref_index(artifact_ref_index, shard.target)?;
    validate_job_batch_page_index(job_batch_page_index, shard.target)?;
    validate_link_batch_page_index(link_batch_page_index, shard.target)?;
    validate_library_partition_index(library_partition_index, shard.target)?;

    let mut jobs = Vec::new();
    let mut job_artifacts = Vec::new();
    for &job_index in &shard.job_indices {
        let job = stored_schedule_job_metadata(store, schedule_index, job_index)?;
        let job_manifest = job_artifact_manifest_from_stored_artifact_refs(
            store,
            shard.target,
            schedule_index,
            artifact_ref_index,
            &job,
        )?;
        jobs.push(job);
        job_artifacts.push(job_manifest);
    }

    let mut job_batches = Vec::new();
    let mut batch_dependencies = Vec::new();
    let mut batch_dependents = Vec::new();
    let mut link_interface_batches = Vec::new();
    let mut link_object_batches = Vec::new();
    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            for &batch_index in &shard.batch_indices {
                let page = store.load_build_job_batch_page_for_target(shard.target, batch_index)?;
                job_batches.push(page.batch);
                batch_dependencies.push(page.dependency);
                let dependents_page = store.load_build_job_batch_dependents_page_for_target(
                    shard.target,
                    batch_index,
                    job_batch_page_index.batch_count,
                )?;
                batch_dependents.push(SourcePackJobBatchDependents {
                    batch_index: dependents_page.batch_index,
                    dependent_batch_indices: Vec::new(),
                });
            }
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            for &batch_index in &shard.batch_indices {
                if batch_index >= link_batch_page_index.link_interface_batch_count {
                    return Err(artifact_shard_contract_error(format!(
                        "link-interface shard {} references batch {} beyond page index count {}",
                        shard.shard_index,
                        batch_index,
                        link_batch_page_index.link_interface_batch_count
                    )));
                }
                let page = store
                    .load_build_link_interface_batch_page_for_target(shard.target, batch_index)?;
                link_interface_batches.push(page.batch);
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            for &batch_index in &shard.batch_indices {
                if batch_index >= link_batch_page_index.link_object_batch_count {
                    return Err(artifact_shard_contract_error(format!(
                        "link-object shard {} references batch {} beyond page index count {}",
                        shard.shard_index,
                        batch_index,
                        link_batch_page_index.link_object_batch_count
                    )));
                }
                let page = store
                    .load_build_link_object_batch_page_for_target(shard.target, batch_index)?;
                link_object_batches.push(page.batch);
            }
        }
    }

    let artifact_indices = shard
        .input_artifact_indices
        .iter()
        .chain(shard.output_artifact_indices.iter())
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let artifact_refs = artifact_refs_for_indices_from_stored_pages(
        store,
        shard.target,
        artifact_ref_index,
        &artifact_indices,
    )?;

    let execution_shard = SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target: shard.target,
        shard: shard.clone(),
        source_files: Vec::new(),
        job_batches,
        batch_dependencies,
        batch_dependents,
        jobs,
        job_artifacts,
        artifact_refs,
        link_interface_batches,
        link_object_batches,
    };
    validate_execution_shard(&execution_shard, shard.target)?;
    Ok(execution_shard)
}
