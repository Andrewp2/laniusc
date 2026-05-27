use super::*;

#[cfg(test)]
pub(in crate::compiler) fn store_source_pack_build_job_batch_pages_from_stored_schedule_pages(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackStoredJobBatchPagesPrepareResult, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let mut builder = SourcePackStoredJobBatchBuilder::new(batch_limits);
    let mut store_batch = |batch_jobs: Vec<SourcePackJob>,
                           batch_index: usize,
                           wave_index: usize,
                           source_bytes: usize,
                           source_file_count: usize,
                           source_lines: usize,
                           oversized: bool|
     -> Result<SourcePackJobBatchDependency, CompileError> {
        store_source_pack_stored_job_batch_page(
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

    let mut batch_count = 0usize;
    let mut dependency_edge_count = 0usize;
    for job_index in 0..schedule_index.job_count {
        let job = source_pack_stored_schedule_job_metadata(store, schedule_index, job_index)?;
        if let Some(dependency) = builder.push(job, &mut store_batch)? {
            dependency_edge_count =
                dependency_edge_count.saturating_add(dependency.dependency_count());
            batch_count += 1;
        }
    }
    if let Some(dependency) = builder.finish(&mut store_batch)? {
        dependency_edge_count = dependency_edge_count.saturating_add(dependency.dependency_count());
        batch_count += 1;
    }
    if batch_count == 0 {
        return Err(source_pack_artifact_shard_contract_error(
            "stored job-batch planner produced no batches",
        ));
    }

    let index = SourcePackBuildJobBatchPageIndex {
        version: SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
        target: schedule_index.target,
        batch_count,
        scheduled_job_count: schedule_index.job_count,
        dependency_edge_count,
    };
    validate_source_pack_build_job_batch_page_index(&index, schedule_index.target)?;
    store.store_build_job_batch_page_index(&index)?;
    Ok(SourcePackStoredJobBatchPagesPrepareResult { index })
}

pub(in crate::compiler) fn store_source_pack_build_job_batch_pages_from_stored_schedule_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemJobBatchPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack job-batch chunk max_new_batches must be greater than zero".into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let batch_limits = batch_limits.normalized();
    if store
        .build_job_batch_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_build_job_batch_page_index_for_target(schedule_index.target)?;
        return Ok(SourcePackFilesystemJobBatchPrepareStepResult {
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
        SourcePackBuildJobBatchPrepareProgress {
            version: SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            batch_limits,
            scheduled_job_count: schedule_index.job_count,
            next_job_index: 0,
            next_batch_index: 0,
            dependency_edge_count: 0,
        }
    };
    validate_source_pack_build_job_batch_prepare_progress(
        &progress,
        schedule_index.target,
        schedule_index.job_count,
        batch_limits,
    )?;

    let mut builder = SourcePackStoredJobBatchBuilder::new(batch_limits);
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
        store_source_pack_stored_job_batch_page(
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
        let job = source_pack_stored_schedule_job_metadata(
            store,
            schedule_index,
            progress.next_job_index,
        )?;
        if builder.should_flush_before(&job) {
            let dependency = builder.flush(&mut store_batch)?.ok_or_else(|| {
                source_pack_artifact_shard_contract_error(
                    "job-batch chunk had no pending jobs to flush",
                )
            })?;
            progress.next_batch_index = builder.next_batch_index;
            progress.dependency_edge_count = progress
                .dependency_edge_count
                .saturating_add(dependency.dependency_count());
            store.store_build_job_batch_prepare_progress(&progress)?;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(SourcePackFilesystemJobBatchPrepareStepResult {
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
            source_pack_artifact_shard_contract_error(
                "job-batch chunk had no final pending jobs to flush",
            )
        })?;
        progress.next_batch_index = builder.next_batch_index;
        progress.dependency_edge_count = progress
            .dependency_edge_count
            .saturating_add(dependency.dependency_count());
        store.store_build_job_batch_prepare_progress(&progress)?;
        new_batch_count += 1;
        if new_batch_count >= max_new_batches && progress.next_job_index < schedule_index.job_count
        {
            return Ok(SourcePackFilesystemJobBatchPrepareStepResult {
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch chunk stopped at job {} but schedule has {} jobs",
            progress.next_job_index, schedule_index.job_count
        )));
    }
    if progress.next_batch_index == 0 {
        return Err(source_pack_artifact_shard_contract_error(
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
    validate_source_pack_build_job_batch_page_index(&index, schedule_index.target)?;
    let job_batch_index_path = store.store_build_job_batch_page_index(&index)?;
    Ok(SourcePackFilesystemJobBatchPrepareStepResult {
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

#[cfg(test)]
pub(in crate::compiler) struct SourcePackStoredJobBatchPagesPrepareResult {
    pub(in crate::compiler) index: SourcePackBuildJobBatchPageIndex,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackBuildJobBatchPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) scheduled_job_count: usize,
    pub(in crate::compiler) next_job_index: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) dependency_edge_count: usize,
}

pub(in crate::compiler) fn validate_source_pack_build_job_batch_prepare_progress(
    progress: &SourcePackBuildJobBatchPrepareProgress,
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_limits != batch_limits.normalized() {
        return Err(source_pack_artifact_shard_contract_error(
            "job-batch prepare progress was created with different batch limits",
        ));
    }
    if progress.scheduled_job_count != scheduled_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch prepare progress scheduled_job_count {} does not match schedule job_count {scheduled_job_count}",
            progress.scheduled_job_count
        )));
    }
    if progress.next_job_index > scheduled_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch prepare progress next_job_index {} exceeds scheduled_job_count {scheduled_job_count}",
            progress.next_job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) struct SourcePackStoredJobBatchBuilder {
    pub(in crate::compiler) limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) current_jobs: Vec<SourcePackJob>,
    pub(in crate::compiler) current_source_bytes: usize,
    pub(in crate::compiler) current_source_file_count: usize,
    pub(in crate::compiler) current_source_lines: usize,
}

impl SourcePackStoredJobBatchBuilder {
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

    #[cfg(test)]
    pub(in crate::compiler) fn push<F>(
        &mut self,
        job: SourcePackJob,
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
        let flushed = if self.should_flush_before(&job) {
            self.flush(emit)?
        } else {
            None
        };
        self.current_source_bytes = self.current_source_bytes.saturating_add(job.source_bytes);
        self.current_source_file_count = self
            .current_source_file_count
            .saturating_add(job.source_file_count);
        self.current_source_lines = self.current_source_lines.saturating_add(job.source_lines);
        self.current_jobs.push(job);
        Ok(flushed)
    }

    #[cfg(test)]
    pub(in crate::compiler) fn finish<F>(
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
        self.flush(emit)
    }

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

pub(in crate::compiler) fn store_source_pack_stored_job_batch_page(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_jobs: Vec<SourcePackJob>,
    batch_index: usize,
    wave_index: usize,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
    oversized: bool,
) -> Result<SourcePackJobBatchDependency, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    if batch_jobs.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {batch_index} has no jobs"
        )));
    }
    let job_indices = batch_jobs
        .iter()
        .map(|job| job.job_index)
        .collect::<Vec<_>>();
    source_pack_manifest_unique_usize_set(
        &job_indices,
        &format!("job-batch page {batch_index} jobs"),
    )?;
    for &job_index in &job_indices {
        if job_index >= schedule_index.job_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
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

    let dependency =
        source_pack_stored_job_batch_dependency(store, schedule_index, batch_index, &batch_jobs)?;
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

pub(in crate::compiler) fn source_pack_stored_job_batch_dependency(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_index: usize,
    batch_jobs: &[SourcePackJob],
) -> Result<SourcePackJobBatchDependency, CompileError> {
    let mut dependency_batch_ranges = Vec::new();
    for job in batch_jobs {
        if matches!(job.phase, SourcePackJobPhase::Link) {
            source_pack_insert_dependency_batch_range_for_jobs(
                store,
                schedule_index,
                batch_index,
                source_pack_library_schedule_index_frontend_job_count(schedule_index),
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
        validate_source_pack_library_schedule_job_page(
            &job_page,
            schedule_index.target,
            schedule_index.job_count,
            Some(job.job_index),
        )?;
        for range in &job_page.dependency_job_ranges {
            let Some(end_job_index) = range.end_job_index() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job-batch page {batch_index} dependency job range starting at {} overflows",
                    range.first_job_index
                )));
            };
            source_pack_insert_dependency_batch_range_for_jobs(
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
    source_pack_validate_job_batch_dependency_ranges(
        &dependency,
        &BTreeSet::new(),
        &format!("job-batch page {batch_index}"),
        batch_index,
        None,
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    let mut writer =
        SourcePackBuildJobBatchDependencyPageWriter::new(store, schedule_index.target, batch_index);
    for job in batch_jobs {
        if matches!(job.phase, SourcePackJobPhase::Link) {
            continue;
        }
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job.job_index,
            schedule_index.job_count,
        )?;
        source_pack_for_each_schedule_job_explicit_dependency_index(
            store,
            schedule_index,
            &job_page,
            |dependency_job_index| {
                source_pack_write_dependency_batch_for_job(
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
                    source_pack_artifact_shard_contract_error(format!(
                        "job-batch page {batch_index} dependency range batch count overflows"
                    ))
                })
            })?;
    source_pack_validate_job_batch_dependency_range_metadata(
        &dependency,
        &format!("job-batch page {batch_index}"),
        |message| source_pack_artifact_shard_contract_error(message),
    )?;
    Ok(dependency)
}

pub(in crate::compiler) fn source_pack_insert_dependency_batch_range_for_jobs(
    store: &SourcePackFilesystemArtifactStore,
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {batch_index} depends on future batch {} through job {first_dependency_job_index}",
            first_locator.batch_index
        )));
    }
    if last_locator.batch_index > batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch page {batch_index} depends on future batch {} through job {last_dependency_job_index}",
            last_locator.batch_index
        )));
    }
    let range_end = last_locator.batch_index.saturating_add(1).min(batch_index);
    if first_locator.batch_index >= range_end {
        return Ok(());
    }
    source_pack_push_dependency_batch_range(
        dependency_batch_ranges,
        first_locator.batch_index,
        range_end - first_locator.batch_index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_push_dependency_batch_range(
    dependency_batch_ranges: &mut Vec<SourcePackJobBatchDependencyRange>,
    first_batch_index: usize,
    batch_count: usize,
) -> Result<(), CompileError> {
    if batch_count == 0 {
        return Ok(());
    }
    first_batch_index.checked_add(batch_count).ok_or_else(|| {
        source_pack_artifact_shard_contract_error(format!(
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
            return Err(source_pack_artifact_shard_contract_error(format!(
                "dependency batch range starting at {} overflows",
                range.first_batch_index
            )));
        };
        if let Some(last) = merged.last_mut() {
            let Some(last_end) = last.end_batch_index() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
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

pub(in crate::compiler) fn source_pack_write_dependency_batch_for_job(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch_index: usize,
    dependency_job_index: usize,
    dependency_batch_ranges: &[SourcePackJobBatchDependencyRange],
    writer: &mut SourcePackBuildJobBatchDependencyPageWriter<'_>,
) -> Result<(), CompileError> {
    let locator = store.load_build_job_batch_job_locator_page_for_target(
        schedule_index.target,
        dependency_job_index,
        schedule_index.job_count,
    )?;
    if locator.batch_index > batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
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

#[cfg(test)]
pub(in crate::compiler) fn store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildLinkBatchPageIndex, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, target)?;
    if artifact_ref_index.artifact_count != schedule_index.job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index has artifact_count {} but schedule has job_count {}",
            artifact_ref_index.artifact_count, schedule_index.job_count
        )));
    }
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if artifact_ref_index.interface_artifact_count != frontend_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index has {} interface artifacts but schedule has {} frontend jobs",
            artifact_ref_index.interface_artifact_count, frontend_job_count
        )));
    }
    if artifact_ref_index.object_artifact_count != schedule_index.codegen_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref index has {} object artifacts but schedule has {} codegen jobs",
            artifact_ref_index.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    let link_interface_batch_count =
        store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages(
            store,
            target,
            artifact_ref_index,
            0..frontend_job_count,
            batch_limits,
        )?;
    let link_object_batch_count =
        store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages(
            store,
            target,
            artifact_ref_index,
            frontend_job_count..schedule_index.link_job_index,
            batch_limits,
        )?;
    let index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
        target,
        link_interface_batch_count,
        link_object_batch_count,
    };
    validate_source_pack_build_link_batch_page_index(&index, target)?;
    store.store_build_link_batch_page_index(&index)?;
    Ok(index)
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackBuildLinkBatchPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) artifact_count: usize,
    pub(in crate::compiler) interface_artifact_count: usize,
    pub(in crate::compiler) object_artifact_count: usize,
    pub(in crate::compiler) next_interface_artifact_index: usize,
    pub(in crate::compiler) next_interface_batch_index: usize,
    pub(in crate::compiler) next_object_artifact_index: usize,
    pub(in crate::compiler) next_object_batch_index: usize,
}

