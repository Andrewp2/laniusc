use super::*;

pub fn execute_claimed_artifact_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    let batch_index = work_queue_singleton_artifact_batch_index_for_item(&store, target, &item)?
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} has no singleton artifact batch execution mapping"
        ))
        })?;

    let executed_batch = execute_claimed_shard_batch_paged(
        &artifact_root,
        batch_index,
        target,
        &worker_id,
        now_unix_nanos,
        executor,
    )?;
    let completion = complete_claimed_work_queue_item(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(FilesystemWorkQueueArtifactItemExecutionResult {
        item_index,
        worker_id,
        executed_batch,
        completion,
    })
}

pub fn execute_claimed_artifact_path_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueArtifactItemExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    let batch_index = work_queue_singleton_artifact_batch_index_for_item(&store, target, &item)?
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} has no singleton artifact batch execution mapping"
        ))
        })?;

    let executed_batch = execute_claimed_path_shard_batch_paged(
        &artifact_root,
        batch_index,
        target,
        &worker_id,
        now_unix_nanos,
        executor,
    )?;
    let completion = complete_claimed_work_queue_item(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(FilesystemWorkQueueArtifactItemExecutionResult {
        item_index,
        worker_id,
        executed_batch,
        completion,
    })
}

pub fn execute_claimed_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let batch_index = work_queue_singleton_artifact_batch_index_for_item(
                &store, target, &item,
            )?
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack work item {item_index} has no singleton artifact batch execution mapping"
                ))
            })?;
            let already_completed = work_queue_item_completed_or_claimed_by(
                &store,
                target,
                item_index,
                &worker_id,
                now_unix_nanos,
            )?;
            if !already_completed {
                let lease_expires_unix_nanos = work_queue_item_claim_lease_expires_by(
                    &store,
                    target,
                    item_index,
                    &worker_id,
                    now_unix_nanos,
                )?;
                work_queue_record_artifact_batch_claim(
                    &store,
                    target,
                    batch_index,
                    &worker_id,
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
            }
            let executed = execute_claimed_artifact_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )?;
            Ok(FilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: FilesystemWorkQueueExecutedItem::ArtifactBatch(executed.executed_batch),
                completion: executed.completion,
            })
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let executed = execute_claimed_link_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )?;
            Ok(FilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: FilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(
                    executed.executed_link_group,
                ),
                completion: executed.completion,
            })
        }
    }
}

pub fn execute_claimed_path_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueItemExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref().to_string();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let item = store.load_work_queue_page_for_target(target, item_index)?;
    match item.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            let batch_index = work_queue_singleton_artifact_batch_index_for_item(
                &store, target, &item,
            )?
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack work item {item_index} has no singleton artifact batch execution mapping"
                ))
            })?;
            let already_completed = work_queue_item_completed_or_claimed_by(
                &store,
                target,
                item_index,
                &worker_id,
                now_unix_nanos,
            )?;
            if !already_completed {
                let lease_expires_unix_nanos = work_queue_item_claim_lease_expires_by(
                    &store,
                    target,
                    item_index,
                    &worker_id,
                    now_unix_nanos,
                )?;
                work_queue_record_artifact_batch_claim(
                    &store,
                    target,
                    batch_index,
                    &worker_id,
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
            }
            let executed = execute_claimed_artifact_path_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )?;
            Ok(FilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: FilesystemWorkQueueExecutedItem::ArtifactBatch(executed.executed_batch),
                completion: executed.completion,
            })
        }
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce => {
            let executed = execute_claimed_link_path_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )?;
            Ok(FilesystemWorkQueueItemExecutionResult {
                item_index,
                worker_id,
                executed: FilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(
                    executed.executed_link_group,
                ),
                completion: executed.completion,
            })
        }
    }
}

pub fn execute_claimed_link_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: HierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    execute_claimed_link_work_queue_item_with_store(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
        store,
    )
}

pub fn execute_claimed_link_path_work_queue_item<E>(
    artifact_root: impl Into<PathBuf>,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: HierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = ArtifactPathStore::new(&artifact_root);
    execute_claimed_link_work_queue_item_with_store(
        artifact_root,
        item_index,
        target,
        worker_id,
        max_ready_items,
        now_unix_nanos,
        executor,
        store,
    )
}

