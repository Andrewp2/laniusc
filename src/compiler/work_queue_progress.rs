use super::*;

pub(super) fn source_pack_work_queue_progress_page_summary(
    page: &SourcePackWorkQueueProgressPage,
) -> SourcePackWorkQueueProgressPageSummary {
    let mut ready_claimed_item_count = 0usize;
    let mut ready_artifact_claimed_item_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    for claim in &page.claimed_items {
        if !page.ready_item_indices.contains(&claim.item_index) {
            continue;
        }
        ready_claimed_item_count = ready_claimed_item_count.saturating_add(1);
        if page.ready_artifact_item_indices.contains(&claim.item_index) {
            ready_artifact_claimed_item_count = ready_artifact_claimed_item_count.saturating_add(1);
        }
        if let Some(expires) = claim.lease_expires_unix_nanos {
            earliest_claim_lease_expires_unix_nanos = Some(
                earliest_claim_lease_expires_unix_nanos
                    .map_or(expires, |earliest| expires.min(earliest)),
            );
        }
    }
    SourcePackWorkQueueProgressPageSummary {
        page_index: page.page_index,
        first_item_index: page.first_item_index,
        item_count: page.item_count,
        artifact_item_count: page.artifact_item_indices.len(),
        completed_item_count: page.completed_item_indices.len(),
        ready_item_count: page.ready_item_indices.len(),
        first_ready_item_index: page.ready_item_indices.iter().copied().min(),
        ready_artifact_item_count: page.ready_artifact_item_indices.len(),
        first_ready_artifact_item_index: page.ready_artifact_item_indices.iter().copied().min(),
        blocked_item_count: page.remaining_dependency_counts.len(),
        pending_dependent_item_count: page.remaining_dependent_counts.len(),
        claimed_item_count: page.claimed_items.len(),
        ready_claimed_item_count,
        ready_artifact_claimed_item_count,
        earliest_claim_lease_expires_unix_nanos,
    }
}

pub(super) fn source_pack_work_queue_progress_page_ready_items_are_claimed(
    summary: &SourcePackWorkQueueProgressPageSummary,
    now_unix_nanos: Option<u128>,
) -> bool {
    if summary.ready_item_count == 0 || summary.ready_claimed_item_count < summary.ready_item_count
    {
        return false;
    }
    match (
        now_unix_nanos,
        summary.earliest_claim_lease_expires_unix_nanos,
    ) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_page_ready_artifact_items_are_claimed(
    summary: &SourcePackWorkQueueProgressPageSummary,
    now_unix_nanos: Option<u128>,
) -> bool {
    if summary.ready_artifact_item_count == 0
        || summary.ready_artifact_claimed_item_count < summary.ready_artifact_item_count
    {
        return false;
    }
    match (
        now_unix_nanos,
        summary.earliest_claim_lease_expires_unix_nanos,
    ) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_directory_ready_pages_are_claimed(
    page: &SourcePackWorkQueueProgressDirectoryPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_page_count == 0 || page.ready_claimed_page_count < page.ready_page_count {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_directory_ready_artifact_pages_are_claimed(
    page: &SourcePackWorkQueueProgressDirectoryPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_artifact_page_count == 0
        || page.ready_artifact_claimed_page_count < page.ready_artifact_page_count
    {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_directory_index_ready_pages_are_claimed(
    page: &SourcePackWorkQueueProgressDirectoryIndexPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_directory_page_count == 0
        || page.fully_claimed_ready_directory_page_count < page.ready_directory_page_count
    {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_directory_index_ready_artifact_pages_are_claimed(
    page: &SourcePackWorkQueueProgressDirectoryIndexPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    if page.ready_artifact_directory_page_count == 0
        || page.fully_claimed_ready_artifact_directory_page_count
            < page.ready_artifact_directory_page_count
    {
        return false;
    }
    match (now_unix_nanos, page.earliest_claim_lease_expires_unix_nanos) {
        (Some(now), Some(expires)) => now < expires,
        _ => true,
    }
}

pub(super) fn source_pack_work_queue_progress_expected_page_shape(
    index: &SourcePackWorkQueueProgressIndex,
    page_index: usize,
) -> Result<(usize, usize), CompileError> {
    if page_index >= index.page_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} exceeds page count {}",
            index.page_count
        )));
    }
    let first_item_index = page_index.checked_mul(index.page_size).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} start index overflows"
        ))
    })?;
    if first_item_index > index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} starts past work item count {}",
            index.work_item_count
        )));
    }
    let item_count = index
        .page_size
        .min(index.work_item_count - first_item_index);
    Ok((first_item_index, item_count))
}

pub(super) fn source_pack_work_queue_progress_directory_page_index_for_progress_page(
    progress_page_index: usize,
) -> usize {
    progress_page_index / SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
}

pub(super) fn source_pack_work_queue_progress_directory_page_count(
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_progress_index(index, index.target)?;
    Ok(index
        .page_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE))
}

pub(super) fn source_pack_work_queue_progress_directory_page_range(
    index: &SourcePackWorkQueueProgressIndex,
    directory_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    let first_progress_page_index = directory_page_index
        .checked_mul(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress directory page {directory_page_index} start overflows"
            ))
        })?;
    if first_progress_page_index >= index.page_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory page {directory_page_index} starts at page {first_progress_page_index} but page_count is {}",
            index.page_count
        )));
    }
    let progress_page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
        .min(index.page_count - first_progress_page_index);
    Ok((first_progress_page_index, progress_page_count))
}

pub(super) fn validate_source_pack_work_queue_progress_directory_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory page {} target {:?} does not match requested target {:?}",
            page.directory_page_index, page.target, target
        )));
    }
    let (expected_first, expected_count) =
        source_pack_work_queue_progress_directory_page_range(index, page.directory_page_index)?;
    if page.first_progress_page_index != expected_first
        || page.progress_page_count != expected_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress directory page {} has invalid first ready page {:?}",
                page.directory_page_index, page.first_ready_page_index
            )));
        }
    } else if page.ready_page_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory page {} has {} ready pages but no first ready page",
            page.directory_page_index, page.ready_page_count
        )));
    }
    if let Some(first_ready_artifact_page_index) = page.first_ready_artifact_page_index {
        if page.ready_artifact_page_count == 0
            || first_ready_artifact_page_index < page.first_progress_page_index
            || first_ready_artifact_page_index >= page_end
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress directory page {} has invalid first ready artifact page {:?}",
                page.directory_page_index, page.first_ready_artifact_page_index
            )));
        }
    } else if page.ready_artifact_page_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory page {} has {} ready artifact pages but no first ready artifact page",
            page.directory_page_index, page.ready_artifact_page_count
        )));
    }
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_directory_index_page_index_for_directory_page(
    directory_page_index: usize,
) -> usize {
    directory_page_index / SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
}

pub(super) fn source_pack_work_queue_progress_directory_index_page_count(
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<usize, CompileError> {
    let directory_page_count = source_pack_work_queue_progress_directory_page_count(index)?;
    Ok(directory_page_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE))
}

