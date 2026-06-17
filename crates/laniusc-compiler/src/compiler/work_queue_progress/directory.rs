// src/compiler/work_queue_progress/directory.rs

use super::*;

pub(in crate::compiler) fn progress_directory_ready_pages_are_claimed(
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

pub(in crate::compiler) fn progress_directory_ready_artifact_pages_are_claimed(
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

pub(in crate::compiler) fn progress_directory_index_ready_pages_are_claimed(
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

pub(in crate::compiler) fn progress_directory_index_ready_artifacts_are_claimed(
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

pub(in crate::compiler) fn progress_directory_page_index_for_progress_page(
    progress_page_index: usize,
) -> usize {
    progress_page_index / SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
}

pub(in crate::compiler) fn progress_directory_page_count(
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<usize, CompileError> {
    validate_progress_index(index, index.target)?;
    Ok(index
        .page_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE))
}

pub(in crate::compiler) fn progress_directory_page_range(
    index: &SourcePackWorkQueueProgressIndex,
    directory_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    let first_progress_page_index = directory_page_index
        .checked_mul(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue progress directory page {directory_page_index} start overflows"
            ))
        })?;
    if first_progress_page_index >= index.page_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory page {directory_page_index} starts at page {first_progress_page_index} but page_count is {}",
            index.page_count
        )));
    }
    let progress_page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE
        .min(index.page_count - first_progress_page_index);
    Ok((first_progress_page_index, progress_page_count))
}

pub(in crate::compiler) fn progress_directory_index_page_index_for_directory_page(
    directory_page_index: usize,
) -> usize {
    directory_page_index / SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
}

pub(in crate::compiler) fn progress_directory_index_page_count(
    index: &SourcePackWorkQueueProgressIndex,
) -> Result<usize, CompileError> {
    let directory_page_count = progress_directory_page_count(index)?;
    Ok(directory_page_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE))
}

pub(in crate::compiler) fn progress_directory_index_page_range(
    index: &SourcePackWorkQueueProgressIndex,
    directory_index_page_index: usize,
) -> Result<(usize, usize), CompileError> {
    let directory_page_count = progress_directory_page_count(index)?;
    let first_directory_page_index = directory_index_page_index
        .checked_mul(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue progress directory-index page {directory_index_page_index} start overflows"
            ))
        })?;
    if first_directory_page_index >= directory_page_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress directory-index page {directory_index_page_index} starts at directory page {first_directory_page_index} but directory page count is {directory_page_count}"
        )));
    }
    let directory_page_count = SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE
        .min(directory_page_count - first_directory_page_index);
    Ok((first_directory_page_index, directory_page_count))
}

pub(in crate::compiler) fn progress_directory_page_from_summaries(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryPage, CompileError> {
    let (first_progress_page_index, progress_page_count) =
        progress_directory_page_range(index, directory_page_index)?;
    let mut ready_page_count = 0usize;
    let mut first_ready_page_index = None;
    let mut ready_artifact_page_count = 0usize;
    let mut first_ready_artifact_page_index = None;
    let mut ready_claimed_page_count = 0usize;
    let mut ready_artifact_claimed_page_count = 0usize;
    let mut earliest_claim_lease_expires_unix_nanos = None;
    let page_end = first_progress_page_index + progress_page_count;
    for page_index in first_progress_page_index..page_end {
        let summary = progress_page_summary_from_changes_or_store(
            store,
            target,
            index,
            changed_pages,
            page_index,
        )?;
        if summary.ready_item_count != 0 {
            ready_page_count = ready_page_count.saturating_add(1);
            first_ready_page_index = first_ready_page_index.or(Some(page_index));
            if progress_page_ready_items_are_claimed(&summary, None) {
                ready_claimed_page_count = ready_claimed_page_count.saturating_add(1);
                earliest_claim_lease_expires_unix_nanos = earliest_lease_expiry(
                    earliest_claim_lease_expires_unix_nanos,
                    summary.earliest_claim_lease_expires_unix_nanos,
                );
            }
        }
        if summary.ready_artifact_item_count != 0 {
            ready_artifact_page_count = ready_artifact_page_count.saturating_add(1);
            first_ready_artifact_page_index = first_ready_artifact_page_index.or(Some(page_index));
            if progress_page_ready_artifact_items_are_claimed(&summary, None) {
                ready_artifact_claimed_page_count =
                    ready_artifact_claimed_page_count.saturating_add(1);
                earliest_claim_lease_expires_unix_nanos = earliest_lease_expiry(
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
    validate_progress_directory_page(&page, target, index)?;
    Ok(page)
}

pub(in crate::compiler) fn progress_directory_page_from_changes_or_store(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryPage, CompileError> {
    if changed_pages.iter().any(|page| {
        progress_directory_page_index_for_progress_page(page.page_index) == directory_page_index
    }) {
        return progress_directory_page_from_summaries(
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
        validate_progress_directory_page(&page, target, index)?;
        return Ok(page);
    }
    progress_directory_page_from_summaries(
        store,
        target,
        index,
        changed_pages,
        directory_page_index,
    )
}

pub(in crate::compiler) fn progress_directory_index_page_from_directory_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_index_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryIndexPage, CompileError> {
    validate_progress_index(index, target)?;
    let (first_directory_page_index, directory_page_count) =
        progress_directory_index_page_range(index, directory_index_page_index)?;
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
        let directory_page = progress_directory_page_from_changes_or_store(
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
            earliest_claim_lease_expires_unix_nanos = earliest_lease_expiry(
                earliest_claim_lease_expires_unix_nanos,
                directory_page.earliest_claim_lease_expires_unix_nanos,
            );
            if progress_directory_ready_pages_are_claimed(&directory_page, None) {
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
            earliest_claim_lease_expires_unix_nanos = earliest_lease_expiry(
                earliest_claim_lease_expires_unix_nanos,
                directory_page.earliest_claim_lease_expires_unix_nanos,
            );
            if progress_directory_ready_artifact_pages_are_claimed(&directory_page, None) {
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
    validate_progress_directory_index_page(&page, target, index)?;
    Ok(page)
}

pub(in crate::compiler) fn progress_directory_index_page_from_changes_or_store(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    directory_index_page_index: usize,
) -> Result<SourcePackWorkQueueProgressDirectoryIndexPage, CompileError> {
    if changed_pages.iter().any(|page| {
        let directory_page_index = progress_directory_page_index_for_progress_page(page.page_index);
        progress_directory_index_page_index_for_directory_page(directory_page_index)
            == directory_index_page_index
    }) {
        return progress_directory_index_page_from_directory_pages(
            store,
            target,
            index,
            changed_pages,
            directory_index_page_index,
        );
    }
    if let Some(page) = store
        .try_load_progress_directory_index_page_for_target(target, directory_index_page_index)?
    {
        validate_progress_directory_index_page(&page, target, index)?;
        return Ok(page);
    }
    progress_directory_index_page_from_directory_pages(
        store,
        target,
        index,
        changed_pages,
        directory_index_page_index,
    )
}