pub(in crate::compiler) fn validate_source_pack_build_link_batch_prepare_progress(
    progress: &SourcePackBuildLinkBatchPrepareProgress,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack link-batch prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-batch prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_limits != batch_limits.normalized() {
        return Err(source_pack_artifact_shard_contract_error(
            "link-batch prepare progress was created with different batch limits",
        ));
    }
    if progress.artifact_count != artifact_ref_index.artifact_count
        || progress.interface_artifact_count != artifact_ref_index.interface_artifact_count
        || progress.object_artifact_count != artifact_ref_index.object_artifact_count
    {
        return Err(source_pack_artifact_shard_contract_error(
            "link-batch prepare progress artifact counts do not match artifact-ref index",
        ));
    }
    if progress.next_interface_artifact_index > artifact_ref_index.interface_artifact_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-batch prepare progress next interface artifact {} exceeds count {}",
            progress.next_interface_artifact_index, artifact_ref_index.interface_artifact_count
        )));
    }
    let object_start = artifact_ref_index.interface_artifact_count;
    let object_end = object_start
        .checked_add(artifact_ref_index.object_artifact_count)
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error("object artifact range overflows")
        })?;
    if progress.next_object_artifact_index < object_start
        || progress.next_object_artifact_index > object_end
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link-batch prepare progress next object artifact {} is outside {}..={}",
            progress.next_object_artifact_index, object_start, object_end
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_build_link_batch_pages_from_stored_artifact_ref_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemLinkBatchPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack link-batch chunk max_new_batches must be greater than zero".into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, target)?;
    if store
        .build_link_batch_index_path_for_target(target)
        .is_file()
    {
        let index = store.load_build_link_batch_page_index_for_target(target)?;
        return Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
            target,
            complete: true,
            link_interface_batch_count: index.link_interface_batch_count,
            link_object_batch_count: index.link_object_batch_count,
            new_batch_count: 0,
            next_interface_artifact_index: artifact_ref_index.interface_artifact_count,
            next_object_artifact_index: artifact_ref_index
                .interface_artifact_count
                .saturating_add(artifact_ref_index.object_artifact_count),
            link_batch_index_path: Some(store.build_link_batch_index_path_for_target(target)),
        });
    }
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if artifact_ref_index.artifact_count != schedule_index.job_count
        || artifact_ref_index.interface_artifact_count != frontend_job_count
        || artifact_ref_index.object_artifact_count != schedule_index.codegen_job_count
    {
        return Err(source_pack_artifact_shard_contract_error(
            "artifact-ref index does not match schedule index for link-batch chunks",
        ));
    }

    let progress_path = store.build_link_batch_prepare_progress_path_for_target(target);
    let object_start = frontend_job_count;
    let object_end = schedule_index.link_job_index;
    let mut progress = if progress_path.is_file() {
        store.load_build_link_batch_prepare_progress_for_target(
            target,
            artifact_ref_index,
            batch_limits,
        )?
    } else {
        SourcePackBuildLinkBatchPrepareProgress {
            version: SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION,
            target,
            batch_limits: batch_limits.normalized(),
            artifact_count: artifact_ref_index.artifact_count,
            interface_artifact_count: artifact_ref_index.interface_artifact_count,
            object_artifact_count: artifact_ref_index.object_artifact_count,
            next_interface_artifact_index: 0,
            next_interface_batch_index: 0,
            next_object_artifact_index: object_start,
            next_object_batch_index: 0,
        }
    };
    validate_source_pack_build_link_batch_prepare_progress(
        &progress,
        target,
        artifact_ref_index,
        batch_limits,
    )?;

    let mut new_batch_count = 0usize;
    if progress.next_interface_artifact_index < frontend_job_count {
        let step = store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages_chunk(
            store,
            target,
            artifact_ref_index,
            progress.next_interface_artifact_index,
            frontend_job_count,
            progress.next_interface_batch_index,
            batch_limits,
            max_new_batches,
        )?;
        progress.next_interface_artifact_index = step.next_artifact_index;
        progress.next_interface_batch_index = step.next_batch_index;
        new_batch_count += step.new_batch_count;
        store.store_build_link_batch_prepare_progress(&progress)?;
        if new_batch_count >= max_new_batches
            && progress.next_interface_artifact_index < frontend_job_count
        {
            return Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
    }

    if progress.next_object_artifact_index < object_end {
        let remaining_new_batches = max_new_batches.saturating_sub(new_batch_count);
        if remaining_new_batches == 0 {
            return Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
        let step =
            store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages_chunk(
                store,
                target,
                artifact_ref_index,
                progress.next_object_artifact_index,
                object_end,
                progress.next_object_batch_index,
                batch_limits,
                remaining_new_batches,
            )?;
        progress.next_object_artifact_index = step.next_artifact_index;
        progress.next_object_batch_index = step.next_batch_index;
        new_batch_count += step.new_batch_count;
        store.store_build_link_batch_prepare_progress(&progress)?;
        if new_batch_count >= max_new_batches && progress.next_object_artifact_index < object_end {
            return Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
                target,
                complete: false,
                link_interface_batch_count: progress.next_interface_batch_index,
                link_object_batch_count: progress.next_object_batch_index,
                new_batch_count,
                next_interface_artifact_index: progress.next_interface_artifact_index,
                next_object_artifact_index: progress.next_object_artifact_index,
                link_batch_index_path: None,
            });
        }
    }

    if progress.next_interface_artifact_index != frontend_job_count
        || progress.next_object_artifact_index != object_end
    {
        return Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
            target,
            complete: false,
            link_interface_batch_count: progress.next_interface_batch_index,
            link_object_batch_count: progress.next_object_batch_index,
            new_batch_count,
            next_interface_artifact_index: progress.next_interface_artifact_index,
            next_object_artifact_index: progress.next_object_artifact_index,
            link_batch_index_path: None,
        });
    }
    let index = SourcePackBuildLinkBatchPageIndex {
        version: SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
        target,
        link_interface_batch_count: progress.next_interface_batch_index,
        link_object_batch_count: progress.next_object_batch_index,
    };
    validate_source_pack_build_link_batch_page_index(&index, target)?;
    let link_batch_index_path = store.store_build_link_batch_page_index(&index)?;
    Ok(SourcePackFilesystemLinkBatchPrepareStepResult {
        target,
        complete: true,
        link_interface_batch_count: index.link_interface_batch_count,
        link_object_batch_count: index.link_object_batch_count,
        new_batch_count,
        next_interface_artifact_index: progress.next_interface_artifact_index,
        next_object_artifact_index: progress.next_object_artifact_index,
        link_batch_index_path: Some(link_batch_index_path),
    })
}

