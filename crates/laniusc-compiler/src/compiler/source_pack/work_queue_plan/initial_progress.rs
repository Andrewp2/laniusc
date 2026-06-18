use super::*;

/// Resumable checkpoint for creating the initial work-queue progress pages.
///
/// The final [`SourcePackWorkQueueProgressIndex`] cannot be written until every
/// work-queue item has been scanned and every progress page has been stored.
/// This record keeps the partial scan state on disk so large source packs can
/// initialize progress in bounded chunks.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct InitialWorkQueueProgressPrepareProgress {
    /// Serialization version for this checkpoint record.
    pub(in crate::compiler) version: u32,
    /// Artifact target whose work queue is being summarized.
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    /// Total number of work-queue item pages that must be scanned.
    pub(in crate::compiler) work_item_count: usize,
    /// Number of work-queue items summarized by each progress page.
    pub(in crate::compiler) page_size: usize,
    /// Number of progress pages required for `work_item_count`.
    pub(in crate::compiler) page_count: usize,
    /// Next progress page to derive from stored work-queue item pages.
    pub(in crate::compiler) next_page_index: usize,
    /// Number of artifact-backed work items seen in completed progress pages.
    pub(in crate::compiler) artifact_item_count: usize,
    /// Number of dependency-free work items seen in completed progress pages.
    pub(in crate::compiler) ready_item_count: usize,
    /// Number of ready items that also produce persisted artifacts.
    pub(in crate::compiler) ready_artifact_item_count: usize,
    /// First dependency-free work item, if any completed page has one.
    pub(in crate::compiler) first_ready_item_index: Option<usize>,
    /// First dependency-free artifact-backed item, if any completed page has one.
    pub(in crate::compiler) first_ready_artifact_item_index: Option<usize>,
}

/// Verifies that an initial-progress checkpoint still matches the queue shape.
///
/// The checkpoint is only valid for the same target, page size, queue item
/// count, and bounded summary counts. This prevents resuming a chunked prepare
/// after the work-queue records have been regenerated with a different shape.
pub(in crate::compiler) fn validate_initial_work_queue_progress_prepare_progress(
    progress: &InitialWorkQueueProgressPrepareProgress,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
) -> Result<(), CompileError> {
    validate_work_queue_index(queue, queue.target)?;
    if progress.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != queue.target {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare target {:?} does not match queue target {:?}",
            progress.target, queue.target
        )));
    }
    if page_size == 0 {
        return Err(library_partition_contract_error(
            "work queue progress prepare page_size is zero",
        ));
    }
    if page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare page_size {page_size} exceeds record cap {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let page_count = queue.work_item_count.div_ceil(page_size);
    if progress.work_item_count != queue.work_item_count
        || progress.page_size != page_size
        || progress.page_count != page_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare shape item/page-size/page-count {}/{}/{} does not match expected {}/{}/{}",
            progress.work_item_count,
            progress.page_size,
            progress.page_count,
            queue.work_item_count,
            page_size,
            page_count
        )));
    }
    if progress.next_page_index > progress.page_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare next page {} exceeds page count {}",
            progress.next_page_index, progress.page_count
        )));
    }
    if progress.artifact_item_count > queue.artifact_item_count
        || progress.ready_item_count > queue.work_item_count
        || progress.ready_artifact_item_count > progress.ready_item_count
        || progress.ready_artifact_item_count > progress.artifact_item_count
    {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare counts artifact/ready/ready-artifact {}/{}/{} exceed queue item counts {}/{}",
            progress.artifact_item_count,
            progress.ready_item_count,
            progress.ready_artifact_item_count,
            queue.artifact_item_count,
            queue.work_item_count
        )));
    }
    if let Some(first_ready_item_index) = progress.first_ready_item_index {
        if first_ready_item_index >= queue.work_item_count || progress.ready_item_count == 0 {
            return Err(library_partition_contract_error(format!(
                "work queue progress prepare first ready item {first_ready_item_index} is invalid"
            )));
        }
    } else if progress.ready_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare has {} ready items but no first ready item",
            progress.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = progress.first_ready_artifact_item_index {
        if first_ready_artifact_item_index >= queue.work_item_count
            || progress.ready_artifact_item_count == 0
        {
            return Err(library_partition_contract_error(format!(
                "work queue progress prepare first ready artifact item {first_ready_artifact_item_index} is invalid"
            )));
        }
    } else if progress.ready_artifact_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare has {} ready artifact items but no first ready artifact item",
            progress.ready_artifact_item_count
        )));
    }
    Ok(())
}

