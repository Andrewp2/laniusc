use super::*;

/// Executes one job batch from a materialized execution shard.
///
/// This sync path requires all dependency interface refs for each job to be
/// available inline in the shard records.
pub(in crate::compiler) fn execute_artifact_execution_shard_batch<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader,
{
    validate_execution_shard(execution_shard, target)?;
    let batch = execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) = execute_execution_shard_job(
            execution_shard,
            link_input_shard_index,
            target,
            job_index,
            executor,
            store,
        )? {
            if linked_output_key
                .replace(job_linked_output_key.clone())
                .is_some()
            {
                return Err(duplicate_linked_output_error(
                    format!("source-pack execution shard batch {}", batch.batch_index),
                    &job_linked_output_key,
                ));
            }
        }
    }

    Ok(ArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

/// Executes one inline-input job from a materialized execution shard.
///
/// Frontend and codegen jobs use inline input refs loaded from the execution
/// shard. Link jobs delegate to the shard link path and require a link-input
/// shard index.
pub(in crate::compiler) fn execute_execution_shard_job<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader,
{
    let job = execution_shard_job(execution_shard, job_index)?;
    let job_manifest = execution_shard_job_artifact(execution_shard, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let dependency_interface_refs = execution_shard_job_input_interface_refs(
                execution_shard,
                store,
                target,
                job_manifest,
            )?;
            let dependency_interfaces =
                load_library_interface_artifacts(store, &dependency_interface_refs)?;
            let source_files = execution_shard_source_files_for_job(store, execution_shard, job)?;
            let interface =
                executor.build_library_interface(job, &source_files, &dependency_interfaces)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = codegen_library_job_index(job)?;
            let input_interface_refs = execution_shard_job_input_interface_refs(
                execution_shard,
                store,
                target,
                job_manifest,
            )?;
            let library_interface_ref = input_interface_refs
                .iter()
                .find(|artifact| artifact.producing_job_index == library_job_index)
                .ok_or_else(|| {
                    artifact_shard_contract_error(format!(
                        "source-pack codegen job {} missing owning interface artifact from job {}",
                        job.job_index, library_job_index
                    ))
                })?;
            let library_interface = store.load_library_interface(library_interface_ref)?;
            let dependency_interface_refs = input_interface_refs
                .iter()
                .filter(|artifact| artifact.artifact_index != library_interface_ref.artifact_index)
                .cloned()
                .collect::<Vec<_>>();
            let dependency_interfaces =
                load_library_interface_artifacts(store, &dependency_interface_refs)?;
            let source_files = execution_shard_source_files_for_job(store, execution_shard, job)?;
            let object = executor.build_codegen_object(
                job,
                &source_files,
                &library_interface,
                &dependency_interfaces,
            )?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::CodegenObject)?;
            store.store_codegen_object(output, object)?;
            Ok(None)
        }
        SourcePackJobPhase::Link => execute_execution_shard_link_job(
            execution_shard,
            link_input_shard_index.ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "source-pack link job {} requires a link input shard index",
                    job.job_index
                ))
            })?,
            target,
            job,
            job_manifest,
            executor,
            store,
        ),
    }
}

/// Executes one job batch from a materialized execution shard using paged inputs.
///
/// This path supports job manifests whose interface inputs are inline, paged, or
/// represented by compact ranges.
pub(in crate::compiler) fn execute_execution_shard_batch_paged<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader,
{
    validate_execution_shard(execution_shard, target)?;
    let batch = execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) = execute_execution_shard_job_paged(
            execution_shard,
            link_input_shard_index,
            target,
            job_index,
            executor,
            store,
        )? {
            if linked_output_key
                .replace(job_linked_output_key.clone())
                .is_some()
            {
                return Err(duplicate_linked_output_error(
                    format!("source-pack execution shard batch {}", batch.batch_index),
                    &job_linked_output_key,
                ));
            }
        }
    }

    Ok(ArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

/// Executes one paged-input job from a materialized execution shard.
///
/// Dependency interfaces are streamed into executor handles in bounded batches,
/// avoiding the inline-input restriction used by the simpler sync shard path.
pub(in crate::compiler) fn execute_execution_shard_job_paged<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: PagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader,
{
    let job = execution_shard_job(execution_shard, job_index)?;
    let job_manifest = execution_shard_job_artifact(execution_shard, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let source_files = execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle = executor.begin_library_interface(job, &source_files)?;
            for_each_execution_shard_job_input_interface_batch(
                store,
                target,
                job_manifest,
                None,
                |dependency_interfaces| {
                    executor.add_library_interface_dependency_batch(
                        job,
                        &mut handle,
                        dependency_interfaces,
                    )
                },
            )?;
            let interface = executor.finish_library_interface(job, handle)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = codegen_library_job_index(job)?;
            let library_interface_ref = execution_shard_job_input_interface_ref(
                store,
                target,
                job_manifest,
                library_job_index,
            )?;
            let library_interface = store.load_library_interface(&library_interface_ref)?;
            let source_files = execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle =
                executor.begin_codegen_object(job, &source_files, &library_interface)?;
            for_each_execution_shard_job_input_interface_batch(
                store,
                target,
                job_manifest,
                Some(library_interface_ref.artifact_index),
                |dependency_interfaces| {
                    executor.add_codegen_object_dependency_batch(
                        job,
                        &mut handle,
                        dependency_interfaces,
                    )
                },
            )?;
            let object = executor.finish_codegen_object(job, handle)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::CodegenObject)?;
            store.store_codegen_object(output, object)?;
            Ok(None)
        }
        SourcePackJobPhase::Link => execute_execution_shard_link_job(
            execution_shard,
            link_input_shard_index.ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "source-pack link job {} requires a link input shard index",
                    job.job_index
                ))
            })?,
            target,
            job,
            job_manifest,
            executor,
            store,
        ),
    }
}
