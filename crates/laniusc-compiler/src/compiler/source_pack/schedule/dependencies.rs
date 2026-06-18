use super::super::*;

/// Incremental writer for one schedule job's dependency pages.
pub(in crate::compiler) struct JobDependencyWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) job_count: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_job_count: usize,
    pub(in crate::compiler) dependency_job_ranges: Vec<SourcePackJobIndexRange>,
    pub(in crate::compiler) current_dependency_job_indices: Vec<usize>,
}

impl<'a> JobDependencyWriter<'a> {
    /// Creates a dependency writer for one schedule job.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        job_index: usize,
        job_count: usize,
    ) -> Self {
        Self {
            store,
            target,
            job_index,
            job_count,
            page_index: 0,
            first_dependency_position: 0,
            dependency_job_count: 0,
            dependency_job_ranges: Vec::new(),
            current_dependency_job_indices: Vec::with_capacity(
                SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Pushes one explicit dependency job index.
    pub(in crate::compiler) fn push(
        &mut self,
        dependency_job_index: usize,
    ) -> Result<(), CompileError> {
        if dependency_job_index >= self.job_index {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job {}",
                self.job_index, dependency_job_index
            )));
        }
        self.current_dependency_job_indices
            .push(dependency_job_index);
        if self.current_dependency_job_indices.len()
            == SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    /// Flushes the current explicit dependency page, if it has records.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_job_indices.is_empty() {
            return Ok(());
        }
        let dependency_job_indices = std::mem::take(&mut self.current_dependency_job_indices);
        let dependency_page = SourcePackLibraryScheduleJobDependencyPage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION,
            target: self.target,
            job_index: self.job_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_job_indices.len(),
            dependency_job_indices,
        };
        validate_schedule_job_dependency_page(
            &dependency_page,
            self.target,
            self.job_count,
            self.job_index,
            self.page_index,
        )?;
        self.store
            .store_library_schedule_job_dependency_page(&dependency_page, self.job_count)?;
        self.dependency_job_count = self
            .dependency_job_count
            .saturating_add(dependency_page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(dependency_page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    /// Pushes a dependency job range, compacting it when possible.
    pub(in crate::compiler) fn push_range(
        &mut self,
        first_job_index: usize,
        job_count: usize,
    ) -> Result<(), CompileError> {
        if job_count == 0 {
            return Ok(());
        }
        let end_job_index = first_job_index.checked_add(job_count).ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule job page {} dependency range {}+{} overflows",
                self.job_index, first_job_index, job_count
            ))
        })?;
        if end_job_index > self.job_index {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job range {}..{}",
                self.job_index, first_job_index, end_job_index
            )));
        }
        if try_compact_dependency_range(
            &mut self.dependency_job_ranges,
            self.job_index,
            first_job_index,
            job_count,
        )? {
            return Ok(());
        }

        for dependency_job_index in first_job_index..end_job_index {
            self.push(dependency_job_index)?;
        }
        Ok(())
    }

    /// Finishes the writer and returns compact dependency metadata.
    pub(in crate::compiler) fn finish(
        mut self,
    ) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
        self.flush()?;
        Ok((
            self.dependency_job_count,
            self.page_index,
            self.dependency_job_ranges,
        ))
    }
}

