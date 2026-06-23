use super::*;

/// Finds the first ready, unclaimed artifact-backed work item and its batch.
pub(in crate::compiler) fn work_queue_first_ready_unclaimed_artifact_item(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    now_unix_nanos: Option<u128>,
) -> Result<Option<(usize, usize)>, CompileError> {
    validate_progress_index(index, target)?;
    if index.ready_item_count == 0
        || index.artifact_item_count == 0
        || index.ready_artifact_item_count == 0
    {
        return Ok(None);
    }
    let Some(start_item_index) = index.first_ready_artifact_item_index else {
        return Ok(None);
    };
    let start_page_index = progress_page_index_for_item(index, start_item_index)?;
    let mut seen_ready_artifact_item_count = 0usize;
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
        if directory_index_page.ready_artifact_directory_page_count == 0 {
            continue;
        }
        if progress_directory_index_ready_artifacts_are_claimed(
            &directory_index_page,
            now_unix_nanos,
        ) {
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
                &[],
                directory_page_index,
            )?;
            let directory_page_end = directory_page
                .first_progress_page_index
                .saturating_add(directory_page.progress_page_count);
            if directory_page.ready_artifact_page_count == 0 {
                continue;
            }
            if progress_directory_ready_artifact_pages_are_claimed(&directory_page, now_unix_nanos)
            {
                continue;
            }
            let mut page_index = directory_page
                .first_ready_artifact_page_index
                .unwrap_or(directory_page.first_progress_page_index)
                .max(start_page_index);
            let mut seen_ready_artifact_page_count = 0usize;
            while page_index < directory_page_end {
                let summary =
                    progress_page_summary_from_index_or_store(store, target, index, page_index)?;
                if summary.ready_artifact_item_count == 0 {
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                seen_ready_artifact_page_count = seen_ready_artifact_page_count.saturating_add(1);
                if progress_page_ready_artifact_items_are_claimed(&summary, now_unix_nanos) {
                    seen_ready_artifact_item_count = seen_ready_artifact_item_count
                        .saturating_add(summary.ready_artifact_item_count);
                    if seen_ready_artifact_item_count >= index.ready_artifact_item_count {
                        return Ok(None);
                    }
                    if seen_ready_artifact_page_count >= directory_page.ready_artifact_page_count {
                        break;
                    }
                    page_index = page_index.saturating_add(1);
                    continue;
                }
                let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
                for &item_index in &page.ready_artifact_item_indices {
                    if item_index < start_item_index {
                        continue;
                    }
                    seen_ready_artifact_item_count =
                        seen_ready_artifact_item_count.saturating_add(1);
                    if progress_page_item_is_completed(&page, item_index)
                        || !progress_page_item_is_ready(&page, item_index)
                        || !progress_page_item_is_artifact_backed(&page, item_index)
                        || progress_page_item_is_claimed(&page, item_index, now_unix_nanos)
                    {
                        continue;
                    }
                    let work_item = store.load_work_queue_page_for_target(target, item_index)?;
                    let Some(batch_index) = work_queue_singleton_artifact_batch_index_for_item(
                        store, target, &work_item,
                    )?
                    else {
                        return Err(library_partition_contract_error(format!(
                            "ready artifact work queue item {item_index} has no singleton artifact batch"
                        )));
                    };
                    return Ok(Some((item_index, batch_index)));
                }
                if seen_ready_artifact_item_count >= index.ready_artifact_item_count {
                    return Ok(None);
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

/// Mirrors a work-queue item claim onto its backing artifact batch.
pub(in crate::compiler) fn work_queue_record_artifact_batch_claim(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    batch_index: usize,
    worker_id: &str,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let execution_shard = execution_shard_for_batch_locator(store, target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let mut progress = store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
    progress.prune_inactive_batch_claims(now_unix_nanos)?;
    if !progress.is_batch_completed(batch_index) {
        if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            return Ok(());
        }
        if !batch_ready_unclaimed_from_locator(store, target, batch_index, now_unix_nanos)? {
            return Err(source_pack_progress_state_error(format!(
                "source-pack artifact batch {batch_index} is not ready for work-queue item claim"
            )));
        }
        progress.record_batch_claim(
            batch_index,
            worker_id.to_string(),
            lease_expires_unix_nanos,
            now_unix_nanos,
        )?;
        store.store_build_progress_shard(&progress)?;
    }
    Ok(())
}

/// Claim the first ready unclaimed work-queue item for a worker.
pub fn claim_ready_work_queue_item(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemWorkQueueItemClaimResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let claimed_item_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let claimed_item_index = if index.completed_item_count == index.work_item_count {
            None
        } else {
            progress_first_ready_unclaimed_item_index(&store, target, &index, now_unix_nanos)?
        };
        if let Some(item_index) = claimed_item_index {
            let page_index = progress_page_index_for_item(&index, item_index)?;
            let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
            progress_page_prune_inactive_claims(&mut page, now_unix_nanos);
            progress_page_record_item_claim(
                &mut page,
                item_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let changed_pages = [page];
            progress_refresh_index_from_pages(&store, target, &mut index, &changed_pages)?;
            store.store_work_queue_progress_page(&changed_pages[0])?;
            store.store_work_queue_progress_index(&index)?;
        }
        claimed_item_index
    };
    let progress =
        work_queue_progress_snapshot_at(&artifact_root, target, max_ready_items, now_unix_nanos)?;
    Ok(FilesystemWorkQueueItemClaimResult {
        claimed_item_index,
        worker_id,
        progress,
    })
}

/// Claim the first ready unclaimed artifact-producing work-queue item for a
/// worker and mirror the claim into its singleton artifact batch.
pub fn claim_ready_artifact_work_queue_item(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemWorkQueueItemClaimResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let claimed_item_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let claimed = if index.completed_item_count == index.work_item_count {
            None
        } else {
            work_queue_first_ready_unclaimed_artifact_item(&store, target, &index, now_unix_nanos)?
        };
        if let Some((item_index, batch_index)) = claimed {
            work_queue_record_artifact_batch_claim(
                &store,
                target,
                batch_index,
                &worker_id,
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let page_index = progress_page_index_for_item(&index, item_index)?;
            let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
            progress_page_prune_inactive_claims(&mut page, now_unix_nanos);
            progress_page_record_item_claim(
                &mut page,
                item_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            let changed_pages = [page];
            progress_refresh_index_from_pages(&store, target, &mut index, &changed_pages)?;
            store.store_work_queue_progress_page(&changed_pages[0])?;
            store.store_work_queue_progress_index(&index)?;
            Some(item_index)
        } else {
            None
        }
    };
    let progress =
        work_queue_progress_snapshot_at(&artifact_root, target, max_ready_items, now_unix_nanos)?;
    Ok(FilesystemWorkQueueItemClaimResult {
        claimed_item_index,
        worker_id,
        progress,
    })
}

/// Mark a claimed work-queue item complete and update dependents that become
/// ready.
pub fn complete_claimed_work_queue_item(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemWorkQueueItemCompletionResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let worker_id = worker_id.into();
    let (newly_completed, newly_ready_item_count) = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut index = store.load_work_queue_progress_index_for_target(target)?;
        let page_index = progress_page_index_for_item(&index, item_index)?;
        let mut page = store.load_work_queue_progress_page_for_target(target, page_index)?;
        let newly_completed =
            progress_page_record_item_completed(&mut page, item_index, &worker_id, now_unix_nanos)?;
        let changed_pages = [page];
        progress_refresh_index_from_pages(&store, target, &mut index, &changed_pages)?;
        store.store_work_queue_progress_page(&changed_pages[0])?;
        let mut newly_ready_item_count = 0usize;

        if newly_completed {
            let work_item = store.load_work_queue_page_for_target(target, item_index)?;
            let mut changed_page_batch =
                ChangedProgressPages::new(SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT);
            newly_ready_item_count = record_work_item_dependents_completed(
                &store,
                target,
                &mut index,
                &mut changed_page_batch,
                &work_item,
            )?;
            changed_page_batch.flush(&store, target, &mut index)?;
            release_work_queue_consumed_outputs_after_completion(
                &store, target, &mut index, &work_item,
            )?;
        }

        store.store_work_queue_progress_index(&index)?;
        (newly_completed, newly_ready_item_count)
    };
    let progress =
        work_queue_progress_snapshot_at(&artifact_root, target, max_ready_items, now_unix_nanos)?;
    Ok(FilesystemWorkQueueItemCompletionResult {
        completed_item_index: item_index,
        worker_id,
        newly_completed,
        newly_ready_item_count,
        progress,
    })
}
