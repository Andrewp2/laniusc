use super::*;

/// Finds the first ready work item using the bounded progress-directory index.
pub(in crate::compiler) fn progress_first_ready_item_index_from_index(
    store: &FilesystemArtifactStore,
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
        .map(|item_index| progress_page_index_for_item(index, item_index))
        .transpose()?
        .unwrap_or(0);
    let first_directory_page_index =
        progress_directory_page_index_for_progress_page(start_page_index);
    let first_directory_index_page_index =
        progress_directory_index_page_index_for_directory_page(first_directory_page_index);
    let directory_index_page_count = progress_directory_index_page_count(index)?;
    for directory_index_page_index in first_directory_index_page_index..directory_index_page_count {
        let directory_index_page = progress_directory_index_page_from_changes_or_store(
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
            let directory_page = progress_directory_page_from_changes_or_store(
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
                let summary = progress_page_summary_from_changes_or_store(
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

/// Finds the first ready artifact-backed work item using the directory index.
pub(in crate::compiler) fn progress_first_ready_artifact_item_index_from_index(
    store: &FilesystemArtifactStore,
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
        .map(|item_index| progress_page_index_for_item(index, item_index))
        .transpose()?
        .unwrap_or(0);
    let first_directory_page_index =
        progress_directory_page_index_for_progress_page(start_page_index);
    let first_directory_index_page_index =
        progress_directory_index_page_index_for_directory_page(first_directory_page_index);
    let directory_index_page_count = progress_directory_index_page_count(index)?;
    for directory_index_page_index in first_directory_index_page_index..directory_index_page_count {
        let directory_index_page = progress_directory_index_page_from_changes_or_store(
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
            let directory_page = progress_directory_page_from_changes_or_store(
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
                let summary = progress_page_summary_from_changes_or_store(
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

/// Applies changed progress pages to the root index and refreshed directory pages.
pub(in crate::compiler) fn progress_refresh_index_from_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_pages: &[SourcePackWorkQueueProgressPage],
) -> Result<(), CompileError> {
    validate_progress_index(index, target)?;
    for page in changed_pages {
        validate_progress_page(page, target, Some(page.page_index))?;
        let old_summary =
            progress_page_summary_from_index_or_store(store, target, index, page.page_index)?;
        let new_summary = progress_page_summary(page);
        progress_validate_page_summary_shape(index, &new_summary)?;
        if old_summary.first_item_index != new_summary.first_item_index
            || old_summary.item_count != new_summary.item_count
            || old_summary.artifact_item_count != new_summary.artifact_item_count
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress changed page {} shape does not match index",
                page.page_index
            )));
        }
        index.completed_item_count = progress_adjust_count(
            index.completed_item_count,
            old_summary.completed_item_count,
            new_summary.completed_item_count,
            "completed",
        )?;
        index.ready_item_count = progress_adjust_count(
            index.ready_item_count,
            old_summary.ready_item_count,
            new_summary.ready_item_count,
            "ready",
        )?;
        index.ready_artifact_item_count = progress_adjust_count(
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
        index.claimed_item_count = progress_adjust_count(
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
        progress_first_ready_item_index_from_index(store, target, index, changed_pages)?;
    index.first_ready_artifact_item_index =
        progress_first_ready_artifact_item_index_from_index(store, target, index, changed_pages)?;
    let changed_directory_page_indices = changed_pages
        .iter()
        .map(|page| progress_directory_page_index_for_progress_page(page.page_index))
        .collect::<BTreeSet<_>>();
    for directory_page_index in changed_directory_page_indices {
        let directory_page = progress_directory_page_from_summaries(
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
                progress_directory_page_index_for_progress_page(page.page_index);
            progress_directory_index_page_index_for_directory_page(directory_page_index)
        })
        .collect::<BTreeSet<_>>();
    for directory_index_page_index in changed_directory_index_page_indices {
        let directory_index_page = progress_directory_index_page_from_directory_pages(
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
    validate_progress_index(index, target)?;
    Ok(())
}

/// Finds ready, unclaimed work items up to an optional caller limit.
pub(in crate::compiler) fn progress_ready_unclaimed_item_indices_from_index_limited(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
    max_items: Option<usize>,
) -> Result<Vec<usize>, CompileError> {
    validate_progress_index(index, target)?;
    if index.ready_item_count == 0 || max_items == Some(0) {
        return Ok(Vec::new());
    }
    let Some(start_item_index) = index.first_ready_item_index else {
        return Ok(Vec::new());
    };
    let start_page_index = progress_page_index_for_item(index, start_item_index)?;
    let mut ready_item_indices = Vec::new();
    let mut seen_ready_item_count = 0usize;
    let first_directory_page_index =
        progress_directory_page_index_for_progress_page(start_page_index);
    let first_directory_index_page_index =
        progress_directory_index_page_index_for_directory_page(first_directory_page_index);
    let directory_index_page_count = progress_directory_index_page_count(index)?;
    for directory_index_page_index in first_directory_index_page_index..directory_index_page_count {
        let directory_index_page = progress_directory_index_page_from_changes_or_store(
            store,
            target,
            index,
            &[],
            directory_index_page_index,
        )?;
        if directory_index_page.ready_directory_page_count == 0 {
            continue;
        }
        if progress_directory_index_ready_pages_are_claimed(&directory_index_page, now_unix_nanos) {
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
            let directory_page = progress_directory_page_from_changes_or_store(
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
            if progress_directory_ready_pages_are_claimed(&directory_page, now_unix_nanos) {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_page_count = 0usize;
            while page_index < directory_page_end {
                let summary =
                    progress_page_summary_from_index_or_store(store, target, index, page_index)?;
                if summary.ready_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_page_count = seen_ready_page_count.saturating_add(1);
                if progress_page_ready_items_are_claimed(&summary, now_unix_nanos) {
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
                    if !progress_page_item_is_completed(&page, item_index)
                        && !progress_page_item_is_claimed(&page, item_index, now_unix_nanos)
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

/// Finds the first ready, unclaimed work item for a worker claim attempt.
pub(in crate::compiler) fn progress_first_ready_unclaimed_item_index(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
) -> Result<Option<usize>, CompileError> {
    if let Some(first_ready_item_index) = index.first_ready_item_index {
        let page_index = progress_page_index_for_item(index, first_ready_item_index)?;
        let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
        if progress_page_item_is_ready(&page, first_ready_item_index)
            && !progress_page_item_is_completed(&page, first_ready_item_index)
            && !progress_page_item_is_claimed(&page, first_ready_item_index, now_unix_nanos)
        {
            return Ok(Some(first_ready_item_index));
        }
    }
    Ok(progress_ready_unclaimed_item_indices_from_index_limited(
        store,
        target,
        index,
        now_unix_nanos,
        Some(1),
    )?
    .first()
    .copied())
}
