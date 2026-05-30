// src/compiler/work_queue_progress/validation.rs

use super::*;

pub(in crate::compiler) fn progress_expected_page_shape(
    index: &SourcePackWorkQueueProgressIndex,
    page_index: usize,
) -> Result<(usize, usize), CompileError> {
    if page_index >= index.page_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {page_index} exceeds page count {}",
            index.page_count
        )));
    }
    let first_item_index = page_index.checked_mul(index.page_size).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue progress page {page_index} start index overflows"
        ))
    })?;
    if first_item_index > index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {page_index} starts past work item count {}",
            index.work_item_count
        )));
    }
    let item_count = index
        .page_size
        .min(index.work_item_count - first_item_index);
    Ok((first_item_index, item_count))
}

pub(in crate::compiler) fn validate_progress_directory_page(
    page: &SourcePackWorkQueueProgressDirectoryPage,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress directory page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} target {:?} does not match requested target {:?}",
            page.directory_page_index, page.target, target
        )));
    }
    let (expected_first, expected_count) =
        progress_directory_page_range(index, page.directory_page_index)?;
    if page.first_progress_page_index != expected_first
        || page.progress_page_count != expected_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} covers {}..{} but expected {}..{}",
            page.directory_page_index,
            page.first_progress_page_index,
            page.first_progress_page_index
                .saturating_add(page.progress_page_count),
            expected_first,
            expected_first.saturating_add(expected_count)
        )));
    }
    if page.ready_artifact_page_count > page.ready_page_count
        || page.ready_page_count > page.progress_page_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} has invalid ready page counts {}/{} for {} progress pages",
            page.directory_page_index,
            page.ready_page_count,
            page.ready_artifact_page_count,
            page.progress_page_count
        )));
    }
    if page.ready_claimed_page_count > page.ready_page_count
        || page.ready_artifact_claimed_page_count > page.ready_artifact_page_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} has invalid ready-claimed page counts {}/{} for ready page counts {}/{}",
            page.directory_page_index,
            page.ready_claimed_page_count,
            page.ready_artifact_claimed_page_count,
            page.ready_page_count,
            page.ready_artifact_page_count
        )));
    }
    if page.ready_claimed_page_count == 0
        && page.ready_artifact_claimed_page_count == 0
        && page.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} has no ready-claimed pages but an earliest claim lease {:?}",
            page.directory_page_index, page.earliest_claim_lease_expires_unix_nanos
        )));
    }
    let page_end = page
        .first_progress_page_index
        .saturating_add(page.progress_page_count);
    if let Some(first_ready_page_index) = page.first_ready_page_index {
        if page.ready_page_count == 0
            || first_ready_page_index < page.first_progress_page_index
            || first_ready_page_index >= page_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress directory page {} has invalid first ready page {:?}",
                page.directory_page_index, page.first_ready_page_index
            )));
        }
    } else if page.ready_page_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} has {} ready pages but no first ready page",
            page.directory_page_index, page.ready_page_count
        )));
    }
    if let Some(first_ready_artifact_page_index) = page.first_ready_artifact_page_index {
        if page.ready_artifact_page_count == 0
            || first_ready_artifact_page_index < page.first_progress_page_index
            || first_ready_artifact_page_index >= page_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress directory page {} has invalid first ready artifact page {:?}",
                page.directory_page_index, page.first_ready_artifact_page_index
            )));
        }
    } else if page.ready_artifact_page_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {} has {} ready artifact pages but no first ready artifact page",
            page.directory_page_index, page.ready_artifact_page_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_progress_directory_index_page(
    page: &SourcePackWorkQueueProgressDirectoryIndexPage,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress directory-index page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} target {:?} does not match requested target {:?}",
            page.directory_index_page_index, page.target, target
        )));
    }
    let (expected_first, expected_count) =
        progress_directory_index_page_range(index, page.directory_index_page_index)?;
    if page.first_directory_page_index != expected_first
        || page.directory_page_count != expected_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} covers directory pages {}..{} but expected {}..{}",
            page.directory_index_page_index,
            page.first_directory_page_index,
            page.first_directory_page_index
                .saturating_add(page.directory_page_count),
            expected_first,
            expected_first.saturating_add(expected_count)
        )));
    }
    if page.ready_artifact_directory_page_count > page.ready_directory_page_count
        || page.ready_directory_page_count > page.directory_page_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} has invalid ready directory counts {}/{} for {} directory pages",
            page.directory_index_page_index,
            page.ready_directory_page_count,
            page.ready_artifact_directory_page_count,
            page.directory_page_count
        )));
    }
    if page.ready_claimed_directory_page_count > page.ready_directory_page_count
        || page.ready_artifact_claimed_directory_page_count
            > page.ready_artifact_directory_page_count
        || page.fully_claimed_ready_directory_page_count > page.ready_claimed_directory_page_count
        || page.fully_claimed_ready_artifact_directory_page_count
            > page.ready_artifact_claimed_directory_page_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} has invalid ready-claimed directory counts {}/{} and fully claimed counts {}/{} for ready directory counts {}/{}",
            page.directory_index_page_index,
            page.ready_claimed_directory_page_count,
            page.ready_artifact_claimed_directory_page_count,
            page.fully_claimed_ready_directory_page_count,
            page.fully_claimed_ready_artifact_directory_page_count,
            page.ready_directory_page_count,
            page.ready_artifact_directory_page_count
        )));
    }
    if page.ready_claimed_directory_page_count == 0
        && page.ready_artifact_claimed_directory_page_count == 0
        && page.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} has no ready-claimed directory pages but an earliest claim lease {:?}",
            page.directory_index_page_index, page.earliest_claim_lease_expires_unix_nanos
        )));
    }
    let directory_end = page
        .first_directory_page_index
        .saturating_add(page.directory_page_count);
    if let Some(first_ready_directory_page_index) = page.first_ready_directory_page_index {
        if page.ready_directory_page_count == 0
            || first_ready_directory_page_index < page.first_directory_page_index
            || first_ready_directory_page_index >= directory_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress directory-index page {} has invalid first ready directory page {:?}",
                page.directory_index_page_index, page.first_ready_directory_page_index
            )));
        }
    } else if page.ready_directory_page_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} has {} ready directory pages but no first ready directory page",
            page.directory_index_page_index, page.ready_directory_page_count
        )));
    }
    if let Some(first_ready_artifact_directory_page_index) =
        page.first_ready_artifact_directory_page_index
    {
        if page.ready_artifact_directory_page_count == 0
            || first_ready_artifact_directory_page_index < page.first_directory_page_index
            || first_ready_artifact_directory_page_index >= directory_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress directory-index page {} has invalid first ready artifact directory page {:?}",
                page.directory_index_page_index, page.first_ready_artifact_directory_page_index
            )));
        }
    } else if page.ready_artifact_directory_page_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {} has {} ready artifact directory pages but no first ready artifact directory page",
            page.directory_index_page_index, page.ready_artifact_directory_page_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn progress_validate_page_summary_shape(
    index: &SourcePackWorkQueueProgressIndex,
    summary: &SourcePackWorkQueueProgressPageSummary,
) -> Result<(), CompileError> {
    let (expected_first_item_index, expected_item_count) =
        progress_expected_page_shape(index, summary.page_index)?;
    if summary.first_item_index != expected_first_item_index {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} starts at {}, expected {}",
            summary.page_index, summary.first_item_index, expected_first_item_index
        )));
    }
    if summary.item_count != expected_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} has item_count {}, expected {}",
            summary.page_index, summary.item_count, expected_item_count
        )));
    }
    if summary.ready_claimed_item_count > summary.ready_item_count
        || summary.ready_claimed_item_count > summary.claimed_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} has ready-claimed count {} for ready/claimed counts {}/{}",
            summary.page_index,
            summary.ready_claimed_item_count,
            summary.ready_item_count,
            summary.claimed_item_count
        )));
    }
    if let Some(first_ready_item_index) = summary.first_ready_item_index {
        let item_end = summary
            .first_item_index
            .checked_add(summary.item_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue progress summary page {} item range overflows",
                    summary.page_index
                ))
            })?;
        if summary.ready_item_count == 0
            || first_ready_item_index < summary.first_item_index
            || first_ready_item_index >= item_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress summary page {} has invalid first ready item {:?}",
                summary.page_index, summary.first_ready_item_index
            )));
        }
    }
    if summary.artifact_item_count > summary.item_count
        || summary.ready_artifact_item_count > summary.ready_item_count
        || summary.ready_artifact_item_count > summary.artifact_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} has artifact/ready-artifact counts {}/{} for item/ready counts {}/{}",
            summary.page_index,
            summary.artifact_item_count,
            summary.ready_artifact_item_count,
            summary.item_count,
            summary.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = summary.first_ready_artifact_item_index {
        let item_end = summary
            .first_item_index
            .checked_add(summary.item_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue progress summary page {} item range overflows",
                    summary.page_index
                ))
            })?;
        if summary.ready_artifact_item_count == 0
            || first_ready_artifact_item_index < summary.first_item_index
            || first_ready_artifact_item_index >= item_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress summary page {} has invalid first ready artifact item {:?}",
                summary.page_index, summary.first_ready_artifact_item_index
            )));
        }
    }
    if summary.ready_artifact_claimed_item_count > summary.ready_artifact_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_claimed_item_count
        || summary.ready_artifact_claimed_item_count > summary.claimed_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} has ready-artifact-claimed count {} for ready-artifact/ready-claimed/claimed counts {}/{}/{}",
            summary.page_index,
            summary.ready_artifact_claimed_item_count,
            summary.ready_artifact_item_count,
            summary.ready_claimed_item_count,
            summary.claimed_item_count
        )));
    }
    if summary
        .completed_item_count
        .saturating_add(summary.ready_item_count)
        .saturating_add(summary.blocked_item_count)
        > summary.item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} accounts for completed/ready/blocked counts {}/{}/{} but only has {} items",
            summary.page_index,
            summary.completed_item_count,
            summary.ready_item_count,
            summary.blocked_item_count,
            summary.item_count
        )));
    }
    if summary.pending_dependent_item_count > summary.item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress summary page {} has {} pending-dependent counters but only {} items",
            summary.page_index, summary.pending_dependent_item_count, summary.item_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_progress_index(
    index: &SourcePackWorkQueueProgressIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress index version {}; expected {}",
            index.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue progress index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.page_size == 0 {
        return Err(library_partition_contract_error(
            "work queue progress index page_size is zero",
        ));
    }
    if index.page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress index page_size {} exceeds record cap {}",
            index.page_size, SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let expected_page_count = index.work_item_count.div_ceil(index.page_size);
    if index.page_count != expected_page_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page count {} expected {}",
            index.page_count, expected_page_count
        )));
    }
    if index.artifact_item_count > index.work_item_count
        || index.completed_item_count > index.work_item_count
        || index.ready_item_count > index.work_item_count
        || index.ready_artifact_item_count > index.ready_item_count
        || index.ready_artifact_item_count > index.artifact_item_count
        || index.claimed_item_count > index.work_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress counts exceed work item count {}",
            index.work_item_count
        )));
    }
    if index
        .completed_item_count
        .checked_add(index.ready_item_count)
        .map_or(true, |accounted_item_count| {
            accounted_item_count > index.work_item_count
        })
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress index accounts for completed/ready counts {}/{} but only has {} items",
            index.completed_item_count, index.ready_item_count, index.work_item_count
        )));
    }
    if index.completed_item_count == index.work_item_count
        && (index.ready_item_count != 0
            || index.ready_artifact_item_count != 0
            || index.claimed_item_count != 0)
    {
        return Err(library_partition_contract_error(format!(
            "complete work queue progress index must not advertise ready or claimed work; ready={}, ready_artifact={}, claimed={}",
            index.ready_item_count, index.ready_artifact_item_count, index.claimed_item_count
        )));
    }
    if let Some(first_ready_item_index) = index.first_ready_item_index {
        if first_ready_item_index >= index.work_item_count || index.ready_item_count == 0 {
            return Err(library_partition_contract_error(format!(
                "work queue progress first ready item {first_ready_item_index} is invalid"
            )));
        }
    } else if index.ready_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress has {} ready items but no first ready item",
            index.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = index.first_ready_artifact_item_index {
        if first_ready_artifact_item_index >= index.work_item_count
            || index.ready_artifact_item_count == 0
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress first ready artifact item {first_ready_artifact_item_index} is invalid"
            )));
        }
    } else if index.ready_artifact_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress has {} ready artifact items but no first ready artifact item",
            index.ready_artifact_item_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_progress_page_record_count(
    page_index: usize,
    label: &str,
    count: usize,
    item_count: usize,
) -> Result<(), CompileError> {
    if count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {page_index} has {count} {label} records but the record cap is {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    if count > item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {page_index} has {count} {label} records but only {item_count} items"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_progress_page(
    page: &SourcePackWorkQueueProgressPage,
    target: SourcePackArtifactTarget,
    expected_page_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} target {:?} does not match requested target {:?}",
            page.page_index, page.target, target
        )));
    }
    if let Some(expected_page_index) = expected_page_index {
        if page.page_index != expected_page_index {
            return Err(library_partition_contract_error(format!(
                "loaded work queue progress page {} but expected {}",
                page.page_index, expected_page_index
            )));
        }
    }
    if page.item_count == 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} has no items",
            page.page_index
        )));
    }
    if page.item_count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} has {} items but the record cap is {}",
            page.page_index, page.item_count, SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    validate_progress_page_record_count(
        page.page_index,
        "artifact-item",
        page.artifact_item_indices.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "remaining-dependency",
        page.remaining_dependency_counts.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "remaining-dependent",
        page.remaining_dependent_counts.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "completed-item",
        page.completed_item_indices.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "ready-item",
        page.ready_item_indices.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "ready-artifact-item",
        page.ready_artifact_item_indices.len(),
        page.item_count,
    )?;
    validate_progress_page_record_count(
        page.page_index,
        "claim",
        page.claimed_items.len(),
        page.item_count,
    )?;
    let item_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue progress page {} item range overflows",
                page.page_index
            ))
        })?;
    unique_usize_set(
        &page.artifact_item_indices,
        &format!(
            "work queue progress page {} artifact items",
            page.page_index
        ),
    )?;
    unique_usize_set(
        &page.completed_item_indices,
        &format!(
            "work queue progress page {} completed items",
            page.page_index
        ),
    )?;
    unique_usize_set(
        &page.ready_item_indices,
        &format!("work queue progress page {} ready items", page.page_index),
    )?;
    unique_usize_set(
        &page.ready_artifact_item_indices,
        &format!(
            "work queue progress page {} ready artifact items",
            page.page_index
        ),
    )?;
    let artifact = page
        .artifact_item_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let completed = page
        .completed_item_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let ready = page
        .ready_item_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let ready_artifact = page
        .ready_artifact_item_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let mut remaining_dependency_items = BTreeSet::new();
    for remaining in &page.remaining_dependency_counts {
        if remaining.remaining_dependency_count == 0 {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} stores zero remaining dependencies for item {}",
                page.page_index, remaining.item_index
            )));
        }
        if remaining.item_index < page.first_item_index || remaining.item_index >= item_end {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} stores remaining dependencies for item {} outside range {}..{}",
                page.page_index, remaining.item_index, page.first_item_index, item_end
            )));
        }
        if !remaining_dependency_items.insert(remaining.item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} contains duplicate remaining dependency counter for item {}",
                page.page_index, remaining.item_index
            )));
        }
    }
    let mut remaining_dependent_items = BTreeSet::new();
    for remaining in &page.remaining_dependent_counts {
        if remaining.remaining_dependent_count == 0 {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} stores zero remaining dependents for item {}",
                page.page_index, remaining.item_index
            )));
        }
        if remaining.item_index < page.first_item_index || remaining.item_index >= item_end {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} stores remaining dependents for item {} outside range {}..{}",
                page.page_index, remaining.item_index, page.first_item_index, item_end
            )));
        }
        if !remaining_dependent_items.insert(remaining.item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} contains duplicate remaining dependent counter for item {}",
                page.page_index, remaining.item_index
            )));
        }
    }
    for &item_index in artifact
        .iter()
        .chain(completed.iter())
        .chain(ready.iter())
        .chain(ready_artifact.iter())
    {
        if item_index < page.first_item_index || item_index >= item_end {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} contains item {} outside range {}..{}",
                page.page_index, item_index, page.first_item_index, item_end
            )));
        }
    }
    for item_index in ready_artifact.difference(&artifact) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} marks non-artifact item {} ready-artifact",
            page.page_index, item_index
        )));
    }
    for item_index in ready_artifact.difference(&ready) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} marks non-ready item {} ready-artifact",
            page.page_index, item_index
        )));
    }
    for item_index in completed.intersection(&ready) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} marks completed item {} ready",
            page.page_index, item_index
        )));
    }
    for item_index in completed.union(&ready) {
        if remaining_dependency_items.contains(item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} stores remaining dependencies for non-blocked item {}",
                page.page_index, item_index
            )));
        }
    }
    if completed
        .len()
        .saturating_add(ready.len())
        .saturating_add(remaining_dependency_items.len())
        > page.item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} accounts for too many completed/ready/blocked items",
            page.page_index
        )));
    }
    let mut seen_claims = BTreeSet::new();
    for claim in &page.claimed_items {
        if claim.item_index < page.first_item_index || claim.item_index >= item_end {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} claims item {} outside range {}..{}",
                page.page_index, claim.item_index, page.first_item_index, item_end
            )));
        }
        if claim.worker_id.trim().is_empty() {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} has empty claim worker for item {}",
                page.page_index, claim.item_index
            )));
        }
        if completed.contains(&claim.item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} claims completed item {}",
                page.page_index, claim.item_index
            )));
        }
        if !ready.contains(&claim.item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} claims non-ready item {}",
                page.page_index, claim.item_index
            )));
        }
        if !seen_claims.insert(claim.item_index) {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {} contains duplicate claim for item {}",
                page.page_index, claim.item_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_progress_page_summary(
    summary: &SourcePackWorkQueueProgressPageSummary,
) -> Result<(), CompileError> {
    if summary.item_count == 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has no items",
            summary.page_index
        )));
    }
    if summary.item_count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has {} items but the record cap is {}",
            summary.page_index,
            summary.item_count,
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    for (label, count) in [
        ("artifact-item", summary.artifact_item_count),
        ("completed-item", summary.completed_item_count),
        ("ready-item", summary.ready_item_count),
        ("ready-artifact-item", summary.ready_artifact_item_count),
        ("blocked-item", summary.blocked_item_count),
        (
            "pending-dependent-item",
            summary.pending_dependent_item_count,
        ),
        ("claim", summary.claimed_item_count),
        ("ready-claim", summary.ready_claimed_item_count),
        (
            "ready-artifact-claim",
            summary.ready_artifact_claimed_item_count,
        ),
    ] {
        validate_progress_page_record_count(summary.page_index, label, count, summary.item_count)?;
    }
    if summary.ready_artifact_item_count > summary.ready_item_count
        || summary.ready_artifact_item_count > summary.artifact_item_count
        || summary.ready_claimed_item_count > summary.ready_item_count
        || summary.ready_claimed_item_count > summary.claimed_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_artifact_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_claimed_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has inconsistent ready/artifact/claim counts",
            summary.page_index
        )));
    }
    if summary.claimed_item_count != summary.ready_claimed_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has {} claims but only {} ready claims; progress claims must refer to ready items",
            summary.page_index, summary.claimed_item_count, summary.ready_claimed_item_count
        )));
    }
    if summary
        .completed_item_count
        .saturating_add(summary.ready_item_count)
        .saturating_add(summary.blocked_item_count)
        > summary.item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} accounts for too many completed/ready/blocked items",
            summary.page_index
        )));
    }
    let item_end = summary
        .first_item_index
        .checked_add(summary.item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue progress page summary {} item range overflows",
                summary.page_index
            ))
        })?;
    if let Some(first_ready_item_index) = summary.first_ready_item_index {
        if summary.ready_item_count == 0
            || first_ready_item_index < summary.first_item_index
            || first_ready_item_index >= item_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress page summary {} has invalid first ready item {:?}",
                summary.page_index, summary.first_ready_item_index
            )));
        }
    } else if summary.ready_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has {} ready items but no first ready item",
            summary.page_index, summary.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = summary.first_ready_artifact_item_index {
        if summary.ready_artifact_item_count == 0
            || first_ready_artifact_item_index < summary.first_item_index
            || first_ready_artifact_item_index >= item_end
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress page summary {} has invalid first ready artifact item {:?}",
                summary.page_index, summary.first_ready_artifact_item_index
            )));
        }
    } else if summary.ready_artifact_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has {} ready artifact items but no first ready artifact item",
            summary.page_index, summary.ready_artifact_item_count
        )));
    }
    if summary.ready_claimed_item_count == 0
        && summary.ready_artifact_claimed_item_count == 0
        && summary.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress page summary {} has no ready claims but an earliest claim lease {:?}",
            summary.page_index, summary.earliest_claim_lease_expires_unix_nanos
        )));
    }
    Ok(())
}