/// Converts a validated initial-progress checkpoint into the final progress index.
///
/// Initial progress has no completed or claimed items, so the generated index
/// carries only queue shape and ready-item summaries accumulated from the
/// progress pages.
pub(in crate::compiler) fn initial_progress_index_from_prepare(
    progress: &InitialWorkQueueProgressPrepareProgress,
) -> SourcePackWorkQueueProgressIndex {
    SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: progress.target,
        work_item_count: progress.work_item_count,
        page_size: progress.page_size,
        page_count: progress.page_count,
        artifact_item_count: progress.artifact_item_count,
        completed_item_count: 0,
        ready_item_count: progress.ready_item_count,
        ready_artifact_item_count: progress.ready_artifact_item_count,
        claimed_item_count: 0,
        first_ready_item_index: progress.first_ready_item_index,
        first_ready_artifact_item_index: progress.first_ready_artifact_item_index,
    }
}

/// Advances an initial-progress checkpoint after a progress page is stored.
///
/// The page must be the next expected page for the checkpoint. Its summary is
/// folded into the aggregate counts before `next_page_index` is incremented.
pub(in crate::compiler) fn update_prepare_progress_from_page(
    progress: &mut InitialWorkQueueProgressPrepareProgress,
    page: &SourcePackWorkQueueProgressPage,
) -> Result<(), CompileError> {
    validate_progress_page(page, progress.target, Some(page.page_index))?;
    if page.page_index != progress.next_page_index {
        return Err(library_partition_contract_error(format!(
            "work queue progress prepare expected page {} but saw {}",
            progress.next_page_index, page.page_index
        )));
    }
    let summary = progress_page_summary(page);
    progress.artifact_item_count = progress
        .artifact_item_count
        .saturating_add(summary.artifact_item_count);
    progress.ready_item_count = progress
        .ready_item_count
        .saturating_add(summary.ready_item_count);
    progress.ready_artifact_item_count = progress
        .ready_artifact_item_count
        .saturating_add(summary.ready_artifact_item_count);
    progress.first_ready_item_index = progress
        .first_ready_item_index
        .or(summary.first_ready_item_index);
    progress.first_ready_artifact_item_index = progress
        .first_ready_artifact_item_index
        .or(summary.first_ready_artifact_item_index);
    progress.next_page_index = progress.next_page_index.checked_add(1).ok_or_else(|| {
        library_partition_contract_error("work queue progress prepare next page index overflows")
    })?;
    Ok(())
}

/// Builds one initial progress page by reading the corresponding work-queue items.
///
/// Dependency-free items become initially ready. Artifact-backed items are
/// tracked separately so the execution layer can identify ready artifact work
/// without scanning every work item again.
pub(in crate::compiler) fn initial_progress_page_from_queue_pages(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    page_index: usize,
    page_size: usize,
    work_item_count: usize,
) -> Result<SourcePackWorkQueueProgressPage, CompileError> {
    if page_size == 0 || page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue progress page_size {page_size} exceeds bounds 1..={}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let first_item_index = page_index.checked_mul(page_size).ok_or_else(|| {
        library_partition_contract_error(format!(
            "work queue progress page {page_index} first item index overflows"
        ))
    })?;
    if first_item_index >= work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue progress page {page_index} starts at {first_item_index} but work item count is {work_item_count}"
        )));
    }
    let item_count = page_size.min(work_item_count - first_item_index);
    let mut artifact_item_indices = Vec::new();
    let mut ready_item_indices = Vec::new();
    let mut ready_artifact_item_indices = Vec::new();
    let mut remaining_dependency_counts = Vec::new();
    let mut remaining_dependent_counts = Vec::new();
    let item_end = first_item_index + item_count;
    for item_index in first_item_index..item_end {
        let item = store.load_work_queue_page_for_target(target, item_index)?;
        validate_work_queue_page(&item, target, Some(item_index))?;
        let artifact_backed = work_queue_item_kind_is_artifact_backed(item.kind);
        if artifact_backed {
            artifact_item_indices.push(item_index);
        }
        let dependency_count = work_queue_page_dependency_count(&item);
        if dependency_count == 0 {
            ready_item_indices.push(item_index);
            if artifact_backed {
                ready_artifact_item_indices.push(item_index);
            }
        } else {
            remaining_dependency_counts.push(SourcePackWorkQueueRemainingDependencyCount {
                item_index,
                remaining_dependency_count: dependency_count,
            });
        }
        let dependent_count = work_queue_page_dependent_count(&item);
        if dependent_count != 0 {
            remaining_dependent_counts.push(SourcePackWorkQueueRemainingDependentCount {
                item_index,
                remaining_dependent_count: dependent_count,
            });
        }
    }
    let page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target,
        page_index,
        first_item_index,
        item_count,
        artifact_item_indices,
        remaining_dependency_counts,
        remaining_dependent_counts,
        completed_item_indices: Vec::new(),
        ready_item_indices,
        ready_artifact_item_indices,
        claimed_items: Vec::new(),
    };
    validate_progress_page(&page, target, Some(page_index))?;
    Ok(page)
}