pub(super) fn source_pack_work_queue_progress_directory_index_page_range(
    index: &SourcePackWorkQueueProgressIndex,
    directory_index_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    let directory_page_count = source_pack_work_queue_progress_directory_page_count(index)?;
    let first_directory_page_index = directory_index_page_index
        .checked_mul(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress directory-index page {directory_index_page_index} start overflows"
            ))
        })?;
    if first_directory_page_index >= directory_page_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory-index page {directory_index_page_index} starts at directory page {first_directory_page_index} but directory page count is {directory_page_count}"
        )));
    }
    let directory_page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
        .min(directory_page_count - first_directory_page_index);
    Ok((first_directory_page_index, directory_page_count))
}

pub(super) fn validate_source_pack_work_queue_progress_directory_index_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory-index page {} target {:?} does not match requested target {:?}",
            page.directory_index_page_index, page.target, target
        )));
    }
    let (expected_first, expected_count) =
        source_pack_work_queue_progress_directory_index_page_range(
            index,
            page.directory_index_page_index,
        )?;
    if page.first_directory_page_index != expected_first
        || page.directory_page_count != expected_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress directory-index page {} has invalid first ready directory page {:?}",
                page.directory_index_page_index, page.first_ready_directory_page_index
            )));
        }
    } else if page.ready_directory_page_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress directory-index page {} has invalid first ready artifact directory page {:?}",
                page.directory_index_page_index, page.first_ready_artifact_directory_page_index
            )));
        }
    } else if page.ready_artifact_directory_page_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress directory-index page {} has {} ready artifact directory pages but no first ready artifact directory page",
            page.directory_index_page_index, page.ready_artifact_directory_page_count
        )));
    }
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_validate_page_summary_shape(
    index: &SourcePackWorkQueueProgressIndex,
    summary: &SourcePackWorkQueueProgressPageSummary,
) -> Result<(), CompileError> {
    let (expected_first_item_index, expected_item_count) =
        source_pack_work_queue_progress_expected_page_shape(index, summary.page_index)?;
    if summary.first_item_index != expected_first_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress summary page {} starts at {}, expected {}",
            summary.page_index, summary.first_item_index, expected_first_item_index
        )));
    }
    if summary.item_count != expected_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress summary page {} has item_count {}, expected {}",
            summary.page_index, summary.item_count, expected_item_count
        )));
    }
    if summary.ready_claimed_item_count > summary.ready_item_count
        || summary.ready_claimed_item_count > summary.claimed_item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
                source_pack_library_partition_contract_error(format!(
                    "work queue progress summary page {} item range overflows",
                    summary.page_index
                ))
            })?;
        if summary.ready_item_count == 0
            || first_ready_item_index < summary.first_item_index
            || first_ready_item_index >= item_end
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress summary page {} has invalid first ready item {:?}",
                summary.page_index, summary.first_ready_item_index
            )));
        }
    }
    if summary.artifact_item_count > summary.item_count
        || summary.ready_artifact_item_count > summary.ready_item_count
        || summary.ready_artifact_item_count > summary.artifact_item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
                source_pack_library_partition_contract_error(format!(
                    "work queue progress summary page {} item range overflows",
                    summary.page_index
                ))
            })?;
        if summary.ready_artifact_item_count == 0
            || first_ready_artifact_item_index < summary.first_item_index
            || first_ready_artifact_item_index >= item_end
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress summary page {} has invalid first ready artifact item {:?}",
                summary.page_index, summary.first_ready_artifact_item_index
            )));
        }
    }
    if summary.ready_artifact_claimed_item_count > summary.ready_artifact_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_claimed_item_count
        || summary.ready_artifact_claimed_item_count > summary.claimed_item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress summary page {} accounts for completed/ready/blocked counts {}/{}/{} but only has {} items",
            summary.page_index,
            summary.completed_item_count,
            summary.ready_item_count,
            summary.blocked_item_count,
            summary.item_count
        )));
    }
    if summary.pending_dependent_item_count > summary.item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress summary page {} has {} pending-dependent counters but only {} items",
            summary.page_index, summary.pending_dependent_item_count, summary.item_count
        )));
    }
    Ok(())
}

pub(super) fn validate_source_pack_work_queue_progress_index(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.page_size == 0 {
        return Err(source_pack_library_partition_contract_error(
            "work queue progress index page_size is zero",
        ));
    }
    if index.page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress index page_size {} exceeds record cap {}",
            index.page_size, SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let expected_page_count = index.work_item_count.div_ceil(index.page_size);
    if index.page_count != expected_page_count {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress counts exceed work item count {}",
            index.work_item_count
        )));
    }
    if let Some(first_ready_item_index) = index.first_ready_item_index {
        if first_ready_item_index >= index.work_item_count || index.ready_item_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress first ready item {first_ready_item_index} is invalid"
            )));
        }
    } else if index.ready_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress has {} ready items but no first ready item",
            index.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = index.first_ready_artifact_item_index {
        if first_ready_artifact_item_index >= index.work_item_count
            || index.ready_artifact_item_count == 0
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress first ready artifact item {first_ready_artifact_item_index} is invalid"
            )));
        }
    } else if index.ready_artifact_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress has {} ready artifact items but no first ready artifact item",
            index.ready_artifact_item_count
        )));
    }
    Ok(())
}

pub(super) fn validate_source_pack_work_queue_progress_page_record_count(
    page_index: usize,
    label: &str,
    count: usize,
    item_count: usize,
) -> Result<(), CompileError> {
    if count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} has {count} {label} records but the record cap is {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    if count > item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} has {count} {label} records but only {item_count} items"
        )));
    }
    Ok(())
}

