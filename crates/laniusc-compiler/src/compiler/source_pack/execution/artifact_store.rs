use super::*;

/// Executes a build plan through an artifact store.
///
/// The plan is first converted into a retained artifact manifest using the
/// requested batch limits, then executed through the manifest-backed artifact
/// store path.
pub(in crate::compiler) fn execute_build_plan_with_store<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    let artifact_manifest = build_plan
        .try_retained_build_artifact_manifest(batch_limits)
        .map_err(schedule_error)?;
    execute_artifact_manifest_build(source_pack, &artifact_manifest, executor, store)
}

/// Executes every batch in a retained artifact manifest.
///
/// The manifest must include execution records. Exactly one link job is expected
/// to produce the final linked output key; once it does, link input artifacts are
/// released from the store.
pub(in crate::compiler) fn execute_artifact_manifest_build<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBuildExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    validate_artifact_manifest(artifact_manifest)?;
    ensure_manifest_execution_records(artifact_manifest)?;
    let mut linked_output_key = None;

    for batch in &artifact_manifest.job_batches.batches {
        let batch_result = execute_artifact_manifest_batch_ref(
            source_pack,
            artifact_manifest,
            batch,
            executor,
            store,
        )?;
        if let Some(batch_linked_output_key) = batch_result.linked_output_key {
            if linked_output_key
                .replace(batch_linked_output_key.clone())
                .is_some()
            {
                return Err(duplicate_linked_output_error(
                    "source-pack artifact manifest",
                    &batch_linked_output_key,
                ));
            }
            release_link_input_artifacts(artifact_manifest, store)?;
        }
    }

    let linked_output_key = linked_output_key.ok_or_else(missing_link_job_error)?;

    Ok(ArtifactStoreBuildExecutionResult { linked_output_key })
}

/// Executes one manifest job batch by batch index.
pub(in crate::compiler) fn execute_artifact_manifest_batch<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    batch_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    validate_artifact_manifest(artifact_manifest)?;
    ensure_manifest_execution_records(artifact_manifest)?;
    let batch = artifact_manifest_batch(artifact_manifest, batch_index)?;
    execute_artifact_manifest_batch_ref(source_pack, artifact_manifest, batch, executor, store)
}

/// Executes the jobs listed by one manifest job-batch record.
///
/// The batch result records the linked output key only if the batch contains the
/// manifest's link job.
pub(in crate::compiler) fn execute_artifact_manifest_batch_ref<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    batch: &SourcePackJobBatch,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
where
    E: ArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore,
{
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) = execute_artifact_manifest_job(
            source_pack,
            artifact_manifest,
            job_index,
            executor,
            store,
        )? {
            if linked_output_key
                .replace(job_linked_output_key.clone())
                .is_some()
            {
                return Err(duplicate_linked_output_error(
                    format!("source-pack job batch {}", batch.batch_index),
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

/// Executes one job from a retained artifact manifest.
///
/// Frontend and codegen jobs read their source files and interface dependencies,
/// then store their produced artifacts. Link jobs stream the manifest's
/// link-interface and link-object batches before storing the linked output.
pub(in crate::compiler) fn execute_artifact_manifest_job<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
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
    S: ArtifactStore,
{
    ensure_manifest_execution_records(artifact_manifest)?;
    let job = schedule_job(&artifact_manifest.job_schedule, job_index)?;
    let job_manifest = job_artifact_manifest(&artifact_manifest.job_artifacts, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let input_interface_refs =
                manifest_job_input_interface_refs(artifact_manifest, job_manifest)?;
            let dependency_interfaces =
                load_library_interface_artifacts(store, &input_interface_refs)?;
            let source_files = path_manifest_source_files_for_job(source_pack, job)?;
            let interface =
                executor.build_library_interface(job, source_files, &dependency_interfaces)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = codegen_library_job_index(job)?;
            let input_interface_refs =
                manifest_job_input_interface_refs(artifact_manifest, job_manifest)?;
            let library_interface_ref = input_interface_refs
                .iter()
                .find(|artifact| artifact.producing_job_index == library_job_index)
                .ok_or_else(|| {
                    manifest_contract_error(format!(
                        "source-pack codegen job {} missing owning interface artifact from job {}",
                        job.job_index, library_job_index
                    ))
                })?;
            let library_interface = store.load_library_interface(library_interface_ref)?;
            let dependency_interfaces = load_library_interface_artifacts_excluding(
                store,
                &input_interface_refs,
                library_interface_ref.artifact_index,
            )?;
            let source_files = path_manifest_source_files_for_job(source_pack, job)?;
            let object = executor.build_codegen_object(
                job,
                source_files,
                &library_interface,
                &dependency_interfaces,
            )?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::CodegenObject)?;
            store.store_codegen_object(output, object)?;
            Ok(None)
        }
        SourcePackJobPhase::Link => {
            let mut link_handle = executor.begin_link_codegen_objects(job)?;
            for link_batch in &artifact_manifest.link_interface_batches.batches {
                let interfaces = load_library_interface_artifacts_for_indices(
                    store,
                    &artifact_manifest.artifacts,
                    &link_batch.input_interface_artifact_indices,
                )?;
                executor.link_library_interface_batch(
                    job,
                    &mut link_handle,
                    link_batch,
                    &interfaces,
                )?;
            }
            for link_batch in &artifact_manifest.link_object_batches.batches {
                let objects = load_codegen_object_artifacts_for_indices(
                    store,
                    &artifact_manifest.artifacts,
                    &link_batch.input_object_artifact_indices,
                )?;
                executor.link_codegen_object_batch(job, &mut link_handle, link_batch, &objects)?;
            }
            let linked_output = executor.finish_link_codegen_objects(job, link_handle)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
            let linked_output_key = output.key.clone();
            store.store_linked_output(output, linked_output)?;
            Ok(Some(linked_output_key))
        }
    }
}
