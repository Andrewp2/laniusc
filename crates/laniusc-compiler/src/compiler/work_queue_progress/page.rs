// src/compiler/work_queue_progress/page.rs

use super::*;

/// Returns whether a progress page owns a work item index.
pub(in crate::compiler) fn progress_page_contains_item(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    let item_end = page.first_item_index.saturating_add(page.item_count);
    item_index >= page.first_item_index && item_index < item_end
}

/// Returns whether a work item is recorded as completed in this page.
pub(in crate::compiler) fn progress_page_item_is_completed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.completed_item_indices.contains(&item_index)
}

/// Returns whether a work item is recorded as ready in this page.
pub(in crate::compiler) fn progress_page_item_is_ready(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.ready_item_indices.contains(&item_index)
}

/// Returns whether a work item produces or owns an artifact record.
pub(in crate::compiler) fn progress_page_item_is_artifact_backed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    page.artifact_item_indices.contains(&item_index)
}

/// Finds the remaining-dependency counter row for a work item.
pub(in crate::compiler) fn progress_page_remaining_dependency_count_position(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Option<usize> {
    page.remaining_dependency_counts
        .iter()
        .position(|remaining| remaining.item_index == item_index)
}

/// Finds the remaining-dependent counter row for a work item.
pub(in crate::compiler) fn progress_page_remaining_dependent_count_position(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Option<usize> {
    page.remaining_dependent_counts
        .iter()
        .position(|remaining| remaining.item_index == item_index)
}

/// Removes a remaining-dependency counter row for a work item.
pub(in crate::compiler) fn progress_page_remove_remaining_dependency_count(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    let before = page.remaining_dependency_counts.len();
    page.remaining_dependency_counts
        .retain(|remaining| remaining.item_index != item_index);
    before != page.remaining_dependency_counts.len()
}

/// Returns whether a completed work item still has dependent work to notify.
pub(in crate::compiler) fn progress_page_item_has_remaining_dependents(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> bool {
    progress_page_remaining_dependent_count_position(page, item_index).is_some()
}

/// Returns whether a work item has a non-expired claim.
pub(in crate::compiler) fn progress_page_item_is_claimed(
    page: &SourcePackWorkQueueProgressPage,
    item_index: usize,
    now_unix_nanos: Option<u128>,
) -> bool {
    page.claimed_items
        .iter()
        .any(|claim| claim.item_index == item_index && !claim.is_expired(now_unix_nanos))
}

/// Drops expired, completed, and duplicate claims from a progress page.
pub(in crate::compiler) fn progress_page_prune_inactive_claims(
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

/// Records or refreshes a worker claim for a ready work item.
pub(in crate::compiler) fn progress_page_record_item_claim(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let worker_id = worker_id.into();
    if worker_id.trim().is_empty() {
        return Err(source_pack_progress_state_error(
            "source-pack work item claim worker id must not be empty",
        ));
    }
    if let (Some(now), Some(expires)) = (now_unix_nanos, lease_expires_unix_nanos) {
        if expires <= now {
            return Err(source_pack_progress_state_error(format!(
                "source-pack work item {item_index} claim lease expires at {expires}, which is not after now {now}"
            )));
        }
    }
    if !progress_page_contains_item(page, item_index) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} cannot claim item {} outside range",
            page.page_index, item_index
        )));
    }
    progress_page_prune_inactive_claims(page, now_unix_nanos);
    if progress_page_item_is_completed(page, item_index) {
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is already complete and cannot be claimed"
        )));
    }
    if !progress_page_item_is_ready(page, item_index) {
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is not ready and cannot be claimed"
        )));
    }
    if let Some(claim) = page
        .claimed_items
        .iter()
        .find(|claim| claim.item_index == item_index)
    {
        if claim.worker_id != worker_id {
            return Err(source_pack_progress_state_error(format!(
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

/// Requires a work item to be actively claimed by the supplied worker.
pub(in crate::compiler) fn progress_page_require_item_claimed_by(
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
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is not claimed by worker {worker_id:?}"
        )));
    };
    if claim.worker_id != worker_id {
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is claimed by worker {:?}, not {:?}",
            claim.worker_id, worker_id
        )));
    }
    Ok(())
}

/// Returns the active claim lease expiry for a worker-owned work item.
pub(in crate::compiler) fn progress_page_item_claim_lease_expires_by(
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
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is not claimed by worker {worker_id:?}"
        )));
    };
    if claim.worker_id != worker_id {
        return Err(source_pack_progress_state_error(format!(
            "source-pack work item {item_index} is claimed by worker {:?}, not {:?}",
            claim.worker_id, worker_id
        )));
    }
    Ok(claim.lease_expires_unix_nanos)
}