pub(super) fn validate_source_pack_work_queue_progress_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} target {:?} does not match requested target {:?}",
            page.page_index, page.target, target
        )));
    }
    if let Some(expected_page_index) = expected_page_index {
        if page.page_index != expected_page_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded work queue progress page {} but expected {}",
                page.page_index, expected_page_index
            )));
        }
    }
    if page.item_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} has no items",
            page.page_index
        )));
    }
    if page.item_count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} has {} items but the record cap is {}",
            page.page_index, page.item_count, SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "artifact-item",
        page.artifact_item_indices.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "remaining-dependency",
        page.remaining_dependency_counts.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "remaining-dependent",
        page.remaining_dependent_counts.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "completed-item",
        page.completed_item_indices.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "ready-item",
        page.ready_item_indices.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "ready-artifact-item",
        page.ready_artifact_item_indices.len(),
        page.item_count,
    )?;
    validate_source_pack_work_queue_progress_page_record_count(
        page.page_index,
        "claim",
        page.claimed_items.len(),
        page.item_count,
    )?;
    let item_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress page {} item range overflows",
                page.page_index
            ))
        })?;
    source_pack_manifest_unique_usize_set(
        &page.artifact_item_indices,
        &format!(
            "work queue progress page {} artifact items",
            page.page_index
        ),
    )?;
    source_pack_manifest_unique_usize_set(
        &page.completed_item_indices,
        &format!(
            "work queue progress page {} completed items",
            page.page_index
        ),
    )?;
    source_pack_manifest_unique_usize_set(
        &page.ready_item_indices,
        &format!("work queue progress page {} ready items", page.page_index),
    )?;
    source_pack_manifest_unique_usize_set(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} stores zero remaining dependencies for item {}",
                page.page_index, remaining.item_index
            )));
        }
        if remaining.item_index < page.first_item_index || remaining.item_index >= item_end {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} stores remaining dependencies for item {} outside range {}..{}",
                page.page_index, remaining.item_index, page.first_item_index, item_end
            )));
        }
        if !remaining_dependency_items.insert(remaining.item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} contains duplicate remaining dependency counter for item {}",
                page.page_index, remaining.item_index
            )));
        }
    }
    let mut remaining_dependent_items = BTreeSet::new();
    for remaining in &page.remaining_dependent_counts {
        if remaining.remaining_dependent_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} stores zero remaining dependents for item {}",
                page.page_index, remaining.item_index
            )));
        }
        if remaining.item_index < page.first_item_index || remaining.item_index >= item_end {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} stores remaining dependents for item {} outside range {}..{}",
                page.page_index, remaining.item_index, page.first_item_index, item_end
            )));
        }
        if !remaining_dependent_items.insert(remaining.item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} contains item {} outside range {}..{}",
                page.page_index, item_index, page.first_item_index, item_end
            )));
        }
    }
    for item_index in ready_artifact.difference(&artifact) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} marks non-artifact item {} ready-artifact",
            page.page_index, item_index
        )));
    }
    for item_index in ready_artifact.difference(&ready) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} marks non-ready item {} ready-artifact",
            page.page_index, item_index
        )));
    }
    for item_index in completed.intersection(&ready) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} marks completed item {} ready",
            page.page_index, item_index
        )));
    }
    for item_index in completed.union(&ready) {
        if remaining_dependency_items.contains(item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} accounts for too many completed/ready/blocked items",
            page.page_index
        )));
    }
    let mut seen_claims = BTreeSet::new();
    for claim in &page.claimed_items {
        if claim.item_index < page.first_item_index || claim.item_index >= item_end {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} claims item {} outside range {}..{}",
                page.page_index, claim.item_index, page.first_item_index, item_end
            )));
        }
        if claim.worker_id.trim().is_empty() {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} has empty claim worker for item {}",
                page.page_index, claim.item_index
            )));
        }
        if completed.contains(&claim.item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} claims completed item {}",
                page.page_index, claim.item_index
            )));
        }
        if !ready.contains(&claim.item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} claims non-ready item {}",
                page.page_index, claim.item_index
            )));
        }
        if !seen_claims.insert(claim.item_index) {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page {} contains duplicate claim for item {}",
                page.page_index, claim.item_index
            )));
        }
    }
    Ok(())
}

pub(super) fn validate_source_pack_work_queue_progress_page_summary(
    summary: &SourcePackWorkQueueProgressPageSummary,
) -> Result<(), CompileError> {
    if summary.item_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} has no items",
            summary.page_index
        )));
    }
    if summary.item_count > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
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
        validate_source_pack_work_queue_progress_page_record_count(
            summary.page_index,
            label,
            count,
            summary.item_count,
        )?;
    }
    if summary.ready_artifact_item_count > summary.ready_item_count
        || summary.ready_artifact_item_count > summary.artifact_item_count
        || summary.ready_claimed_item_count > summary.ready_item_count
        || summary.ready_claimed_item_count > summary.claimed_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_artifact_item_count
        || summary.ready_artifact_claimed_item_count > summary.ready_claimed_item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} has inconsistent ready/artifact/claim counts",
            summary.page_index
        )));
    }
    if summary
        .completed_item_count
        .saturating_add(summary.ready_item_count)
        .saturating_add(summary.blocked_item_count)
        > summary.item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} accounts for too many completed/ready/blocked items",
            summary.page_index
        )));
    }
    let item_end = summary
        .first_item_index
        .checked_add(summary.item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress page summary {} item range overflows",
                summary.page_index
            ))
        })?;
    if let Some(first_ready_item_index) = summary.first_ready_item_index {
        if summary.ready_item_count == 0
            || first_ready_item_index < summary.first_item_index
            || first_ready_item_index >= item_end
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page summary {} has invalid first ready item {:?}",
                summary.page_index, summary.first_ready_item_index
            )));
        }
    } else if summary.ready_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} has {} ready items but no first ready item",
            summary.page_index, summary.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = summary.first_ready_artifact_item_index {
        if summary.ready_artifact_item_count == 0
            || first_ready_artifact_item_index < summary.first_item_index
            || first_ready_artifact_item_index >= item_end
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress page summary {} has invalid first ready artifact item {:?}",
                summary.page_index, summary.first_ready_artifact_item_index
            )));
        }
    } else if summary.ready_artifact_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} has {} ready artifact items but no first ready artifact item",
            summary.page_index, summary.ready_artifact_item_count
        )));
    }
    if summary.ready_claimed_item_count == 0
        && summary.ready_artifact_claimed_item_count == 0
        && summary.earliest_claim_lease_expires_unix_nanos.is_some()
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page summary {} has no ready claims but an earliest claim lease {:?}",
            summary.page_index, summary.earliest_claim_lease_expires_unix_nanos
        )));
    }
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_page_contains_item(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    let item_end = page.first_item_index.saturating_add(page.item_count);
    item_index >= page.first_item_index && item_index < item_end
}

pub(super) fn source_pack_work_queue_progress_page_item_is_completed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.completed_item_indices.contains(&item_index)
}

pub(super) fn source_pack_work_queue_progress_page_item_is_ready(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.ready_item_indices.contains(&item_index)
}

pub(super) fn source_pack_work_queue_progress_page_item_is_artifact_backed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.artifact_item_indices.contains(&item_index)
}

