use super::*;

/// Validates a locator from a build batch to its artifact shard.
pub(in crate::compiler) fn validate_batch_shard_locator(
    locator: &SourcePackBuildBatchShardLocator,
    target: SourcePackArtifactTarget,
    batch_index: usize,
) -> Result<(), CompileError> {
    if locator.version != SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack batch shard locator version {}; expected {}",
            locator.version, SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION
        )));
    }
    if locator.target != target {
        return Err(artifact_shard_contract_error(format!(
            "batch shard locator target {:?} does not match requested target {:?}",
            locator.target, target
        )));
    }
    if locator.batch_index != batch_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded batch shard locator for batch {} but requested batch {}",
            locator.batch_index, batch_index
        )));
    }
    Ok(())
}

/// Validates the compact index for persisted job-batch pages.
pub(in crate::compiler) fn validate_job_batch_page_index(
    index: &SourcePackBuildJobBatchPageIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch page index version {}; expected {}",
            index.version, SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.batch_count == 0 {
        return Err(artifact_shard_contract_error(
            "job-batch page index has no batches",
        ));
    }
    if index.scheduled_job_count == 0 {
        return Err(artifact_shard_contract_error(
            "job-batch page index has no scheduled jobs",
        ));
    }
    Ok(())
}

/// Validates a persisted job-batch page.
pub(in crate::compiler) fn validate_job_batch_page(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_job_batch_page_with_mode(
        page,
        target,
        batch_index,
        JobBatchPageValidationMode::Persisted,
    )
}

/// Validates a job-batch page before store-time sidecar expansion.
pub(in crate::compiler) fn validate_job_batch_page_store_input(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_job_batch_page_with_mode(
        page,
        target,
        batch_index,
        JobBatchPageValidationMode::StoreInput,
    )
}

/// Validation mode for compact persisted pages versus store inputs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum JobBatchPageValidationMode {
    /// Validate the compact page that is already persisted.
    Persisted,
    /// Validate caller-provided data before sidecar pages are split out.
    StoreInput,
}

/// Validates an inline record count against persisted-page caps.
pub(in crate::compiler) fn validate_job_batch_inline_record_count(
    page: &SourcePackBuildJobBatchPage,
    label: &str,
    count: usize,
    cap: usize,
    mode: JobBatchPageValidationMode,
) -> Result<(), CompileError> {
    if mode == JobBatchPageValidationMode::Persisted && count > cap {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} stores {} inline {} records, exceeding record cap {}",
            page.batch_index, count, label, cap
        )));
    }
    Ok(())
}