#[cfg(test)]
pub(in crate::compiler) fn store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_indices: std::ops::Range<usize>,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<usize, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut batch_count = 0usize;
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;

    let flush = |batch_count: &mut usize,
                 current_artifacts: &mut Vec<usize>,
                 current_source_bytes: &mut usize,
                 current_source_file_count: &mut usize,
                 current_source_lines: &mut usize|
     -> Result<(), CompileError> {
        if current_artifacts.is_empty() {
            return Ok(());
        }
        let batch = SourcePackLinkInterfaceBatch {
            batch_index: *batch_count,
            input_interface_artifact_indices: std::mem::take(current_artifacts),
            source_bytes: std::mem::take(current_source_bytes),
            source_file_count: std::mem::take(current_source_file_count),
            source_lines: std::mem::take(current_source_lines),
        };
        let page = SourcePackBuildLinkInterfaceBatchPage {
            version: SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION,
            target,
            batch_index: batch.batch_index,
            batch,
        };
        store.store_build_link_interface_batch_page(&page)?;
        *batch_count += 1;
        Ok(())
    };

    for artifact_index in artifact_indices {
        let page = source_pack_load_artifact_ref_page_for_index(
            store,
            target,
            artifact_ref_index,
            artifact_index,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link-interface batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            flush(
                &mut batch_count,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
    }
    flush(
        &mut batch_count,
        &mut current_artifacts,
        &mut current_source_bytes,
        &mut current_source_file_count,
        &mut current_source_lines,
    )?;
    Ok(batch_count)
}

#[cfg(test)]
pub(in crate::compiler) fn store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_indices: std::ops::Range<usize>,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<usize, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut batch_count = 0usize;
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;

    let flush = |batch_count: &mut usize,
                 current_artifacts: &mut Vec<usize>,
                 current_source_bytes: &mut usize,
                 current_source_file_count: &mut usize,
                 current_source_lines: &mut usize|
     -> Result<(), CompileError> {
        if current_artifacts.is_empty() {
            return Ok(());
        }
        let batch = SourcePackLinkObjectBatch {
            batch_index: *batch_count,
            input_object_artifact_indices: std::mem::take(current_artifacts),
            source_bytes: std::mem::take(current_source_bytes),
            source_file_count: std::mem::take(current_source_file_count),
            source_lines: std::mem::take(current_source_lines),
        };
        let page = SourcePackBuildLinkObjectBatchPage {
            version: SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION,
            target,
            batch_index: batch.batch_index,
            batch,
        };
        store.store_build_link_object_batch_page(&page)?;
        *batch_count += 1;
        Ok(())
    };

    for artifact_index in artifact_indices {
        let page = source_pack_load_artifact_ref_page_for_index(
            store,
            target,
            artifact_ref_index,
            artifact_index,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link-object batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            flush(
                &mut batch_count,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
    }
    flush(
        &mut batch_count,
        &mut current_artifacts,
        &mut current_source_bytes,
        &mut current_source_file_count,
        &mut current_source_lines,
    )?;
    Ok(batch_count)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct SourcePackLinkBatchChunkStep {
    pub(in crate::compiler) next_artifact_index: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) new_batch_count: usize,
}

pub(in crate::compiler) fn store_source_pack_build_link_interface_batch_pages_from_stored_artifact_ref_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    mut artifact_index: usize,
    end_artifact_index: usize,
    mut batch_index: usize,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackLinkBatchChunkStep, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;
    let mut new_batch_count = 0usize;

    while artifact_index < end_artifact_index {
        let page = source_pack_load_artifact_ref_page_for_index(
            store,
            target,
            artifact_ref_index,
            artifact_index,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link-interface batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            source_pack_store_link_interface_batch_page(
                store,
                target,
                batch_index,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
            batch_index += 1;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(SourcePackLinkBatchChunkStep {
                    next_artifact_index: artifact_index,
                    next_batch_index: batch_index,
                    new_batch_count,
                });
            }
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
        artifact_index += 1;
    }
    if !current_artifacts.is_empty() {
        source_pack_store_link_interface_batch_page(
            store,
            target,
            batch_index,
            &mut current_artifacts,
            &mut current_source_bytes,
            &mut current_source_file_count,
            &mut current_source_lines,
        )?;
        batch_index += 1;
        new_batch_count += 1;
    }
    Ok(SourcePackLinkBatchChunkStep {
        next_artifact_index: artifact_index,
        next_batch_index: batch_index,
        new_batch_count,
    })
}

pub(in crate::compiler) fn source_pack_store_link_interface_batch_page(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    current_artifacts: &mut Vec<usize>,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    current_source_lines: &mut usize,
) -> Result<(), CompileError> {
    let batch = SourcePackLinkInterfaceBatch {
        batch_index,
        input_interface_artifact_indices: std::mem::take(current_artifacts),
        source_bytes: std::mem::take(current_source_bytes),
        source_file_count: std::mem::take(current_source_file_count),
        source_lines: std::mem::take(current_source_lines),
    };
    let page = SourcePackBuildLinkInterfaceBatchPage {
        version: SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION,
        target,
        batch_index: batch.batch_index,
        batch,
    };
    store.store_build_link_interface_batch_page(&page)?;
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_build_link_object_batch_pages_from_stored_artifact_ref_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    mut artifact_index: usize,
    end_artifact_index: usize,
    mut batch_index: usize,
    batch_limits: SourcePackJobBatchLimits,
    max_new_batches: usize,
) -> Result<SourcePackLinkBatchChunkStep, CompileError> {
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;
    let mut new_batch_count = 0usize;

    while artifact_index < end_artifact_index {
        let page = source_pack_load_artifact_ref_page_for_index(
            store,
            target,
            artifact_ref_index,
            artifact_index,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link-object batch input artifact {} has kind {:?}",
                page.artifact_index, page.artifact_ref.kind
            )));
        }
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(page.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(page.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            source_pack_store_link_object_batch_page(
                store,
                target,
                batch_index,
                &mut current_artifacts,
                &mut current_source_bytes,
                &mut current_source_file_count,
                &mut current_source_lines,
            )?;
            batch_index += 1;
            new_batch_count += 1;
            if new_batch_count >= max_new_batches {
                return Ok(SourcePackLinkBatchChunkStep {
                    next_artifact_index: artifact_index,
                    next_batch_index: batch_index,
                    new_batch_count,
                });
            }
        }
        current_artifacts.push(page.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(page.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(page.source_file_count);
        current_source_lines = current_source_lines.saturating_add(page.source_lines);
        artifact_index += 1;
    }
    if !current_artifacts.is_empty() {
        source_pack_store_link_object_batch_page(
            store,
            target,
            batch_index,
            &mut current_artifacts,
            &mut current_source_bytes,
            &mut current_source_file_count,
            &mut current_source_lines,
        )?;
        batch_index += 1;
        new_batch_count += 1;
    }
    Ok(SourcePackLinkBatchChunkStep {
        next_artifact_index: artifact_index,
        next_batch_index: batch_index,
        new_batch_count,
    })
}

pub(in crate::compiler) fn source_pack_store_link_object_batch_page(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    current_artifacts: &mut Vec<usize>,
    current_source_bytes: &mut usize,
    current_source_file_count: &mut usize,
    current_source_lines: &mut usize,
) -> Result<(), CompileError> {
    let batch = SourcePackLinkObjectBatch {
        batch_index,
        input_object_artifact_indices: std::mem::take(current_artifacts),
        source_bytes: std::mem::take(current_source_bytes),
        source_file_count: std::mem::take(current_source_file_count),
        source_lines: std::mem::take(current_source_lines),
    };
    let page = SourcePackBuildLinkObjectBatchPage {
        version: SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION,
        target,
        batch_index: batch.batch_index,
        batch,
    };
    store.store_build_link_object_batch_page(&page)?;
    Ok(())
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackJobBatchDependentsPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_count: usize,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) dependent_edge_count: usize,
}

pub(in crate::compiler) fn validate_source_pack_job_batch_dependents_prepare_progress(
    progress: &SourcePackJobBatchDependentsPrepareProgress,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependents prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents prepare target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.batch_count != batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents prepare batch count {} does not match expected {batch_count}",
            progress.batch_count
        )));
    }
    if progress.next_batch_index > batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents prepare next batch {} exceeds batch count {batch_count}",
            progress.next_batch_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_job_batch_dependents_pages_from_stored_job_batch_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildJobBatchPageIndex,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemJobBatchDependentsPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack job-batch dependents chunk max_new_batches must be greater than zero"
                .into(),
        ));
    }
    validate_source_pack_build_job_batch_page_index(index, target)?;
    let progress_path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    let mut progress = if progress_path.is_file() {
        source_pack_load_job_batch_dependents_prepare_progress(store, target, index.batch_count)?
    } else {
        SourcePackJobBatchDependentsPrepareProgress {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION,
            target,
            batch_count: index.batch_count,
            next_batch_index: 0,
            dependent_edge_count: 0,
        }
    };
    validate_source_pack_job_batch_dependents_prepare_progress(
        &progress,
        target,
        index.batch_count,
    )?;

    let mut new_batch_count = 0usize;
    while progress.next_batch_index < index.batch_count && new_batch_count < max_new_batches {
        let batch_index = progress.next_batch_index;
        let dependency_page = store.load_build_job_batch_page_for_target(target, batch_index)?;
        let mut batch_dependent_edge_count = 0usize;
        source_pack_for_each_stored_job_batch_dependency_index(
            store,
            target,
            &dependency_page.dependency,
            |dependency_batch_index| {
                if dependency_batch_index >= index.batch_count {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job-batch page {batch_index} depends on missing batch {dependency_batch_index}"
                    )));
                }
                source_pack_append_job_batch_dependent_page(
                    store,
                    target,
                    dependency_batch_index,
                    index.batch_count,
                    batch_index,
                )?;
                batch_dependent_edge_count = batch_dependent_edge_count.saturating_add(1);
                Ok(())
            },
        )?;
        progress.dependent_edge_count = progress
            .dependent_edge_count
            .saturating_add(batch_dependent_edge_count);
        progress.next_batch_index = progress.next_batch_index.checked_add(1).ok_or_else(|| {
            source_pack_artifact_shard_contract_error(
                "job-batch dependents prepare next batch index overflows",
            )
        })?;
        new_batch_count = new_batch_count.checked_add(1).ok_or_else(|| {
            source_pack_artifact_shard_contract_error(
                "job-batch dependents prepare new batch count overflows",
            )
        })?;
        source_pack_store_job_batch_dependents_prepare_progress(store, &progress)?;
    }

    Ok(SourcePackFilesystemJobBatchDependentsPrepareStepResult {
        target,
        complete: progress.next_batch_index == index.batch_count,
        batch_count: index.batch_count,
        next_batch_index: progress.next_batch_index,
        new_batch_count,
        dependent_edge_count: progress.dependent_edge_count,
    })
}