pub(in crate::compiler) fn execute_claimed_link_work_queue_item_with_store<E, S>(
    artifact_root: PathBuf,
    item_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<FilesystemWorkQueueLinkItemExecutionResult, CompileError>
where
    E: HierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: HierarchicalLinkArtifactStore + ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref().to_string();
    let item = store
        .as_ref()
        .load_work_queue_page_for_target(target, item_index)?;
    if !matches!(
        item.kind,
        SourcePackWorkQueueItemKind::LinkLeaf | SourcePackWorkQueueItemKind::LinkReduce
    ) {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack work item {item_index} is {:?}, not a link item",
            item.kind
        )));
    }
    let group_index = item.link_group_index.ok_or_else(|| {
        library_partition_contract_error(format!(
            "source-pack link work item {item_index} has no link group index"
        ))
    })?;
    let page = store
        .as_ref()
        .load_hierarchical_link_execution_page_for_target(target, group_index)?;
    let expected_item_kind = match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
        SourcePackHierarchicalLinkGroupKind::Reduce => SourcePackWorkQueueItemKind::LinkReduce,
    };
    if item.kind != expected_item_kind || item.job_index != page.job_index {
        return Err(library_partition_contract_error(format!(
            "source-pack link work item {} kind {:?} job {} does not match execution page group {} kind {:?} job {}",
            item.item_index, item.kind, item.job_index, page.group_index, page.kind, page.job_index
        )));
    }

    let already_completed = work_queue_item_completed_or_claimed_by(
        store.as_ref(),
        target,
        item_index,
        &worker_id,
        now_unix_nanos,
    )?;
    if !already_completed {
        execute_hierarchical_link_page(&page, executor, &mut store)?;
    }

    let output_path = completed_hierarchical_link_output_path(store.as_ref(), &page)?;
    let linked_output_key = page.final_output.then(|| page.output_key.clone());
    let linked_output_path = page.final_output.then(|| output_path.clone());
    let executed_link_group = FilesystemHierarchicalLinkGroupExecutionResult {
        group_index: page.group_index,
        job_index: page.job_index,
        kind: page.kind,
        input_interface_count: hierarchical_link_execution_input_interface_count(&page),
        input_object_count: hierarchical_link_execution_input_object_count(&page),
        input_group_count: hierarchical_link_execution_input_group_count(&page),
        descriptor_summary: page.descriptor_summary.clone(),
        output_key: page.output_key.clone(),
        output_path,
        final_output: page.final_output,
        linked_output_key,
        linked_output_path,
    };
    let completion = complete_claimed_work_queue_item(
        &artifact_root,
        item_index,
        target,
        worker_id.clone(),
        max_ready_items,
        now_unix_nanos,
    )?;

    Ok(FilesystemWorkQueueLinkItemExecutionResult {
        item_index,
        worker_id,
        executed_link_group,
        completion,
    })
}