/// Validates a job-batch page using the requested page validation mode.
pub(in crate::compiler) fn validate_job_batch_page_with_mode(
    page: &SourcePackBuildJobBatchPage,
    target: SourcePackArtifactTarget,
    batch_index: Option<usize>,
    mode: JobBatchPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(batch_index) = batch_index {
        if page.batch_index != batch_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded job-batch page {} but requested batch {}",
                page.batch_index, batch_index
            )));
        }
    }
    if page.batch.batch_index != page.batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} contains batch record {}",
            page.batch_index, page.batch.batch_index
        )));
    }
    if page.dependency.batch_index != page.batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} contains dependency record {}",
            page.batch_index, page.dependency.batch_index
        )));
    }
    if page.batch.job_indices.is_empty() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} has no jobs",
            page.batch_index
        )));
    }
    if page.batch.job_indices.len() > SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} stores {} inline job records, exceeding record cap {}",
            page.batch_index,
            page.batch.job_indices.len(),
            SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    unique_usize_set(
        &page.batch.job_indices,
        &format!("job-batch page {} jobs", page.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.batch.job_indices,
        &format!("job-batch page {} jobs", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    validate_job_batch_inline_record_count(
        page,
        "dependency",
        page.dependency.dependency_batch_indices.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    validate_job_batch_inline_record_count(
        page,
        "dependency range",
        page.dependency.dependency_batch_ranges.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    let explicit_dependency_count = page.dependency.explicit_dependency_count();
    if !page.dependency.dependency_batch_indices.is_empty()
        && page.dependency.dependency_batch_count != 0
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} records both inline and paged dependencies",
            page.batch_index
        )));
    }
    if page.dependency.dependency_batch_count == 0 {
        if page.dependency.dependency_page_count != 0 {
            return Err(artifact_shard_contract_error(format!(
                "job-batch page {} has dependency page count {} without dependencies",
                page.batch_index, page.dependency.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency
            .dependency_batch_count
            .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if page.dependency.dependency_page_count != expected_page_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch page {} has dependency page count {} but expected {} for {} dependencies",
                page.batch_index,
                page.dependency.dependency_page_count,
                expected_page_count,
                page.dependency.dependency_batch_count
            )));
        }
    }
    validate_job_batch_dependency_range_metadata(
        &page.dependency,
        &format!("job-batch page {}", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    if !page.dependency.dependency_batch_indices.is_empty()
        && explicit_dependency_count > page.batch_index
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch page {} dependency count {} exceeds prior batch count {}",
            page.batch_index, explicit_dependency_count, page.batch_index
        )));
    }
    let explicit_dependencies = unique_usize_set(
        &page.dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", page.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.dependency.dependency_batch_indices,
        &format!("job-batch page {} dependencies", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    for &dependency_batch_index in &page.dependency.dependency_batch_indices {
        if dependency_batch_index >= page.batch_index {
            return Err(artifact_shard_contract_error(format!(
                "job-batch page {} depends on non-earlier batch {}",
                page.batch_index, dependency_batch_index
            )));
        }
    }
    validate_job_batch_dependency_ranges(
        &page.dependency,
        &explicit_dependencies,
        &format!("job-batch page {}", page.batch_index),
        page.batch_index,
        None,
        |message| artifact_shard_contract_error(message),
    )?;
    Ok(())
}

/// Validates one explicit dependency-batch sidecar page.
pub(in crate::compiler) fn validate_job_batch_dependency_page(
    page: &SourcePackBuildJobBatchDependencyPage,
    target: SourcePackArtifactTarget,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependency page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependency page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependency page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} starts at {} but expected {}",
            page.page_index,
            page.batch_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_batch_indices.len() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} records {} dependencies but stores {}",
            page.page_index,
            page.batch_index,
            page.dependency_count,
            page.dependency_batch_indices.len()
        )));
    }
    if page.dependency_count == 0
        || page.dependency_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency page {} for batch {} has invalid dependency count {}",
            page.page_index, page.batch_index, page.dependency_count
        )));
    }
    unique_usize_set(
        &page.dependency_batch_indices,
        &format!(
            "job-batch dependency page {} for batch {} dependencies",
            page.page_index, page.batch_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &page.dependency_batch_indices,
        &format!(
            "job-batch dependency page {} for batch {} dependencies",
            page.page_index, page.batch_index
        ),
        |message| artifact_shard_contract_error(message),
    )?;
    for &dependency_batch_index in &page.dependency_batch_indices {
        if dependency_batch_index >= page.batch_index {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependency page {} for batch {} has invalid dependency batch {}",
                page.page_index, page.batch_index, dependency_batch_index
            )));
        }
    }
    Ok(())
}

/// Validates one dependency-batch range sidecar page.
pub(in crate::compiler) fn validate_job_batch_dependency_range_page(
    page: &SourcePackBuildJobBatchDependencyRangePage,
    target: SourcePackArtifactTarget,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependency range page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency range page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependency range page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependency range page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE);
    if page.first_range_position != expected_first_position {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} starts at {} but expected {}",
            page.page_index, page.batch_index, page.first_range_position, expected_first_position
        )));
    }
    if page.range_count != page.dependency_batch_ranges.len() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} records {} ranges but stores {}",
            page.page_index,
            page.batch_index,
            page.range_count,
            page.dependency_batch_ranges.len()
        )));
    }
    if page.range_count == 0
        || page.range_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} has invalid range count {}",
            page.page_index, page.batch_index, page.range_count
        )));
    }
    let dependency_batch_count = page
        .dependency_batch_ranges
        .iter()
        .fold(0usize, |count, range| {
            count.saturating_add(range.batch_count)
        });
    if page.dependency_batch_count != dependency_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependency range page {} for batch {} records {} dependency batches but ranges sum to {}",
            page.page_index, page.batch_index, page.dependency_batch_count, dependency_batch_count
        )));
    }
    let dependency = SourcePackJobBatchDependency {
        batch_index: page.batch_index,
        dependency_batch_count: 0,
        dependency_page_count: 0,
        dependency_range_count: 0,
        dependency_range_page_count: 0,
        dependency_range_batch_count: 0,
        dependency_batch_indices: Vec::new(),
        dependency_batch_ranges: page.dependency_batch_ranges.clone(),
    };
    validate_job_batch_dependency_ranges(
        &dependency,
        &BTreeSet::new(),
        &format!(
            "job-batch dependency range page {} for batch {}",
            page.page_index, page.batch_index
        ),
        page.batch_index,
        None,
        |message| artifact_shard_contract_error(message),
    )?;
    Ok(())
}