pub(in crate::compiler) fn source_pack_store_job_batch_dependents_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackJobBatchDependentsPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_job_batch_dependents_prepare_progress(
        progress,
        progress.target,
        progress.batch_count,
    )?;
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack job-batch dependents prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack job-batch dependents prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_job_batch_dependents_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_count: usize,
) -> Result<SourcePackJobBatchDependentsPrepareProgress, CompileError> {
    let path = store.build_job_batch_dependents_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack job-batch dependents prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<SourcePackJobBatchDependentsPrepareProgress>(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack job-batch dependents prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_source_pack_job_batch_dependents_prepare_progress(&progress, target, batch_count)?;
    Ok(progress)
}

pub(in crate::compiler) fn store_source_pack_job_batch_dependents_pages_from_manifest_dependencies(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_dependencies: &[SourcePackJobBatchDependency],
    batch_count: usize,
) -> Result<(), CompileError> {
    for dependency in batch_dependencies {
        if dependency.batch_index >= batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependency {} exceeds batch count {}",
                dependency.batch_index, batch_count
            )));
        }
        source_pack_for_each_job_batch_dependency_index(dependency, |dependency_batch_index| {
            if dependency_batch_index >= batch_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job-batch dependency {} references missing batch {}",
                    dependency.batch_index, dependency_batch_index
                )));
            }
            source_pack_append_job_batch_dependent_page(
                store,
                target,
                dependency_batch_index,
                batch_count,
                dependency.batch_index,
            )
        })?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_empty_build_job_batch_dependents_page(
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
) -> Result<SourcePackBuildJobBatchDependentsPage, CompileError> {
    let page = SourcePackBuildJobBatchDependentsPage {
        version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
        target,
        batch_count,
        batch_index,
        dependents: SourcePackJobBatchDependents {
            batch_index,
            dependent_batch_indices: Vec::new(),
        },
        dependent_batch_count: 0,
        dependent_page_count: 0,
    };
    validate_source_pack_build_job_batch_dependents_page(
        &page,
        target,
        batch_count,
        Some(batch_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_append_job_batch_dependent_page(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
    dependent_batch_index: usize,
) -> Result<(), CompileError> {
    if batch_index >= batch_count || dependent_batch_index >= batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent edge {batch_index}->{dependent_batch_index} exceeds batch count {batch_count}"
        )));
    }
    if batch_index == dependent_batch_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependent edge {batch_index}->{dependent_batch_index} is self-referential"
        )));
    }
    let mut dependents_page =
        store.load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)?;
    if !dependents_page
        .dependents
        .dependent_batch_indices
        .is_empty()
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch dependents page {batch_index} mixes inline dependents with stored dependent pages"
        )));
    }

    let dependent_position = dependents_page.dependent_batch_count;
    let page_index = dependent_position / SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE;
    let is_new_dependent_page =
        dependent_position % SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE == 0;
    let mut dependent_page = if is_new_dependent_page {
        SourcePackBuildJobBatchDependentBatchPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION,
            target,
            batch_count,
            batch_index,
            page_index,
            first_dependent_position: page_index
                .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE),
            dependent_count: 0,
            dependent_batch_indices: Vec::new(),
        }
    } else {
        store.load_build_job_batch_dependent_batch_page_for_target(
            target,
            batch_index,
            page_index,
            batch_count,
        )?
    };

    dependent_page
        .dependent_batch_indices
        .push(dependent_batch_index);
    dependent_page.dependent_count = dependent_page.dependent_batch_indices.len();
    validate_source_pack_build_job_batch_dependent_batch_page(
        &dependent_page,
        target,
        batch_count,
        batch_index,
        page_index,
    )?;
    store.store_build_job_batch_dependent_batch_page(&dependent_page, batch_count)?;

    dependents_page.dependent_batch_count = dependents_page.dependent_batch_count.saturating_add(1);
    dependents_page.dependent_page_count = dependents_page
        .dependent_batch_count
        .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
    store.store_build_job_batch_dependents_page(&dependents_page, batch_count)?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_job_batch_dependent_index<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    batch_count: usize,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let dependents_page =
        store.load_build_job_batch_dependents_page_for_target(target, batch_index, batch_count)?;
    if !dependents_page
        .dependents
        .dependent_batch_indices
        .is_empty()
    {
        for &dependent_batch_index in &dependents_page.dependents.dependent_batch_indices {
            visit(dependent_batch_index)?;
        }
        return Ok(());
    }

    let mut seen_dependent_count = 0usize;
    for page_index in 0..dependents_page.dependent_page_count {
        let page = store.load_build_job_batch_dependent_batch_page_for_target(
            target,
            batch_index,
            page_index,
            batch_count,
        )?;
        seen_dependent_count = seen_dependent_count.saturating_add(page.dependent_count);
        for &dependent_batch_index in &page.dependent_batch_indices {
            visit(dependent_batch_index)?;
        }
    }
    if seen_dependent_count != dependents_page.dependent_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job-batch {batch_index} iterated {seen_dependent_count} dependents but expected {}",
            dependents_page.dependent_batch_count
        )));
    }
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_job_schedule_from_library_schedule_pages(
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
) -> Result<SourcePackJobSchedule, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    if schedule_pages.len() != schedule_index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "job schedule has {} schedule pages but schedule index partition_count {}",
            schedule_pages.len(),
            schedule_index.partition_count
        )));
    }
    let mut jobs = vec![None; schedule_index.job_count];
    let mut codegen_job_indices = Vec::with_capacity(schedule_index.codegen_job_count);

    for page in schedule_pages {
        validate_source_pack_library_schedule_page(
            page,
            schedule_index.target,
            Some(page.partition_index),
        )?;
        if page.frontend_jobs.is_empty() {
            source_pack_insert_schedule_job(&mut jobs, page.frontend_job.clone())?;
        } else {
            for job in &page.frontend_jobs {
                source_pack_insert_schedule_job(&mut jobs, job.clone())?;
            }
        }
        for job in &page.codegen_jobs {
            codegen_job_indices.push(job.job_index);
            source_pack_insert_schedule_job(&mut jobs, job.clone())?;
        }
    }
    codegen_job_indices.sort_unstable();
    codegen_job_indices.dedup();
    if codegen_job_indices.len() != schedule_index.codegen_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "job schedule recorded {} codegen jobs but schedule index codegen_job_count {}",
            codegen_job_indices.len(),
            schedule_index.codegen_job_count
        )));
    }
    source_pack_insert_schedule_job(
        &mut jobs,
        SourcePackJob {
            job_index: schedule_index.link_job_index,
            phase: SourcePackJobPhase::Link,
            phase_unit_index: 0,
            library_job_index: None,
            library_id: u32::MAX,
            first_source_index: 0,
            source_file_count: 0,
            source_bytes: 0,
            source_lines: 0,
            oversized_source_file: false,
            dependency_job_indices: codegen_job_indices,
        },
    )?;

    let jobs = jobs
        .into_iter()
        .enumerate()
        .map(|(job_index, job)| {
            job.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "job schedule missing job {job_index}"
                ))
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let schedule = SourcePackJobSchedule {
        jobs,
        dependency_job_ranges_by_job_index: Vec::new(),
    };
    if schedule.jobs.len() != schedule_index.job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "job schedule has {} jobs but schedule index job_count {}",
            schedule.jobs.len(),
            schedule_index.job_count
        )));
    }
    Ok(schedule)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_insert_schedule_job(
    jobs: &mut [Option<SourcePackJob>],
    job: SourcePackJob,
) -> Result<(), CompileError> {
    let Some(slot) = jobs.get_mut(job.job_index) else {
        return Err(source_pack_library_partition_contract_error(format!(
            "job schedule job {} exceeds job_count {}",
            job.job_index,
            jobs.len()
        )));
    };
    if slot.is_some() {
        return Err(source_pack_library_partition_contract_error(format!(
            "job schedule job {} appears more than once",
            job.job_index
        )));
    }
    *slot = Some(job);
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_link_interface_batches_from_output_refs<'a, I>(
    refs: I,
    source_metadata_by_artifact_index: &BTreeMap<usize, SourcePackArtifactSourceMetadata>,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<Vec<SourcePackLinkInterfaceBatch>, CompileError>
where
    I: IntoIterator<Item = &'a SourcePackArtifactRef>,
{
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut batches = Vec::new();
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;

    for artifact_ref in refs {
        if artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link interface batch input artifact {} has kind {:?}",
                artifact_ref.artifact_index, artifact_ref.kind
            )));
        }
        let source_metadata = source_metadata_by_artifact_index
            .get(&artifact_ref.artifact_index)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "link interface batch input artifact {} has no source metadata",
                    artifact_ref.artifact_index
                ))
            })?;
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(source_metadata.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(source_metadata.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            batches.push(SourcePackLinkInterfaceBatch {
                batch_index: batches.len(),
                input_interface_artifact_indices: std::mem::take(&mut current_artifacts),
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            });
            current_source_bytes = 0;
            current_source_file_count = 0;
            current_source_lines = 0;
        }
        current_artifacts.push(artifact_ref.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(source_metadata.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(source_metadata.source_file_count);
        current_source_lines = current_source_lines.saturating_add(source_metadata.source_lines);
    }

    if !current_artifacts.is_empty() {
        batches.push(SourcePackLinkInterfaceBatch {
            batch_index: batches.len(),
            input_interface_artifact_indices: current_artifacts,
            source_bytes: current_source_bytes,
            source_file_count: current_source_file_count,
            source_lines: current_source_lines,
        });
    }
    Ok(batches)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_link_object_batches_from_output_refs<'a, I>(
    refs: I,
    source_metadata_by_artifact_index: &BTreeMap<usize, SourcePackArtifactSourceMetadata>,
    batch_limits: SourcePackJobBatchLimits,
) -> Result<Vec<SourcePackLinkObjectBatch>, CompileError>
where
    I: IntoIterator<Item = &'a SourcePackArtifactRef>,
{
    let limits = batch_limits.normalized();
    let max_input_artifacts_per_batch = source_pack_link_batch_input_limit(batch_limits);
    let mut batches = Vec::new();
    let mut current_artifacts = Vec::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_lines = 0usize;

    for artifact_ref in refs {
        if artifact_ref.kind != SourcePackArtifactKind::CodegenObject {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "link object batch input artifact {} has kind {:?}",
                artifact_ref.artifact_index, artifact_ref.kind
            )));
        }
        let source_metadata = source_metadata_by_artifact_index
            .get(&artifact_ref.artifact_index)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "link object batch input artifact {} has no source metadata",
                    artifact_ref.artifact_index
                ))
            })?;
        let should_flush = !current_artifacts.is_empty()
            && (current_artifacts.len() >= max_input_artifacts_per_batch
                || current_source_bytes.saturating_add(source_metadata.source_bytes)
                    > limits.max_source_bytes_per_batch
                || current_source_file_count.saturating_add(source_metadata.source_file_count)
                    > limits.max_source_files_per_batch);
        if should_flush {
            batches.push(SourcePackLinkObjectBatch {
                batch_index: batches.len(),
                input_object_artifact_indices: std::mem::take(&mut current_artifacts),
                source_bytes: current_source_bytes,
                source_file_count: current_source_file_count,
                source_lines: current_source_lines,
            });
            current_source_bytes = 0;
            current_source_file_count = 0;
            current_source_lines = 0;
        }
        current_artifacts.push(artifact_ref.artifact_index);
        current_source_bytes = current_source_bytes.saturating_add(source_metadata.source_bytes);
        current_source_file_count =
            current_source_file_count.saturating_add(source_metadata.source_file_count);
        current_source_lines = current_source_lines.saturating_add(source_metadata.source_lines);
    }

    if !current_artifacts.is_empty() {
        batches.push(SourcePackLinkObjectBatch {
            batch_index: batches.len(),
            input_object_artifact_indices: current_artifacts,
            source_bytes: current_source_bytes,
            source_file_count: current_source_file_count,
            source_lines: current_source_lines,
        });
    }
    Ok(batches)
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackPageArtifactShardBuilder {
    pub(in crate::compiler) kind: SourcePackBuildArtifactShardKind,
    pub(in crate::compiler) batch_indices: Vec<usize>,
    pub(in crate::compiler) job_indices: BTreeSet<usize>,
    pub(in crate::compiler) input_artifact_indices: BTreeSet<usize>,
    pub(in crate::compiler) input_artifact_ranges: Vec<SourcePackArtifactIndexRange>,
    pub(in crate::compiler) output_artifact_indices: BTreeSet<usize>,
    pub(in crate::compiler) source_bytes: usize,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) source_lines: usize,
    pub(in crate::compiler) oversized_batch: bool,
}

