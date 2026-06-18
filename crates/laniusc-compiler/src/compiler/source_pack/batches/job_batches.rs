use super::*;

/// Advances persisted job-batch preparation by a bounded number of batches.
pub(in crate::compiler) fn store_build_job_batch_pages_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<FilesystemJobBatchPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack job-batch chunk max_new_batches must be greater than zero".into(),
        ));
    }
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    let batch_limits = batch_limits.normalized();
    if store
        .build_job_batch_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_build_job_batch_page_index_for_target(schedule_index.target)?;
        return Ok(FilesystemJobBatchPrepareStepResult {
            target: schedule_index.target,
            complete: true,
            scheduled_job_count: index.scheduled_job_count,
            batch_count: index.batch_count,
            new_batch_count: 0,
            dependency_edge_count: index.dependency_edge_count,
            next_job_index: index.scheduled_job_count,
            job_batch_index_path: Some(
                store.build_job_batch_index_path_for_target(schedule_index.target),
            ),
        });
    }

    let progress_path =
        store.build_job_batch_prepare_progress_path_for_target(schedule_index.target);
    let mut progress = if progress_path.is_file() {
        store.load_build_job_batch_prepare_progress_for_target(
            schedule_index.target,
            schedule_index.job_count,
            batch_limits,
        )?
    } else {
        JobBatchPrepareProgress {
            version: SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            batch_limits,
            scheduled_job_count: schedule_index.job_count,
            next_job_index: 0,
            next_batch_index: 0,
            dependency_edge_count: 0,
        }
    };
    validate_build_job_batch_prepare_progress(
        &progress,
        schedule_index.target,
        schedule_index.job_count,
        batch_limits,
    )?;

    let mut builder = StoredJobBatchBuilder::new(batch_limits);
    builder.next_batch_index = progress.next_batch_index;
    let mut new_batch_count = 0usize;
    let mut store_batch = |batch_jobs: Vec<SourcePackJob>,
                           batch_index: usize,
                           wave_index: usize,
                           source_bytes: usize,
                           source_file_count: usize,
                           source_lines: usize,
                           oversized: bool|
     -> Result<SourcePackJobBatchDependency, CompileError> {
        store_job_batch_page_from_jobs(
            store,
            schedule_index,
            batch_jobs,
            batch_index,
            wave_index,
            source_bytes,
            source_file_count,
            source_lines,
            oversized,
        )
    };

    while progress.next_job_index < schedule_index.job_count {
        let job = stored_schedule_job_metadata(store, schedule_index, progress.next_job_index)?;
        if builder.should_flush_before(&job) {
            let dependency = builder.flush(&mut store_batch)?.ok_or_else(|| {
                artifact_shard_contract_error("job-batch chunk had no pending jobs to flush")
            })?;
            progress.next_batch_index = builder.next_batch_index;
            progress.dependency_edge_count = progress
                .dependency_edge_count
                .saturating_add(dependency.dependency_count());
            store.store_build_job_batch_prepare_progress(&progress)?;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(FilesystemJobBatchPrepareStepResult {
                    target: schedule_index.target,
                    complete: false,
                    scheduled_job_count: schedule_index.job_count,
                    batch_count: progress.next_batch_index,
                    new_batch_count,
                    dependency_edge_count: progress.dependency_edge_count,
                    next_job_index: progress.next_job_index,
                    job_batch_index_path: None,
                });
            }
        }
        builder.current_source_bytes = builder
            .current_source_bytes
            .saturating_add(job.source_bytes);
        builder.current_source_file_count = builder
            .current_source_file_count
            .saturating_add(job.source_file_count);
        builder.current_source_lines = builder
            .current_source_lines
            .saturating_add(job.source_lines);
        builder.current_jobs.push(job);
        progress.next_job_index += 1;
    }

    if !builder.current_jobs.is_empty() {
        let dependency = builder.flush(&mut store_batch)?.ok_or_else(|| {
            artifact_shard_contract_error("job-batch chunk had no final pending jobs to flush")
        })?;
        progress.next_batch_index = builder.next_batch_index;
        progress.dependency_edge_count = progress
            .dependency_edge_count
            .saturating_add(dependency.dependency_count());
        store.store_build_job_batch_prepare_progress(&progress)?;
        new_batch_count += 1;
        if new_batch_count >= max_new_batches && progress.next_job_index < schedule_index.job_count
        {
            return Ok(FilesystemJobBatchPrepareStepResult {
                target: schedule_index.target,
                complete: false,
                scheduled_job_count: schedule_index.job_count,
                batch_count: progress.next_batch_index,
                new_batch_count,
                dependency_edge_count: progress.dependency_edge_count,
                next_job_index: progress.next_job_index,
                job_batch_index_path: None,
            });
        }
    }

    if progress.next_job_index != schedule_index.job_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch chunk stopped at job {} but schedule has {} jobs",
            progress.next_job_index, schedule_index.job_count
        )));
    }
    if progress.next_batch_index == 0 {
        return Err(artifact_shard_contract_error(
            "stored job-batch chunk planner produced no batches",
        ));
    }
    let index = SourcePackBuildJobBatchPageIndex {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
        target: schedule_index.target,
        batch_count: progress.next_batch_index,
        scheduled_job_count: schedule_index.job_count,
        dependency_edge_count: progress.dependency_edge_count,
    };
    validate_job_batch_page_index(&index, schedule_index.target)?;
    let job_batch_index_path = store.store_build_job_batch_page_index(&index)?;
    Ok(FilesystemJobBatchPrepareStepResult {
        target: schedule_index.target,
        complete: true,
        scheduled_job_count: index.scheduled_job_count,
        batch_count: index.batch_count,
        new_batch_count,
        dependency_edge_count: index.dependency_edge_count,
        next_job_index: progress.next_job_index,
        job_batch_index_path: Some(job_batch_index_path),
    })
}