/// Writes completed progress directory rollups after a progress page lands.
///
/// Directory pages are emitted only when the just-written progress page closes
/// its directory span. Directory-index pages are emitted with the same boundary
/// rule one level higher.
pub(in crate::compiler) fn store_directory_pages_after_progress_page(
    store: &FilesystemArtifactStore,
    index: &SourcePackWorkQueueProgressIndex,
    progress_page_index: usize,
) -> Result<(), CompileError> {
    validate_progress_index(index, index.target)?;
    let directory_page_index = progress_directory_page_index_for_progress_page(progress_page_index);
    let (first_progress_page_index, progress_page_count) =
        progress_directory_page_range(index, directory_page_index)?;
    if progress_page_index + 1 != first_progress_page_index + progress_page_count {
        return Ok(());
    }
    let directory_page = progress_directory_page_from_summaries(
        store,
        index.target,
        index,
        &[],
        directory_page_index,
    )?;
    store.store_work_queue_progress_directory_page_for_target(index.target, &directory_page)?;

    let directory_index_page_index =
        progress_directory_index_page_index_for_directory_page(directory_page_index);
    let (first_directory_page_index, directory_page_count) =
        progress_directory_index_page_range(index, directory_index_page_index)?;
    if directory_page_index + 1 != first_directory_page_index + directory_page_count {
        return Ok(());
    }
    let directory_index_page = progress_directory_index_page_from_directory_pages(
        store,
        index.target,
        index,
        &[],
        directory_index_page_index,
    )?;
    store.store_work_queue_progress_directory_index_page_for_target(
        index.target,
        &directory_index_page,
        index,
    )?;
    Ok(())
}

