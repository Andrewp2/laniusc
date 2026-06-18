use super::*;

/// Validates compact dependency-batch ranges against explicit dependencies.
pub(in crate::compiler) fn validate_job_batch_dependency_ranges<F>(
    dependency: &SourcePackJobBatchDependency,
    explicit_dependencies: &BTreeSet<usize>,
    context: &str,
    max_dependency_batch_index_exclusive: usize,
    rejected_batch_index: Option<usize>,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut previous_range_end = None;
    for (range_position, range) in dependency.dependency_batch_ranges.iter().enumerate() {
        if range.batch_count == 0 {
            return Err(make_error(format!(
                "{context} dependency range {range_position} is empty"
            )));
        }
        let Some(end_batch_index) = range.end_batch_index() else {
            return Err(make_error(format!(
                "{context} dependency range {range_position} overflows usize"
            )));
        };
        if end_batch_index > max_dependency_batch_index_exclusive {
            return Err(make_error(format!(
                "{context} dependency range {}..{} exceeds dependency bound {}",
                range.first_batch_index, end_batch_index, max_dependency_batch_index_exclusive
            )));
        }
        if let Some(rejected_batch_index) = rejected_batch_index {
            if range.contains(rejected_batch_index) {
                return Err(make_error(format!(
                    "{context} dependency range {}..{} includes batch {}",
                    range.first_batch_index, end_batch_index, rejected_batch_index
                )));
            }
        }
        if let Some(previous_range_end) = previous_range_end
            && range.first_batch_index < previous_range_end
        {
            return Err(make_error(format!(
                "{context} dependency ranges must be sorted and non-overlapping; range {}..{} follows previous end {}",
                range.first_batch_index, end_batch_index, previous_range_end
            )));
        }
        if let Some(duplicate) = explicit_dependencies
            .iter()
            .copied()
            .find(|&dependency_batch_index| range.contains(dependency_batch_index))
        {
            return Err(make_error(format!(
                "{context} dependency range {}..{} duplicates explicit dependency {}",
                range.first_batch_index, end_batch_index, duplicate
            )));
        }
        previous_range_end = Some(end_batch_index);
    }
    Ok(())
}

/// Validates dependency-range counts and page counts for a batch dependency.
pub(in crate::compiler) fn validate_job_batch_dependency_range_metadata<F>(
    dependency: &SourcePackJobBatchDependency,
    context: &str,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    if !dependency.dependency_batch_ranges.is_empty() {
        if dependency.dependency_range_page_count != 0 {
            return Err(make_error(format!(
                "{context} records both inline and paged dependency ranges"
            )));
        }
        if dependency.dependency_range_count != dependency.dependency_batch_ranges.len() {
            return Err(make_error(format!(
                "{context} records {} inline dependency ranges but range count {}",
                dependency.dependency_batch_ranges.len(),
                dependency.dependency_range_count
            )));
        }
        let inline_dependency_range_batch_count = dependency
            .dependency_batch_ranges
            .iter()
            .try_fold(0usize, |count, range| {
                count.checked_add(range.batch_count).ok_or_else(|| {
                    make_error(format!(
                        "{context} inline dependency range batch count overflows"
                    ))
                })
            })?;
        if dependency.dependency_range_batch_count != inline_dependency_range_batch_count {
            return Err(make_error(format!(
                "{context} records {} dependency batches in inline ranges but range batch count {}",
                inline_dependency_range_batch_count, dependency.dependency_range_batch_count
            )));
        }
        return Ok(());
    }

    if dependency.dependency_range_count == 0 {
        if dependency.dependency_range_page_count != 0
            || dependency.dependency_range_batch_count != 0
        {
            return Err(make_error(format!(
                "{context} has dependency range metadata without ranges"
            )));
        }
        return Ok(());
    }

    let expected_page_count = dependency
        .dependency_range_count
        .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE);
    if dependency.dependency_range_page_count != expected_page_count {
        return Err(make_error(format!(
            "{context} has dependency range page count {} but expected {} for {} ranges",
            dependency.dependency_range_page_count,
            expected_page_count,
            dependency.dependency_range_count
        )));
    }
    if dependency.dependency_range_batch_count == 0 {
        return Err(make_error(format!(
            "{context} has dependency ranges without dependency batches"
        )));
    }
    Ok(())
}