/// Persisted cursor for resumable job-batch preparation.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct JobBatchPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) scheduled_job_count: usize,
    pub(in crate::compiler) next_job_index: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) dependency_edge_count: usize,
}

/// Validates persisted job-batch preparation progress.
pub(in crate::compiler) fn validate_build_job_batch_prepare_progress(
    progress: &JobBatchPrepareProgress,
    target: SourcePackArtifactTarget,
    scheduled_job_count: usize,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_limits != batch_limits.normalized() {
        return Err(artifact_shard_contract_error(
            "job-batch prepare progress was created with different batch limits",
        ));
    }
    if progress.scheduled_job_count != scheduled_job_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch prepare progress scheduled_job_count {} does not match schedule job_count {scheduled_job_count}",
            progress.scheduled_job_count
        )));
    }
    if progress.next_job_index > scheduled_job_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch prepare progress next_job_index {} exceeds scheduled_job_count {scheduled_job_count}",
            progress.next_job_index
        )));
    }
    Ok(())
}

/// Accumulates scheduled jobs into one bounded persisted job batch.
pub(in crate::compiler) struct StoredJobBatchBuilder {
    pub(in crate::compiler) limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) current_jobs: Vec<SourcePackJob>,
    pub(in crate::compiler) current_source_bytes: usize,
    pub(in crate::compiler) current_source_file_count: usize,
    pub(in crate::compiler) current_source_lines: usize,
}

impl StoredJobBatchBuilder {
    /// Creates an empty job-batch builder.
    pub(in crate::compiler) fn new(limits: SourcePackJobBatchLimits) -> Self {
        Self {
            limits: limits.normalized(),
            next_batch_index: 0,
            current_jobs: Vec::new(),
            current_source_bytes: 0,
            current_source_file_count: 0,
            current_source_lines: 0,
        }
    }

    /// Returns whether the current batch should be flushed before adding `job`.
    pub(in crate::compiler) fn should_flush_before(&self, job: &SourcePackJob) -> bool {
        !self.current_jobs.is_empty()
            && (self.current_jobs.len() >= self.limits.max_jobs_per_batch
                || self.current_source_bytes.saturating_add(job.source_bytes)
                    > self.limits.max_source_bytes_per_batch
                || self
                    .current_source_file_count
                    .saturating_add(job.source_file_count)
                    > self.limits.max_source_files_per_batch)
    }

    /// Emits the current batch and resets the builder.
    pub(in crate::compiler) fn flush<F>(
        &mut self,
        emit: &mut F,
    ) -> Result<Option<SourcePackJobBatchDependency>, CompileError>
    where
        F: FnMut(
            Vec<SourcePackJob>,
            usize,
            usize,
            usize,
            usize,
            usize,
            bool,
        ) -> Result<SourcePackJobBatchDependency, CompileError>,
    {
        if self.current_jobs.is_empty() {
            return Ok(None);
        }
        let batch_index = self.next_batch_index;
        self.next_batch_index += 1;
        let source_bytes = std::mem::take(&mut self.current_source_bytes);
        let source_file_count = std::mem::take(&mut self.current_source_file_count);
        let source_lines = std::mem::take(&mut self.current_source_lines);
        let oversized = self.current_jobs.len() > self.limits.max_jobs_per_batch
            || source_bytes > self.limits.max_source_bytes_per_batch
            || source_file_count > self.limits.max_source_files_per_batch;
        let jobs = std::mem::take(&mut self.current_jobs);
        emit(
            jobs,
            batch_index,
            batch_index,
            source_bytes,
            source_file_count,
            source_lines,
            oversized,
        )
        .map(Some)
    }
}

