// src/compiler/work_queue_progress/summary.rs

use super::*;

pub(in crate::compiler) fn progress_page_summary(
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

pub(in crate::compiler) fn progress_page_ready_items_are_claimed(
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

pub(in crate::compiler) fn progress_page_ready_artifact_items_are_claimed(
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

pub(in crate::compiler) fn progress_adjust_count(
    total: usize,
    old_count: usize,
    new_count: usize,
    label: &str,
) -> Result<usize, CompileError> {
    total
        .checked_sub(old_count)
        .and_then(|count| count.checked_add(new_count))
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue progress {label} count cannot replace {old_count} with {new_count} in total {total}"
            ))
        })
}

pub(in crate::compiler) fn progress_page_summary_from_index_or_store(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    page_index: usize,
) -> Result<SourcePackWorkQueueProgressPageSummary, CompileError> {
    validate_progress_index(index, target)?;
    if let Some(summary) =
        store.try_load_work_queue_progress_page_summary_for_target(target, page_index)?
    {
        progress_validate_page_summary_shape(index, &summary)?;
        return Ok(summary);
    }
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    let summary = progress_page_summary(&page);
    progress_validate_page_summary_shape(index, &summary)?;
    Ok(summary)
}

pub(in crate::compiler) fn progress_page_summary_from_changes_or_store(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
    page_index: usize,
) -> Result<SourcePackWorkQueueProgressPageSummary, CompileError> {
    if let Some(page) = changed_pages
        .iter()
        .find(|page| page.page_index == page_index)
    {
        let summary = progress_page_summary(page);
        progress_validate_page_summary_shape(index, &summary)?;
        return Ok(summary);
    }
    progress_page_summary_from_index_or_store(store, target, index, page_index)
}