impl SourcePackPageArtifactShardBuilder {
    pub(in crate::compiler) fn new(kind: SourcePackBuildArtifactShardKind) -> Self {
        Self {
            kind,
            batch_indices: Vec::new(),
            job_indices: BTreeSet::new(),
            input_artifact_indices: BTreeSet::new(),
            input_artifact_ranges: Vec::new(),
            output_artifact_indices: BTreeSet::new(),
            source_bytes: 0,
            source_file_count: 0,
            source_lines: 0,
            oversized_batch: false,
        }
    }

    pub(in crate::compiler) fn is_empty(&self) -> bool {
        self.batch_indices.is_empty()
    }

    pub(in crate::compiler) fn would_exceed(
        &self,
        next: &SourcePackPageArtifactShardBuilder,
        limits: SourcePackBuildShardLimits,
    ) -> bool {
        if self.is_empty() {
            return false;
        }
        let batch_count = self
            .batch_indices
            .len()
            .saturating_add(next.batch_indices.len());
        let job_count = self.job_indices.union(&next.job_indices).count();
        let artifact_count = source_pack_page_artifact_shard_record_union_count(self, next);
        batch_count > limits.max_batches_per_shard
            || job_count > limits.max_jobs_per_shard
            || artifact_count > limits.max_artifacts_per_shard
    }

    pub(in crate::compiler) fn absorb(&mut self, next: SourcePackPageArtifactShardBuilder) {
        self.batch_indices.extend(next.batch_indices);
        self.job_indices.extend(next.job_indices);
        self.input_artifact_indices
            .extend(next.input_artifact_indices);
        self.input_artifact_ranges
            .extend(next.input_artifact_ranges);
        self.output_artifact_indices
            .extend(next.output_artifact_indices);
        self.source_bytes = self.source_bytes.saturating_add(next.source_bytes);
        self.source_file_count = self
            .source_file_count
            .saturating_add(next.source_file_count);
        self.source_lines = self.source_lines.saturating_add(next.source_lines);
        self.oversized_batch |= next.oversized_batch;
    }

    pub(in crate::compiler) fn finish(
        mut self,
        shard_index: usize,
        target: SourcePackArtifactTarget,
        limits: SourcePackBuildShardLimits,
    ) -> Option<SourcePackBuildArtifactShard> {
        if self.is_empty() {
            return None;
        }
        let input_artifact_ranges = source_pack_compact_artifact_index_ranges(std::mem::take(
            &mut self.input_artifact_ranges,
        ));
        let input_artifact_indices = self
            .input_artifact_indices
            .into_iter()
            .filter(|artifact_index| {
                !source_pack_artifact_index_covered_by_ranges(
                    *artifact_index,
                    &input_artifact_ranges,
                )
            })
            .collect::<BTreeSet<_>>();
        let artifact_record_count = input_artifact_indices
            .len()
            .saturating_add(input_artifact_ranges.len())
            .saturating_add(self.output_artifact_indices.len());
        let oversized = self.batch_indices.len() > limits.max_batches_per_shard
            || self.job_indices.len() > limits.max_jobs_per_shard
            || artifact_record_count > limits.max_artifacts_per_shard
            || self.oversized_batch;
        Some(SourcePackBuildArtifactShard {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            target,
            limits,
            shard_index,
            kind: self.kind,
            batch_indices: self.batch_indices,
            job_indices: self.job_indices.into_iter().collect(),
            input_artifact_indices: input_artifact_indices.into_iter().collect(),
            input_artifact_ranges,
            output_artifact_indices: self.output_artifact_indices.into_iter().collect(),
            source_bytes: self.source_bytes,
            source_file_count: self.source_file_count,
            source_lines: self.source_lines,
            oversized,
        })
    }
}

pub(in crate::compiler) fn source_pack_page_artifact_shard_record_union_count(
    left: &SourcePackPageArtifactShardBuilder,
    right: &SourcePackPageArtifactShardBuilder,
) -> usize {
    let input_artifact_ranges = source_pack_compact_artifact_index_ranges(
        left.input_artifact_ranges
            .iter()
            .chain(right.input_artifact_ranges.iter())
            .cloned()
            .collect(),
    );
    let input_artifact_count = left
        .input_artifact_indices
        .iter()
        .chain(right.input_artifact_indices.iter())
        .copied()
        .filter(|artifact_index| {
            !source_pack_artifact_index_covered_by_ranges(*artifact_index, &input_artifact_ranges)
        })
        .collect::<BTreeSet<_>>()
        .len();
    let output_artifact_count = left
        .output_artifact_indices
        .union(&right.output_artifact_indices)
        .count();
    input_artifact_count
        .saturating_add(input_artifact_ranges.len())
        .saturating_add(output_artifact_count)
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) enum SourcePackBuildArtifactShardPreparePhase {
    JobBatches,
    LinkInterfaceBatches,
    LinkObjectBatches,
    BuildProgressDirectoryPages,
    BuildProgressDirectoryIndexPages,
    Complete,
}

impl SourcePackBuildArtifactShardPreparePhase {
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

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackBuildArtifactShardPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) limits: SourcePackBuildShardLimits,
    pub(in crate::compiler) job_count: usize,
    pub(in crate::compiler) job_batch_count: usize,
    pub(in crate::compiler) artifact_count: usize,
    pub(in crate::compiler) link_interface_batch_count: usize,
    pub(in crate::compiler) link_object_batch_count: usize,
    pub(in crate::compiler) phase: SourcePackBuildArtifactShardPreparePhase,
    pub(in crate::compiler) next_batch_index: usize,
    pub(in crate::compiler) next_shard_index: usize,
    pub(in crate::compiler) current_builder: Option<SourcePackPageArtifactShardBuilder>,
    pub(in crate::compiler) job_batch_shard_count: usize,
    pub(in crate::compiler) link_interface_shard_range: Option<SourcePackLinkInputShardRange>,
    pub(in crate::compiler) link_object_shard_range: Option<SourcePackLinkInputShardRange>,
    pub(in crate::compiler) ready_batch_count: usize,
    pub(in crate::compiler) first_ready_batch_index: Option<usize>,
}

pub(in crate::compiler) fn source_pack_build_artifact_shard_prepare_phase_batch_count(
    progress: &SourcePackBuildArtifactShardPrepareProgress,
) -> usize {
    match progress.phase {
        SourcePackBuildArtifactShardPreparePhase::JobBatches => progress.job_batch_count,
        SourcePackBuildArtifactShardPreparePhase::LinkInterfaceBatches => {
            progress.link_interface_batch_count
        }
        SourcePackBuildArtifactShardPreparePhase::LinkObjectBatches => {
            progress.link_object_batch_count
        }
        SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryPages => progress
            .job_batch_shard_count
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE),
        SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => progress
            .job_batch_shard_count
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
            .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE),
        SourcePackBuildArtifactShardPreparePhase::Complete => 0,
    }
}

pub(in crate::compiler) fn source_pack_build_artifact_shard_prepare_progress_directory_page_count(
    progress: &SourcePackBuildArtifactShardPrepareProgress,
) -> usize {
    progress
        .job_batch_shard_count
        .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
}

pub(in crate::compiler) fn source_pack_build_artifact_shard_prepare_progress_directory_index_page_count(
    progress: &SourcePackBuildArtifactShardPrepareProgress,
) -> usize {
    source_pack_build_artifact_shard_prepare_progress_directory_page_count(progress)
        .div_ceil(SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE)
}