/// Stores a bounded chunk of initial work-queue progress pages.
///
/// The function is resumable and idempotent: if the final progress index already
/// exists, it reports completion without rewriting pages. Otherwise it resumes
/// from the checkpoint, stores at most `max_new_pages`, and writes the final
/// index when the last progress page has been generated.
pub(in crate::compiler) fn store_initial_progress_chunk(
    store: &FilesystemArtifactStore,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
    max_new_pages: usize,
) -> Result<FilesystemWorkQueueProgressPrepareStepResult, CompileError> {
    if max_new_pages == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue progress chunk max_new_pages must be greater than zero".into(),
        ));
    }
    validate_work_queue_index(queue, queue.target)?;
    if page_size == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue progress chunk page_size must be greater than zero".into(),
        ));
    }
    if page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "source-pack work queue progress chunk page_size {page_size} exceeds record cap {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let page_count = queue.work_item_count.div_ceil(page_size);
    if store
        .work_queue_progress_index_path_for_target(queue.target)
        .is_file()
    {
        let index = store.load_work_queue_progress_index_for_target(queue.target)?;
        return Ok(FilesystemWorkQueueProgressPrepareStepResult {
            target: queue.target,
            complete: true,
            work_item_count: index.work_item_count,
            page_size: index.page_size,
            page_count: index.page_count,
            next_page_index: index.page_count,
            new_progress_page_count: 0,
            artifact_item_count: index.artifact_item_count,
            ready_item_count: index.ready_item_count,
            ready_artifact_item_count: index.ready_artifact_item_count,
            first_ready_item_index: index.first_ready_item_index,
            first_ready_artifact_item_index: index.first_ready_artifact_item_index,
            work_queue_progress_index_path: Some(
                store.work_queue_progress_index_path_for_target(queue.target),
            ),
        });
    }

    let progress_path = store.work_queue_progress_prepare_progress_path_for_target(queue.target);
    let mut progress = if progress_path.is_file() {
        load_initial_work_queue_progress_prepare_progress(store, queue, page_size)?
    } else {
        InitialWorkQueueProgressPrepareProgress {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION,
            target: queue.target,
            work_item_count: queue.work_item_count,
            page_size,
            page_count,
            next_page_index: 0,
            artifact_item_count: 0,
            ready_item_count: 0,
            ready_artifact_item_count: 0,
            first_ready_item_index: None,
            first_ready_artifact_item_index: None,
        }
    };
    validate_initial_work_queue_progress_prepare_progress(&progress, queue, page_size)?;

    let mut new_progress_page_count = 0usize;
    while progress.next_page_index < page_count && new_progress_page_count < max_new_pages {
        let progress_page = initial_progress_page_from_queue_pages(
            store,
            queue.target,
            progress.next_page_index,
            page_size,
            queue.work_item_count,
        )?;
        store.store_work_queue_progress_page(&progress_page)?;
        update_prepare_progress_from_page(&mut progress, &progress_page)?;
        let progress_index = initial_progress_index_from_prepare(&progress);
        store_directory_pages_after_progress_page(
            store,
            &progress_index,
            progress_page.page_index,
        )?;
        store_prepare_progress(store, &progress)?;
        new_progress_page_count = new_progress_page_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("work queue progress chunk new page count overflows")
        })?;
    }

    let mut work_queue_progress_index_path = None;
    if progress.next_page_index == page_count {
        if progress.artifact_item_count != queue.artifact_item_count {
            return Err(library_partition_contract_error(format!(
                "work queue progress prepared {} artifact-backed items but queue index records {}",
                progress.artifact_item_count, queue.artifact_item_count
            )));
        }
        let index = initial_progress_index_from_prepare(&progress);
        validate_progress_index(&index, queue.target)?;
        work_queue_progress_index_path = Some(store.store_work_queue_progress_index(&index)?);
    }

    Ok(FilesystemWorkQueueProgressPrepareStepResult {
        target: queue.target,
        complete: work_queue_progress_index_path.is_some(),
        work_item_count: progress.work_item_count,
        page_size: progress.page_size,
        page_count: progress.page_count,
        next_page_index: progress.next_page_index,
        new_progress_page_count,
        artifact_item_count: progress.artifact_item_count,
        ready_item_count: progress.ready_item_count,
        ready_artifact_item_count: progress.ready_artifact_item_count,
        first_ready_item_index: progress.first_ready_item_index,
        first_ready_artifact_item_index: progress.first_ready_artifact_item_index,
        work_queue_progress_index_path,
    })
}

/// Persists the resumable initial-progress checkpoint atomically.
///
/// The checkpoint is validated against its own recorded shape before it is
/// written, catching corrupted or internally inconsistent counters before the
/// next chunk attempts to resume.
pub(in crate::compiler) fn store_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &InitialWorkQueueProgressPrepareProgress,
) -> Result<PathBuf, CompileError> {
    let queue_shape = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target: progress.target,
        work_item_count: progress.work_item_count,
        artifact_item_count: progress.artifact_item_count,
        final_item_index: progress.work_item_count.saturating_sub(1),
        final_job_index: progress.work_item_count.saturating_sub(1),
    };
    validate_initial_work_queue_progress_prepare_progress(
        progress,
        &queue_shape,
        progress.page_size,
    )?;
    let path = store.work_queue_progress_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack work queue progress prepare progress: {err}"
        ))
    })?;
    write_file_atomic(
        &path,
        &bytes,
        "source-pack work queue progress prepare progress",
    )?;
    Ok(path)
}

/// Loads and validates the resumable initial-progress checkpoint for a queue.
///
/// Callers provide the current queue index and page size so stale checkpoints
/// from a previous queue shape are rejected before any new progress pages are
/// derived.
pub(in crate::compiler) fn load_initial_work_queue_progress_prepare_progress(
    store: &FilesystemArtifactStore,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
) -> Result<InitialWorkQueueProgressPrepareProgress, CompileError> {
    let path = store.work_queue_progress_prepare_progress_path_for_target(queue.target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack work queue progress prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<InitialWorkQueueProgressPrepareProgress>(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack work queue progress prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_initial_work_queue_progress_prepare_progress(&progress, queue, page_size)?;
    Ok(progress)
}
