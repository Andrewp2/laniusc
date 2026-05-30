use super::*;

pub fn work_queue_progress_snapshot(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_ready_items: usize,
) -> Result<FilesystemWorkQueueProgressSnapshot, CompileError> {
    work_queue_progress_snapshot_at(
        artifact_root,
        target,
        max_ready_items,
        Some(current_unix_nanos()?),
    )
}

pub fn work_queue_progress_snapshot_at(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemWorkQueueProgressSnapshot, CompileError> {
    let store = FilesystemArtifactStore::new(artifact_root);
    let index = store.load_work_queue_progress_index_for_target(target)?;
    work_queue_progress_snapshot_from_index(&store, target, &index, max_ready_items, now_unix_nanos)
}

pub(in crate::compiler) fn work_queue_progress_snapshot_from_index(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackWorkQueueProgressIndex,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemWorkQueueProgressSnapshot, CompileError> {
    let max_ready_items = limit_ready_state_items(max_ready_items);
    validate_progress_index(index, target)?;
    let complete = index.completed_item_count == index.work_item_count;
    let ready_item_indices = if complete || max_ready_items == 0 {
        Vec::new()
    } else {
        progress_ready_unclaimed_item_indices_from_index_limited(
            store,
            target,
            index,
            now_unix_nanos,
            Some(max_ready_items),
        )?
    };
    Ok(FilesystemWorkQueueProgressSnapshot {
        target,
        work_item_count: index.work_item_count,
        completed_item_count: index.completed_item_count,
        ready_item_count: index.ready_item_count,
        claimed_item_count: index.claimed_item_count,
        first_ready_item_index: index.first_ready_item_index,
        ready_item_indices,
        complete,
        work_queue_index_path: store.work_queue_index_path_for_target(target),
        progress_index_path: store.work_queue_progress_index_path_for_target(target),
    })
}

pub(in crate::compiler) fn final_linked_output_for_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    progress: &FilesystemWorkQueueProgressSnapshot,
) -> Result<(Option<String>, Option<PathBuf>), CompileError> {
    if !progress.complete {
        return Ok((None, None));
    }
    let link_index = store.load_hierarchical_link_execution_index_for_target(target)?;
    let linked_output_key = link_index.final_output_key;
    let linked_output_path =
        store.require_artifact_key_file(&linked_output_key, "complete linked output")?;
    Ok((Some(linked_output_key), Some(linked_output_path)))
}

pub(in crate::compiler) fn completed_hierarchical_link_output_path(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<PathBuf, CompileError> {
    let artifact_label = if page.final_output {
        "completed linked output"
    } else {
        "completed partial link output"
    };
    store.require_artifact_key_file(&page.output_key, artifact_label)
}