/// Attempts to merge a job dependency range into compact inline ranges.
pub(in crate::compiler) fn try_compact_dependency_range(
    dependency_job_ranges: &mut Vec<SourcePackJobIndexRange>,
    job_index: usize,
    first_job_index: usize,
    job_count: usize,
) -> Result<bool, CompileError> {
    let end_job_index = first_job_index.checked_add(job_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "schedule job page {job_index} dependency range {first_job_index}+{job_count} overflows"
        ))
    })?;
    if end_job_index > job_index {
        return Err(library_partition_contract_error(format!(
            "schedule job page {job_index} depends on non-prior job range {first_job_index}..{end_job_index}"
        )));
    }

    let mut merged_ranges = dependency_job_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index,
        job_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(library_partition_contract_error(format!(
                "schedule job page {job_index} dependency range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(library_partition_contract_error(format!(
                    "schedule job page {job_index} dependency range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependency_job_ranges = compact_ranges;
    Ok(true)
}

/// Stores one schedule job page after writing dependency sidecars.
pub(in crate::compiler) fn store_schedule_job_with_dependencies<F>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    job_count: usize,
    job: &SourcePackJob,
    mut write_dependencies: F,
) -> Result<PathBuf, CompileError>
where
    F: FnMut(&mut JobDependencyWriter<'_>) -> Result<(), CompileError>,
{
    let mut writer = JobDependencyWriter::new(store, target, job.job_index, job_count);
    write_dependencies(&mut writer)?;
    let (dependency_job_count, dependency_page_count, dependency_job_ranges) = writer.finish()?;
    let mut stored_job = job.clone();
    stored_job.dependency_job_indices.clear();
    let page = SourcePackLibraryScheduleJobPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
        target,
        job_index: job.job_index,
        job: stored_job,
        dependency_job_count,
        dependency_page_count,
        dependency_job_ranges,
    };
    store.write_library_schedule_job_page_file(&page, job_count)
}

/// Writes frontend-job dependency ranges for all dependency libraries.
pub(in crate::compiler) fn write_dependency_frontend_job_ranges(
    writer: &mut JobDependencyWriter<'_>,
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
) -> Result<(), CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    if !partition.dependency_library_ids.is_empty() {
        for &dependency_library_id in &partition.dependency_library_ids {
            write_dependency_frontend_job_range(writer, store, partition, dependency_library_id)?;
        }
        return Ok(());
    }

    let mut loaded_dependency_count = 0usize;
    for page_index in 0..partition.dependency_page_count {
        let dependency_page = store.load_library_dependency_page_for_target(
            partition.target,
            partition.partition_index,
            page_index,
        )?;
        if dependency_page.first_dependency_position != loaded_dependency_count {
            return Err(library_partition_contract_error(format!(
                "partition {} dependency page {} starts at {} but loaded {} dependencies",
                partition.partition_index,
                page_index,
                dependency_page.first_dependency_position,
                loaded_dependency_count
            )));
        }
        let remaining_dependency_count = partition
            .dependency_library_count
            .checked_sub(loaded_dependency_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} loaded too many dependencies before page {}",
                    partition.partition_index, page_index
                ))
            })?;
        let expected_page_dependency_count =
            remaining_dependency_count.min(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(library_partition_contract_error(format!(
                "partition {} dependency page {} has {} dependencies but expected {}",
                partition.partition_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        for dependency_library_id in dependency_page.dependency_library_ids {
            write_dependency_frontend_job_range(writer, store, partition, dependency_library_id)?;
            loaded_dependency_count += 1;
        }
    }
    if loaded_dependency_count != partition.dependency_library_count {
        return Err(library_partition_contract_error(format!(
            "partition {} loaded {} library dependencies but expected {}",
            partition.partition_index, loaded_dependency_count, partition.dependency_library_count
        )));
    }
    Ok(())
}

/// Writes the frontend-job range for one dependency library.
pub(in crate::compiler) fn write_dependency_frontend_job_range(
    writer: &mut JobDependencyWriter<'_>,
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    dependency_library_id: u32,
) -> Result<(), CompileError> {
    if dependency_library_id == partition.library_id {
        return Err(library_partition_contract_error(format!(
            "partition {} library {} depends on itself",
            partition.partition_index, partition.library_id
        )));
    }
    let locator = store.load_library_frontend_job_locator_page_for_target(
        partition.target,
        dependency_library_id,
    )?;
    if locator.partition_index >= partition.partition_index {
        return Err(library_partition_contract_error(format!(
            "partition {} library {} depends on library {} in partition {}",
            partition.partition_index,
            partition.library_id,
            dependency_library_id,
            locator.partition_index
        )));
    }
    writer.push_range(
        locator.frontend_job_index,
        library_frontend_job_locator_count(&locator),
    )
}

/// Stores sorted dependency library ids into fixed-size pages.
pub(in crate::compiler) fn store_partition_dependency_ids<I>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    expected_dependency_library_count: usize,
    dependency_library_ids: I,
) -> Result<(usize, usize), CompileError>
where
    I: IntoIterator<Item = u32>,
{
    let mut dependency_library_count = 0usize;
    let mut dependency_page_count = 0usize;
    let mut first_dependency_position = 0usize;
    let mut dependency_page_ids =
        Vec::with_capacity(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
    let mut previous_dependency_library_id = None;

    for dependency_library_id in dependency_library_ids {
        if dependency_library_count >= expected_dependency_library_count {
            return Err(library_partition_contract_error(format!(
                "partition {partition_index} received more than {expected_dependency_library_count} dependency libraries"
            )));
        }
        if dependency_library_id == library_id {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} depends on itself"
            )));
        }
        if previous_dependency_library_id.is_some_and(|previous_dependency_library_id| {
            dependency_library_id <= previous_dependency_library_id
        }) {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} dependency ids must be strictly sorted and unique"
            )));
        }
        let partition_locator_path =
            store.library_partition_locator_page_path_for_target(target, dependency_library_id);
        let frontend_job_locator_path =
            store.library_frontend_job_locator_page_path_for_target(target, dependency_library_id);
        let dependency_partition_index = if partition_locator_path.is_file() {
            store
                .load_library_partition_locator_page_for_target(target, dependency_library_id)?
                .partition_index
        } else if frontend_job_locator_path.is_file() {
            store
                .load_library_frontend_job_locator_page_for_target(target, dependency_library_id)?
                .partition_index
        } else {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} depends on missing or later library {dependency_library_id}"
            )));
        };
        if dependency_partition_index >= partition_index {
            return Err(library_partition_contract_error(format!(
                "partition {partition_index} library {library_id} depends on library {dependency_library_id} in partition {}",
                dependency_partition_index
            )));
        }
        previous_dependency_library_id = Some(dependency_library_id);
        dependency_page_ids.push(dependency_library_id);
        dependency_library_count += 1;
        if dependency_page_ids.len() == SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
            store_partition_dependency_id_page(
                store,
                target,
                partition_index,
                dependency_page_count,
                first_dependency_position,
                std::mem::take(&mut dependency_page_ids),
            )?;
            dependency_page_count += 1;
            first_dependency_position = dependency_library_count;
            dependency_page_ids =
                Vec::with_capacity(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        }
    }

    if dependency_library_count != expected_dependency_library_count {
        return Err(library_partition_contract_error(format!(
            "partition {partition_index} received {dependency_library_count} dependency libraries but expected {expected_dependency_library_count}"
        )));
    }
    if !dependency_page_ids.is_empty() {
        store_partition_dependency_id_page(
            store,
            target,
            partition_index,
            dependency_page_count,
            first_dependency_position,
            dependency_page_ids,
        )?;
        dependency_page_count += 1;
    }

    Ok((dependency_library_count, dependency_page_count))
}

/// Stores one dependency-library id page for a partition.
pub(in crate::compiler) fn store_partition_dependency_id_page(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    page_index: usize,
    first_dependency_position: usize,
    dependency_library_ids: Vec<u32>,
) -> Result<(), CompileError> {
    let dependency_page = SourcePackLibraryDependencyPage {
        version: SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION,
        target,
        partition_index,
        page_index,
        first_dependency_position,
        dependency_count: dependency_library_ids.len(),
        dependency_library_ids,
    };
    validate_library_dependency_page(&dependency_page, target, partition_index, page_index)?;
    store.store_library_dependency_page(&dependency_page)?;
    Ok(())
}
