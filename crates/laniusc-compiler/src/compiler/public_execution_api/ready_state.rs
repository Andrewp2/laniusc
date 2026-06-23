use super::*;

fn validate_completed_batch_artifacts(
    store: &FilesystemArtifactStore,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<(), CompileError> {
    let batch = execution_shard_job_batch(execution_shard, batch_index)?;
    for &job_index in &batch.job_indices {
        let job_manifest = execution_shard_job_artifact(execution_shard, job_index)?;
        for artifact in &job_manifest.outputs {
            if !store.artifact_exists(artifact)? {
                return Err(source_pack_progress_state_error(format!(
                    "source-pack build state marks batch {} complete but output artifact {:?} from job {} is missing",
                    batch.batch_index, artifact.key, job_manifest.job_index
                )));
            }
        }
    }
    Ok(())
}

/// Validates that every ready batch's dependency artifacts are complete and present.
pub(in crate::compiler) fn validate_ready_batch_dependency_artifacts(
    store: &FilesystemArtifactStore,
    job_batch_count: usize,
    target: SourcePackArtifactTarget,
    ready_batch_indices: &[usize],
) -> Result<(), CompileError> {
    for &ready_batch_index in ready_batch_indices {
        if ready_batch_index >= job_batch_count {
            return Err(artifact_shard_contract_error(format!(
                "ready batch {ready_batch_index} exceeds job batch count {job_batch_count}"
            )));
        }
        let ready_execution_shard =
            execution_shard_for_batch_locator(store, target, ready_batch_index)?;
        validate_execution_shard(&ready_execution_shard, target)?;
        let dependency =
            execution_shard_batch_dependency(&ready_execution_shard, ready_batch_index)?;
        for_each_stored_job_batch_dependency_index(
            store,
            target,
            dependency,
            |dependency_batch_index| {
                validate_ready_batch_dependency_artifact(
                    store,
                    job_batch_count,
                    target,
                    ready_batch_index,
                    dependency_batch_index,
                )?;
                Ok(())
            },
        )?;
    }
    Ok(())
}

fn validate_ready_batch_dependency_artifact(
    store: &FilesystemArtifactStore,
    job_batch_count: usize,
    target: SourcePackArtifactTarget,
    ready_batch_index: usize,
    dependency_batch_index: usize,
) -> Result<(), CompileError> {
    if dependency_batch_index >= job_batch_count {
        return Err(artifact_shard_contract_error(format!(
            "ready batch {ready_batch_index} dependency {dependency_batch_index} exceeds job batch count {job_batch_count}"
        )));
    }
    if !batch_completed_from_locator(store, target, dependency_batch_index)? {
        return Err(source_pack_progress_state_error(format!(
            "source-pack ready batch {ready_batch_index} dependency {dependency_batch_index} is not complete"
        )));
    }
    let dependency_execution_shard =
        execution_shard_for_batch_locator(store, target, dependency_batch_index)?;
    validate_execution_shard(&dependency_execution_shard, target)?;
    validate_completed_batch_artifacts(store, &dependency_execution_shard, dependency_batch_index)?;
    Ok(())
}

/// Return ready unclaimed generic-target artifact-manifest batch indices.
pub fn artifact_manifest_ready_batch_indices(
    artifact_root: impl Into<PathBuf>,
) -> Result<Vec<usize>, CompileError> {
    artifact_manifest_ready_batch_indices_for_target(
        artifact_root,
        SourcePackArtifactTarget::Generic,
    )
}

/// Return ready unclaimed artifact-manifest batch indices for a target.
pub fn artifact_manifest_ready_batch_indices_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<Vec<usize>, CompileError> {
    artifact_manifest_ready_batch_indices_limited_for_target(
        artifact_root,
        SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT,
        target,
    )
}

/// Return at most `max_batches` ready unclaimed generic-target
/// artifact-manifest batch indices.
pub fn artifact_manifest_ready_batch_indices_limited(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
) -> Result<Vec<usize>, CompileError> {
    artifact_manifest_ready_batch_indices_limited_for_target(
        artifact_root,
        max_batches,
        SourcePackArtifactTarget::Generic,
    )
}

/// Return at most `max_batches` ready unclaimed artifact-manifest batch indices
/// for a target.
pub fn artifact_manifest_ready_batch_indices_limited_for_target(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    target: SourcePackArtifactTarget,
) -> Result<Vec<usize>, CompileError> {
    let max_batches = limit_ready_state_batches(max_batches);
    let store = FilesystemArtifactStore::new(artifact_root);
    let summary = summary_for_frontier_bounded(&store, target)?;
    let now_unix_nanos = Some(current_unix_nanos()?);
    let ready_batch_indices = if summary.is_complete() || max_batches == 0 {
        Vec::new()
    } else {
        ready_unclaimed_batch_indices_limited(
            &store,
            target,
            &summary,
            now_unix_nanos,
            Some(max_batches),
        )?
    };
    validate_ready_batch_dependency_artifacts(
        &store,
        summary.job_batch_count,
        target,
        &ready_batch_indices,
    )?;
    Ok(ready_batch_indices)
}