/// Stores one job-batch page and returns its dependency summary.
pub(in crate::compiler) fn store_job_batch_page_from_jobs(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_jobs: Vec<SourcePackJob>,
    batch_index: usize,
    wave_index: usize,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
    oversized: bool,
) -> Result<SourcePackJobBatchDependency, CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    if batch_jobs.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {batch_index} has no jobs"
        )));
    }
    let job_indices = batch_jobs
        .iter()
        .map(|job| job.job_index)
        .collect::<Vec<_>>();
    unique_usize_set(&job_indices, &format!("job-batch page {batch_index} jobs"))?;
    for &job_index in &job_indices {
        if job_index >= schedule_index.job_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch page {batch_index} references job {job_index} beyond scheduled job count {}",
                schedule_index.job_count
            )));
        }
        let locator = SourcePackBuildJobBatchJobLocatorPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION,
            target: schedule_index.target,
            job_index,
            batch_index,
        };
        store.store_build_job_batch_job_locator_page(&locator, schedule_index.job_count)?;
    }

    let dependency = stored_job_batch_dependency(store, schedule_index, batch_index, &batch_jobs)?;
    let batch = SourcePackJobBatch {
        batch_index,
        wave_index,
        job_indices,
        source_bytes,
        source_file_count,
        source_lines,
        oversized,
    };
    let page = SourcePackBuildJobBatchPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
        target: schedule_index.target,
        batch_index,
        batch,
        dependency: dependency.clone(),
    };
    store.store_build_job_batch_page(&page)?;
    Ok(dependency)
}

/// Computes the dependency batch summary for a persisted job batch.
pub(in crate::compiler) fn stored_job_batch_dependency(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_index: usize,
    batch_jobs: &[SourcePackJob],
) -> Result<SourcePackJobBatchDependency, CompileError> {
    let mut dependency_batch_ranges = Vec::new();
    for job in batch_jobs {
        if matches!(job.phase, SourcePackJobPhase::Link) {
            insert_dependency_batch_range_for_jobs(
                store,
                schedule_index,
                batch_index,
                library_schedule_index_frontend_job_count(schedule_index),
                schedule_index.link_job_index,
                &mut dependency_batch_ranges,
            )?;
            continue;
        }
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job.job_index,
            schedule_index.job_count,
        )?;
        validate_schedule_job_page(
            &job_page,
            schedule_index.target,
            schedule_index.job_count,
            Some(job.job_index),
        )?;
        for range in &job_page.dependency_job_ranges {
            let Some(end_job_index) = range.end_job_index() else {
                return Err(artifact_shard_contract_error(format!(
                    "job-batch page {batch_index} dependency job range starting at {} overflows",
                    range.first_job_index
                )));
            };
            insert_dependency_batch_range_for_jobs(
                store,
                schedule_index,
                batch_index,
                range.first_job_index,
                end_job_index,
                &mut dependency_batch_ranges,
            )?;
        }
    }
    let mut dependency = SourcePackJobBatchDependency {
        batch_index,
        dependency_batch_count: 0,
        dependency_page_count: 0,
        dependency_range_count: 0,
        dependency_range_page_count: 0,
        dependency_range_batch_count: 0,
        dependency_batch_indices: Vec::new(),
        dependency_batch_ranges,
    };
    validate_job_batch_dependency_ranges(
        &dependency,
        &BTreeSet::new(),
        &format!("job-batch page {batch_index}"),
        batch_index,
        None,
        |message| artifact_shard_contract_error(message),
    )?;
    let mut writer = JobBatchDependencyPageWriter::new(store, schedule_index.target, batch_index);
    for job in batch_jobs {
        if matches!(job.phase, SourcePackJobPhase::Link) {
            continue;
        }
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job.job_index,
            schedule_index.job_count,
        )?;
        for_each_schedule_job_explicit_dependency_index(
            store,
            schedule_index,
            &job_page,
            |dependency_job_index| {
                write_dependency_batch_for_job(
                    store,
                    schedule_index,
                    batch_index,
                    dependency_job_index,
                    &dependency.dependency_batch_ranges,
                    &mut writer,
                )
            },
        )?;
    }
    let (dependency_batch_count, dependency_page_count) = writer.finish()?;
    dependency.dependency_batch_count = dependency_batch_count;
    dependency.dependency_page_count = dependency_page_count;
    dependency.dependency_range_count = dependency.dependency_batch_ranges.len();
    dependency.dependency_range_batch_count =
        dependency
            .dependency_batch_ranges
            .iter()
            .try_fold(0usize, |count, range| {
                count.checked_add(range.batch_count).ok_or_else(|| {
                    artifact_shard_contract_error(format!(
                        "job-batch page {batch_index} dependency range batch count overflows"
                    ))
                })
            })?;
    validate_job_batch_dependency_range_metadata(
        &dependency,
        &format!("job-batch page {batch_index}"),
        |message| artifact_shard_contract_error(message),
    )?;
    Ok(dependency)
}