pub(super) fn source_pack_work_queue_progress_page_remaining_dependency_count_position(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Option<usize> {
    page.remaining_dependency_counts
        .iter()
        .position(|remaining| remaining.item_index == item_index)
}

pub(super) fn source_pack_work_queue_progress_page_remaining_dependent_count_position(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Option<usize> {
    page.remaining_dependent_counts
        .iter()
        .position(|remaining| remaining.item_index == item_index)
}

pub(super) fn source_pack_work_queue_progress_page_remove_remaining_dependency_count(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    let before = page.remaining_dependency_counts.len();
    page.remaining_dependency_counts
        .retain(|remaining| remaining.item_index != item_index);
    before != page.remaining_dependency_counts.len()
}

pub(super) fn source_pack_work_queue_progress_page_item_has_remaining_dependents(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    source_pack_work_queue_progress_page_remaining_dependent_count_position(page, item_index)
        .is_some()
}

pub(super) fn source_pack_work_queue_progress_page_item_is_claimed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
    now_unix_nanos: Option<u128>,
) -> bool {
    page.claimed_items
        .iter()
        .any(|claim| claim.item_index == item_index && !claim.is_expired(now_unix_nanos))
}

pub(super) fn source_pack_work_queue_progress_page_prune_inactive_claims(
    page: &mut SourcePackWorkQueueProgressPage,
    now_unix_nanos: Option<u128>,
) -> bool {
    let before = page.claimed_items.clone();
    let completed = page
        .completed_item_indices
        .iter()
        .copied()
        .collect::<BTreeSet<_>>();
    let mut seen_item_indices = BTreeSet::new();
    page.claimed_items.retain(|claim| {
        !completed.contains(&claim.item_index)
            && !claim.is_expired(now_unix_nanos)
            && seen_item_indices.insert(claim.item_index)
    });
    page.claimed_items
        .sort_by_key(|claim| (claim.item_index, claim.worker_id.clone()));
    before != page.claimed_items
}

pub(super) fn source_pack_work_queue_progress_page_record_item_claim(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let worker_id = worker_id.into();
    if worker_id.trim().is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-pack work item claim worker id must not be empty".into(),
        ));
    }
    if let (Some(now), Some(expires)) = (now_unix_nanos, lease_expires_unix_nanos) {
        if expires <= now {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack work item {item_index} claim lease expires at {expires}, which is not after now {now}"
            )));
        }
    }
    if !source_pack_work_queue_progress_page_contains_item(page, item_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} cannot claim item {} outside range",
            page.page_index, item_index
        )));
    }
    source_pack_work_queue_progress_page_prune_inactive_claims(page, now_unix_nanos);
    if source_pack_work_queue_progress_page_item_is_completed(page, item_index) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is already complete and cannot be claimed"
        )));
    }
    if !source_pack_work_queue_progress_page_item_is_ready(page, item_index) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is not ready and cannot be claimed"
        )));
    }
    if let Some(claim) = page
        .claimed_items
        .iter()
        .find(|claim| claim.item_index == item_index)
    {
        if claim.worker_id != worker_id {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack work item {item_index} is already claimed by worker {:?}",
                claim.worker_id
            )));
        }
    }
    page.claimed_items
        .retain(|claim| claim.item_index != item_index);
    page.claimed_items.push(SourcePackWorkQueueItemClaim {
        item_index,
        worker_id,
        lease_expires_unix_nanos,
    });
    page.claimed_items
        .sort_by_key(|claim| (claim.item_index, claim.worker_id.clone()));
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_page_require_item_claimed_by(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let Some(claim) = page
        .claimed_items
        .iter()
        .find(|claim| claim.item_index == item_index && !claim.is_expired(now_unix_nanos))
    else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is not claimed by worker {worker_id:?}"
        )));
    };
    if claim.worker_id != worker_id {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is claimed by worker {:?}, not {:?}",
            claim.worker_id, worker_id
        )));
    }
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_page_item_claim_lease_expires_by(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<Option<u128>, CompileError> {
    let Some(claim) = page
        .claimed_items
        .iter()
        .find(|claim| claim.item_index == item_index && !claim.is_expired(now_unix_nanos))
    else {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is not claimed by worker {worker_id:?}"
        )));
    };
    if claim.worker_id != worker_id {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is claimed by worker {:?}, not {:?}",
            claim.worker_id, worker_id
        )));
    }
    Ok(claim.lease_expires_unix_nanos)
}

pub(super) fn source_pack_work_queue_progress_page_record_item_ready(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<bool, CompileError> {
    if !source_pack_work_queue_progress_page_contains_item(page, item_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} cannot ready item {} outside range",
            page.page_index, item_index
        )));
    }
    if source_pack_work_queue_progress_page_item_is_completed(page, item_index) {
        return Ok(false);
    }
    let removed_counter =
        source_pack_work_queue_progress_page_remove_remaining_dependency_count(page, item_index);
    if source_pack_work_queue_progress_page_item_is_ready(page, item_index) {
        if source_pack_work_queue_progress_page_item_is_artifact_backed(page, item_index)
            && !page.ready_artifact_item_indices.contains(&item_index)
        {
            page.ready_artifact_item_indices.push(item_index);
            page.ready_artifact_item_indices.sort_unstable();
            page.ready_artifact_item_indices.dedup();
            return Ok(true);
        }
        return Ok(removed_counter);
    }
    page.ready_item_indices.push(item_index);
    page.ready_item_indices.sort_unstable();
    page.ready_item_indices.dedup();
    if source_pack_work_queue_progress_page_item_is_artifact_backed(page, item_index) {
        page.ready_artifact_item_indices.push(item_index);
        page.ready_artifact_item_indices.sort_unstable();
        page.ready_artifact_item_indices.dedup();
    }
    Ok(true)
}

pub(super) fn source_pack_work_queue_progress_page_record_dependency_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<(bool, bool), CompileError> {
    if !source_pack_work_queue_progress_page_contains_item(page, item_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} cannot update dependency counter for item {} outside range",
            page.page_index, item_index
        )));
    }
    if source_pack_work_queue_progress_page_item_is_completed(page, item_index)
        || source_pack_work_queue_progress_page_item_is_ready(page, item_index)
    {
        return Ok((false, false));
    }
    let Some(position) =
        source_pack_work_queue_progress_page_remaining_dependency_count_position(page, item_index)
    else {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} has no remaining dependency counter for blocked item {}",
            page.page_index, item_index
        )));
    };
    let remaining = &mut page.remaining_dependency_counts[position];
    if remaining.remaining_dependency_count > 1 {
        remaining.remaining_dependency_count -= 1;
        return Ok((true, false));
    }
    page.remaining_dependency_counts.remove(position);
    source_pack_work_queue_progress_page_record_item_ready(page, item_index)
        .map(|became_ready| (true, became_ready))
}

