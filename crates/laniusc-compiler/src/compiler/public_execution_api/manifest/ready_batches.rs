use super::*;

/// Execute ready generic-target artifact-manifest batches up to `max_batches`.
pub fn execute_ready_artifact_manifest_batches<E>(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    executor: &mut E,
) -> Result<FilesystemArtifactResumeExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    execute_ready_artifact_manifest_batches_for_target(
        artifact_root,
        max_batches,
        SourcePackArtifactTarget::Generic,
        executor,
    )
}

/// Execute ready artifact-manifest batches for a target up to `max_batches`.
pub fn execute_ready_artifact_manifest_batches_for_target<E>(
    artifact_root: impl Into<PathBuf>,
    max_batches: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
) -> Result<FilesystemArtifactResumeExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = Vec<u8>,
            CodegenObjectArtifact = Vec<u8>,
            LinkedOutputArtifact = Vec<u8>,
        >,
{
    let artifact_root = artifact_root.into();
    let store = FilesystemArtifactStore::new(&artifact_root);
    let now_unix_nanos = Some(current_unix_nanos()?);
    let initial_summary = summary_for_frontier_bounded(&store, target)?;
    validate_progress_summary_complete_output(&store, &initial_summary)?;
    let max_batches = limit_artifact_worker_run_batches(max_batches);
    let mut executed_batch_count = 0usize;

    if !initial_summary.is_complete() && max_batches != 0 {
        let ready_batch_indices = ready_unclaimed_batch_indices_limited(
            &store,
            target,
            &initial_summary,
            now_unix_nanos,
            Some(max_batches),
        )?;
        if ready_batch_indices.is_empty() {
            return Err(source_pack_progress_state_error(format!(
                "source-pack build state has no unclaimed ready batches and is incomplete; completed {} batches; claimed {} batches",
                initial_summary.completed_batch_count, initial_summary.claimed_batch_count
            )));
        }
        validate_ready_batch_dependency_artifacts(
            &store,
            initial_summary.job_batch_count,
            target,
            &ready_batch_indices,
        )?;
        for batch_index in ready_batch_indices {
            execute_shard_batch_for_target(
                &artifact_root,
                batch_index,
                target,
                now_unix_nanos,
                executor,
            )?;
            executed_batch_count = executed_batch_count.saturating_add(1);
        }
    }

    let final_summary = summary_for_frontier_bounded(&store, target)?;
    let final_state = build_state_from_progress_summary(&final_summary)?;
    validate_progress_summary_complete_output(&store, &final_summary)?;
    let complete = final_summary.is_complete();
    let linked_output_path = final_state
        .linked_output_key
        .as_ref()
        .map(|key| store.path_for_key(key))
        .transpose()?;

    Ok(FilesystemArtifactResumeExecutionResult {
        executed_batch_count,
        completed_batch_count: final_summary.completed_batch_count,
        ready_batch_count: final_summary.ready_batch_count,
        linked_output_key: final_state.linked_output_key,
        linked_output_path,
        complete,
        build_manifest_path: store.build_manifest_path_for_target(target),
        artifact_manifest_path: store.artifact_manifest_path_for_target(target),
        build_state_path: store.build_state_path_for_target(target),
    })
}