/// Inserts dependency batch ranges covering a dependency job range.
pub(in crate::compiler) fn insert_dependency_batch_range_for_jobs(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_index: usize,
    first_dependency_job_index: usize,
    end_dependency_job_index: usize,
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
) -> Result<(), CompileError> {
    if first_dependency_job_index >= end_dependency_job_index {
        return Ok(());
    }
    let first_locator = store.load_build_job_batch_job_locator_page_for_target(
        schedule_index.target,
        first_dependency_job_index,
        schedule_index.job_count,
    )?;
    let last_dependency_job_index = end_dependency_job_index - 1;
    let last_locator = store.load_build_job_batch_job_locator_page_for_target(
        schedule_index.target,
        last_dependency_job_index,
        schedule_index.job_count,
    )?;
    if first_locator.batch_index > batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {batch_index} depends on future batch {} through job {first_dependency_job_index}",
            first_locator.batch_index
        )));
    }
    if last_locator.batch_index > batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {batch_index} depends on future batch {} through job {last_dependency_job_index}",
            last_locator.batch_index
        )));
    }
    let range_end = last_locator.batch_index.saturating_add(1).min(batch_index);
    if first_locator.batch_index >= range_end {
        return Ok(());
    }
    push_dependency_batch_range(
        dependency_batch_ranges,
        first_locator.batch_index,
        range_end - first_locator.batch_index,
    )?;
    Ok(())
}

/// Inserts and compacts one dependency batch range.
pub(in crate::compiler) fn push_dependency_batch_range(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    first_batch_index: usize,
    batch_count: usize,
) -> Result<(), CompileError> {
    if batch_count == 0 {
        return Ok(());
    }
    first_batch_index.checked_add(batch_count).ok_or_else(|| {
        artifact_shard_contract_error(format!(
            "dependency batch range {first_batch_index}+{batch_count} overflows"
        ))
    })?;
    dependency_batch_ranges.push(SourcePackJobBatchDependencyRange {
        first_batch_index,
        batch_count,
    });
    dependency_batch_ranges.sort_by_key(|range| range.first_batch_index);
    let mut merged =
        Vec::<SourcePackJobBatchDependencyRange>::with_capacity(dependency_batch_ranges.len());
    for range in dependency_batch_ranges.drain(..) {
        let Some(range_end) = range.end_batch_index() else {
            return Err(artifact_shard_contract_error(format!(
                "dependency batch range starting at {} overflows",
                range.first_batch_index
            )));
        };
        if let Some(last) = merged.last_mut() {
            let Some(last_end) = last.end_batch_index() else {
                return Err(artifact_shard_contract_error(format!(
                    "dependency batch range starting at {} overflows",
                    last.first_batch_index
                )));
            };
            if range.first_batch_index <= last_end {
                let merged_end = last_end.max(range_end);
                last.batch_count = merged_end - last.first_batch_index;
                continue;
            }
        }
        merged.push(range);
    }
    *dependency_batch_ranges = merged;
    Ok(())
}

/// Writes one explicit dependency batch for a dependency job.
pub(in crate::compiler) fn write_dependency_batch_for_job(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_index: usize,
    dependency_job_index: usize,
    dependency_batch_ranges: &[SourcePackJobBatchDependencyRange],
    writer: &mut JobBatchDependencyPageWriter<'_>,
) -> Result<(), CompileError> {
    let locator = store.load_build_job_batch_job_locator_page_for_target(
        schedule_index.target,
        dependency_job_index,
        schedule_index.job_count,
    )?;
    if locator.batch_index > batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {batch_index} depends on future batch {} through job {dependency_job_index}",
            locator.batch_index
        )));
    }
    if locator.batch_index == batch_index
        || dependency_batch_ranges
            .iter()
            .any(|range| range.contains(locator.batch_index))
    {
        return Ok(());
    }
    writer.push(locator.batch_index)
}
