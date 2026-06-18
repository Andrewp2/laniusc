use super::*;

/// Load or initialize the generic-target artifact-manifest build state.
pub fn artifact_manifest_build_state(
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackBuildState, CompileError> {
    artifact_manifest_build_state_for_target(artifact_root, SourcePackArtifactTarget::Generic)
}

/// Load or initialize the artifact-manifest build state for a target.
pub fn artifact_manifest_build_state_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildState, CompileError> {
    FilesystemArtifactStore::new(artifact_root).load_or_init_build_state_for_target(target)
}

/// Load the generic-target artifact-manifest progress summary.
pub fn artifact_manifest_progress_summary(
    artifact_root: impl Into<PathBuf>,
) -> Result<SourcePackBuildProgressSummary, CompileError> {
    artifact_manifest_progress_summary_for_target(artifact_root, SourcePackArtifactTarget::Generic)
}

/// Load the artifact-manifest progress summary for a target.
pub fn artifact_manifest_progress_summary_for_target(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackBuildProgressSummary, CompileError> {
    let store = FilesystemArtifactStore::new(artifact_root);
    store.load_build_progress_summary_for_target(target)
}

/// Build a progress snapshot with ready unclaimed batches evaluated at the
/// supplied time.
pub fn artifact_manifest_progress_snapshot_at(
    artifact_root: impl Into<PathBuf>,
    max_ready_batches: usize,
    target: SourcePackArtifactTarget,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemArtifactProgressSnapshot, CompileError> {
    let max_ready_batches = limit_ready_state_batches(max_ready_batches);
    let store = FilesystemArtifactStore::new(artifact_root);
    let summary = summary_for_frontier_bounded(&store, target)?;
    let ready_batch_indices = if summary.is_complete() || max_ready_batches == 0 {
        Vec::new()
    } else {
        ready_unclaimed_batch_indices_limited(
            &store,
            target,
            &summary,
            now_unix_nanos,
            Some(max_ready_batches),
        )?
    };
    let linked_output_path = summary
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;
    let complete = summary.is_complete();

    Ok(FilesystemArtifactProgressSnapshot {
        target,
        job_batch_count: summary.job_batch_count,
        completed_batch_count: summary.completed_batch_count,
        ready_batch_count: summary.ready_batch_count,
        claimed_batch_count: summary.claimed_batch_count,
        ready_claimed_batch_count: summary.ready_claimed_batch_count,
        earliest_claim_lease_expires_unix_nanos: summary.earliest_claim_lease_expires_unix_nanos,
        first_ready_batch_index: summary.first_ready_batch_index,
        ready_batch_indices,
        linked_output_key: summary.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
        progress_summary_path: store.build_progress_summary_path_for_target(target),
    })
}

/// Load one artifact-manifest progress page and derive its active claim list at
/// the supplied time.
pub fn artifact_manifest_progress_page_at(
    artifact_root: impl Into<PathBuf>,
    shard_index: usize,
    target: SourcePackArtifactTarget,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemArtifactProgressPage, CompileError> {
    let store = FilesystemArtifactStore::new(artifact_root);
    let shard = store.load_build_artifact_shard_for_target(target, shard_index)?;
    if shard.kind != SourcePackBuildArtifactShardKind::JobBatches {
        return Err(artifact_shard_contract_error(format!(
            "progress page shard {shard_index} has non-job kind {:?}",
            shard.kind
        )));
    }
    let progress = store.load_or_init_build_progress_shard_for_target(target, &shard)?;
    validate_progress_shard_matches_artifact_shard(&progress, &shard)?;
    let claimed_batch_indices = progress.claimed_batch_indices(now_unix_nanos)?;
    let claimed_batches = progress
        .claimed_batches
        .iter()
        .filter(|claim| {
            !progress
                .completed_batch_indices
                .contains(&claim.batch_index)
                && !claim.is_expired(now_unix_nanos)
        })
        .cloned()
        .collect::<Vec<_>>();

    Ok(FilesystemArtifactProgressPage {
        target,
        shard_index,
        batch_indices: progress.batch_indices,
        completed_batch_indices: progress.completed_batch_indices,
        ready_batch_indices: progress.ready_batch_indices,
        claimed_batch_indices,
        claimed_batches,
        linked_output_key: progress.linked_output_key,
        progress_shard_path: store.build_progress_shard_path_for_target(target, shard_index),
        progress_summary_path: store.build_progress_summary_path_for_target(target),
    })
}