pub(super) fn source_pack_work_queue_progress_page_record_dependency_range_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    first_item_index: usize,
    item_count: usize,
) -> Result<(bool, usize), CompileError> {
    if item_count == 0 {
        return Ok((false, 0));
    }
    let range_end = first_item_index.checked_add(item_count).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue progress page {} dependency range {first_item_index}+{item_count} overflows",
            page.page_index
        ))
    })?;
    let page_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress page {} item range overflows",
                page.page_index
            ))
        })?;
    let update_start = first_item_index.max(page.first_item_index);
    let update_end = range_end.min(page_end);
    if update_start >= update_end {
        return Ok((false, 0));
    }
    let update_item_count = update_end - update_start;
    let completed_item_count = page
        .completed_item_indices
        .iter()
        .filter(|&&item_index| update_start <= item_index && item_index < update_end)
        .count();
    let ready_item_count = page
        .ready_item_indices
        .iter()
        .filter(|&&item_index| update_start <= item_index && item_index < update_end)
        .count();
    let blocked_item_count = page
        .remaining_dependency_counts
        .iter()
        .filter(|remaining| {
            update_start <= remaining.item_index && remaining.item_index < update_end
        })
        .count();
    let accounted_item_count = completed_item_count
        .saturating_add(ready_item_count)
        .saturating_add(blocked_item_count);
    if accounted_item_count != update_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} accounts for {accounted_item_count} items in dependency range {}..{} but expected {update_item_count}",
            page.page_index, update_start, update_end
        )));
    }

    let mut page_changed = false;
    let mut newly_ready_item_count = 0usize;
    let mut position = 0usize;
    while position < page.remaining_dependency_counts.len() {
        let item_index = page.remaining_dependency_counts[position].item_index;
        if item_index < update_start || item_index >= update_end {
            position += 1;
            continue;
        }
        if page.remaining_dependency_counts[position].remaining_dependency_count > 1 {
            page.remaining_dependency_counts[position].remaining_dependency_count -= 1;
            page_changed = true;
            position += 1;
            continue;
        }
        page.remaining_dependency_counts.remove(position);
        page_changed = true;
        if source_pack_work_queue_progress_page_record_item_ready(page, item_index)? {
            newly_ready_item_count = newly_ready_item_count.saturating_add(1);
        }
    }
    Ok((page_changed, newly_ready_item_count))
}

pub(super) fn source_pack_work_queue_progress_page_record_dependent_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<bool, CompileError> {
    if !source_pack_work_queue_progress_page_contains_item(page, item_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} cannot update dependent counter for item {} outside range",
            page.page_index, item_index
        )));
    }
    let Some(position) =
        source_pack_work_queue_progress_page_remaining_dependent_count_position(page, item_index)
    else {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} has no remaining dependent counter for item {}",
            page.page_index, item_index
        )));
    };
    let remaining = &mut page.remaining_dependent_counts[position];
    if remaining.remaining_dependent_count > 1 {
        remaining.remaining_dependent_count -= 1;
        return Ok(false);
    }
    page.remaining_dependent_counts.remove(position);
    Ok(true)
}

pub(super) fn source_pack_work_queue_progress_page_record_dependent_range_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    first_item_index: usize,
    item_count: usize,
) -> Result<(bool, Vec<usize>), CompileError> {
    if item_count == 0 {
        return Ok((false, Vec::new()));
    }
    let range_end = first_item_index.checked_add(item_count).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue progress page {} dependent range {first_item_index}+{item_count} overflows",
            page.page_index
        ))
    })?;
    let page_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress page {} item range overflows",
                page.page_index
            ))
        })?;
    let update_start = first_item_index.max(page.first_item_index);
    let update_end = range_end.min(page_end);
    if update_start >= update_end {
        return Ok((false, Vec::new()));
    }
    let update_item_count = update_end - update_start;
    let pending_dependent_item_count = page
        .remaining_dependent_counts
        .iter()
        .filter(|remaining| {
            update_start <= remaining.item_index && remaining.item_index < update_end
        })
        .count();
    if pending_dependent_item_count != update_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} has {pending_dependent_item_count} dependent counters in range {}..{} but expected {update_item_count}",
            page.page_index, update_start, update_end
        )));
    }

    let mut page_changed = false;
    let mut no_remaining_dependent_item_indices = Vec::new();
    let mut position = 0usize;
    while position < page.remaining_dependent_counts.len() {
        let item_index = page.remaining_dependent_counts[position].item_index;
        if item_index < update_start || item_index >= update_end {
            position += 1;
            continue;
        }
        if page.remaining_dependent_counts[position].remaining_dependent_count > 1 {
            page.remaining_dependent_counts[position].remaining_dependent_count -= 1;
            page_changed = true;
            position += 1;
            continue;
        }
        page.remaining_dependent_counts.remove(position);
        page_changed = true;
        no_remaining_dependent_item_indices.push(item_index);
    }
    no_remaining_dependent_item_indices.sort_unstable();
    Ok((page_changed, no_remaining_dependent_item_indices))
}

pub(super) fn source_pack_work_queue_progress_page_remove_ready_item(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    let before = page.ready_item_indices.len();
    page.ready_item_indices
        .retain(|ready_item_index| *ready_item_index != item_index);
    let ready_changed = before != page.ready_item_indices.len();
    let before_artifact = page.ready_artifact_item_indices.len();
    page.ready_artifact_item_indices
        .retain(|ready_item_index| *ready_item_index != item_index);
    ready_changed || before_artifact != page.ready_artifact_item_indices.len()
}

pub(super) fn source_pack_work_queue_progress_page_record_item_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<bool, CompileError> {
    if !source_pack_work_queue_progress_page_contains_item(page, item_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {} cannot complete item {} outside range",
            page.page_index, item_index
        )));
    }
    source_pack_work_queue_progress_page_prune_inactive_claims(page, now_unix_nanos);
    if source_pack_work_queue_progress_page_item_is_completed(page, item_index) {
        source_pack_work_queue_progress_page_remove_ready_item(page, item_index);
        source_pack_work_queue_progress_page_remove_remaining_dependency_count(page, item_index);
        page.claimed_items
            .retain(|claim| claim.item_index != item_index);
        return Ok(false);
    }
    source_pack_work_queue_progress_page_require_item_claimed_by(
        page,
        item_index,
        worker_id,
        now_unix_nanos,
    )?;
    page.completed_item_indices.push(item_index);
    page.completed_item_indices.sort_unstable();
    page.completed_item_indices.dedup();
    source_pack_work_queue_progress_page_remove_ready_item(page, item_index);
    source_pack_work_queue_progress_page_remove_remaining_dependency_count(page, item_index);
    page.claimed_items
        .retain(|claim| claim.item_index != item_index);
    Ok(true)
}

pub(super) fn source_pack_work_queue_progress_page_index_for_item(
    index: &SourcePackWorkQueueProgressIndex,
    item_index: usize,
) -> Result<usize, CompileError> {
    validate_source_pack_work_queue_progress_index(index, index.target)?;
    if item_index >= index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress item {} exceeds work item count {}",
            item_index, index.work_item_count
        )));
    }
    Ok(item_index / index.page_size)
}

pub(super) fn source_pack_work_queue_progress_adjust_count(
    total: usize,
    old_count: usize,
    new_count: usize,
    label: &str,
) -> Result<usize, CompileError> {
    total
        .checked_sub(old_count)
        .and_then(|count| count.checked_add(new_count))
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue progress {label} count cannot replace {old_count} with {new_count} in total {total}"
            ))
        })
}

pub(super) fn source_pack_work_queue_progress_page_summary_from_index_or_store(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    page_index: usize,
) -> Result<SourcePackWorkQueueProgressPageSummary, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    if let Some(summary) =
        store.try_load_work_queue_progress_page_summary_for_target(target, page_index)?
    {
        source_pack_work_queue_progress_validate_page_summary_shape(index, &summary)?;
        return Ok(summary);
    }
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    let summary = source_pack_work_queue_progress_page_summary(&page);
    source_pack_work_queue_progress_validate_page_summary_shape(index, &summary)?;
    Ok(summary)
}