/// Validates a locator from a scheduled job to its job batch.
pub(in crate::compiler) fn validate_job_batch_locator_page(
    page: &SourcePackBuildJobBatchJobLocatorPage,
    target: SourcePackArtifactTarget,
    scheduled_job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch job-locator page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch job-locator page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded job-batch job-locator page {} but requested job {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= scheduled_job_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch job-locator page {} exceeds scheduled job count {}",
            page.job_index, scheduled_job_count
        )));
    }
    Ok(())
}

/// Validates a persisted dependents page for one job batch.
pub(in crate::compiler) fn validate_job_batch_dependents_page(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_job_batch_dependents_page_with_mode(
        page,
        target,
        batch_count,
        expected_batch_index,
        JobBatchDependentsPageValidationMode::Persisted,
    )
}

/// Validates a dependents page before store-time sidecar expansion.
pub(in crate::compiler) fn validate_job_batch_dependents_page_store_input(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_job_batch_dependents_page_with_mode(
        page,
        target,
        batch_count,
        expected_batch_index,
        JobBatchDependentsPageValidationMode::StoreInput,
    )
}

/// Validation mode for compact persisted dependents pages versus store inputs.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum JobBatchDependentsPageValidationMode {
    /// Validate the compact dependents page that is already persisted.
    Persisted,
    /// Validate caller-provided dependents before sidecar pages are split out.
    StoreInput,
}

/// Validates an inline dependents record count against persisted-page caps.
pub(in crate::compiler) fn validate_job_batch_dependents_inline_record_count(
    page: &SourcePackBuildJobBatchDependentsPage,
    label: &str,
    count: usize,
    cap: usize,
    mode: JobBatchDependentsPageValidationMode,
) -> Result<(), CompileError> {
    if mode == JobBatchDependentsPageValidationMode::Persisted && count > cap {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {} stores {} inline {} records, exceeding record cap {}",
            page.batch_index, count, label, cap
        )));
    }
    Ok(())
}

/// Validates a job-batch dependents page using the requested validation mode.
pub(in crate::compiler) fn validate_job_batch_dependents_page_with_mode(
    page: &SourcePackBuildJobBatchDependentsPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: Option<usize>,
    mode: JobBatchDependentsPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependents page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_count != batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {} has batch count {} but expected {}",
            page.batch_index, page.batch_count, batch_count
        )));
    }
    if let Some(expected_batch_index) = expected_batch_index {
        if page.batch_index != expected_batch_index {
            return Err(artifact_shard_contract_error(format!(
                "loaded job-batch dependents page {} but requested batch {}",
                page.batch_index, expected_batch_index
            )));
        }
    }
    if page.batch_index >= batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {} exceeds batch count {}",
            page.batch_index, batch_count
        )));
    }
    if page.dependents.batch_index != page.batch_index {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {} contains dependent record {}",
            page.batch_index, page.dependents.batch_index
        )));
    }
    validate_job_batch_dependents_inline_record_count(
        page,
        "dependent",
        page.dependents.dependent_batch_indices.len(),
        SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE,
        mode,
    )?;
    unique_usize_set(
        &page.dependents.dependent_batch_indices,
        &format!("job-batch dependents page {} dependents", page.batch_index),
    )?;
    validate_usize_values_strictly_ascending(
        &page.dependents.dependent_batch_indices,
        &format!("job-batch dependents page {} dependents", page.batch_index),
        |message| artifact_shard_contract_error(message),
    )?;
    for &dependent_batch_index in &page.dependents.dependent_batch_indices {
        if dependent_batch_index >= batch_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependents page {} references missing dependent batch {}",
                page.batch_index, dependent_batch_index
            )));
        }
        if dependent_batch_index <= page.batch_index {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependents page {} has non-later dependent batch {}",
                page.batch_index, dependent_batch_index
            )));
        }
    }
    if !page.dependents.dependent_batch_indices.is_empty() && page.dependent_batch_count != 0 {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependents page {} records both inline and paged dependents",
            page.batch_index
        )));
    }
    if page.dependent_batch_count == 0 {
        if page.dependent_page_count != 0 {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependents page {} has dependent page count {} without dependents",
                page.batch_index, page.dependent_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependent_batch_count
            .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
        if page.dependent_page_count != expected_page_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependents page {} has dependent page count {} but expected {} for {} dependents",
                page.batch_index,
                page.dependent_page_count,
                expected_page_count,
                page.dependent_batch_count
            )));
        }
    }
    Ok(())
}