pub(in crate::compiler) fn source_pack_build_progress_summary_from_artifact_shard_prepare_progress(
    progress: &SourcePackBuildArtifactShardPrepareProgress,
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

pub(in crate::compiler) fn validate_source_pack_build_artifact_shard_prepare_progress(
    progress: &SourcePackBuildArtifactShardPrepareProgress,
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-shard prepare target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    let limits = limits.normalized();
    if progress.limits.normalized() != limits {
        return Err(source_pack_artifact_shard_contract_error(format!(
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
        return Err(source_pack_artifact_shard_contract_error(format!(
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
    let phase_batch_count = source_pack_build_artifact_shard_prepare_phase_batch_count(progress);
    if progress.next_batch_index > phase_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-shard prepare phase {:?} next batch {} exceeds phase batch count {}",
            progress.phase, progress.next_batch_index, phase_batch_count
        )));
    }
    if progress.job_batch_shard_count > progress.job_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-shard prepare has {} job-batch shards but only {} job batches",
            progress.job_batch_shard_count, progress.job_batch_count
        )));
    }
    if !matches!(
        progress.phase,
        SourcePackBuildArtifactShardPreparePhase::JobBatches
    ) && progress.job_batch_count != 0
        && progress.job_batch_shard_count == 0
    {
        return Err(source_pack_artifact_shard_contract_error(
            "artifact-shard prepare left job-batch phase without job-batch shards",
        ));
    }
    match (progress.phase.kind(), &progress.current_builder) {
        (Some(kind), Some(builder)) if builder.kind == kind => {}
        (Some(kind), Some(builder)) => {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has builder kind {:?}, expected {:?}",
                progress.phase, builder.kind, kind
            )));
        }
        (Some(kind), None) => {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has no {:?} builder",
                progress.phase, kind
            )));
        }
        (None, None) => {}
        (None, Some(_)) => {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has a pending shard builder",
                progress.phase
            )));
        }
    }
    let progress_summary =
        source_pack_build_progress_summary_from_artifact_shard_prepare_progress(progress);
    validate_source_pack_build_progress_summary(&progress_summary)?;
    source_pack_validate_link_input_shard_range(
        progress.link_interface_shard_range.as_ref(),
        "interface",
    )?;
    source_pack_validate_link_input_shard_range(
        progress.link_object_shard_range.as_ref(),
        "object",
    )?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_build_artifact_shard_builder_for_stored_phase_batch(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    phase: SourcePackBuildArtifactShardPreparePhase,
    batch_index: usize,
) -> Result<SourcePackPageArtifactShardBuilder, CompileError> {
    match phase {
        SourcePackBuildArtifactShardPreparePhase::JobBatches => {
            let page = store.load_build_job_batch_page_for_target(target, batch_index)?;
            source_pack_job_batch_shard_builder_from_stored_schedule_page(
                store,
                schedule_index,
                &page.batch,
            )
        }
        SourcePackBuildArtifactShardPreparePhase::LinkInterfaceBatches => {
            let page =
                store.load_build_link_interface_batch_page_for_target(target, batch_index)?;
            source_pack_link_interface_batch_shard_builder_from_page(&page)
        }
        SourcePackBuildArtifactShardPreparePhase::LinkObjectBatches => {
            let page = store.load_build_link_object_batch_page_for_target(target, batch_index)?;
            source_pack_link_object_batch_shard_builder_from_page(&page)
        }
        SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryPages
        | SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
            Err(source_pack_artifact_shard_contract_error(format!(
                "artifact-shard prepare phase {:?} has no shard input batch",
                phase
            )))
        }
        SourcePackBuildArtifactShardPreparePhase::Complete => {
            Err(source_pack_artifact_shard_contract_error(
                "completed artifact-shard prepare has no input batch",
            ))
        }
    }
}

pub(in crate::compiler) fn source_pack_store_build_artifact_shard_from_page_metadata(
    store: &SourcePackFilesystemArtifactStore,
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
    store_source_pack_build_artifact_shard_page(store, &shard)?;
    store_source_pack_build_batch_shard_locators(store, &shard)?;
    let execution_shard = source_pack_build_artifact_execution_shard_from_stored_pages(
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
            let progress = source_pack_initial_build_progress_shard_from_execution_shard(
                target,
                &execution_shard,
            )?;
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
            source_pack_extend_link_input_shard_range(
                link_interface_shard_range,
                shard.shard_index,
                "interface",
            )?;
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            source_pack_extend_link_input_shard_range(
                link_object_shard_range,
                shard.shard_index,
                "object",
            )?;
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_store_pending_artifact_shard_prepare_builder(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    progress: &mut SourcePackBuildArtifactShardPrepareProgress,
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
        progress.current_builder = progress
            .phase
            .kind()
            .map(SourcePackPageArtifactShardBuilder::new);
        return Ok(false);
    };
    source_pack_store_build_artifact_shard_from_page_metadata(
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
        source_pack_artifact_shard_contract_error(
            "artifact-shard prepare next shard index overflows",
        )
    })?;
    progress.current_builder = progress
        .phase
        .kind()
        .map(SourcePackPageArtifactShardBuilder::new);
    Ok(true)
}

pub(in crate::compiler) fn source_pack_store_build_progress_directory_page_from_artifact_shard_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackBuildArtifactShardPrepareProgress,
    directory_page_index: usize,
) -> Result<PathBuf, CompileError> {
    let progress_summary =
        source_pack_build_progress_summary_from_artifact_shard_prepare_progress(progress);
    validate_source_pack_build_progress_summary(&progress_summary)?;
    let directory_page = source_pack_build_progress_directory_page_from_summaries(
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

pub(in crate::compiler) fn source_pack_store_build_progress_directory_index_page_from_artifact_shard_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackBuildArtifactShardPrepareProgress,
    directory_index_page_index: usize,
) -> Result<PathBuf, CompileError> {
    let progress_summary =
        source_pack_build_progress_summary_from_artifact_shard_prepare_progress(progress);
    validate_source_pack_build_progress_summary(&progress_summary)?;
    let directory_index_page =
        source_pack_build_progress_directory_index_page_from_directory_pages(
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

pub(in crate::compiler) fn store_source_pack_build_artifact_shards_from_page_metadata_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
    max_new_batches: usize,
) -> Result<SourcePackFilesystemArtifactShardPrepareStepResult, CompileError> {
    if max_new_batches == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact-shard chunk max_new_batches must be greater than zero".into(),
        ));
    }
    let limits = limits.normalized();
    validate_source_pack_library_schedule_index(schedule_index, target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, target)?;
    validate_source_pack_library_partition_index(library_partition_index, target)?;
    validate_source_pack_build_job_batch_page_index(job_batch_page_index, target)?;
    validate_source_pack_build_link_batch_page_index(link_batch_page_index, target)?;
    if store.artifact_shard_index_path_for_target(target).is_file() {
        let index = store.load_build_artifact_shard_index_for_target(target)?;
        let progress_summary = store.load_build_progress_summary_for_target(target).ok();
        let progress_directory_page_count = progress_summary
            .as_ref()
            .and_then(|summary| source_pack_build_progress_directory_page_count(summary).ok())
            .unwrap_or(0);
        let progress_directory_index_page_count = progress_summary
            .as_ref()
            .and_then(|summary| source_pack_build_progress_directory_index_page_count(summary).ok())
            .unwrap_or(0);
        return Ok(SourcePackFilesystemArtifactShardPrepareStepResult {
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

    let dependents_progress = source_pack_load_job_batch_dependents_prepare_progress(
        store,
        target,
        job_batch_page_index.batch_count,
    )?;
    if dependents_progress.next_batch_index != job_batch_page_index.batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-shard chunk requires completed job-batch dependents; next batch {} of {}",
            dependents_progress.next_batch_index, job_batch_page_index.batch_count
        )));
    }

    let progress_path = store.artifact_shard_prepare_progress_path_for_target(target);
    let mut progress = if progress_path.is_file() {
        source_pack_load_artifact_shard_prepare_progress(
            store,
            target,
            limits,
            schedule_index,
            artifact_ref_index,
            job_batch_page_index,
            link_batch_page_index,
        )?
    } else {
        SourcePackBuildArtifactShardPrepareProgress {
            version: SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION,
            target,
            limits,
            job_count: schedule_index.job_count,
            job_batch_count: job_batch_page_index.batch_count,
            artifact_count: artifact_ref_index.artifact_count,
            link_interface_batch_count: link_batch_page_index.link_interface_batch_count,
            link_object_batch_count: link_batch_page_index.link_object_batch_count,
            phase: SourcePackBuildArtifactShardPreparePhase::JobBatches,
            next_batch_index: 0,
            next_shard_index: 0,
            current_builder: Some(SourcePackPageArtifactShardBuilder::new(
                SourcePackBuildArtifactShardKind::JobBatches,
            )),
            job_batch_shard_count: 0,
            link_interface_shard_range: None,
            link_object_shard_range: None,
            ready_batch_count: 0,
            first_ready_batch_index: None,
        }
    };
    validate_source_pack_build_artifact_shard_prepare_progress(
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
        && progress.phase != SourcePackBuildArtifactShardPreparePhase::Complete
    {
        let phase_batch_count =
            source_pack_build_artifact_shard_prepare_phase_batch_count(&progress);
        if progress.next_batch_index == phase_batch_count {
            if source_pack_store_pending_artifact_shard_prepare_builder(
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
            if progress.phase == SourcePackBuildArtifactShardPreparePhase::JobBatches {
                progress.job_batch_shard_count = progress.next_shard_index;
            }
            progress.phase = progress.phase.next();
            progress.next_batch_index = 0;
            progress.current_builder = progress
                .phase
                .kind()
                .map(SourcePackPageArtifactShardBuilder::new);
            source_pack_store_artifact_shard_prepare_progress(store, &progress)?;
            continue;
        }

        match progress.phase {
            SourcePackBuildArtifactShardPreparePhase::JobBatches
            | SourcePackBuildArtifactShardPreparePhase::LinkInterfaceBatches
            | SourcePackBuildArtifactShardPreparePhase::LinkObjectBatches => {
                let builder = source_pack_build_artifact_shard_builder_for_stored_phase_batch(
                    store,
                    target,
                    schedule_index,
                    progress.phase,
                    progress.next_batch_index,
                )?;
                let current = progress.current_builder.as_mut().ok_or_else(|| {
                    source_pack_artifact_shard_contract_error(
                        "artifact-shard prepare has no current builder",
                    )
                })?;
                if current.would_exceed(&builder, limits) {
                    if source_pack_store_pending_artifact_shard_prepare_builder(
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
                    source_pack_artifact_shard_contract_error(
                        "artifact-shard prepare has no current builder after flush",
                    )
                })?;
                current.absorb(builder);
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        source_pack_artifact_shard_contract_error(
                            "artifact-shard prepare next batch index overflows",
                        )
                    })?;
                new_input_batch_count = new_input_batch_count.checked_add(1).ok_or_else(|| {
                    source_pack_artifact_shard_contract_error(
                        "artifact-shard prepare new input batch count overflows",
                    )
                })?;
            }
            SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryPages => {
                source_pack_store_build_progress_directory_page_from_artifact_shard_prepare_progress(
                    store,
                    &progress,
                    progress.next_batch_index,
                )?;
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        source_pack_artifact_shard_contract_error(
                            "artifact-shard prepare progress-directory page index overflows",
                        )
                    })?;
                new_progress_directory_page_count = new_progress_directory_page_count
                    .checked_add(1)
                    .ok_or_else(|| {
                        source_pack_artifact_shard_contract_error(
                            "artifact-shard prepare new progress-directory page count overflows",
                        )
                    })?;
            }
            SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
                source_pack_store_build_progress_directory_index_page_from_artifact_shard_prepare_progress(
                    store,
                    &progress,
                    progress.next_batch_index,
                )?;
                progress.next_batch_index =
                    progress.next_batch_index.checked_add(1).ok_or_else(|| {
                        source_pack_artifact_shard_contract_error(
                            "artifact-shard prepare progress-directory index page index overflows",
                        )
                    })?;
                new_progress_directory_index_page_count =
                    new_progress_directory_index_page_count
                        .checked_add(1)
                        .ok_or_else(|| {
                            source_pack_artifact_shard_contract_error(
                                "artifact-shard prepare new progress-directory index page count overflows",
                            )
                        })?;
            }
            SourcePackBuildArtifactShardPreparePhase::Complete => {}
        }
        new_prepare_unit_count = new_prepare_unit_count.checked_add(1).ok_or_else(|| {
            source_pack_artifact_shard_contract_error(
                "artifact-shard prepare new unit count overflows",
            )
        })?;
        source_pack_store_artifact_shard_prepare_progress(store, &progress)?;
    }

    let progress_directory_page_count =
        source_pack_build_artifact_shard_prepare_progress_directory_page_count(&progress);
    let progress_directory_index_page_count =
        source_pack_build_artifact_shard_prepare_progress_directory_index_page_count(&progress);

    let mut artifact_shard_index_path = None;
    let mut link_input_shard_index_path = None;
    if progress.phase == SourcePackBuildArtifactShardPreparePhase::Complete {
        let progress_summary =
            source_pack_build_progress_summary_from_artifact_shard_prepare_progress(&progress);
        validate_source_pack_build_progress_summary(&progress_summary)?;
        let stored_directory_page_count =
            source_pack_build_progress_directory_page_count(&progress_summary)?;
        let stored_directory_index_page_count =
            source_pack_build_progress_directory_index_page_count(&progress_summary)?;
        if progress_directory_page_count != stored_directory_page_count
            || progress_directory_index_page_count != stored_directory_index_page_count
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "artifact-shard prepare progress directory counts {}/{} do not match summary counts {}/{}",
                progress_directory_page_count,
                progress_directory_index_page_count,
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
        validate_source_pack_build_artifact_shard_index(&index)?;
        let link_input_index = SourcePackBuildLinkInputShardIndex {
            version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
            target,
            link_interface_shard_range: progress.link_interface_shard_range.clone(),
            link_object_shard_range: progress.link_object_shard_range.clone(),
        };
        validate_source_pack_build_link_input_shard_index(&link_input_index, target)?;
        store_source_pack_build_artifact_shard_compact_indexes(store, &index, &link_input_index)?;
        artifact_shard_index_path = Some(store.artifact_shard_index_path_for_target(target));
        link_input_shard_index_path = Some(store.link_input_shard_index_path_for_target(target));
        store.store_build_progress_summary(&progress_summary)?;
    }

    Ok(SourcePackFilesystemArtifactShardPrepareStepResult {
        target,
        complete: artifact_shard_index_path.is_some(),
        shard_count: progress.next_shard_index,
        new_shard_count,
        next_input_kind: progress.phase.kind(),
        next_batch_index: progress.next_batch_index,
        new_input_batch_count,
        progress_directory_page_count,
        progress_directory_index_page_count,
        next_progress_directory_page_index: match progress.phase {
            SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryPages => {
                progress.next_batch_index
            }
            SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages
            | SourcePackBuildArtifactShardPreparePhase::Complete => progress_directory_page_count,
            _ => 0,
        },
        next_progress_directory_index_page_index: match progress.phase {
            SourcePackBuildArtifactShardPreparePhase::BuildProgressDirectoryIndexPages => {
                progress.next_batch_index
            }
            SourcePackBuildArtifactShardPreparePhase::Complete => {
                progress_directory_index_page_count
            }
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

pub(in crate::compiler) fn source_pack_store_artifact_shard_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackBuildArtifactShardPrepareProgress,
) -> Result<PathBuf, CompileError> {
    let path = store.artifact_shard_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack artifact-shard prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack artifact-shard prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_artifact_shard_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: SourcePackBuildShardLimits,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
) -> Result<SourcePackBuildArtifactShardPrepareProgress, CompileError> {
    let path = store.artifact_shard_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack artifact-shard prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<SourcePackBuildArtifactShardPrepareProgress>(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack artifact-shard prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_source_pack_build_artifact_shard_prepare_progress(
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

pub(in crate::compiler) fn source_pack_extend_link_input_shard_range(
    range: &mut Option<SourcePackLinkInputShardRange>,
    shard_index: usize,
    label: &str,
) -> Result<(), CompileError> {
    if let Some(range) = range {
        let end_shard_index = range.end_shard_index().ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "{label} link input shard range overflows"
            ))
        })?;
        if shard_index != end_shard_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "{label} link input shard range expected shard {end_shard_index} but saw {shard_index}"
            )));
        }
        range.shard_count = range.shard_count.checked_add(1).ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "{label} link input shard range count overflows"
            ))
        })?;
    } else {
        *range = Some(SourcePackLinkInputShardRange {
            first_shard_index: shard_index,
            shard_count: 1,
        });
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_build_artifact_shard_page(
    store: &SourcePackFilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_build_artifact_shard(shard, shard.target)?;
    let path = store.artifact_shard_path_for_target(shard.target, shard.shard_index);
    let bytes = serde_json::to_vec_pretty(shard).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack build artifact shard {}: {err}",
            shard.shard_index
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack build artifact shard",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn store_source_pack_build_batch_shard_locators(
    store: &SourcePackFilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
) -> Result<usize, CompileError> {
    validate_source_pack_build_artifact_shard(shard, shard.target)?;
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
        write_source_pack_filesystem_file_atomically(
            &locator_path,
            &bytes,
            "source-pack batch shard locator",
        )?;
        batch_shard_locator_count += 1;
    }
    Ok(batch_shard_locator_count)
}