pub(super) fn source_pack_work_queue_progress_page_summary_from_changes_or_store(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    page_index: usize,
) -> Result<SourcePackWorkQueueProgressPageSummary, CompileError> {
    if let Some(page) = changed_pages
        .iter()
        .find(|page| page.page_index == page_index)
    {
        let summary = source_pack_work_queue_progress_page_summary(page);
        source_pack_work_queue_progress_validate_page_summary_shape(index, &summary)?;
        return Ok(summary);
    }
    source_pack_work_queue_progress_page_summary_from_index_or_store(
        store, target, index, page_index,
    )
}

pub(super) fn source_pack_work_queue_progress_directory_page_from_summaries(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryPage, CompileError> {
    let (first_progress_page_index, progress_page_count) =
        source_pack_work_queue_progress_directory_page_range(index, directory_page_index)?;
    let mut ready_page_count = 0usize;
    let mut first_ready_page_index = None;
    let mut ready_artifact_page_count = 0usize;
    let mut first_ready_artifact_page_index = None;
    let mut ready_claimed_page_count = 0usize;
    let mut ready_artifact_claimed_page_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    let page_end = first_progress_page_index + progress_page_count;
    for page_index in first_progress_page_index..page_end {
        let summary = source_pack_work_queue_progress_page_summary_from_changes_or_store(
            store,
            target,
            index,
            changed_pages,
            page_index,
        )?;
        if summary.ready_item_count != 0 {
            ready_page_count = ready_page_count.saturating_add(1);
            first_ready_page_index = first_ready_page_index.or(Some(page_index));
            if source_pack_work_queue_progress_page_ready_items_are_claimed(&summary, None) {
                ready_claimed_page_count = ready_claimed_page_count.saturating_add(1);
                earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                    earliest_claim_lease_expires_unix_nanos,
                    summary.earliest_claim_lease_expires_unix_nanos,
                );
            }
        }
        if summary.ready_artifact_item_count != 0 {
            ready_artifact_page_count = ready_artifact_page_count.saturating_add(1);
            first_ready_artifact_page_index = first_ready_artifact_page_index.or(Some(page_index));
            if source_pack_work_queue_progress_page_ready_artifact_items_are_claimed(&summary, None)
            {
                ready_artifact_claimed_page_count =
                    ready_artifact_claimed_page_count.saturating_add(1);
                earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                    earliest_claim_lease_expires_unix_nanos,
                    summary.earliest_claim_lease_expires_unix_nanos,
                );
            }
        }
    }
    let page = SourcePackWorkQueueProgressDirectoryPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION,
        target,
        directory_page_index,
        first_progress_page_index,
        progress_page_count,
        ready_page_count,
        first_ready_page_index,
        ready_artifact_page_count,
        first_ready_artifact_page_index,
        ready_claimed_page_count,
        ready_artifact_claimed_page_count,
        earliest_claim_lease_expires_unix_nanos,
    };
    validate_source_pack_work_queue_progress_directory_page(&page, target, index)?;
    Ok(page)
}

pub(super) fn source_pack_work_queue_progress_directory_page_from_changes_or_store(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryPage, CompileError> {
    if changed_pages.iter().any(|page| {
        source_pack_work_queue_progress_directory_page_index_for_progress_page(page.page_index)
            == directory_page_index
    }) {
        return source_pack_work_queue_progress_directory_page_from_summaries(
            store,
            target,
            index,
            changed_pages,
            directory_page_index,
        );
    }
    if let Some(page) = store
        .try_load_work_queue_progress_directory_page_for_target(target, directory_page_index)?
    {
        validate_source_pack_work_queue_progress_directory_page(&page, target, index)?;
        return Ok(page);
    }
    source_pack_work_queue_progress_directory_page_from_summaries(
        store,
        target,
        index,
        changed_pages,
        directory_page_index,
    )
}

pub(super) fn source_pack_work_queue_progress_directory_index_page_from_directory_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_index_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryIndexPage, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    let (first_directory_page_index, directory_page_count) =
        source_pack_work_queue_progress_directory_index_page_range(
            index,
            directory_index_page_index,
        )?;
    let mut ready_directory_page_count = 0usize;
    let mut first_ready_directory_page_index = None;
    let mut ready_artifact_directory_page_count = 0usize;
    let mut first_ready_artifact_directory_page_index = None;
    let mut ready_claimed_directory_page_count = 0usize;
    let mut ready_artifact_claimed_directory_page_count = 0usize;
    let mut fully_claimed_ready_directory_page_count = 0usize;
    let mut fully_claimed_ready_artifact_directory_page_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    let directory_page_end = first_directory_page_index + directory_page_count;
    for directory_page_index in first_directory_page_index..directory_page_end {
        let directory_page = source_pack_work_queue_progress_directory_page_from_changes_or_store(
            store,
            target,
            index,
            changed_pages,
            directory_page_index,
        )?;
        if directory_page.ready_page_count != 0 {
            ready_directory_page_count = ready_directory_page_count.saturating_add(1);
            first_ready_directory_page_index =
                first_ready_directory_page_index.or(Some(directory_page_index));
        }
        if directory_page.ready_claimed_page_count != 0 {
            ready_claimed_directory_page_count =
                ready_claimed_directory_page_count.saturating_add(1);
            earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                earliest_claim_lease_expires_unix_nanos,
                directory_page.earliest_claim_lease_expires_unix_nanos,
            );
            if source_pack_work_queue_progress_directory_ready_pages_are_claimed(
                &directory_page,
                None,
            ) {
                fully_claimed_ready_directory_page_count =
                    fully_claimed_ready_directory_page_count.saturating_add(1);
            }
        }
        if directory_page.ready_artifact_page_count != 0 {
            ready_artifact_directory_page_count =
                ready_artifact_directory_page_count.saturating_add(1);
            first_ready_artifact_directory_page_index =
                first_ready_artifact_directory_page_index.or(Some(directory_page_index));
        }
        if directory_page.ready_artifact_claimed_page_count != 0 {
            ready_artifact_claimed_directory_page_count =
                ready_artifact_claimed_directory_page_count.saturating_add(1);
            earliest_claim_lease_expires_unix_nanos = source_pack_progress_summary_min_lease(
                earliest_claim_lease_expires_unix_nanos,
                directory_page.earliest_claim_lease_expires_unix_nanos,
            );
            if source_pack_work_queue_progress_directory_ready_artifact_pages_are_claimed(
                &directory_page,
                None,
            ) {
                fully_claimed_ready_artifact_directory_page_count =
                    fully_claimed_ready_artifact_directory_page_count.saturating_add(1);
            }
        }
    }
    let page = SourcePackWorkQueueProgressDirectoryIndexPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
        target,
        directory_index_page_index,
        first_directory_page_index,
        directory_page_count,
        ready_directory_page_count,
        first_ready_directory_page_index,
        ready_artifact_directory_page_count,
        first_ready_artifact_directory_page_index,
        ready_claimed_directory_page_count,
        ready_artifact_claimed_directory_page_count,
        fully_claimed_ready_directory_page_count,
        fully_claimed_ready_artifact_directory_page_count,
        earliest_claim_lease_expires_unix_nanos,
    };
    validate_source_pack_work_queue_progress_directory_index_page(&page, target, index)?;
    Ok(page)
}

