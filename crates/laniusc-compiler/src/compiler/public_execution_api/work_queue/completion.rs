use super::*;

/// Returns the singleton artifact batch backing a frontend or codegen work item.
pub(in crate::compiler) fn work_queue_singleton_artifact_batch_index_for_item(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<usize>, CompileError> {
    let Some(batch_index) = item.artifact_batch_index else {
        return Ok(None);
    };
    let execution_shard = execution_shard_for_batch_locator(store, target, batch_index)?;
    let batch = execution_shard_job_batch(&execution_shard, batch_index)?;
    if batch.job_indices.as_slice() != [item.job_index] {
        return Err(artifact_shard_contract_error(format!(
            "work queue item {} maps to artifact batch {} with jobs {:?}, expected singleton job {}",
            item.item_index, batch_index, batch.job_indices, item.job_index
        )));
    }
    let job = execution_shard_job(&execution_shard, item.job_index)?;
    let expected_kind = match job.phase {
        SourcePackJobPhase::LibraryFrontend => SourcePackWorkQueueItemKind::LibraryFrontend,
        SourcePackJobPhase::Codegen => SourcePackWorkQueueItemKind::Codegen,
        SourcePackJobPhase::Link => {
            return Err(artifact_shard_contract_error(format!(
                "work queue item {} maps to artifact link job {}; hierarchical link items are not singleton artifact jobs",
                item.item_index, job.job_index
            )));
        }
    };
    if item.kind != expected_kind {
        return Err(artifact_shard_contract_error(format!(
            "work queue item {} kind {:?} maps to artifact job phase {:?}",
            item.item_index, item.kind, job.phase
        )));
    }
    Ok(Some(batch_index))
}

fn work_queue_item_output_key_for_release(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<(String, &'static str)>, CompileError> {
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let Some(batch_index) =
                work_queue_singleton_artifact_batch_index_for_item(store, target, item)?
            else {
                return Ok(None);
            };
            let execution_shard = execution_shard_for_batch_locator(store, target, batch_index)?;
            let job_manifest = execution_shard_job_artifact(&execution_shard, item.job_index)?;
            let (kind, label) = match item.kind {
                SourcePackWorkQueueItemKind::LibraryFrontend => (
                    SourcePackArtifactKind::LibraryInterface,
                    "library interface",
                ),
                SourcePackWorkQueueItemKind::Codegen => {
                    (SourcePackArtifactKind::CodegenObject, "codegen object")
                }
                SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
                    unreachable!()
                }
            };
            let output = single_output_artifact_ref(job_manifest, kind)?;
            Ok(Some((output.key.clone(), label)))
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let group_index = item.link_group_index.ok_or_else(|| {
                library_partition_contract_error(format!(
                    "source-pack link work item {} has no link group index",
                    item.item_index
                ))
            })?;
            let page =
                store.load_hierarchical_link_execution_page_for_target(target, group_index)?;
            let expected_item_kind = match page.kind {
                SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
                SourcePackHierarchicalLinkGroupKind::Reduce => {
                    SourcePackWorkQueueItemKind::LinkReduce
                }
            };
            if item.kind != expected_item_kind || item.job_index != page.job_index {
                return Err(library_partition_contract_error(format!(
                    "source-pack link work item {} kind {:?} job {} does not match execution page group {} kind {:?} job {}",
                    item.item_index,
                    item.kind,
                    item.job_index,
                    page.group_index,
                    page.kind,
                    page.job_index
                )));
            }
            if page.final_output {
                Ok(None)
            } else {
                Ok(Some((page.output_key, "partial link output")))
            }
        }
    }
}

/// In-memory batch of changed progress pages flushed together with index refreshes.
pub(in crate::compiler) struct ChangedProgressPages {
    pages: Vec<SourcePackWorkQueueProgressPage>,
    page_limit: usize,
}

impl ChangedProgressPages {
    /// Creates a changed-page batch with a bounded page capacity.
    pub(in crate::compiler) fn new(page_limit: usize) -> Self {
        Self {
            pages: Vec::new(),
            page_limit: page_limit.max(1),
        }
    }