pub(in crate::compiler) fn work_queue_item_completed_or_claimed_by(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<bool, CompileError> {
    let index = store.load_work_queue_progress_index_for_target(target)?;
    let page_index = progress_page_index_for_item(&index, item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    if progress_page_item_is_completed(&page, item_index) {
        return Ok(true);
    }
    progress_page_require_item_claimed_by(&page, item_index, worker_id, now_unix_nanos)?;
    Ok(false)
}

pub(in crate::compiler) fn work_queue_item_claim_lease_expires_by(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    item_index: usize,
    worker_id: &str,
    now_unix_nanos: Option<u128>,
) -> Result<Option<u128>, CompileError> {
    let index = store.load_work_queue_progress_index_for_target(target)?;
    let page_index = progress_page_index_for_item(&index, item_index)?;
    let page = store.load_work_queue_progress_page_for_target(target, page_index)?;
    progress_page_item_claim_lease_expires_by(&page, item_index, worker_id, now_unix_nanos)
}

pub fn step_work_queue<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_work_queue_item(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_items,
        now_unix_nanos,
    )?;
    let executed_item = claim
        .claimed_item_index
        .map(|item_index| {
            execute_claimed_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = executed_item
        .as_ref()
        .map(|execution| execution.completion.progress.clone())
        .unwrap_or_else(|| claim.progress.clone());
    Ok(FilesystemWorkQueueWorkerStepExecutionResult {
        worker_id,
        claimed_item_index: claim.claimed_item_index,
        executed_item,
        progress,
    })
}

pub fn step_path_work_queue<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueWorkerStepExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_work_queue_item(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_items,
        now_unix_nanos,
    )?;
    let executed_item = claim
        .claimed_item_index
        .map(|item_index| {
            execute_claimed_path_work_queue_item(
                &artifact_root,
                item_index,
                target,
                &worker_id,
                max_ready_items,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = executed_item
        .as_ref()
        .map(|execution| execution.completion.progress.clone())
        .unwrap_or_else(|| claim.progress.clone());
    Ok(FilesystemWorkQueueWorkerStepExecutionResult {
        worker_id,
        claimed_item_index: claim.claimed_item_index,
        executed_item,
        progress,
    })
}

pub fn run_work_queue<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
            PartialLinkArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_items = limit_ready_state_items(max_ready_items);
    let step_limit = limit_work_queue_worker_run_items(max_items);
    let mut executed_item_count = 0usize;
    let mut executed_artifact_batch_count = 0usize;
    let mut executed_link_group_count = 0usize;
    let mut progress =
        work_queue_progress_snapshot_at(&artifact_root, target, max_ready_items, now_unix_nanos)?;

    for _ in 0..step_limit {
        let step = step_work_queue(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            max_ready_items,
            now_unix_nanos,
            executor,
        )?;
        progress = step.progress;
        let Some(executed_item) = step.executed_item else {
            break;
        };
        executed_item_count = executed_item_count.saturating_add(1);
        match executed_item.executed {
            FilesystemWorkQueueExecutedItem::ArtifactBatch(_) => {
                executed_artifact_batch_count = executed_artifact_batch_count.saturating_add(1);
            }
            FilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(_) => {
                executed_link_group_count = executed_link_group_count.saturating_add(1);
            }
        }
        if progress.complete {
            break;
        }
    }

    let store = FilesystemArtifactStore::new(&artifact_root);
    let (linked_output_key, linked_output_path) =
        final_linked_output_for_progress(&store, target, &progress)?;
    Ok(FilesystemWorkQueueWorkerRunExecutionResult {
        worker_id,
        executed_item_count,
        executed_artifact_batch_count,
        executed_link_group_count,
        linked_output_key,
        linked_output_path,
        progress,
    })
}

pub fn run_path_work_queue<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    executor: &mut E,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    run_path_work_queue_at(
        artifact_root,
        target,
        worker_id,
        max_items,
        lease_expires_unix_nanos,
        max_ready_items,
        Some(current_unix_nanos()?),
        executor,
    )
}

pub fn run_path_work_queue_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_items: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_items: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemWorkQueueWorkerRunExecutionResult, CompileError>
where
    E: PagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
            PartialLinkArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_items = limit_ready_state_items(max_ready_items);
    let step_limit = limit_work_queue_worker_run_items(max_items);
    let mut executed_item_count = 0usize;
    let mut executed_artifact_batch_count = 0usize;
    let mut executed_link_group_count = 0usize;
    let mut progress =
        work_queue_progress_snapshot_at(&artifact_root, target, max_ready_items, now_unix_nanos)?;

    for _ in 0..step_limit {
        let step = step_path_work_queue(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            max_ready_items,
            now_unix_nanos,
            executor,
        )?;
        progress = step.progress;
        let Some(executed_item) = step.executed_item else {
            break;
        };
        executed_item_count = executed_item_count.saturating_add(1);
        match executed_item.executed {
            FilesystemWorkQueueExecutedItem::ArtifactBatch(_) => {
                executed_artifact_batch_count = executed_artifact_batch_count.saturating_add(1);
            }
            FilesystemWorkQueueExecutedItem::HierarchicalLinkGroup(_) => {
                executed_link_group_count = executed_link_group_count.saturating_add(1);
            }
        }
        if progress.complete {
            break;
        }
    }

    let store = FilesystemArtifactStore::new(&artifact_root);
    let (linked_output_key, linked_output_path) =
        final_linked_output_for_progress(&store, target, &progress)?;
    Ok(FilesystemWorkQueueWorkerRunExecutionResult {
        worker_id,
        executed_item_count,
        executed_artifact_batch_count,
        executed_link_group_count,
        linked_output_key,
        linked_output_path,
        progress,
    })
}