/// Marks a work item ready and updates artifact-ready indexes as needed.
pub(in crate::compiler) fn progress_page_record_item_ready(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<bool, CompileError> {
    if !progress_page_contains_item(page, item_index) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} cannot ready item {} outside range",
            page.page_index, item_index
        )));
    }
    if progress_page_item_is_completed(page, item_index) {
        return Ok(false);
    }
    let removed_counter = progress_page_remove_remaining_dependency_count(page, item_index);
    if progress_page_item_is_ready(page, item_index) {
        if progress_page_item_is_artifact_backed(page, item_index)
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
    if progress_page_item_is_artifact_backed(page, item_index) {
        page.ready_artifact_item_indices.push(item_index);
        page.ready_artifact_item_indices.sort_unstable();
        page.ready_artifact_item_indices.dedup();
    }
    Ok(true)
}

/// Records completion of one dependency edge for a blocked work item.
pub(in crate::compiler) fn progress_page_record_dependency_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<(bool, bool), CompileError> {
    if !progress_page_contains_item(page, item_index) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} cannot update dependency counter for item {} outside range",
            page.page_index, item_index
        )));
    }
    if progress_page_item_is_completed(page, item_index)
        || progress_page_item_is_ready(page, item_index)
    {
        return Ok((false, false));
    }
    let Some(position) = progress_page_remaining_dependency_count_position(page, item_index) else {
        return Err(library_partition_contract_error(format!(
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
    progress_page_record_item_ready(page, item_index).map(|became_ready| (true, became_ready))
}

/// Records one completed dependency edge for every item in an intersecting range.
pub(in crate::compiler) fn progress_page_record_dependency_range_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    first_item_index: usize,
    item_count: usize,
) -> Result<(bool, usize), CompileError> {
    if item_count == 0 {
        return Ok((false, 0));
    }
    let range_end = first_item_index.checked_add(item_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue progress page {} dependency range {first_item_index}+{item_count} overflows",
            page.page_index
        ))
    })?;
    let page_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
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
        return Err(library_partition_contract_error(format!(
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
        if progress_page_record_item_ready(page, item_index)? {
            newly_ready_item_count = newly_ready_item_count.saturating_add(1);
        }
    }
    Ok((page_changed, newly_ready_item_count))
}

/// Records that one dependent of a completed work item has been notified.
pub(in crate::compiler) fn progress_page_record_dependent_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
) -> Result<bool, CompileError> {
    if !progress_page_contains_item(page, item_index) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} cannot update dependent counter for item {} outside range",
            page.page_index, item_index
        )));
    }
    let Some(position) = progress_page_remaining_dependent_count_position(page, item_index) else {
        return Err(library_partition_contract_error(format!(
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

/// Records dependent completion for every item in an intersecting range.
pub(in crate::compiler) fn progress_page_record_dependent_range_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    first_item_index: usize,
    item_count: usize,
) -> Result<(bool, Vec<usize>), CompileError> {
    if item_count == 0 {
        return Ok((false, Vec::new()));
    }
    let range_end = first_item_index.checked_add(item_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue progress page {} dependent range {first_item_index}+{item_count} overflows",
            page.page_index
        ))
    })?;
    let page_end = page
        .first_item_index
        .checked_add(page.item_count)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
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
        return Err(library_partition_contract_error(format!(
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

/// Removes a work item from normal and artifact-ready queues.
pub(in crate::compiler) fn progress_page_remove_ready_item(
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

/// Marks a claimed work item complete and removes it from claim/ready state.
pub(in crate::compiler) fn progress_page_record_item_completed(
    page: &mut SourcePackWorkQueueProgressPage,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<bool, CompileError> {
    if !progress_page_contains_item(page, item_index) {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {} cannot complete item {} outside range",
            page.page_index, item_index
        )));
    }
    progress_page_prune_inactive_claims(page, now_unix_nanos);
    if progress_page_item_is_completed(page, item_index) {
        progress_page_remove_ready_item(page, item_index);
        progress_page_remove_remaining_dependency_count(page, item_index);
        page.claimed_items
            .retain(|claim| claim.item_index != item_index);
        return Ok(false);
    }
    progress_page_require_item_claimed_by(page, item_index, worker_id, now_unix_nanos)?;
    page.completed_item_indices.push(item_index);
    page.completed_item_indices.sort_unstable();
    page.completed_item_indices.dedup();
    progress_page_remove_ready_item(page, item_index);
    progress_page_remove_remaining_dependency_count(page, item_index);
    page.claimed_items
        .retain(|claim| claim.item_index != item_index);
    Ok(true)
}

/// Returns the progress-page index that owns a work item.
pub(in crate::compiler) fn progress_page_index_for_item(
    index: &SourcePackWorkQueueProgressIndex,
    item_index: usize,
) -> Result<usize, CompileError> {
    validate_progress_index(index, index.target)?;
    if item_index >= index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress item {} exceeds work item count {}",
            item_index, index.work_item_count
        )));
    }
    Ok(item_index / index.page_size)
}