    fn page_for_item_mut(
        &mut self,
        store: &FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
        item_index: usize,
    ) -> Result<&mut SourcePackWorkQueueProgressPage, CompileError> {
        let page_index = progress_page_index_for_item(index, item_index)?;
        self.page_for_index_mut(store, target, index, page_index)
    }

    /// Loads or returns a mutable changed progress page by page index.
    pub(in crate::compiler) fn page_for_index_mut(
        &mut self,
        store: &FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
        page_index: usize,
    ) -> Result<&mut SourcePackWorkQueueProgressPage, CompileError> {
        validate_progress_index(index, target)?;
        if page_index >= index.page_count {
            return Err(library_partition_contract_error(format!(
                "work queue progress page {page_index} exceeds page count {}",
                index.page_count
            )));
        }
        if let Some(position) = self
            .pages
            .iter()
            .position(|page| page.page_index == page_index)
        {
            return Ok(&mut self.pages[position]);
        }
        if self.pages.len() >= self.page_limit {
            self.flush(store, target, index)?;
        }
        self.pages
            .push(store.load_work_queue_progress_page_for_target(target, page_index)?);
        let position = self.pages.len() - 1;
        Ok(&mut self.pages[position])
    }

    /// Stores changed pages and refreshes the root/directory progress indexes.
    pub(in crate::compiler) fn flush(
        &mut self,
        store: &FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        index: &mut SourcePackWorkQueueProgressIndex,
    ) -> Result<(), CompileError> {
        if self.pages.is_empty() {
            return Ok(());
        }
        progress_refresh_index_from_pages(store, target, index, &self.pages)?;
        for page in &self.pages {
            store.store_work_queue_progress_page(page)?;
        }
        self.pages.clear();
        Ok(())
    }
}

fn work_queue_item_has_no_remaining_dependents(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    item: &SourcePackWorkQueuePage,
) -> Result<bool, CompileError> {
    let page_index = progress_page_index_for_item(index, item.item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    if progress_page_item_has_remaining_dependents(&page, item.item_index) {
        return Ok(false);
    }
    if work_queue_page_dependent_count(item) == 0 {
        return Ok(true);
    }
    Err(library_partition_contract_error(format!(
        "work queue progress page {} has no remaining dependent counter for item {} with {} dependents",
        page.page_index,
        item.item_index,
        work_queue_page_dependent_count(item)
    )))
}

fn work_queue_record_dependent_dependency_completed(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    dependent_item_index: usize,
) -> Result<Option<bool>, CompileError> {
    let (page_changed, became_ready) = {
        let dependent_progress_page =
            changed_page_batch.page_for_item_mut(store, target, index, dependent_item_index)?;
        progress_page_record_dependency_completed(dependent_progress_page, dependent_item_index)?
    };
    if page_changed {
        let dependent_progress_page =
            changed_page_batch.page_for_item_mut(store, target, index, dependent_item_index)?;
        let is_ready = progress_page_item_is_ready(dependent_progress_page, dependent_item_index);
        Ok(Some(became_ready && is_ready))
    } else {
        Ok(None)
    }
}

fn work_queue_record_dependent_range_dependency_completed(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    dependent_range: &SourcePackJobIndexRange,
) -> Result<usize, CompileError> {
    validate_progress_index(index, target)?;
    if dependent_range.is_empty() {
        return Ok(0);
    }
    let Some(range_end) = dependent_range.end_job_index() else {
        return Err(library_partition_contract_error(format!(
            "work queue dependent range starting at {} overflows",
            dependent_range.first_job_index
        )));
    };
    if range_end > index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue dependent range {}..{} exceeds work item count {}",
            dependent_range.first_job_index, range_end, index.work_item_count
        )));
    }

    let start_page_index = progress_page_index_for_item(index, dependent_range.first_job_index)?;
    let last_item_index = range_end - 1;
    let end_page_index = progress_page_index_for_item(index, last_item_index)?;
    let mut newly_ready_item_count = 0usize;
    for page_index in start_page_index..=end_page_index {
        let progress_page =
            changed_page_batch.page_for_index_mut(store, target, index, page_index)?;
        let page_end = progress_page
            .first_item_index
            .checked_add(progress_page.item_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue progress page {} item range overflows",
                    progress_page.page_index
                ))
            })?;
        let update_start = dependent_range
            .first_job_index
            .max(progress_page.first_item_index);
        let update_end = range_end.min(page_end);
        if update_start >= update_end {
            continue;
        }
        let (_page_changed, page_newly_ready_item_count) =
            progress_page_record_dependency_range_completed(
                progress_page,
                update_start,
                update_end - update_start,
            )?;
        newly_ready_item_count = newly_ready_item_count.saturating_add(page_newly_ready_item_count);
    }
    Ok(newly_ready_item_count)
}

