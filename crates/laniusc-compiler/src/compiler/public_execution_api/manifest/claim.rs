use super::*;

pub fn claim_ready_artifact_manifest_batch(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemArtifactBatchClaimResult, CompileError> {
    let store = FilesystemArtifactStore::new(artifact_root);
    let _state_lock = store.try_lock_build_state_for_target(target)?;

    let worker_id = worker_id.into();
    let summary = summary_for_frontier_bounded(&store, target)?;
    let claimed_batch_index = if summary.is_complete() {
        None
    } else {
        let claimed_batch_index =
            first_ready_unclaimed_batch_index(&store, target, &summary, now_unix_nanos)?;
        if let Some(batch_index) = claimed_batch_index {
            let locator = store.load_build_batch_shard_locator_for_target(target, batch_index)?;
            let progress_shard =
                store.load_build_artifact_shard_for_target(target, locator.shard_index)?;
            if progress_shard.kind != SourcePackBuildArtifactShardKind::JobBatches
                || !progress_shard.batch_indices.contains(&batch_index)
            {
                return Err(artifact_shard_contract_error(format!(
                    "batch {batch_index} locator points to shard {} with kind {:?} batches {:?}",
                    progress_shard.shard_index, progress_shard.kind, progress_shard.batch_indices
                )));
            }
            let mut progress =
                store.load_or_init_build_progress_shard_for_target(target, &progress_shard)?;
            progress.prune_inactive_batch_claims(now_unix_nanos)?;
            progress.record_batch_claim(
                batch_index,
                worker_id.clone(),
                lease_expires_unix_nanos,
                now_unix_nanos,
            )?;
            store.store_build_progress_shard(&progress)?;
        }
        claimed_batch_index
    };

    let summary = summary_for_frontier_bounded(&store, target)?;
    let build_state = build_state_from_progress_summary(&summary)?;
    validate_progress_summary_complete_output(&store, &summary)?;
    let build_state_path = store.store_build_state_marker_for_target(target, &build_state)?;
    Ok(FilesystemArtifactBatchClaimResult {
        claimed_batch_index,
        worker_id,
        completed_batch_count: summary.completed_batch_count,
        claimed_batch_count: summary.claimed_batch_count,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path,
    })
}

pub fn claim_ready_artifact_manifest_batch_with_progress(
    artifact_root: impl Into<PathBuf>,
    target: SourcePackArtifactTarget,
    worker_id: impl Into<String>,
    lease_expires_unix_nanos: Option<u128>,
    max_ready_batches: usize,
    now_unix_nanos: Option<u128>,
) -> Result<FilesystemArtifactBatchClaimProgressResult, CompileError> {
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);

    let worker_id = worker_id.into();
    let claimed_batch_index = {
        let _state_lock = store.try_lock_build_state_for_target(target)?;
        let summary = summary_for_frontier_bounded(&store, target)?;
        if summary.is_complete() {
            None
        } else {
            let claimed_batch_index =
                first_ready_unclaimed_batch_index(&store, target, &summary, now_unix_nanos)?;
            if let Some(batch_index) = claimed_batch_index {
                let locator =
                    store.load_build_batch_shard_locator_for_target(target, batch_index)?;
                let mut progress =
                    store.load_build_progress_shard_for_target(target, locator.shard_index)?;
                progress.prune_inactive_batch_claims(now_unix_nanos)?;
                progress.record_batch_claim(
                    batch_index,
                    worker_id.clone(),
                    lease_expires_unix_nanos,
                    now_unix_nanos,
                )?;
                store.store_build_progress_shard(&progress)?;
            }
            claimed_batch_index
        }
    };

    let progress = artifact_manifest_progress_snapshot_at(
        &artifact_root,
        max_ready_batches,
        target,
        now_unix_nanos,
    )?;
    Ok(FilesystemArtifactBatchClaimProgressResult {
        claimed_batch_index,
        worker_id,
        progress,
    })
}
