use super::*;

/// Execute an already claimed artifact-manifest batch with a paged in-memory
/// artifact executor.
pub fn execute_claimed_artifact_manifest_batch<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_claimed_shard_batch_paged(
        artifact_root,
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
    )
}

/// Execute an already claimed shard batch with an in-memory artifact executor.
pub fn execute_claimed_shard_batch<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.as_ref();
    let mut store = FilesystemArtifactStore::new(&artifact_root);
    let execution_shard = execution_shard_for_batch_locator(&store, target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(store.load_link_input_shard_index_for_target(target)?)
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(execution_shard_batch_result(&execution_shard, batch_index)?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_artifact_execution_shard_batch(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )?
    };

    let build_state_path = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            update_ready_frontier_after_batch_completion(
                &store,
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store.load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        let build_state_path = store.store_build_state_marker_for_target(target, &state_marker)?;
        build_state_path
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;
    Ok(FilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

/// Execute an already claimed shard batch with a paged in-memory artifact
/// executor.
pub fn execute_claimed_shard_batch_paged<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    execute_claimed_shard_batch_paged_with_store(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
}

/// Execute an already claimed shard batch with a paged path artifact executor.
pub fn execute_claimed_path_shard_batch_paged<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = ArtifactPathStore::new(&artifact_root);
    execute_claimed_shard_batch_paged_with_store(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
}

/// Execute an already claimed shard batch with an async paged in-memory
/// artifact executor.
pub async fn execute_claimed_shard_batch_paged_async<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    execute_claimed_shard_batch_paged_with_store_async(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
    .await
}

/// Execute an already claimed shard batch with an async paged path artifact
/// executor.
pub async fn execute_claimed_path_shard_batch_paged_async<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let store = ArtifactPathStore::new(&artifact_root);
    execute_claimed_shard_batch_paged_with_store_async(
        batch_index,
        target,
        worker_id,
        now_unix_nanos,
        executor,
        store,
    )
    .await
}

/// Executes a claimed shard batch using an async executor and explicit artifact store.
pub(in crate::compiler) async fn execute_claimed_shard_batch_paged_with_store_async<E, S>(
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref();
    let execution_shard = execution_shard_for_batch_locator(store.as_ref(), target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(
                store
                    .as_ref()
                    .load_link_input_shard_index_for_target(target)?,
            )
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(execution_shard_batch_result(&execution_shard, batch_index)?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_execution_shard_batch_paged_async(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )
        .await?
    };

    let build_state_path = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.as_ref().store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            update_ready_frontier_after_batch_completion(
                store.as_ref(),
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store
            .as_ref()
            .load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        store
            .as_ref()
            .store_build_state_marker_for_target(target, &state_marker)?
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.as_ref().path_for_key(key))
        .transpose()?;
    let store = store.as_ref();
    Ok(FilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

/// Executes a claimed shard batch using a sync executor and explicit artifact store.
pub(in crate::compiler) fn execute_claimed_shard_batch_paged_with_store<E, S>(
    batch_index: usize,
    target: SourcePackArtifactTarget,
    worker_id: impl AsRef<str>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
    mut store: S,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    let worker_id = worker_id.as_ref();
    let execution_shard = execution_shard_for_batch_locator(store.as_ref(), target, batch_index)?;
    let batch_shard = execution_shard.shard.clone();
    let link_input_shard_index =
        if execution_shard_batch_contains_link_job(&execution_shard, batch_index)? {
            Some(
                store
                    .as_ref()
                    .load_link_input_shard_index_for_target(target)?,
            )
        } else {
            None
        };
    let replay_result = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;

        if progress.is_batch_completed(batch_index) {
            Some(execution_shard_batch_result(&execution_shard, batch_index)?)
        } else {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
            None
        }
    };

    let result = if let Some(result) = replay_result {
        result
    } else {
        execute_execution_shard_batch_paged(
            &execution_shard,
            link_input_shard_index.as_ref(),
            batch_index,
            target,
            executor,
            &mut store,
        )?
    };

    let build_state_path = {
        let _state_lock = store.as_ref().try_lock_build_state_for_target(target)?;
        let mut progress = store
            .as_ref()
            .load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            progress.require_batch_claimed_by(batch_index, worker_id, now_unix_nanos)?;
        }
        progress.record_batch_result(&result)?;
        store.as_ref().store_build_progress_shard(&progress)?;
        if !batch_was_completed {
            update_ready_frontier_after_batch_completion(
                store.as_ref(),
                target,
                batch_index,
                now_unix_nanos,
            )?;
        }
        let summary = store
            .as_ref()
            .load_build_progress_summary_for_target(target)?;
        let state_marker = SourcePackBuildState {
            version: SOURCE_PACK_BUILD_STATE_VERSION,
            completed_batch_count: summary.completed_batch_count,
            claimed_batch_count: summary.claimed_batch_count,
            linked_output_key: result
                .linked_output_key
                .clone()
                .or(summary.linked_output_key),
        };
        store
            .as_ref()
            .store_build_state_marker_for_target(target, &state_marker)?
    };
    let linked_output_path = result
        .linked_output_key
        .as_ref()
        .map(|key| store.as_ref().path_for_key(key))
        .transpose()?;
    let store = store.as_ref();
    Ok(FilesystemArtifactBatchExecutionResult {
        batch_index: result.batch_index,
        job_count: result.job_count,
        linked_output_key: result.linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}