/// Records dependency completion for every dependent of a completed work item.
pub(in crate::compiler) fn record_work_item_dependents_completed(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    work_item: &SourcePackWorkQueuePage,
) -> Result<usize, CompileError> {
    validate_work_queue_page(work_item, target, Some(work_item.item_index))?;
    let mut newly_ready_item_count = 0usize;
    if !work_item.dependent_item_indices.is_empty() {
        for &dependent_item_index in &work_item.dependent_item_indices {
            let Some(became_ready) = work_queue_record_dependent_dependency_completed(
                store,
                target,
                index,
                changed_page_batch,
                dependent_item_index,
            )?
            else {
                continue;
            };
            if became_ready {
                newly_ready_item_count = newly_ready_item_count.saturating_add(1);
            }
        }
    } else {
        let mut seen_dependent_count = 0usize;
        for page_index in 0..work_item.dependent_page_count {
            let page = store.load_work_queue_dependents_page_for_target(
                target,
                work_item.item_index,
                page_index,
            )?;
            seen_dependent_count = seen_dependent_count.saturating_add(page.dependent_count);
            for &dependent_item_index in &page.dependent_item_indices {
                let Some(became_ready) = work_queue_record_dependent_dependency_completed(
                    store,
                    target,
                    index,
                    changed_page_batch,
                    dependent_item_index,
                )?
                else {
                    continue;
                };
                if became_ready {
                    newly_ready_item_count = newly_ready_item_count.saturating_add(1);
                }
            }
        }
        if seen_dependent_count != work_item.dependent_item_count {
            return Err(library_partition_contract_error(format!(
                "work queue item {} iterated {} dependents but expected {}",
                work_item.item_index, seen_dependent_count, work_item.dependent_item_count
            )));
        }
    }
    for dependent_range in &work_item.dependent_item_ranges {
        newly_ready_item_count = newly_ready_item_count.saturating_add(
            work_queue_record_dependent_range_dependency_completed(
                store,
                target,
                index,
                changed_page_batch,
                dependent_range,
            )?,
        );
    }
    Ok(newly_ready_item_count)
}

fn record_dependent_release_candidate_completed(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    item_index: usize,
) -> Result<bool, CompileError> {
    let no_remaining_dependents = {
        let page = changed_page_batch.page_for_item_mut(store, target, index, item_index)?;
        progress_page_record_dependent_completed(page, item_index)?
    };
    Ok(no_remaining_dependents)
}

fn release_work_queue_dependency_item_after_completion(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    release_candidate_index: usize,
) -> Result<usize, CompileError> {
    let release_candidate =
        store.load_work_queue_page_for_target(target, release_candidate_index)?;
    if record_dependent_release_candidate_completed(
        store,
        target,
        index,
        changed_page_batch,
        release_candidate_index,
    )? {
        if let Some(key) = release_work_queue_item_output(store, target, &release_candidate)? {
            drop(key);
            return Ok(1);
        }
    }
    Ok(0)
}