pub(super) fn source_pack_work_queue_progress_directory_index_page_from_changes_or_store(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_index_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryIndexPage, CompileError> {
    if changed_pages.iter().any(|page| {
        let directory_page_index =
            source_pack_work_queue_progress_directory_page_index_for_progress_page(page.page_index);
        source_pack_work_queue_progress_directory_index_page_index_for_directory_page(
            directory_page_index,
        ) == directory_index_page_index
    }) {
        return source_pack_work_queue_progress_directory_index_page_from_directory_pages(
            store,
            target,
            index,
            changed_pages,
            directory_index_page_index,
        );
    }
    if let Some(page) = store.try_load_work_queue_progress_directory_index_page_for_target(
        target,
        directory_index_page_index,
    )? {
        validate_source_pack_work_queue_progress_directory_index_page(&page, target, index)?;
        return Ok(page);
    }
    source_pack_work_queue_progress_directory_index_page_from_directory_pages(
        store,
        target,
        index,
        changed_pages,
        directory_index_page_index,
    )
}

pub(super) fn source_pack_work_queue_progress_first_ready_item_index_from_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
) -> Result<Option<usize>, CompileError> {
    if index.ready_item_count == 0 {
        return Ok(None);
    }
    let changed_first_ready_item_index = changed_pages
        .iter()
        .filter_map(|page| page.ready_item_indices.iter().copied().min())
        .min();
    let start_item_index = match (index.first_ready_item_index, changed_first_ready_item_index) {
        (Some(index_first), Some(changed_first)) => Some(index_first.min(changed_first)),
        (Some(index_first), None) => Some(index_first),
        (None, Some(changed_first)) => Some(changed_first),
        (None, None) => None,
    };
    let start_page_index = start_item_index
        .map(|item_index| source_pack_work_queue_progress_page_index_for_item(index, item_index))
        .transpose()?
        .unwrap_or(0);
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
                changed_pages,
                directory_index_page_index,
            )?;
        if directory_index_page.ready_directory_page_count == 0 {
            continue;
        }
        let directory_start = directory_index_page
            .first_ready_directory_page_index
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
                    changed_pages,
                    directory_page_index,
                )?;
            let directory_page_end = directory_page
                .first_progress_page_index
                .saturating_add(directory_page.progress_page_count);
            if directory_page.ready_page_count == 0 {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_page_count = 0usize;
            while page_index < directory_page_end {
                let summary = source_pack_work_queue_progress_page_summary_from_changes_or_store(
                    store,
                    target,
                    index,
                    changed_pages,
                    page_index,
                )?;
                if summary.ready_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_page_count = seen_ready_page_count.saturating_add(1);
                if let Some(page) = changed_pages
                    .iter()
                    .find(|page| page.page_index == page_index)
                {
                    if let Some(first_ready) = page.ready_item_indices.iter().copied().min() {
                        return Ok(Some(first_ready));
                    }
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                if let Some(first_ready) = summary.first_ready_item_index {
                    return Ok(Some(first_ready));
                }
                let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
                if let Some(first_ready) = page.ready_item_indices.iter().copied().min() {
                    return Ok(Some(first_ready));
                }
                if seen_ready_page_count >= directory_page.ready_page_count {
                    break;
                }
                page_index = page_index.saturating_add(1);
            }
        }
    }
    Ok(None)
}

pub(super) fn source_pack_work_queue_progress_first_ready_artifact_item_index_from_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
) -> Result<Option<usize>, CompileError> {
    if index.ready_artifact_item_count == 0 {
        return Ok(None);
    }
    let changed_first_ready_artifact_item_index = changed_pages
        .iter()
        .filter_map(|page| page.ready_artifact_item_indices.iter().copied().min())
        .min();
    let start_item_index = match (
        index.first_ready_artifact_item_index,
        changed_first_ready_artifact_item_index,
    ) {
        (Some(index_first), Some(changed_first)) => Some(index_first.min(changed_first)),
        (Some(index_first), None) => Some(index_first),
        (None, Some(changed_first)) => Some(changed_first),
        (None, None) => None,
    };
    let start_page_index = start_item_index
        .map(|item_index| source_pack_work_queue_progress_page_index_for_item(index, item_index))
        .transpose()?
        .unwrap_or(0);
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
                changed_pages,
                directory_index_page_index,
            )?;
        if directory_index_page.ready_artifact_directory_page_count == 0 {
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
                    changed_pages,
                    directory_page_index,
                )?;
            let directory_page_end = directory_page
                .first_progress_page_index
                .saturating_add(directory_page.progress_page_count);
            if directory_page.ready_artifact_page_count == 0 {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_artifact_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_artifact_page_count = 0usize;
            while page_index < directory_page_end {
                let summary = source_pack_work_queue_progress_page_summary_from_changes_or_store(
                    store,
                    target,
                    index,
                    changed_pages,
                    page_index,
                )?;
                if summary.ready_artifact_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_artifact_page_count = seen_ready_artifact_page_count.saturating_add(1);
                if let Some(page) = changed_pages
                    .iter()
                    .find(|page| page.page_index == page_index)
                {
                    if let Some(first_ready) =
                        page.ready_artifact_item_indices.iter().copied().min()
                    {
                        return Ok(Some(first_ready));
                    }
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                if let Some(first_ready) = summary.first_ready_artifact_item_index {
                    return Ok(Some(first_ready));
                }
                let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
                if let Some(first_ready) = page.ready_artifact_item_indices.iter().copied().min() {
                    return Ok(Some(first_ready));
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

pub(super) fn source_pack_work_queue_progress_refresh_index_from_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    for page in changed_pages {
        validate_source_pack_work_queue_progress_page(page, target, Some(page.page_index))?;
        let old_summary = source_pack_work_queue_progress_page_summary_from_index_or_store(
            store,
            target,
            index,
            page.page_index,
        )?;
        let new_summary = source_pack_work_queue_progress_page_summary(page);
        source_pack_work_queue_progress_validate_page_summary_shape(index, &new_summary)?;
        if old_summary.first_item_index != new_summary.first_item_index
            || old_summary.item_count != new_summary.item_count
            || old_summary.artifact_item_count != new_summary.artifact_item_count
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress changed page {} shape does not match index",
                page.page_index
            )));
        }
        index.completed_item_count = source_pack_work_queue_progress_adjust_count(
            index.completed_item_count,
            old_summary.completed_item_count,
            new_summary.completed_item_count,
            "completed",
        )?;
        index.ready_item_count = source_pack_work_queue_progress_adjust_count(
            index.ready_item_count,
            old_summary.ready_item_count,
            new_summary.ready_item_count,
            "ready",
        )?;
        index.ready_artifact_item_count = source_pack_work_queue_progress_adjust_count(
            index.ready_artifact_item_count,
            old_summary.ready_artifact_item_count,
            new_summary.ready_artifact_item_count,
            "ready artifact",
        )?;
        if index.ready_item_count != 0 && index.first_ready_item_index.is_none() {
            index.first_ready_item_index = page.ready_item_indices.iter().copied().min();
        }
        if index.ready_artifact_item_count != 0 && index.first_ready_artifact_item_index.is_none() {
            index.first_ready_artifact_item_index =
                page.ready_artifact_item_indices.iter().copied().min();
        }
        index.claimed_item_count = source_pack_work_queue_progress_adjust_count(
            index.claimed_item_count,
            old_summary.claimed_item_count,
            new_summary.claimed_item_count,
            "claimed",
        )?;
    }
    if index.ready_item_count == 0 {
        index.first_ready_item_index = None;
    } else if index.first_ready_item_index.is_none() {
        index.first_ready_item_index = changed_pages
            .iter()
            .filter_map(|page| page.ready_item_indices.iter().copied().min())
            .min();
    }
    if index.ready_artifact_item_count == 0 {
        index.first_ready_artifact_item_index = None;
    } else if index.first_ready_artifact_item_index.is_none() {
        index.first_ready_artifact_item_index = changed_pages
            .iter()
            .filter_map(|page| page.ready_artifact_item_indices.iter().copied().min())
            .min();
    }
    index.first_ready_item_index =
        source_pack_work_queue_progress_first_ready_item_index_from_index(
            store,
            target,
            index,
            changed_pages,
        )?;
    index.first_ready_artifact_item_index =
        source_pack_work_queue_progress_first_ready_artifact_item_index_from_index(
            store,
            target,
            index,
            changed_pages,
        )?;
    let changed_directory_page_indices = changed_pages
        .iter()
        .map(|page| {
            source_pack_work_queue_progress_directory_page_index_for_progress_page(page.page_index)
        })
        .collect::<BTreeSet<_>>();
    for directory_page_index in changed_directory_page_indices {
        let directory_page = source_pack_work_queue_progress_directory_page_from_summaries(
            store,
            target,
            index,
            changed_pages,
            directory_page_index,
        )?;
        store.store_work_queue_progress_directory_page_for_target(target, &directory_page)?;
    }
    let changed_directory_index_page_indices = changed_pages
        .iter()
        .map(|page| {
            let directory_page_index =
                source_pack_work_queue_progress_directory_page_index_for_progress_page(
                    page.page_index,
                );
            source_pack_work_queue_progress_directory_index_page_index_for_directory_page(
                directory_page_index,
            )
        })
        .collect::<BTreeSet<_>>();
    for directory_index_page_index in changed_directory_index_page_indices {
        let directory_index_page =
            source_pack_work_queue_progress_directory_index_page_from_directory_pages(
                store,
                target,
                index,
                changed_pages,
                directory_index_page_index,
            )?;
        store.store_work_queue_progress_directory_index_page_for_target(
            target,
            &directory_index_page,
            index,
        )?;
    }
    validate_source_pack_work_queue_progress_index(index, target)?;
    Ok(())
}