pub(in crate::compiler) fn store_source_pack_build_artifact_shard_compact_indexes(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackBuildArtifactShardIndex,
    link_input_index: &SourcePackBuildLinkInputShardIndex,
) -> Result<(), CompileError> {
    validate_source_pack_build_artifact_shard_index(index)?;
    validate_source_pack_build_link_input_shard_index(link_input_index, index.target)?;
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
    write_source_pack_filesystem_file_atomically(
        &link_input_index_path,
        &link_input_index_bytes,
        "source-pack link input shard index",
    )?;
    write_source_pack_filesystem_file_atomically(
        &index_path,
        &index_bytes,
        "source-pack build artifact shard index",
    )?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_initial_build_progress_shard_from_execution_shard(
    target: SourcePackArtifactTarget,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
) -> Result<SourcePackBuildProgressShard, CompileError> {
    validate_source_pack_build_artifact_execution_shard(execution_shard, target)?;
    let mut progress = SourcePackBuildProgressShard::new(target, &execution_shard.shard);
    for dependency in &execution_shard.batch_dependencies {
        if !dependency.has_dependencies() {
            progress.record_batch_ready(dependency.batch_index)?;
        }
    }
    Ok(progress)
}

pub(in crate::compiler) fn source_pack_job_batch_shard_builder_from_stored_schedule_page(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    batch: &SourcePackJobBatch,
) -> Result<SourcePackPageArtifactShardBuilder, CompileError> {
    let mut builder =
        SourcePackPageArtifactShardBuilder::new(SourcePackBuildArtifactShardKind::JobBatches);
    builder.batch_indices.push(batch.batch_index);
    builder.oversized_batch = batch.oversized;
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;

    for &job_index in &batch.job_indices {
        let job = source_pack_stored_schedule_job_metadata(store, schedule_index, job_index)?;
        builder.job_indices.insert(job_index);
        builder.output_artifact_indices.insert(job.job_index);
    }
    Ok(builder)
}

pub(in crate::compiler) fn source_pack_link_interface_batch_shard_builder_from_page(
    page: &SourcePackBuildLinkInterfaceBatchPage,
) -> Result<SourcePackPageArtifactShardBuilder, CompileError> {
    validate_source_pack_build_link_interface_batch_page(
        page,
        page.target,
        Some(page.batch_index),
    )?;
    let batch = &page.batch;
    let mut builder = SourcePackPageArtifactShardBuilder::new(
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
    );
    builder.batch_indices.push(batch.batch_index);
    builder
        .input_artifact_indices
        .extend(batch.input_interface_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    Ok(builder)
}

pub(in crate::compiler) fn source_pack_link_object_batch_shard_builder_from_page(
    page: &SourcePackBuildLinkObjectBatchPage,
) -> Result<SourcePackPageArtifactShardBuilder, CompileError> {
    validate_source_pack_build_link_object_batch_page(page, page.target, Some(page.batch_index))?;
    let batch = &page.batch;
    let mut builder = SourcePackPageArtifactShardBuilder::new(
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
    );
    builder.batch_indices.push(batch.batch_index);
    builder
        .input_artifact_indices
        .extend(batch.input_object_artifact_indices.iter().copied());
    builder.source_bytes = batch.source_bytes;
    builder.source_file_count = batch.source_file_count;
    builder.source_lines = batch.source_lines;
    Ok(builder)
}

pub(in crate::compiler) fn source_pack_build_artifact_execution_shard_from_stored_pages(
    store: &SourcePackFilesystemArtifactStore,
    shard: &SourcePackBuildArtifactShard,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
    validate_source_pack_build_artifact_shard(shard, shard.target)?;
    validate_source_pack_library_schedule_index(schedule_index, shard.target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, shard.target)?;
    validate_source_pack_build_job_batch_page_index(job_batch_page_index, shard.target)?;
    validate_source_pack_build_link_batch_page_index(link_batch_page_index, shard.target)?;
    validate_source_pack_library_partition_index(library_partition_index, shard.target)?;

    let mut jobs = Vec::new();
    let mut job_artifacts = Vec::new();
    for &job_index in &shard.job_indices {
        let job = source_pack_stored_schedule_job_metadata(store, schedule_index, job_index)?;
        let job_manifest = source_pack_job_artifact_manifest_from_stored_artifact_refs(
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
                    return Err(source_pack_artifact_shard_contract_error(format!(
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
                    return Err(source_pack_artifact_shard_contract_error(format!(
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
    let artifact_refs = source_pack_artifact_refs_for_indices_from_stored_pages(
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
    validate_source_pack_build_artifact_execution_shard(&execution_shard, shard.target)?;
    Ok(execution_shard)
}

pub(in crate::compiler) fn source_pack_stored_source_file_for_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    library_partition_index: &SourcePackLibraryPartitionIndex,
    source_index: usize,
    partition_cache: &mut BTreeMap<usize, SourcePackLibraryPartition>,
    page_cache: &mut BTreeMap<usize, SourcePackLibrarySourceFilePage>,
) -> Result<ExplicitSourcePathFile, CompileError> {
    let partition = source_pack_library_partition_for_source_index_from_stored_pages(
        store,
        library_partition_index,
        target,
        source_index,
        partition_cache,
    )?;
    if !page_cache.contains_key(&partition.partition_index) {
        let page =
            store.load_library_source_file_page_for_target(target, partition.partition_index)?;
        validate_source_pack_library_source_file_page(
            &page,
            target,
            Some(partition.partition_index),
        )?;
        page_cache.insert(partition.partition_index, page);
    }
    let page = page_cache.get(&partition.partition_index).ok_or_else(|| {
        source_pack_artifact_shard_contract_error(format!(
            "source file page {} was not cached",
            partition.partition_index
        ))
    })?;
    if page.source_files.is_empty() {
        let record = store.load_library_source_file_record_page_for_target(target, source_index)?;
        validate_source_pack_library_source_file_record_page(&record, target, Some(source_index))?;
        if record.partition_index != partition.partition_index
            || record.library_id != partition.library_id
            || record.first_source_index != partition.first_source_index
            || record.source_file_count != partition.source_file_count
        {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-file record {} does not match partition {} metadata",
                source_index, partition.partition_index
            )));
        }
        return Ok(record.file);
    }
    page.source_files
        .iter()
        .find(|source_file| source_file.source_index == source_index)
        .map(|source_file| source_file.file.clone())
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "source file page {} does not contain source file {}",
                partition.partition_index, source_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_library_partition_for_source_index_from_stored_pages(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackLibraryPartitionIndex,
    target: SourcePackArtifactTarget,
    source_index: usize,
    partition_cache: &mut BTreeMap<usize, SourcePackLibraryPartition>,
) -> Result<SourcePackLibraryPartition, CompileError> {
    validate_source_pack_library_partition_index(index, target)?;
    if source_index >= index.source_file_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "source index {} exceeds partition index source file count {}",
            source_index, index.source_file_count
        )));
    }
    if let Some(partition) = partition_cache.values().find(|partition| {
        partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .is_some_and(|source_end| {
                partition.first_source_index <= source_index && source_index < source_end
            })
    }) {
        return Ok(partition.clone());
    }

    let mut low = 0usize;
    let mut high = index.partition_count;
    while low < high {
        let partition_index = low + (high - low) / 2;
        let partition = if let Some(partition) = partition_cache.get(&partition_index) {
            partition.clone()
        } else {
            let partition = store.load_library_partition_for_target(target, partition_index)?;
            partition_cache.insert(partition_index, partition.clone());
            partition
        };
        let source_end = partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        if source_index < partition.first_source_index {
            high = partition_index;
        } else if source_index >= source_end {
            low = partition_index + 1;
        } else {
            return Ok(partition);
        }
    }

    Err(source_pack_artifact_shard_contract_error(format!(
        "source index {} is not covered by any persisted library partition",
        source_index
    )))
}

pub(in crate::compiler) fn source_pack_job_artifact_manifest_from_stored_artifact_refs(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job: &SourcePackJob,
) -> Result<SourcePackJobArtifactManifest, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, target)?;
    let (
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interfaces,
        input_objects,
        outputs,
    ) = match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let (input_interface_count, input_interface_page_count, input_interface_ranges) =
                    store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies(
                        store,
                        target,
                        schedule_index,
                        artifact_ref_index,
                        job.job_index,
                    )?;
            (
                input_interface_count,
                input_interface_page_count,
                input_interface_ranges,
                Vec::new(),
                Vec::new(),
                vec![source_pack_artifact_ref_for_index_from_stored_pages(
                    store,
                    target,
                    artifact_ref_index,
                    job.job_index,
                    SourcePackArtifactKind::LibraryInterface,
                )?],
            )
        }
        SourcePackJobPhase::Codegen => {
            let (input_interface_count, input_interface_page_count, input_interface_ranges) =
                    store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies(
                        store,
                        target,
                        schedule_index,
                        artifact_ref_index,
                        job.job_index,
                    )?;
            (
                input_interface_count,
                input_interface_page_count,
                input_interface_ranges,
                Vec::new(),
                Vec::new(),
                vec![source_pack_artifact_ref_for_index_from_stored_pages(
                    store,
                    target,
                    artifact_ref_index,
                    job.job_index,
                    SourcePackArtifactKind::CodegenObject,
                )?],
            )
        }
        SourcePackJobPhase::Link => (
            0,
            0,
            Vec::new(),
            Vec::new(),
            Vec::new(),
            vec![source_pack_artifact_ref_for_index_from_stored_pages(
                store,
                target,
                artifact_ref_index,
                schedule_index.link_job_index,
                SourcePackArtifactKind::LinkedOutput,
            )?],
        ),
    };

    Ok(SourcePackJobArtifactManifest {
        job_index: job.job_index,
        phase: job.phase,
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interface_artifact_ranges: Vec::new(),
        input_interfaces,
        input_object_count: input_objects.len(),
        input_object_page_count: 0,
        input_object_artifact_ranges: Vec::new(),
        input_objects,
        outputs,
    })
}

