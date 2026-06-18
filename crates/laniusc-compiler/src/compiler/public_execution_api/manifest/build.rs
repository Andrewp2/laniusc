use super::*;

/// Execute ready artifact-manifest batches for a target until the persisted
/// build completes or the bounded full-build step limit is reached.
pub fn execute_artifact_manifest_build_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBuildExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let now_unix_nanos = Some(current_unix_nanos()?);
    let mut progress =
        artifact_manifest_progress_snapshot_at(&artifact_root, 0, target, now_unix_nanos)?;
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_manifest_full_build_batches(usize::MAX);

    for _ in 0..step_limit {
        if progress.complete {
            break;
        }
        let step = step_artifact_manifest_worker_with_progress(
            &artifact_root,
            target,
            "source-pack-build",
            None,
            0,
            now_unix_nanos,
            executor,
        )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        progress = step.progress;
        if !progress.complete && step.claimed_batch_index.is_none() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack filesystem artifact build stopped before completion after executing {executed_batch_count} batches"
            )));
        }
    }
    if !progress.complete {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack filesystem artifact build did not complete within {step_limit} bounded batches; keep calling run_artifact_manifest_worker or execute_ready_artifact_manifest_batches_for_target to continue persisted execution"
        )));
    }

    let linked_output_key = progress.linked_output_key.ok_or_else(|| {
        CompileError::GpuFrontend(
            "source-pack filesystem artifact build completed without a linked output key".into(),
        )
    })?;
    let store = FilesystemArtifactStore::new(&artifact_root);
    let linked_output_path = progress
        .linked_output_path
        .unwrap_or(store.path_for_key(&linked_output_key)?);
    Ok(FilesystemArtifactBuildExecutionResult {
        linked_output_key,
        linked_output_path,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}

/// Execute one ready artifact-manifest batch for a target without first
/// recording an explicit worker claim.
pub fn execute_artifact_manifest_batch_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_shard_batch_for_target(
        artifact_root,
        batch_index,
        target,
        Some(current_unix_nanos()?),
        executor,
    )
}

/// Executes one artifact-manifest shard batch for a concrete target.
pub(in crate::compiler) fn execute_shard_batch_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
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
            if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is claimed by another worker; use claimed-batch execution"
                )));
            }
            if !batch_ready_unclaimed_from_locator(&store, target, batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is not ready in its persisted progress shard"
                )));
            }
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
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let mut progress =
            store.load_or_init_build_progress_shard_for_target(target, &batch_shard)?;
        progress.prune_inactive_batch_claims(now_unix_nanos)?;
        let batch_was_completed = progress.is_batch_completed(batch_index);
        if !batch_was_completed {
            if progress.is_batch_claimed(batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is claimed by another worker; use claimed-batch execution"
                )));
            }
            if !batch_ready_unclaimed_from_locator(&store, target, batch_index, now_unix_nanos)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack batch {batch_index} is not ready in its persisted progress shard"
                )));
            }
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