/// Visits dependency batch indices that are stored inline on a dependency.
pub(in crate::compiler) fn for_each_job_batch_dependency_index<F>(
    dependency: &SourcePackJobBatchDependency,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    if dependency.dependency_batch_indices.len() != dependency.explicit_dependency_count() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch {} dependency ids are paged and require the stored dependency iterator",
            dependency.batch_index
        )));
    }
    if dependency.dependency_batch_ranges.is_empty() && dependency.dependency_range_count != 0 {
        return Err(artifact_shard_contract_error(format!(
            "job-batch {} dependency ranges are paged and require the stored dependency iterator",
            dependency.batch_index
        )));
    }
    for &dependency_batch_index in &dependency.dependency_batch_indices {
        visit(dependency_batch_index)?;
    }
    for range in &dependency.dependency_batch_ranges {
        let Some(indices) = range.iter() else {
            return Err(artifact_shard_contract_error(format!(
                "batch {} has overflowing dependency range starting at {}",
                dependency.batch_index, range.first_batch_index
            )));
        };
        for dependency_batch_index in indices {
            visit(dependency_batch_index)?;
        }
    }
    Ok(())
}

/// Splits explicit dependency batch indices into sidecar pages.
pub(in crate::compiler) fn store_job_batch_dependency_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
) -> Result<(usize, usize), CompileError> {
    if dependency.dependency_batch_indices.is_empty() {
        return Ok((
            dependency.dependency_batch_count,
            dependency.dependency_page_count,
        ));
    }
    unique_usize_set(
        &dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", dependency.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", dependency.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    let mut dependency_batch_count = 0usize;
    let mut dependency_page_count = 0usize;
    for dependency_chunk in dependency
        .dependency_batch_indices
        .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE)
    {
        let page = SourcePackBuildJobBatchDependencyPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
            target,
            batch_index: dependency.batch_index,
            page_index: dependency_page_count,
            first_dependency_position: dependency_page_count
                .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE),
            dependency_count: dependency_chunk.len(),
            dependency_batch_indices: dependency_chunk.to_vec(),
        };
        validate_job_batch_dependency_page(
            &page,
            target,
            dependency.batch_index,
            dependency_page_count,
        )?;
        store.store_build_job_batch_dependency_page(&page)?;
        dependency_batch_count = dependency_batch_count.saturating_add(page.dependency_count);
        dependency_page_count += 1;
    }
    Ok((dependency_batch_count, dependency_page_count))
}

/// Splits dependency batch ranges into sidecar pages.
pub(in crate::compiler) fn store_job_batch_dependency_range_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
) -> Result<(usize, usize, usize), CompileError> {
    if dependency.dependency_batch_ranges.is_empty() {
        return Ok((
            dependency.dependency_range_count,
            dependency.dependency_range_page_count,
            dependency.dependency_range_batch_count,
        ));
    }
    let mut dependency_range_count = 0usize;
    let mut dependency_range_page_count = 0usize;
    let mut dependency_range_batch_count = 0usize;
    for range_chunk in dependency
        .dependency_batch_ranges
        .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE)
    {
        let page_dependency_batch_count = range_chunk.iter().fold(0usize, |count, range| {
            count.saturating_add(range.batch_count)
        });
        let page = SourcePackBuildJobBatchDependencyRangePage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
            target,
            batch_index: dependency.batch_index,
            page_index: dependency_range_page_count,
            first_range_position: dependency_range_count,
            range_count: range_chunk.len(),
            dependency_batch_count: page_dependency_batch_count,
            dependency_batch_ranges: range_chunk.to_vec(),
        };
        validate_job_batch_dependency_range_page(
            &page,
            target,
            dependency.batch_index,
            dependency_range_page_count,
        )?;
        store.store_build_job_batch_dependency_range_page(&page)?;
        dependency_range_count = dependency_range_count.saturating_add(page.range_count);
        dependency_range_batch_count =
            dependency_range_batch_count.saturating_add(page.dependency_batch_count);
        dependency_range_page_count += 1;
    }
    Ok((
        dependency_range_count,
        dependency_range_page_count,
        dependency_range_batch_count,
    ))
}

/// Incremental writer for explicit dependency batch sidecar pages.
pub(in crate::compiler) struct JobBatchDependencyPageWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) batch_index: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_batch_count: usize,
    pub(in crate::compiler) seen_dependency_batch_indices: BTreeSet<usize>,
    pub(in crate::compiler) current_dependency_batch_indices: Vec<usize>,
}