pub(in crate::compiler) struct SourcePackJobArtifactInputInterfacePageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_interfaces: Vec<SourcePackArtifactRef>,
}

impl<'a> SourcePackJobArtifactInputInterfacePageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        job_index: usize,
        artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    ) -> Self {
        Self {
            store,
            target,
            job_index,
            artifact_ref_index,
            page_index: 0,
            first_input_position: 0,
            input_count: 0,
            current_input_interfaces: Vec::with_capacity(
                SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    pub(in crate::compiler) fn push_job(
        &mut self,
        input_job_index: usize,
    ) -> Result<(), CompileError> {
        let artifact_ref = source_pack_artifact_ref_for_index_from_stored_pages(
            self.store,
            self.target,
            self.artifact_ref_index,
            input_job_index,
            SourcePackArtifactKind::LibraryInterface,
        )?;
        self.current_input_interfaces.push(artifact_ref);
        if self.current_input_interfaces.len()
            == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_input_interfaces.is_empty() {
            return Ok(());
        }
        let input_interfaces = std::mem::take(&mut self.current_input_interfaces);
        let page = SourcePackJobArtifactInputInterfacePage {
            version: SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION,
            target: self.target,
            job_index: self.job_index,
            page_index: self.page_index,
            first_input_position: self.first_input_position,
            input_count: input_interfaces.len(),
            input_interfaces,
        };
        validate_source_pack_job_artifact_input_interface_page(
            &page,
            self.target,
            self.job_index,
            self.page_index,
        )?;
        self.store.store_job_artifact_input_interface_page(&page)?;
        self.input_count = self.input_count.saturating_add(page.input_count);
        self.first_input_position = self.first_input_position.saturating_add(page.input_count);
        self.page_index += 1;
        Ok(())
    }

    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

pub(in crate::compiler) fn store_source_pack_job_artifact_input_interface_pages_from_stored_schedule_dependencies(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_index: usize,
) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
    let mut writer = SourcePackJobArtifactInputInterfacePageWriter::new(
        store,
        target,
        job_index,
        artifact_ref_index,
    );
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    source_pack_for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| {
            writer.push_job(dependency_job_index)?;
            Ok(())
        },
    )?;
    let (explicit_input_count, input_interface_page_count) = writer.finish()?;
    let ranged_input_count =
        source_pack_job_index_range_dependency_count(&job_page.dependency_job_ranges);
    Ok((
        explicit_input_count.saturating_add(ranged_input_count),
        input_interface_page_count,
        job_page.dependency_job_ranges,
    ))
}

pub(in crate::compiler) fn source_pack_compact_path_build_manifest_from_stored_indexes(
    limits: CodegenUnitLimits,
    batch_limits: SourcePackJobBatchLimits,
    target: SourcePackArtifactTarget,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    link_batch_page_index: &SourcePackBuildLinkBatchPageIndex,
    source_file_count: usize,
    source_byte_count: usize,
    source_line_count: usize,
) -> SourcePackPathBuildManifest {
    SourcePackPathBuildManifest {
        version: SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION,
        source_file_count,
        source_byte_count,
        source_line_count,
        source_files: Vec::new(),
        library_dependencies: Vec::new(),
        limits,
        batch_limits,
        artifacts: SourcePackBuildArtifactManifest {
            version: SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            target,
            job_count: schedule_index.job_count,
            job_batch_count: job_batch_page_index.batch_count,
            batch_dependency_count: job_batch_page_index.batch_count,
            artifact_count: artifact_ref_index.artifact_count,
            job_artifact_count: schedule_index.job_count,
            job_artifact_io_count: schedule_index.job_count,
            artifact_use_count: artifact_ref_index.artifact_count,
            link_interface_batch_count: link_batch_page_index.link_interface_batch_count,
            link_object_batch_count: link_batch_page_index.link_object_batch_count,
            job_schedule: Default::default(),
            job_batches: Default::default(),
            batch_dependencies: Default::default(),
            artifacts: Default::default(),
            job_artifacts: Default::default(),
            job_artifact_io: Default::default(),
            artifact_uses: Default::default(),
            link_interface_batches: Default::default(),
            link_object_batches: Default::default(),
        },
    }
}

pub(in crate::compiler) fn source_pack_work_queue_artifact_item_count_from_pages(
    pages: &[SourcePackWorkQueuePage],
) -> usize {
    pages
        .iter()
        .filter(|page| source_pack_work_queue_item_kind_is_artifact_backed(page.kind))
        .count()
}

pub(in crate::compiler) fn source_pack_work_queue_page_dependency_count(
    page: &SourcePackWorkQueuePage,
) -> usize {
    page.dependency_item_count
        .max(page.dependency_item_indices.len())
        .saturating_add(source_pack_job_index_range_dependency_count(
            &page.dependency_item_ranges,
        ))
}

pub(in crate::compiler) fn source_pack_work_queue_page_dependent_count(
    page: &SourcePackWorkQueuePage,
) -> usize {
    page.dependent_item_count
        .max(page.dependent_item_indices.len())
        .saturating_add(source_pack_job_index_range_dependency_count(
            &page.dependent_item_ranges,
        ))
}