/// Validates one dependent-batch sidecar page.
pub(in crate::compiler) fn validate_job_batch_dependent_batch_page(
    page: &SourcePackBuildJobBatchDependentBatchPage,
    target: SourcePackArtifactTarget,
    batch_count: usize,
    expected_batch_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack job-batch dependent-batch page version {}; expected {}",
            page.version, SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if page.batch_count != batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} has batch count {} but expected {}",
            page.page_index, page.batch_index, page.batch_count, batch_count
        )));
    }
    if page.batch_index != expected_batch_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependent-batch page for batch {} but requested batch {}",
            page.batch_index, expected_batch_index
        )));
    }
    if page.batch_index >= batch_count {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} exceeds batch count {}",
            page.batch_index, batch_count
        )));
    }
    if page.page_index != expected_page_index {
        return Err(artifact_shard_contract_error(format!(
            "loaded job-batch dependent-batch page {} for batch {} but expected page {}",
            page.page_index, page.batch_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE);
    if page.first_dependent_position != expected_first_position {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} starts at {} but expected {}",
            page.page_index,
            page.batch_index,
            page.first_dependent_position,
            expected_first_position
        )));
    }
    if page.dependent_count != page.dependent_batch_indices.len() {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} records {} dependents but stores {}",
            page.page_index,
            page.batch_index,
            page.dependent_count,
            page.dependent_batch_indices.len()
        )));
    }
    if page.dependent_count == 0
        || page.dependent_count > SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE
    {
        return Err(artifact_shard_contract_error(format!(
            "job-batch dependent-batch page {} for batch {} has invalid dependent count {}",
            page.page_index, page.batch_index, page.dependent_count
        )));
    }
    unique_usize_set(
        &page.dependent_batch_indices,
        &format!(
            "job-batch dependent-batch page {} for batch {} dependents",
            page.page_index, page.batch_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &page.dependent_batch_indices,
        &format!(
            "job-batch dependent-batch page {} for batch {} dependents",
            page.page_index, page.batch_index
        ),
        |message| artifact_shard_contract_error(message),
    )?;
    for &dependent_batch_index in &page.dependent_batch_indices {
        if dependent_batch_index >= batch_count {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependent-batch page {} for batch {} references missing dependent batch {}",
                page.page_index, page.batch_index, dependent_batch_index
            )));
        }
        if dependent_batch_index <= page.batch_index {
            return Err(artifact_shard_contract_error(format!(
                "job-batch dependent-batch page {} for batch {} has non-later dependent batch {}",
                page.page_index, page.batch_index, dependent_batch_index
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn inline_dependents_page(
        dependent_batch_indices: Vec<usize>,
    ) -> SourcePackBuildJobBatchDependentsPage {
        SourcePackBuildJobBatchDependentsPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            batch_count: 4,
            batch_index: 1,
            dependents: SourcePackJobBatchDependents {
                batch_index: 1,
                dependent_batch_indices,
            },
            dependent_batch_count: 0,
            dependent_page_count: 0,
        }
    }

    fn dependent_batch_page(
        dependent_batch_indices: Vec<usize>,
    ) -> SourcePackBuildJobBatchDependentBatchPage {
        SourcePackBuildJobBatchDependentBatchPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            batch_count: 4,
            batch_index: 1,
            page_index: 0,
            first_dependent_position: 0,
            dependent_count: dependent_batch_indices.len(),
            dependent_batch_indices,
        }
    }

    fn dependency_page(
        dependency_batch_indices: Vec<usize>,
    ) -> SourcePackBuildJobBatchDependencyPage {
        SourcePackBuildJobBatchDependencyPage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            batch_index: 1,
            page_index: 0,
            first_dependency_position: 0,
            dependency_count: dependency_batch_indices.len(),
            dependency_batch_indices,
        }
    }

    fn dependency_range_page(
        dependency_batch_ranges: Vec<SourcePackJobBatchDependencyRange>,
    ) -> SourcePackBuildJobBatchDependencyRangePage {
        let dependency_batch_count = dependency_batch_ranges
            .iter()
            .map(|range| range.batch_count)
            .sum();
        SourcePackBuildJobBatchDependencyRangePage {
            version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            batch_index: 1,
            page_index: 0,
            first_range_position: 0,
            range_count: dependency_batch_ranges.len(),
            dependency_batch_count,
            dependency_batch_ranges,
        }
    }

    #[test]
    fn job_batch_dependents_must_reference_later_batches() {
        validate_job_batch_dependents_page(
            &inline_dependents_page(vec![2, 3]),
            SourcePackArtifactTarget::Generic,
            4,
            Some(1),
        )
        .expect("later inline dependents should validate");

        assert!(
            validate_job_batch_dependents_page(
                &inline_dependents_page(vec![0]),
                SourcePackArtifactTarget::Generic,
                4,
                Some(1),
            )
            .is_err(),
            "inline dependents must not point back to already prior batches"
        );

        validate_job_batch_dependent_batch_page(
            &dependent_batch_page(vec![2, 3]),
            SourcePackArtifactTarget::Generic,
            4,
            1,
            0,
        )
        .expect("later paged dependents should validate");

        assert!(
            validate_job_batch_dependent_batch_page(
                &dependent_batch_page(vec![1]),
                SourcePackArtifactTarget::Generic,
                4,
                1,
                0,
            )
            .is_err(),
            "paged dependents must not point to their own batch"
        );
    }

    #[test]
    fn job_batch_sidecar_pages_reject_empty_records() {
        validate_job_batch_dependency_page(
            &dependency_page(vec![0]),
            SourcePackArtifactTarget::Generic,
            1,
            0,
        )
        .expect("non-empty dependency sidecar pages should validate");

        assert!(
            validate_job_batch_dependency_page(
                &dependency_page(Vec::new()),
                SourcePackArtifactTarget::Generic,
                1,
                0,
            )
            .is_err(),
            "dependency sidecar pages must carry at least one record"
        );

        validate_job_batch_dependency_range_page(
            &dependency_range_page(vec![SourcePackJobBatchDependencyRange {
                first_batch_index: 0,
                batch_count: 1,
            }]),
            SourcePackArtifactTarget::Generic,
            1,
            0,
        )
        .expect("non-empty dependency-range sidecar pages should validate");

        assert!(
            validate_job_batch_dependency_range_page(
                &dependency_range_page(Vec::new()),
                SourcePackArtifactTarget::Generic,
                1,
                0,
            )
            .is_err(),
            "dependency-range sidecar pages must carry at least one record"
        );

        validate_job_batch_dependent_batch_page(
            &dependent_batch_page(vec![2]),
            SourcePackArtifactTarget::Generic,
            4,
            1,
            0,
        )
        .expect("non-empty dependent-batch sidecar pages should validate");

        assert!(
            validate_job_batch_dependent_batch_page(
                &dependent_batch_page(Vec::new()),
                SourcePackArtifactTarget::Generic,
                4,
                1,
                0,
            )
            .is_err(),
            "dependent-batch sidecar pages must carry at least one record"
        );
    }
}