pub(super) fn source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
    max_items: Option<usize>,
) -> Result<Vec<usize>, CompileError> {
    validate_source_pack_work_queue_progress_index(index, target)?;
    if index.ready_item_count == 0 || max_items == Some(0) {
        return Ok(Vec::new());
    }
    let Some(start_item_index) = index.first_ready_item_index else {
        return Ok(Vec::new());
    };
    let start_page_index =
        source_pack_work_queue_progress_page_index_for_item(index, start_item_index)?;
    let mut ready_item_indices = Vec::new();
    let mut seen_ready_item_count = 0usize;
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
        if directory_index_page.ready_directory_page_count == 0 {
            continue;
        }
        if source_pack_work_queue_progress_directory_index_ready_pages_are_claimed(
            &directory_index_page,
            now_unix_nanos,
        ) {
            continue;
        }
        let directory_start = directory_index_page
            .first_ready_directory_page_index
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
            if directory_page.ready_page_count == 0 {
                continue;
            }
            if source_pack_work_queue_progress_directory_ready_pages_are_claimed(
                &directory_page,
                now_unix_nanos,
            ) {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_page_count = 0usize;
            while page_index < directory_page_end {
                let summary = source_pack_work_queue_progress_page_summary_from_index_or_store(
                    store, target, index, page_index,
                )?;
                if summary.ready_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_page_count = seen_ready_page_count.saturating_add(1);
                if source_pack_work_queue_progress_page_ready_items_are_claimed(
                    &summary,
                    now_unix_nanos,
                ) {
                    seen_ready_item_count =
                        seen_ready_item_count.saturating_add(summary.ready_item_count);
                    if seen_ready_item_count >= index.ready_item_count {
                        return Ok(ready_item_indices);
                    }
                    if seen_ready_page_count >= directory_page.ready_page_count {
                        break;
                    }
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
                for &item_index in &page.ready_item_indices {
                    if item_index < start_item_index {
                        continue;
                    }
                    seen_ready_item_count = seen_ready_item_count.saturating_add(1);
                    if !source_pack_work_queue_progress_page_item_is_completed(&page, item_index)
                        && !source_pack_work_queue_progress_page_item_is_claimed(
                            &page,
                            item_index,
                            now_unix_nanos,
                        )
                    {
                        ready_item_indices.push(item_index);
                        if max_items.is_some_and(|max_items| ready_item_indices.len() >= max_items)
                        {
                            return Ok(ready_item_indices);
                        }
                    }
                    if seen_ready_item_count >= index.ready_item_count {
                        return Ok(ready_item_indices);
                    }
                }
                if seen_ready_page_count >= directory_page.ready_page_count {
                    break;
                }
                page_index = page_index.saturating_add(1);
            }
        }
    }
    Ok(ready_item_indices)
}

pub(super) fn source_pack_work_queue_progress_first_ready_unclaimed_item_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
) -> Result<Option<usize>, CompileError> {
    if let Some(first_ready_item_index) = index.first_ready_item_index {
        let page_index =
            source_pack_work_queue_progress_page_index_for_item(index, first_ready_item_index)?;
        let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
        if source_pack_work_queue_progress_page_item_is_ready(&page, first_ready_item_index)
            && !source_pack_work_queue_progress_page_item_is_completed(
                &page,
                first_ready_item_index,
            )
            && !source_pack_work_queue_progress_page_item_is_claimed(
                &page,
                first_ready_item_index,
                now_unix_nanos,
            )
        {
            return Ok(Some(first_ready_item_index));
        }
    }
    Ok(
        source_pack_work_queue_progress_ready_unclaimed_item_indices_from_index_limited(
            store,
            target,
            index,
            now_unix_nanos,
            Some(1),
        )?
        .first()
        .copied(),
    )
}