impl<'a> JobBatchDependencyPageWriter<'a> {
    /// Creates a dependency batch writer for one job batch.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Self {
        Self {
            store,
            target,
            batch_index,
            page_index: 0,
            first_dependency_position: 0,
            dependency_batch_count: 0,
            seen_dependency_batch_indices: BTreeSet::new(),
            current_dependency_batch_indices: Vec::with_capacity(
                SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Records one dependency batch index if it has not already been seen.
    pub(in crate::compiler) fn push(
        &mut self,
        dependency_batch_index: usize,
    ) -> Result<(), CompileError> {
        if dependency_batch_index >= self.batch_index {
            return Err(artifact_shard_contract_error(format!(
                "job-batch page {} depends on non-earlier batch {}",
                self.batch_index, dependency_batch_index
            )));
        }
        if !self
            .seen_dependency_batch_indices
            .insert(dependency_batch_index)
        {
            return Ok(());
        }
        Ok(())
    }

    /// Flushes the current dependency sidecar page, if it has records.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_batch_indices.is_empty() {
            return Ok(());
        }
        let dependency_batch_indices = std::mem::take(&mut self.current_dependency_batch_indices);
        let page = SourcePackBuildJobBatchDependencyPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
            target: self.target,
            batch_index: self.batch_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_batch_indices.len(),
            dependency_batch_indices,
        };
        validate_job_batch_dependency_page(&page, self.target, self.batch_index, self.page_index)?;
        self.store.store_build_job_batch_dependency_page(&page)?;
        self.dependency_batch_count = self
            .dependency_batch_count
            .saturating_add(page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    /// Finishes the writer and returns dependency count/page count metadata.
    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        let dependency_batch_indices = self
            .seen_dependency_batch_indices
            .iter()
            .copied()
            .collect::<Vec<_>>();
        for chunk in dependency_batch_indices
            .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE)
        {
            self.current_dependency_batch_indices = chunk.to_vec();
            self.flush()?;
        }
        Ok((self.dependency_batch_count, self.page_index))
    }
}

/// Visits all dependency batch indices, loading sidecar pages as needed.
pub(in crate::compiler) fn for_each_stored_job_batch_dependency_index<F>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency: &SourcePackJobBatchDependency,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    if !dependency.dependency_batch_indices.is_empty() {
        for_each_job_batch_dependency_index(dependency, visit)?;
        return Ok(());
    }

    let mut seen_dependency_count = 0usize;
    for page_index in 0..dependency.dependency_page_count {
        let page = store.load_build_job_batch_dependency_page_for_target(
            target,
            dependency.batch_index,
            page_index,
        )?;
        seen_dependency_count = seen_dependency_count.saturating_add(page.dependency_count);
        for &dependency_batch_index in &page.dependency_batch_indices {
            visit(dependency_batch_index)?;
        }
    }
    if seen_dependency_count != dependency.dependency_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch {} iterated {} dependency batches but expected {}",
            dependency.batch_index, seen_dependency_count, dependency.dependency_batch_count
        )));
    }
    if !dependency.dependency_batch_ranges.is_empty() {
        for range in &dependency.dependency_batch_ranges {
            let Some(indices) = range.iter() else {
                return Err(artifact_shard_contract_error(format!(
                    "batch {} has overflowing dependency range starting at {}",
                    dependency.batch_index, range.first_batch_index
                )));
            };
            for dependency_batch_index in indices {
                visit(dependency_batch_index)?;
            }
        }
    } else {
        let mut seen_range_count = 0usize;
        let mut seen_range_dependency_batch_count = 0usize;
        for page_index in 0..dependency.dependency_range_page_count {
            let page = store.load_build_job_batch_dependency_range_page_for_target(
                target,
                dependency.batch_index,
                page_index,
            )?;
            seen_range_count = seen_range_count.saturating_add(page.range_count);
            seen_range_dependency_batch_count =
                seen_range_dependency_batch_count.saturating_add(page.dependency_batch_count);
            for range in &page.dependency_batch_ranges {
                let Some(indices) = range.iter() else {
                    return Err(artifact_shard_contract_error(format!(
                        "batch {} has overflowing dependency range starting at {}",
                        dependency.batch_index, range.first_batch_index
                    )));
                };
                for dependency_batch_index in indices {
                    visit(dependency_batch_index)?;
                }
            }
        }
        if seen_range_count != dependency.dependency_range_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch {} iterated {} dependency ranges but expected {}",
                dependency.batch_index, seen_range_count, dependency.dependency_range_count
            )));
        }
        if seen_range_dependency_batch_count != dependency.dependency_range_batch_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch {} iterated {} range dependency batches but expected {}",
                dependency.batch_index,
                seen_range_dependency_batch_count,
                dependency.dependency_range_batch_count
            )));
        }
    }
    Ok(())
}
