use super::*;

/// Claim and execute at most one artifact-manifest batch with a paged in-memory
/// artifact executor.
pub fn step_artifact_manifest_worker<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_artifact_manifest_batch(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_claimed_shard_batch_paged(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;

    finish_artifact_manifest_worker_step(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

/// Claim and execute at most one artifact-manifest batch with a paged path
/// artifact executor.
pub fn step_path_artifact_manifest_worker<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_artifact_manifest_batch(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_claimed_path_shard_batch_paged(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;

    finish_artifact_manifest_worker_step(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

/// Claim and execute at most one artifact-manifest batch with an async paged
/// in-memory artifact executor.
pub async fn step_artifact_manifest_worker_async<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_artifact_manifest_batch(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = if let Some(batch_index) = claim.claimed_batch_index {
        Some(
            execute_claimed_shard_batch_paged_async(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
            .await?,
        )
    } else {
        None
    };

    finish_artifact_manifest_worker_step(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

/// Claim and execute at most one artifact-manifest batch with an async paged
/// path artifact executor.
pub async fn step_path_artifact_manifest_worker_async<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerStepExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_artifact_manifest_batch(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        now_unix_nanos,
    )?;
    let executed_batch = if let Some(batch_index) = claim.claimed_batch_index {
        Some(
            execute_claimed_path_shard_batch_paged_async(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
            .await?,
        )
    } else {
        None
    };

    finish_artifact_manifest_worker_step(
        &artifact_root,
        target,
        worker_id,
        claim.claimed_batch_index,
        executed_batch,
        now_unix_nanos,
    )
}

/// Claim and execute at most one artifact-manifest batch and return a bounded
/// progress snapshot.
pub fn step_artifact_manifest_worker_with_progress<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerStepProgressExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let claim = claim_ready_artifact_manifest_batch_with_progress(
        &artifact_root,
        target,
        worker_id.clone(),
        lease_expires_unix_nanos,
        max_ready_batches,
        now_unix_nanos,
    )?;
    let executed_batch = claim
        .claimed_batch_index
        .map(|batch_index| {
            execute_claimed_shard_batch_paged(
                &artifact_root,
                batch_index,
                target,
                &worker_id,
                now_unix_nanos,
                executor,
            )
        })
        .transpose()?;
    let progress = if executed_batch.is_some() {
        artifact_manifest_progress_snapshot_at(
            &artifact_root,
            max_ready_batches,
            target,
            now_unix_nanos,
        )?
    } else {
        claim.progress
    };

    Ok(FilesystemArtifactWorkerStepProgressExecutionResult {
        worker_id,
        claimed_batch_index: claim.claimed_batch_index,
        executed_batch,
        progress,
    })
}

/// Builds the public result for one artifact-manifest worker step.
pub(in crate::compiler) fn finish_artifact_manifest_worker_step(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: String,
    claimed_batch_index: Option<usize>,
    executed_batch: Option<FilesystemArtifactBatchExecutionResult>,
    _now_unix_nanos: Option<u128>,
) -> Result<FilesystemArtifactWorkerStepExecutionResult, CompileError> {
    let store = FilesystemArtifactStore::new(artifact_root);
    let summary = summary_for_frontier_bounded(&store, target)?;
    let build_state = build_state_from_progress_summary(&summary)?;
    validate_progress_summary_complete_output(&store, &summary)?;
    let complete = summary.is_complete();
    let linked_output_path = build_state
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;

    Ok(FilesystemArtifactWorkerStepExecutionResult {
        worker_id,
        claimed_batch_index,
        executed_batch,
        completed_batch_count: summary.completed_batch_count,
        ready_batch_count: summary.ready_batch_count,
        linked_output_key: build_state.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}

/// Run artifact-manifest worker steps up to `max_batches` and return the final
/// bounded progress snapshot.
pub fn run_artifact_manifest_worker_with_progress<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunProgressExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let max_ready_batches = limit_ready_state_batches(max_ready_batches);
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_worker_run_batches(max_batches);
    let mut last_progress = None;

    for _ in 0..step_limit {
        let step = step_artifact_manifest_worker_with_progress(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            max_ready_batches,
            now_unix_nanos,
            executor,
        )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.progress.complete || step.claimed_batch_index.is_none();
        last_progress = Some(step.progress);
        if should_stop {
            break;
        }
    }

    let progress = match last_progress {
        Some(progress) => progress,
        None => artifact_manifest_progress_snapshot_at(
            &artifact_root,
            max_ready_batches,
            target,
            now_unix_nanos,
        )?,
    };

    Ok(FilesystemArtifactWorkerRunProgressExecutionResult {
        worker_id,
        executed_batch_count,
        progress,
    })
}

/// Run artifact-manifest worker steps up to `max_batches` using the current
/// time for claim pruning.
pub fn run_artifact_manifest_worker<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    run_artifact_manifest_worker_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(current_unix_nanos()?),
        executor,
    )
}

/// Run artifact-manifest worker steps up to `max_batches` using an explicit
/// timestamp for claim pruning.
pub fn run_artifact_manifest_worker_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step = step_artifact_manifest_worker(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            now_unix_nanos,
            executor,
        )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => finish_artifact_manifest_worker_step(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(FilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

/// Run path-artifact manifest worker steps up to `max_batches` using the
/// current time for claim pruning.
pub fn run_path_artifact_manifest_worker<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    run_path_artifact_manifest_worker_at(
        artifact_root,
        target,
        worker_id,
        max_batches,
        lease_expires_unix_nanos,
        Some(current_unix_nanos()?),
        executor,
    )
}

/// Run path-artifact manifest worker steps up to `max_batches` using an
/// explicit timestamp for claim pruning.
pub fn run_path_artifact_manifest_worker_at<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step = step_path_artifact_manifest_worker(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            now_unix_nanos,
            executor,
        )?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => finish_artifact_manifest_worker_step(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(FilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

/// Run async artifact-manifest worker steps up to `max_batches` using an
/// explicit timestamp for claim pruning.
pub async fn run_artifact_manifest_worker_async<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step = step_artifact_manifest_worker_async(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            now_unix_nanos,
            executor,
        )
        .await?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => finish_artifact_manifest_worker_step(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(FilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}

/// Run async path-artifact manifest worker steps up to `max_batches` using an
/// explicit timestamp for claim pruning.
pub async fn run_path_artifact_manifest_worker_async<E>(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    max_batches: usize,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
    executor: &mut E,
) -> Result<FilesystemArtifactWorkerRunExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = ArtifactPath,
            CodegenObjectArtifact = ArtifactPath,
            LinkedOutputArtifact = ArtifactPath,
        >,
{
    let artifact_root = artifact_root.into();
    let worker_id = worker_id.into();
    let mut executed_batch_count = 0usize;
    let step_limit = limit_artifact_worker_run_batches(max_batches);
    let mut last_step = None;

    for _ in 0..step_limit {
        let step = step_path_artifact_manifest_worker_async(
            &artifact_root,
            target,
            worker_id.clone(),
            lease_expires_unix_nanos,
            now_unix_nanos,
            executor,
        )
        .await?;
        if step.executed_batch.is_some() {
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
        let should_stop = step.complete || step.claimed_batch_index.is_none();
        last_step = Some(step);
        if should_stop {
            break;
        }
    }

    let last_step = match last_step {
        Some(step) => step,
        None => finish_artifact_manifest_worker_step(
            &artifact_root,
            target,
            worker_id.clone(),
            None,
            None,
            now_unix_nanos,
        )?,
    };

    Ok(FilesystemArtifactWorkerRunExecutionResult {
        worker_id,
        executed_batch_count,
        completed_batch_count: last_step.completed_batch_count,
        ready_batch_count: last_step.ready_batch_count,
        linked_output_key: last_step.linked_output_key,
        linked_output_path: last_step.linked_output_path,
        complete: last_step.complete,
        build_manifest_path: last_step.build_manifest_path,
        artifact_manifest_path: last_step.artifact_manifest_path,
        build_state_path: last_step.build_state_path,
    })
}