fn release_work_queue_dependency_range_after_completion(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    changed_page_batch: &mut ChangedProgressPages,
    dependency_range: &SourcePackJobIndexRange,
) -> Result<usize, CompileError> {
    validate_progress_index(index, target)?;
    if dependency_range.is_empty() {
        return Ok(0);
    }
    let Some(range_end) = dependency_range.end_job_index() else {
        return Err(library_partition_contract_error(format!(
            "work queue dependency range starting at {} overflows",
            dependency_range.first_job_index
        )));
    };
    if range_end > index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue dependency range {}..{} exceeds work item count {}",
            dependency_range.first_job_index, range_end, index.work_item_count
        )));
    }

    let start_page_index = progress_page_index_for_item(index, dependency_range.first_job_index)?;
    let last_item_index = range_end - 1;
    let end_page_index = progress_page_index_for_item(index, last_item_index)?;
    let mut released_count = 0usize;
    for page_index in start_page_index..=end_page_index {
        let progress_page =
            changed_page_batch.page_for_index_mut(store, target, index, page_index)?;
        let page_end = progress_page
            .first_item_index
            .checked_add(progress_page.item_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue progress page {} item range overflows",
                    progress_page.page_index
                ))
            })?;
        let update_start = dependency_range
            .first_job_index
            .max(progress_page.first_item_index);
        let update_end = range_end.min(page_end);
        if update_start >= update_end {
            continue;
        }
        let (_page_changed, no_remaining_dependent_item_indices) =
            progress_page_record_dependent_range_completed(
                progress_page,
                update_start,
                update_end - update_start,
            )?;
        for release_candidate_index in no_remaining_dependent_item_indices {
            let release_candidate =
                store.load_work_queue_page_for_target(target, release_candidate_index)?;
            if let Some(key) = release_work_queue_item_output(store, target, &release_candidate)? {
                drop(key);
                released_count = released_count.saturating_add(1);
            }
        }
    }
    Ok(released_count)
}

fn release_work_queue_item_output(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item: &SourcePackWorkQueuePage,
) -> Result<Option<String>, CompileError> {
    let Some((key, label)) = work_queue_item_output_key_for_release(store, target, item)? else {
        return Ok(None);
    };
    remove_artifact(store.root(), &key, label)?;
    Ok(Some(key))
}

/// Releases dependency artifacts whose final dependent completed.
pub(in crate::compiler) fn release_work_queue_consumed_outputs_after_completion(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &mut SourcePackWorkQueueProgressIndex,
    completed_item: &SourcePackWorkQueuePage,
) -> Result<usize, CompileError> {
    validate_work_queue_page(completed_item, target, Some(completed_item.item_index))?;
    let mut released_count = 0usize;
    let mut changed_page_batch =
        ChangedProgressPages::new(SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT);
    if !completed_item.dependency_item_indices.is_empty() {
        for &release_candidate_index in &completed_item.dependency_item_indices {
            released_count =
                released_count.saturating_add(release_work_queue_dependency_item_after_completion(
                    store,
                    target,
                    index,
                    &mut changed_page_batch,
                    release_candidate_index,
                )?);
        }
    } else {
        let mut seen_dependency_count = 0usize;
        for page_index in 0..completed_item.dependency_page_count {
            let page = store.load_work_queue_dependencies_page_for_target(
                target,
                completed_item.item_index,
                page_index,
            )?;
            seen_dependency_count = seen_dependency_count.saturating_add(page.dependency_count);
            for &release_candidate_index in &page.dependency_item_indices {
                released_count = released_count.saturating_add(
                    release_work_queue_dependency_item_after_completion(
                        store,
                        target,
                        index,
                        &mut changed_page_batch,
                        release_candidate_index,
                    )?,
                );
            }
        }
        if seen_dependency_count != completed_item.dependency_item_count {
            return Err(library_partition_contract_error(format!(
                "work queue item {} iterated {} dependencies but expected {}",
                completed_item.item_index,
                seen_dependency_count,
                completed_item.dependency_item_count
            )));
        }
    }
    for dependency_range in &completed_item.dependency_item_ranges {
        released_count =
            released_count.saturating_add(release_work_queue_dependency_range_after_completion(
                store,
                target,
                index,
                &mut changed_page_batch,
                dependency_range,
            )?);
    }
    changed_page_batch.flush(store, target, index)?;
    {
        let release_candidate =
            store.load_work_queue_page_for_target(target, completed_item.item_index)?;
        if work_queue_item_has_no_remaining_dependents(store, target, index, &release_candidate)? {
            if let Some(key) = release_work_queue_item_output(store, target, &release_candidate)? {
                drop(key);
                released_count = released_count.saturating_add(1);
            }
        }
    }
    Ok(released_count)
}
