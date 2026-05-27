use super::*;

pub(in crate::compiler) fn execute_source_pack_build<E>(
    source_pack: &ExplicitSourcePack,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<
    SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
    CompileError,
>
where
    E: SourcePackBuildExecutor,
{
    let mut library_interfaces = Vec::new();
    let mut codegen_objects = Vec::new();
    let mut interface_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut object_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan.schedule.try_for_each_execution_batch(
        batch_limits,
        source_pack_schedule_error,
        |batch| {
            for &job_index in &batch.job_indices {
                let job = source_pack_schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_slice_for_job(job),
                            &dependency_interfaces,
                        )?;
                        interface_by_job[job.job_index] = Some(library_interfaces.len());
                        library_interfaces.push(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface_index = interface_by_job
                        .get(library_job_index)
                        .and_then(|index| *index)
                        .ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                        })?;
                        let library_interface = &library_interfaces[library_interface_index];
                        let dependency_interfaces = collect_interface_refs_excluding(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_slice_for_job(job),
                            library_interface,
                            &dependency_interfaces,
                        )?;
                        object_by_job[job.job_index] = Some(codegen_objects.len());
                        codegen_objects.push(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_refs = collect_link_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            build_plan,
                        )?;
                        let object_refs =
                            collect_link_object_refs(&codegen_objects, &object_by_job, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_refs,
                            &object_refs,
                        )?);
                    }
                }
            }
            Ok(())
        },
    )?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(SourcePackBuildExecutionResult {
        library_interfaces,
        codegen_objects,
        linked_output,
    })
}

pub(in crate::compiler) fn execute_source_pack_path_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<
    SourcePackBuildExecutionResult<E::LibraryInterface, E::CodegenObject, E::LinkedOutput>,
    CompileError,
>
where
    E: SourcePackPathBuildExecutor,
{
    let mut library_interfaces = Vec::new();
    let mut codegen_objects = Vec::new();
    let mut interface_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut object_by_job = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan.schedule.try_for_each_execution_batch(
        batch_limits,
        source_pack_schedule_error,
        |batch| {
            for &job_index in &batch.job_indices {
                let job = source_pack_schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        interface_by_job[job.job_index] = Some(library_interfaces.len());
                        library_interfaces.push(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface_index = interface_by_job
                        .get(library_job_index)
                        .and_then(|index| *index)
                        .ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                        })?;
                        let library_interface = &library_interfaces[library_interface_index];
                        let dependency_interfaces = collect_interface_refs_excluding(
                            &library_interfaces,
                            &interface_by_job,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            library_interface,
                            &dependency_interfaces,
                        )?;
                        object_by_job[job.job_index] = Some(codegen_objects.len());
                        codegen_objects.push(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_refs = collect_link_interface_refs(
                            &library_interfaces,
                            &interface_by_job,
                            build_plan,
                        )?;
                        let object_refs =
                            collect_link_object_refs(&codegen_objects, &object_by_job, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_refs,
                            &object_refs,
                        )?);
                    }
                }
            }
            Ok(())
        },
    )?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(SourcePackBuildExecutionResult {
        library_interfaces,
        codegen_objects,
        linked_output,
    })
}

pub(in crate::compiler) fn execute_source_pack_path_handle_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackHandleBuildExecutionResult<E::LinkedOutput>, CompileError>
where
    E: SourcePackPathHandleBuildExecutor,
{
    let mut library_interfaces = vec![None; build_plan.schedule.jobs.len()];
    let mut codegen_objects = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan.schedule.try_for_each_execution_batch(
        batch_limits,
        source_pack_schedule_error,
        |batch| {
            for &job_index in &batch.job_indices {
                let job = source_pack_schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_handle_clones(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        library_interfaces[job.job_index] = Some(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface = library_interfaces
                        .get(library_job_index)
                        .and_then(|handle| handle.as_ref())
                        .cloned()
                        .ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                        })?;
                        let dependency_interfaces = collect_interface_handle_clones_excluding(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            &library_interface,
                            &dependency_interfaces,
                        )?;
                        codegen_objects[job.job_index] = Some(object);
                    }
                    SourcePackJobPhase::Link => {
                        let interface_handles =
                            collect_link_interface_handle_clones(&library_interfaces, build_plan)?;
                        let object_handles =
                            collect_link_object_handle_clones(&codegen_objects, build_plan)?;
                        linked_output = Some(executor.link_codegen_objects(
                            job,
                            &interface_handles,
                            &object_handles,
                        )?);
                        release_link_input_handles(
                            build_plan,
                            &mut library_interfaces,
                            &mut codegen_objects,
                            executor,
                        )?;
                    }
                }
            }
            Ok(())
        },
    )?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(SourcePackHandleBuildExecutionResult { linked_output })
}

pub(in crate::compiler) fn execute_source_pack_path_batched_link_build<E>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
) -> Result<SourcePackHandleBuildExecutionResult<E::LinkedOutput>, CompileError>
where
    E: SourcePackPathHandleBatchedLinkBuildExecutor,
{
    let mut library_interfaces = vec![None; build_plan.schedule.jobs.len()];
    let mut codegen_objects = vec![None; build_plan.schedule.jobs.len()];
    let mut linked_output = None;

    build_plan.schedule.try_for_each_execution_batch(
        batch_limits,
        source_pack_schedule_error,
        |batch| {
            for &job_index in &batch.job_indices {
                let job = source_pack_schedule_job(&build_plan.schedule, job_index)?;
                match job.phase {
                    SourcePackJobPhase::LibraryFrontend => {
                        let dependency_interfaces = collect_interface_handle_clones(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                        )?;
                        let interface = executor.build_library_interface(
                            job,
                            source_pack.source_files_for_job(job),
                            &dependency_interfaces,
                        )?;
                        library_interfaces[job.job_index] = Some(interface);
                    }
                    SourcePackJobPhase::Codegen => {
                        let library_job_index = job.library_job_index.ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} has no owning library job",
                                job.job_index
                            ))
                        })?;
                        let library_interface = library_interfaces
                        .get(library_job_index)
                        .and_then(|handle| handle.as_ref())
                        .cloned()
                        .ok_or_else(|| {
                            CompileError::GpuFrontend(format!(
                                "source-pack codegen job {} missing library interface from job {}",
                                job.job_index, library_job_index
                            ))
                        })?;
                        let dependency_interfaces = collect_interface_handle_clones_excluding(
                            &library_interfaces,
                            &build_plan.schedule,
                            job,
                            Some(library_job_index),
                        )?;
                        let object = executor.build_codegen_object(
                            job,
                            source_pack.source_files_for_job(job),
                            &library_interface,
                            &dependency_interfaces,
                        )?;
                        codegen_objects[job.job_index] = Some(object);
                    }
                    SourcePackJobPhase::Link => {
                        let mut link_handle = executor.begin_link_codegen_objects(job)?;
                        build_plan.try_for_each_link_interface_batch(
                            batch_limits,
                            |link_batch| {
                                let interface_handles =
                                    collect_link_interface_handle_clones_for_batch(
                                        &library_interfaces,
                                        build_plan,
                                        &link_batch,
                                    )?;
                                executor.link_library_interface_batch(
                                    job,
                                    &mut link_handle,
                                    &link_batch,
                                    &interface_handles,
                                )?;
                                release_library_interface_handles_for_link_batch(
                                    build_plan,
                                    &link_batch,
                                    &mut library_interfaces,
                                    executor,
                                )?;
                                Ok::<(), CompileError>(())
                            },
                        )?;
                        build_plan.try_for_each_link_object_batch(batch_limits, |link_batch| {
                            let object_handles = collect_link_object_handle_clones_for_batch(
                                &codegen_objects,
                                build_plan,
                                &link_batch,
                            )?;
                            executor.link_codegen_object_batch(
                                job,
                                &mut link_handle,
                                &link_batch,
                                &object_handles,
                            )?;
                            release_codegen_object_handles_for_link_batch(
                                build_plan,
                                &link_batch,
                                &mut codegen_objects,
                                executor,
                            )?;
                            Ok::<(), CompileError>(())
                        })?;
                        linked_output =
                            Some(executor.finish_link_codegen_objects(job, link_handle)?);
                    }
                }
            }
            Ok(())
        },
    )?;

    let linked_output = linked_output.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(SourcePackHandleBuildExecutionResult { linked_output })
}

pub(in crate::compiler) fn execute_source_pack_path_artifact_store_build<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    build_plan: &SourcePackBuildPlan,
    batch_limits: SourcePackJobBatchLimits,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    let artifact_manifest = build_plan
        .try_retained_build_artifact_manifest(batch_limits)
        .map_err(source_pack_schedule_error)?;
    execute_source_pack_path_artifact_manifest_store_build(
        source_pack,
        &artifact_manifest,
        executor,
        store,
    )
}

pub(in crate::compiler) fn execute_source_pack_path_artifact_manifest_store_build<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBuildExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    validate_source_pack_build_artifact_manifest(artifact_manifest)?;
    ensure_inline_build_artifact_records_for_manifest_execution(artifact_manifest)?;
    let mut linked_output_key = None;

    for batch in &artifact_manifest.job_batches.batches {
        let batch_result = execute_source_pack_path_artifact_manifest_store_batch_ref(
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
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack artifact manifest produced more than one linked output; duplicate key {batch_linked_output_key:?}"
                )));
            }
            release_source_pack_link_input_artifacts(artifact_manifest, store)?;
        }
    }

    let linked_output_key = linked_output_key.ok_or_else(|| {
        CompileError::GpuFrontend("source-pack build plan did not execute a link job".into())
    })?;

    Ok(SourcePackArtifactStoreBuildExecutionResult { linked_output_key })
}

pub(in crate::compiler) fn execute_source_pack_path_artifact_manifest_store_batch<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    batch_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    validate_source_pack_build_artifact_manifest(artifact_manifest)?;
    ensure_inline_build_artifact_records_for_manifest_execution(artifact_manifest)?;
    let batch = source_pack_artifact_manifest_batch(artifact_manifest, batch_index)?;
    execute_source_pack_path_artifact_manifest_store_batch_ref(
        source_pack,
        artifact_manifest,
        batch,
        executor,
        store,
    )
}

pub(in crate::compiler) fn execute_source_pack_path_artifact_manifest_store_batch_ref<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    batch: &SourcePackJobBatch,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) = execute_source_pack_path_artifact_manifest_store_job(
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
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack job batch {} produced more than one linked output; duplicate key {job_linked_output_key:?}",
                    batch.batch_index
                )));
            }
        }
    }

    Ok(SourcePackArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) fn execute_source_pack_path_artifact_manifest_store_job<E, S>(
    source_pack: &ExplicitSourcePackPathManifest,
    artifact_manifest: &SourcePackBuildArtifactManifest,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore,
{
    ensure_inline_build_artifact_records_for_manifest_execution(artifact_manifest)?;
    let job = source_pack_schedule_job(&artifact_manifest.job_schedule, job_index)?;
    let job_manifest =
        source_pack_job_artifact_manifest(&artifact_manifest.job_artifacts, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let input_interface_refs =
                source_pack_manifest_job_input_interface_refs(artifact_manifest, job_manifest)?;
            let dependency_interfaces =
                load_library_interface_artifacts(store, &input_interface_refs)?;
            let source_files = source_pack_path_manifest_source_files_for_job(source_pack, job)?;
            let interface =
                executor.build_library_interface(job, source_files, &dependency_interfaces)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = job.library_job_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack codegen job {} has no owning library job",
                    job.job_index
                ))
            })?;
            let input_interface_refs =
                source_pack_manifest_job_input_interface_refs(artifact_manifest, job_manifest)?;
            let library_interface_ref = input_interface_refs
                .iter()
                .find(|artifact| artifact.producing_job_index == library_job_index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
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
            let source_files = source_pack_path_manifest_source_files_for_job(source_pack, job)?;
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

pub(in crate::compiler) fn execute_source_pack_build_artifact_execution_shard_batch<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_build_artifact_execution_shard(execution_shard, target)?;
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) = execute_source_pack_build_artifact_execution_shard_job(
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
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack execution shard batch {} produced more than one linked output; duplicate key {job_linked_output_key:?}",
                    batch.batch_index
                )));
            }
        }
    }

    Ok(SourcePackArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) fn execute_source_pack_build_artifact_execution_shard_job<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let job = source_pack_execution_shard_job(execution_shard, job_index)?;
    let job_manifest = source_pack_execution_shard_job_artifact(execution_shard, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let dependency_interface_refs = source_pack_execution_shard_job_input_interface_refs(
                execution_shard,
                store,
                target,
                job_manifest,
            )?;
            let dependency_interfaces =
                load_library_interface_artifacts(store, &dependency_interface_refs)?;
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
            let interface =
                executor.build_library_interface(job, &source_files, &dependency_interfaces)?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = job.library_job_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack codegen job {} has no owning library job",
                    job.job_index
                ))
            })?;
            let input_interface_refs = source_pack_execution_shard_job_input_interface_refs(
                execution_shard,
                store,
                target,
                job_manifest,
            )?;
            let library_interface_ref = input_interface_refs
                .iter()
                .find(|artifact| artifact.producing_job_index == library_job_index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
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
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
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
        SourcePackJobPhase::Link => execute_source_pack_build_artifact_execution_shard_link_job(
            execution_shard,
            link_input_shard_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) fn execute_source_pack_build_artifact_execution_shard_batch_paged<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_build_artifact_execution_shard(execution_shard, target)?;
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) =
            execute_source_pack_build_artifact_execution_shard_job_paged(
                execution_shard,
                link_input_shard_index,
                target,
                job_index,
                executor,
                store,
            )?
        {
            if linked_output_key
                .replace(job_linked_output_key.clone())
                .is_some()
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack execution shard batch {} produced more than one linked output; duplicate key {job_linked_output_key:?}",
                    batch.batch_index
                )));
            }
        }
    }

    Ok(SourcePackArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) fn execute_source_pack_build_artifact_execution_shard_job_paged<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let job = source_pack_execution_shard_job(execution_shard, job_index)?;
    let job_manifest = source_pack_execution_shard_job_artifact(execution_shard, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle = executor.begin_library_interface(job, &source_files)?;
            source_pack_for_each_execution_shard_job_input_interface_batch(
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
            let library_job_index = job.library_job_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack codegen job {} has no owning library job",
                    job.job_index
                ))
            })?;
            let library_interface_ref = source_pack_execution_shard_job_input_interface_ref(
                store,
                target,
                job_manifest,
                library_job_index,
            )?;
            let library_interface = store.load_library_interface(&library_interface_ref)?;
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle =
                executor.begin_codegen_object(job, &source_files, &library_interface)?;
            source_pack_for_each_execution_shard_job_input_interface_batch(
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
        SourcePackJobPhase::Link => execute_source_pack_build_artifact_execution_shard_link_job(
            execution_shard,
            link_input_shard_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) async fn execute_source_pack_build_artifact_execution_shard_batch_paged_async<
    E,
    S,
>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_build_artifact_execution_shard(execution_shard, target)?;
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        if let Some(job_linked_output_key) =
            execute_source_pack_build_artifact_execution_shard_job_paged_async(
                execution_shard,
                link_input_shard_index,
                target,
                job_index,
                executor,
                store,
            )
            .await?
        {
            if linked_output_key
                .replace(job_linked_output_key.clone())
                .is_some()
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack async execution shard batch {} produced more than one linked output; duplicate key {job_linked_output_key:?}",
                    batch.batch_index
                )));
            }
        }
    }

    Ok(SourcePackArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) async fn execute_source_pack_build_artifact_execution_shard_job_paged_async<
    E,
    S,
>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let job = source_pack_execution_shard_job(execution_shard, job_index)?;
    let job_manifest = source_pack_execution_shard_job_artifact(execution_shard, job.job_index)?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle = executor.begin_library_interface(job, &source_files).await?;
            source_pack_add_library_interface_dependency_batches_async(
                store,
                target,
                job_manifest,
                executor,
                job,
                &mut handle,
            )
            .await?;
            let interface = executor.finish_library_interface(job, handle).await?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LibraryInterface)?;
            store.store_library_interface(output, interface)?;
            Ok(None)
        }
        SourcePackJobPhase::Codegen => {
            let library_job_index = job.library_job_index.ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack codegen job {} has no owning library job",
                    job.job_index
                ))
            })?;
            let library_interface_ref = source_pack_execution_shard_job_input_interface_ref(
                store,
                target,
                job_manifest,
                library_job_index,
            )?;
            let library_interface = store.load_library_interface(&library_interface_ref)?;
            let source_files =
                source_pack_execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle = executor
                .begin_codegen_object(job, &source_files, &library_interface)
                .await?;
            source_pack_add_codegen_object_dependency_batches_async(
                store,
                target,
                job_manifest,
                Some(library_interface_ref.artifact_index),
                executor,
                job,
                &mut handle,
            )
            .await?;
            let object = executor.finish_codegen_object(job, handle).await?;
            let output =
                single_output_artifact_ref(job_manifest, SourcePackArtifactKind::CodegenObject)?;
            store.store_codegen_object(output, object)?;
            Ok(None)
        }
        SourcePackJobPhase::Link => {
            execute_source_pack_build_artifact_execution_shard_link_job_async(
                execution_shard,
                link_input_shard_index.ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link job {} requires a link input shard index",
                        job.job_index
                    ))
                })?,
                target,
                job,
                job_manifest,
                executor,
                store,
            )
            .await
        }
    }
}

pub(in crate::compiler) async fn source_pack_add_library_interface_dependency_batches_async<E, S>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    executor: &mut E,
    job: &SourcePackJob,
    handle: &mut E::LibraryInterfaceBuildHandle,
) -> Result<usize, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let mut loaded_input_count = 0usize;
    let mut seen_input_count = 0usize;
    if job_manifest.input_interface_page_count == 0 {
        for chunk in job_manifest
            .input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
        {
            seen_input_count = seen_input_count.saturating_add(chunk.len());
            let interfaces = load_library_interface_artifact_batch_excluding(store, chunk, None)?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            executor
                .add_library_interface_dependency_batch(job, handle, &interfaces)
                .await?;
        }
    } else if !job_manifest.input_interfaces.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} mixes inline and paged interface inputs",
            job_manifest.job_index
        )));
    } else {
        for page_index in 0..job_manifest.input_interface_page_count {
            let page = store.load_job_artifact_input_interface_page(
                target,
                job_manifest.job_index,
                page_index,
            )?;
            if page.first_input_position != seen_input_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} input page {} starts at {} but streamed {} refs",
                    job_manifest.job_index, page_index, page.first_input_position, seen_input_count
                )));
            }
            seen_input_count = seen_input_count.saturating_add(page.input_count);
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &page.input_interfaces,
                None,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            executor
                .add_library_interface_dependency_batch(job, handle, &interfaces)
                .await?;
        }
    }
    if !job_manifest.input_interface_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface range starting at {} overflows",
                    job_manifest.job_index, range.first_job_index
                )));
            };
            for job_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    job_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface range references artifact {} with kind {:?}",
                        job_manifest.job_index, job_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        None,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        executor
                            .add_library_interface_dependency_batch(job, handle, &interfaces)
                            .await?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces =
                load_library_interface_artifact_batch_excluding(store, &artifact_refs, None)?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                executor
                    .add_library_interface_dependency_batch(job, handle, &interfaces)
                    .await?;
            }
        }
    }
    if !job_manifest.input_interface_artifact_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface artifact range starting at {} overflows",
                    job_manifest.job_index, range.first_artifact_index
                )));
            };
            for artifact_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    artifact_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface artifact range references artifact {} with kind {:?}",
                        job_manifest.job_index, artifact_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        None,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        executor
                            .add_library_interface_dependency_batch(job, handle, &interfaces)
                            .await?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces =
                load_library_interface_artifact_batch_excluding(store, &artifact_refs, None)?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                executor
                    .add_library_interface_dependency_batch(job, handle, &interfaces)
                    .await?;
            }
        }
    }
    if seen_input_count != job_manifest.input_interface_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}

pub(in crate::compiler) async fn source_pack_add_codegen_object_dependency_batches_async<E, S>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    excluded_artifact_index: Option<usize>,
    executor: &mut E,
    job: &SourcePackJob,
    handle: &mut E::CodegenObjectBuildHandle,
) -> Result<usize, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let mut loaded_input_count = 0usize;
    let mut seen_input_count = 0usize;
    if job_manifest.input_interface_page_count == 0 {
        for chunk in job_manifest
            .input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
        {
            seen_input_count = seen_input_count.saturating_add(chunk.len());
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                chunk,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            executor
                .add_codegen_object_dependency_batch(job, handle, &interfaces)
                .await?;
        }
    } else if !job_manifest.input_interfaces.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} mixes inline and paged interface inputs",
            job_manifest.job_index
        )));
    } else {
        for page_index in 0..job_manifest.input_interface_page_count {
            let page = store.load_job_artifact_input_interface_page(
                target,
                job_manifest.job_index,
                page_index,
            )?;
            if page.first_input_position != seen_input_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} input page {} starts at {} but streamed {} refs",
                    job_manifest.job_index, page_index, page.first_input_position, seen_input_count
                )));
            }
            seen_input_count = seen_input_count.saturating_add(page.input_count);
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &page.input_interfaces,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            executor
                .add_codegen_object_dependency_batch(job, handle, &interfaces)
                .await?;
        }
    }
    if !job_manifest.input_interface_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface range starting at {} overflows",
                    job_manifest.job_index, range.first_job_index
                )));
            };
            for job_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    job_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface range references artifact {} with kind {:?}",
                        job_manifest.job_index, job_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        executor
                            .add_codegen_object_dependency_batch(job, handle, &interfaces)
                            .await?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                executor
                    .add_codegen_object_dependency_batch(job, handle, &interfaces)
                    .await?;
            }
        }
    }
    if !job_manifest.input_interface_artifact_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface artifact range starting at {} overflows",
                    job_manifest.job_index, range.first_artifact_index
                )));
            };
            for artifact_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    artifact_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface artifact range references artifact {} with kind {:?}",
                        job_manifest.job_index, artifact_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        executor
                            .add_codegen_object_dependency_batch(job, handle, &interfaces)
                            .await?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                executor
                    .add_codegen_object_dependency_batch(job, handle, &interfaces)
                    .await?;
            }
        }
    }
    if seen_input_count != job_manifest.input_interface_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}

pub(in crate::compiler) async fn execute_source_pack_build_artifact_execution_shard_link_job_async<
    E,
    S,
>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    job_manifest: &SourcePackJobArtifactManifest,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_build_link_input_shard_index(link_input_shard_index, target)?;
    let mut link_handle = executor.begin_link_codegen_objects(job).await?;
    execute_source_pack_link_input_interface_shards_async(
        link_input_shard_index,
        target,
        job,
        executor,
        store,
        &mut link_handle,
    )
    .await?;
    execute_source_pack_link_input_object_shards_async(
        link_input_shard_index,
        target,
        job,
        executor,
        store,
        &mut link_handle,
    )
    .await?;
    let linked_output = executor
        .finish_link_codegen_objects(job, link_handle)
        .await?;
    let output = single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
    let linked_output_key = output.key.clone();
    store.store_linked_output(output, linked_output)?;

    if !execution_shard
        .shard
        .output_artifact_indices
        .contains(&output.artifact_index)
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link job {} output artifact {} is not listed in execution shard {}",
            job.job_index, output.artifact_index, execution_shard.shard.shard_index
        )));
    }

    Ok(Some(linked_output_key))
}

pub(in crate::compiler) async fn execute_source_pack_link_input_interface_shards_async<E, S>(
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    if let Some(range) = link_input_shard_index.link_interface_shard_range.as_ref() {
        let Some(indices) = range.iter() else {
            return Err(source_pack_artifact_shard_contract_error(
                "interface link input shard range overflows",
            ));
        };
        for shard_index in indices {
            execute_source_pack_link_input_interface_shard_async(
                shard_index,
                target,
                job,
                executor,
                store,
                link_handle,
            )
            .await?;
        }
    }
    Ok(())
}

pub(in crate::compiler) async fn execute_source_pack_link_input_interface_shard_async<E, S>(
    shard_index: usize,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let link_shard = store.load_execution_shard(target, shard_index)?;
    validate_source_pack_build_artifact_execution_shard(&link_shard, target)?;
    if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkInterfaceBatches {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link input shard index lists shard {shard_index} as an interface shard, but it is {:?}",
            link_shard.shard.kind
        )));
    }
    for link_batch in &link_shard.link_interface_batches {
        let interfaces = load_library_interface_artifacts_from_execution_shard_indices(
            store,
            &link_shard,
            &link_batch.input_interface_artifact_indices,
        )?;
        executor
            .link_library_interface_batch(job, link_handle, link_batch, &interfaces)
            .await?;
    }
    Ok(())
}

pub(in crate::compiler) async fn execute_source_pack_link_input_object_shards_async<E, S>(
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        CodegenObjectArtifact = S::CodegenObjectArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    if let Some(range) = link_input_shard_index.link_object_shard_range.as_ref() {
        let Some(indices) = range.iter() else {
            return Err(source_pack_artifact_shard_contract_error(
                "object link input shard range overflows",
            ));
        };
        for shard_index in indices {
            execute_source_pack_link_input_object_shard_async(
                shard_index,
                target,
                job,
                executor,
                store,
                link_handle,
            )
            .await?;
        }
    }
    Ok(())
}

pub(in crate::compiler) async fn execute_source_pack_link_input_object_shard_async<E, S>(
    shard_index: usize,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: SourcePackPathAsyncPagedArtifactBuildExecutor<
        CodegenObjectArtifact = S::CodegenObjectArtifact,
    >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    let link_shard = store.load_execution_shard(target, shard_index)?;
    validate_source_pack_build_artifact_execution_shard(&link_shard, target)?;
    if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkObjectBatches {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link input shard index lists shard {shard_index} as an object shard, but it is {:?}",
            link_shard.shard.kind
        )));
    }
    for link_batch in &link_shard.link_object_batches {
        let objects = load_codegen_object_artifacts_from_execution_shard_indices(
            store,
            &link_shard,
            &link_batch.input_object_artifact_indices,
        )?;
        executor
            .link_codegen_object_batch(job, link_handle, link_batch, &objects)
            .await?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_execution_shard_job_input_interface_refs<S>(
    _execution_shard: &SourcePackBuildArtifactExecutionShard,
    _store: &S,
    _target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<Vec<SourcePackArtifactRef>, CompileError>
where
    S: SourcePackFilesystemExecutionShardLoader,
{
    if job_manifest.input_interface_page_count != 0
        || !job_manifest.input_interface_ranges.is_empty()
        || !job_manifest.input_interface_artifact_ranges.is_empty()
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "legacy source-pack execution for job {} requires bounded inline interface inputs; paged or ranged interface inputs must use paged execution",
            job_manifest.job_index
        )));
    }
    let input_interfaces = job_manifest.input_interfaces.clone();
    if input_interfaces.len() != job_manifest.input_interface_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} records {} inline interface inputs but expected {}",
            job_manifest.job_index,
            input_interfaces.len(),
            job_manifest.input_interface_count
        )));
    }
    Ok(input_interfaces)
}

pub(in crate::compiler) fn source_pack_execution_shard_job_input_interface_ref<S>(
    store: &S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    producing_job_index: usize,
) -> Result<SourcePackArtifactRef, CompileError>
where
    S: SourcePackFilesystemExecutionShardLoader,
{
    if let Some(artifact) = job_manifest
        .input_interfaces
        .iter()
        .find(|artifact| artifact.producing_job_index == producing_job_index)
    {
        return Ok(artifact.clone());
    }

    for page_index in 0..job_manifest.input_interface_page_count {
        let page = store.load_job_artifact_input_interface_page(
            target,
            job_manifest.job_index,
            page_index,
        )?;
        if let Some(artifact) = page
            .input_interfaces
            .into_iter()
            .find(|artifact| artifact.producing_job_index == producing_job_index)
        {
            return Ok(artifact);
        }
    }
    if job_manifest
        .input_interface_ranges
        .iter()
        .any(|range| range.contains(producing_job_index))
    {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let page = store.load_build_artifact_ref_page(
            target,
            producing_job_index,
            artifact_ref_index.artifact_count,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job artifact manifest {} expected interface artifact from producer {} but found {:?}",
                job_manifest.job_index, producing_job_index, page.artifact_ref.kind
            )));
        }
        return Ok(page.artifact_ref);
    }
    if job_manifest
        .input_interface_artifact_ranges
        .iter()
        .any(|range| range.contains(producing_job_index))
    {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let page = store.load_build_artifact_ref_page(
            target,
            producing_job_index,
            artifact_ref_index.artifact_count,
        )?;
        if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job artifact manifest {} expected interface artifact from ranged producer {} but found {:?}",
                job_manifest.job_index, producing_job_index, page.artifact_ref.kind
            )));
        }
        return Ok(page.artifact_ref);
    }
    Err(CompileError::GpuFrontend(format!(
        "source-pack job {} missing paged interface artifact from producer {}",
        job_manifest.job_index, producing_job_index
    )))
}

pub(in crate::compiler) fn source_pack_for_each_execution_shard_job_input_interface_batch<S, F>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    excluded_artifact_index: Option<usize>,
    mut visit: F,
) -> Result<usize, CompileError>
where
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
    F: FnMut(&[S::LibraryInterfaceArtifact]) -> Result<(), CompileError>,
{
    let mut loaded_input_count = 0usize;
    let mut seen_input_count = 0usize;
    if job_manifest.input_interface_page_count == 0 {
        for chunk in job_manifest
            .input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
        {
            seen_input_count = seen_input_count.saturating_add(chunk.len());
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                chunk,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            visit(&interfaces)?;
        }
    } else if !job_manifest.input_interfaces.is_empty() {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} mixes inline and paged interface inputs",
            job_manifest.job_index
        )));
    } else {
        for page_index in 0..job_manifest.input_interface_page_count {
            let page = store.load_job_artifact_input_interface_page(
                target,
                job_manifest.job_index,
                page_index,
            )?;
            if page.first_input_position != seen_input_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} input page {} starts at {} but streamed {} refs",
                    job_manifest.job_index, page_index, page.first_input_position, seen_input_count
                )));
            }
            seen_input_count = seen_input_count.saturating_add(page.input_count);
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &page.input_interfaces,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if interfaces.is_empty() {
                continue;
            }
            visit(&interfaces)?;
        }
    }
    if !job_manifest.input_interface_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface range starting at {} overflows",
                    job_manifest.job_index, range.first_job_index
                )));
            };
            for job_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    job_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface range references artifact {} with kind {:?}",
                        job_manifest.job_index, job_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        visit(&interfaces)?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                visit(&interfaces)?;
            }
        }
    }
    if !job_manifest.input_interface_artifact_ranges.is_empty() {
        let artifact_ref_index = store.load_build_artifact_ref_index(target)?;
        let mut artifact_refs =
            Vec::with_capacity(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE);
        for range in &job_manifest.input_interface_artifact_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "job artifact manifest {} interface artifact range starting at {} overflows",
                    job_manifest.job_index, range.first_artifact_index
                )));
            };
            for artifact_index in indices {
                let page = store.load_build_artifact_ref_page(
                    target,
                    artifact_index,
                    artifact_ref_index.artifact_count,
                )?;
                if page.artifact_ref.kind != SourcePackArtifactKind::LibraryInterface {
                    return Err(source_pack_artifact_shard_contract_error(format!(
                        "job artifact manifest {} interface artifact range references artifact {} with kind {:?}",
                        job_manifest.job_index, artifact_index, page.artifact_ref.kind
                    )));
                }
                artifact_refs.push(page.artifact_ref);
                seen_input_count = seen_input_count.saturating_add(1);
                if artifact_refs.len() == SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE
                {
                    let interfaces = load_library_interface_artifact_batch_excluding(
                        store,
                        &artifact_refs,
                        excluded_artifact_index,
                    )?;
                    loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
                    if !interfaces.is_empty() {
                        visit(&interfaces)?;
                    }
                    artifact_refs.clear();
                }
            }
        }
        if !artifact_refs.is_empty() {
            let interfaces = load_library_interface_artifact_batch_excluding(
                store,
                &artifact_refs,
                excluded_artifact_index,
            )?;
            loaded_input_count = loaded_input_count.saturating_add(interfaces.len());
            if !interfaces.is_empty() {
                visit(&interfaces)?;
            }
        }
    }
    if seen_input_count != job_manifest.input_interface_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}

pub(in crate::compiler) fn execute_source_pack_build_artifact_execution_shard_link_job<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    job_manifest: &SourcePackJobArtifactManifest,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: SourcePackPathArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: SourcePackPathArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_build_link_input_shard_index(link_input_shard_index, target)?;
    let mut link_handle = executor.begin_link_codegen_objects(job)?;
    source_pack_for_each_link_input_shard_index(
        link_input_shard_index,
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
        |shard_index| {
            let link_shard = store.load_execution_shard(target, shard_index)?;
            validate_source_pack_build_artifact_execution_shard(&link_shard, target)?;
            if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkInterfaceBatches {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "link input shard index lists shard {shard_index} as an interface shard, but it is {:?}",
                    link_shard.shard.kind
                )));
            }
            for link_batch in &link_shard.link_interface_batches {
                let interfaces = load_library_interface_artifacts_from_execution_shard_indices(
                    store,
                    &link_shard,
                    &link_batch.input_interface_artifact_indices,
                )?;
                executor.link_library_interface_batch(
                    job,
                    &mut link_handle,
                    link_batch,
                    &interfaces,
                )?;
            }
            Ok(())
        },
    )?;
    source_pack_for_each_link_input_shard_index(
        link_input_shard_index,
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
        |shard_index| {
            let link_shard = store.load_execution_shard(target, shard_index)?;
            validate_source_pack_build_artifact_execution_shard(&link_shard, target)?;
            if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkObjectBatches {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "link input shard index lists shard {shard_index} as an object shard, but it is {:?}",
                    link_shard.shard.kind
                )));
            }
            for link_batch in &link_shard.link_object_batches {
                let objects = load_codegen_object_artifacts_from_execution_shard_indices(
                    store,
                    &link_shard,
                    &link_batch.input_object_artifact_indices,
                )?;
                executor.link_codegen_object_batch(job, &mut link_handle, link_batch, &objects)?;
            }
            Ok(())
        },
    )?;
    let linked_output = executor.finish_link_codegen_objects(job, link_handle)?;
    let output = single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
    let linked_output_key = output.key.clone();
    store.store_linked_output(output, linked_output)?;

    if !execution_shard
        .shard
        .output_artifact_indices
        .contains(&output.artifact_index)
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "link job {} output artifact {} is not listed in execution shard {}",
            job.job_index, output.artifact_index, execution_shard.shard.shard_index
        )));
    }

    Ok(Some(linked_output_key))
}

pub(in crate::compiler) fn execute_source_pack_hierarchical_link_execution_page<E, S>(
    page: &SourcePackHierarchicalLinkExecutionPage,
    executor: &mut E,
    store: &mut S,
) -> Result<(), CompileError>
where
    E: SourcePackPathHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: SourcePackPathHierarchicalLinkArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_hierarchical_link_execution_page(
        page,
        page.target,
        Some(page.group_index),
    )?;
    let mut link_handle = executor.begin_hierarchical_link_group(page)?;
    match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            let mut streamed_interface_count = 0usize;
            if page.input_interface_page_count == 0 {
                streamed_interface_count =
                    streamed_interface_count.saturating_add(page.input_interfaces.len());
                if !page.input_interfaces.is_empty() {
                    let interfaces =
                        load_library_interface_artifacts(store, &page.input_interfaces)?;
                    executor.link_hierarchical_library_interfaces(
                        page,
                        &mut link_handle,
                        &interfaces,
                    )?;
                }
            } else {
                for page_index in 0..page.input_interface_page_count {
                    let interface_page = store.load_hierarchical_link_execution_interface_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_interface_count =
                        streamed_interface_count.saturating_add(interface_page.input_count);
                    let interfaces =
                        load_library_interface_artifacts(store, &interface_page.input_interfaces)?;
                    executor.link_hierarchical_library_interfaces(
                        page,
                        &mut link_handle,
                        &interfaces,
                    )?;
                }
            }
            if !page.input_interface_ranges.is_empty() {
                let artifact_ref_index = store.load_build_artifact_ref_index(page.target)?;
                let mut artifact_refs = Vec::with_capacity(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                );
                for range in &page.input_interface_ranges {
                    let Some(indices) = range.iter() else {
                        return Err(source_pack_artifact_shard_contract_error(format!(
                            "hierarchical link execution group {} interface range starting at {} overflows",
                            page.group_index, range.first_job_index
                        )));
                    };
                    for job_index in indices {
                        let artifact_page = store.load_build_artifact_ref_page(
                            page.target,
                            job_index,
                            artifact_ref_index.artifact_count,
                        )?;
                        if artifact_page.artifact_ref.kind
                            != SourcePackArtifactKind::LibraryInterface
                        {
                            return Err(source_pack_artifact_shard_contract_error(format!(
                                "hierarchical link execution group {} interface range references artifact {} with kind {:?}",
                                page.group_index, job_index, artifact_page.artifact_ref.kind
                            )));
                        }
                        artifact_refs.push(artifact_page.artifact_ref);
                        streamed_interface_count = streamed_interface_count.saturating_add(1);
                        if artifact_refs.len()
                            == SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
                        {
                            let interfaces =
                                load_library_interface_artifacts(store, &artifact_refs)?;
                            executor.link_hierarchical_library_interfaces(
                                page,
                                &mut link_handle,
                                &interfaces,
                            )?;
                            artifact_refs.clear();
                        }
                    }
                }
                if !artifact_refs.is_empty() {
                    let interfaces = load_library_interface_artifacts(store, &artifact_refs)?;
                    executor.link_hierarchical_library_interfaces(
                        page,
                        &mut link_handle,
                        &interfaces,
                    )?;
                }
            }
            let expected_interface_count =
                source_pack_hierarchical_link_execution_input_interface_count(page);
            if streamed_interface_count != expected_interface_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} interface refs but expected {}",
                    page.group_index, streamed_interface_count, expected_interface_count
                )));
            }
            let mut streamed_object_count = 0usize;
            if page.input_object_page_count == 0 {
                streamed_object_count =
                    streamed_object_count.saturating_add(page.input_objects.len());
                let objects = load_codegen_object_artifacts(store, &page.input_objects)?;
                executor.link_hierarchical_codegen_objects(page, &mut link_handle, &objects)?;
            } else {
                for page_index in 0..page.input_object_page_count {
                    let object_page = store.load_hierarchical_link_execution_object_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_object_count =
                        streamed_object_count.saturating_add(object_page.input_count);
                    let objects = load_codegen_object_artifacts(store, &object_page.input_objects)?;
                    executor.link_hierarchical_codegen_objects(page, &mut link_handle, &objects)?;
                }
            }
            let expected_object_count =
                source_pack_hierarchical_link_execution_input_object_count(page);
            if streamed_object_count != expected_object_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} object refs but expected {}",
                    page.group_index, streamed_object_count, expected_object_count
                )));
            }
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            let mut streamed_partial_count = 0usize;
            if page.input_group_page_count == 0 {
                streamed_partial_count =
                    streamed_partial_count.saturating_add(page.input_group_output_keys.len());
                let partial_links =
                    load_partial_link_outputs(store, &page.input_group_output_keys)?;
                executor.link_hierarchical_partial_links(page, &mut link_handle, &partial_links)?;
            } else {
                for page_index in 0..page.input_group_page_count {
                    let partial_page = store.load_hierarchical_link_execution_partial_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_partial_count =
                        streamed_partial_count.saturating_add(partial_page.input_count);
                    let partial_links =
                        load_partial_link_outputs(store, &partial_page.input_group_output_keys)?;
                    executor.link_hierarchical_partial_links(
                        page,
                        &mut link_handle,
                        &partial_links,
                    )?;
                }
            }
            let expected_partial_count =
                source_pack_hierarchical_link_execution_input_group_count(page);
            if streamed_partial_count != expected_partial_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} partial-link refs but expected {}",
                    page.group_index, streamed_partial_count, expected_partial_count
                )));
            }
        }
    }

    if page.final_output {
        let output = executor.finish_hierarchical_link_output(page, link_handle)?;
        store.store_hierarchical_linked_output(&page.output_key, output)?;
    } else {
        let output = executor.finish_hierarchical_partial_link_group(page, link_handle)?;
        store.store_partial_link_output(&page.output_key, output)?;
    }
    Ok(())
}

pub(in crate::compiler) async fn execute_source_pack_hierarchical_link_execution_page_async<E, S>(
    page: &SourcePackHierarchicalLinkExecutionPage,
    executor: &mut E,
    store: &mut S,
) -> Result<(), CompileError>
where
    E: SourcePackPathAsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: SourcePackPathHierarchicalLinkArtifactStore + SourcePackFilesystemExecutionShardLoader,
{
    validate_source_pack_hierarchical_link_execution_page(
        page,
        page.target,
        Some(page.group_index),
    )?;
    let mut link_handle = executor.begin_hierarchical_link_group(page).await?;
    match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            let mut streamed_interface_count = 0usize;
            if page.input_interface_page_count == 0 {
                streamed_interface_count =
                    streamed_interface_count.saturating_add(page.input_interfaces.len());
                if !page.input_interfaces.is_empty() {
                    let interfaces =
                        load_library_interface_artifacts(store, &page.input_interfaces)?;
                    executor
                        .link_hierarchical_library_interfaces(page, &mut link_handle, &interfaces)
                        .await?;
                }
            } else {
                for page_index in 0..page.input_interface_page_count {
                    let interface_page = store.load_hierarchical_link_execution_interface_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_interface_count =
                        streamed_interface_count.saturating_add(interface_page.input_count);
                    let interfaces =
                        load_library_interface_artifacts(store, &interface_page.input_interfaces)?;
                    executor
                        .link_hierarchical_library_interfaces(page, &mut link_handle, &interfaces)
                        .await?;
                }
            }
            if !page.input_interface_ranges.is_empty() {
                let artifact_ref_index = store.load_build_artifact_ref_index(page.target)?;
                let mut artifact_refs = Vec::with_capacity(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                );
                for range in &page.input_interface_ranges {
                    let Some(indices) = range.iter() else {
                        return Err(source_pack_artifact_shard_contract_error(format!(
                            "hierarchical link execution group {} interface range starting at {} overflows",
                            page.group_index, range.first_job_index
                        )));
                    };
                    for job_index in indices {
                        let artifact_page = store.load_build_artifact_ref_page(
                            page.target,
                            job_index,
                            artifact_ref_index.artifact_count,
                        )?;
                        if artifact_page.artifact_ref.kind
                            != SourcePackArtifactKind::LibraryInterface
                        {
                            return Err(source_pack_artifact_shard_contract_error(format!(
                                "hierarchical link execution group {} interface range references artifact {} with kind {:?}",
                                page.group_index, job_index, artifact_page.artifact_ref.kind
                            )));
                        }
                        artifact_refs.push(artifact_page.artifact_ref);
                        streamed_interface_count = streamed_interface_count.saturating_add(1);
                        if artifact_refs.len()
                            == SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
                        {
                            let interfaces =
                                load_library_interface_artifacts(store, &artifact_refs)?;
                            executor
                                .link_hierarchical_library_interfaces(
                                    page,
                                    &mut link_handle,
                                    &interfaces,
                                )
                                .await?;
                            artifact_refs.clear();
                        }
                    }
                }
                if !artifact_refs.is_empty() {
                    let interfaces = load_library_interface_artifacts(store, &artifact_refs)?;
                    executor
                        .link_hierarchical_library_interfaces(page, &mut link_handle, &interfaces)
                        .await?;
                }
            }
            let expected_interface_count =
                source_pack_hierarchical_link_execution_input_interface_count(page);
            if streamed_interface_count != expected_interface_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} interface refs but expected {}",
                    page.group_index, streamed_interface_count, expected_interface_count
                )));
            }
            let mut streamed_object_count = 0usize;
            if page.input_object_page_count == 0 {
                streamed_object_count =
                    streamed_object_count.saturating_add(page.input_objects.len());
                let objects = load_codegen_object_artifacts(store, &page.input_objects)?;
                executor
                    .link_hierarchical_codegen_objects(page, &mut link_handle, &objects)
                    .await?;
            } else {
                for page_index in 0..page.input_object_page_count {
                    let object_page = store.load_hierarchical_link_execution_object_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_object_count =
                        streamed_object_count.saturating_add(object_page.input_count);
                    let objects = load_codegen_object_artifacts(store, &object_page.input_objects)?;
                    executor
                        .link_hierarchical_codegen_objects(page, &mut link_handle, &objects)
                        .await?;
                }
            }
            let expected_object_count =
                source_pack_hierarchical_link_execution_input_object_count(page);
            if streamed_object_count != expected_object_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} object refs but expected {}",
                    page.group_index, streamed_object_count, expected_object_count
                )));
            }
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            let mut streamed_partial_count = 0usize;
            if page.input_group_page_count == 0 {
                streamed_partial_count =
                    streamed_partial_count.saturating_add(page.input_group_output_keys.len());
                let partial_links =
                    load_partial_link_outputs(store, &page.input_group_output_keys)?;
                executor
                    .link_hierarchical_partial_links(page, &mut link_handle, &partial_links)
                    .await?;
            } else {
                for page_index in 0..page.input_group_page_count {
                    let partial_page = store.load_hierarchical_link_execution_partial_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    streamed_partial_count =
                        streamed_partial_count.saturating_add(partial_page.input_count);
                    let partial_links =
                        load_partial_link_outputs(store, &partial_page.input_group_output_keys)?;
                    executor
                        .link_hierarchical_partial_links(page, &mut link_handle, &partial_links)
                        .await?;
                }
            }
            let expected_partial_count =
                source_pack_hierarchical_link_execution_input_group_count(page);
            if streamed_partial_count != expected_partial_count {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "hierarchical link execution group {} streamed {} partial-link refs but expected {}",
                    page.group_index, streamed_partial_count, expected_partial_count
                )));
            }
        }
    }

    if page.final_output {
        let output = executor
            .finish_hierarchical_link_output(page, link_handle)
            .await?;
        store.store_hierarchical_linked_output(&page.output_key, output)?;
    } else {
        let output = executor
            .finish_hierarchical_partial_link_group(page, link_handle)
            .await?;
        store.store_partial_link_output(&page.output_key, output)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_schedule_error(
    err: SourcePackScheduleError,
) -> CompileError {
    CompileError::GpuFrontend(format!(
        "source-pack job schedule has no dependency-ready wave for jobs {:?}",
        err.unscheduled_job_indices
    ))
}

pub(in crate::compiler) fn source_pack_schedule_job(
    schedule: &SourcePackJobSchedule,
    job_index: usize,
) -> Result<&SourcePackJob, CompileError> {
    if let Some(job) = schedule.jobs.get(job_index) {
        if job.job_index == job_index {
            return Ok(job);
        }
    }
    schedule
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack job schedule references missing job {job_index}"
            ))
        })
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_load_schedule_job_dependencies(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibraryScheduleJobPage,
) -> Result<Vec<usize>, CompileError> {
    validate_source_pack_library_schedule_job_page(
        page,
        schedule_index.target,
        schedule_index.job_count,
        Some(page.job_index),
    )?;
    if !page.job.dependency_job_indices.is_empty() {
        return Ok(page.job.dependency_job_indices.clone());
    }
    let explicit_dependency_job_count =
        source_pack_schedule_job_page_explicit_dependency_count(page);
    let mut dependencies = Vec::with_capacity(source_pack_schedule_job_page_dependency_count(page));
    for page_index in 0..page.dependency_page_count {
        let dependency_page = store.load_library_schedule_job_dependency_page_for_target(
            schedule_index.target,
            page.job_index,
            page_index,
            schedule_index.job_count,
        )?;
        if dependency_page.first_dependency_position != dependencies.len() {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} dependency page {} starts at {} but loaded {} dependencies",
                page.job_index,
                page_index,
                dependency_page.first_dependency_position,
                dependencies.len()
            )));
        }
        let remaining_dependency_count = page
            .dependency_job_count
            .checked_sub(dependencies.len())
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule job page {} loaded too many dependencies before page {}",
                    page.job_index, page_index
                ))
            })?;
        let expected_page_dependency_count = remaining_dependency_count
            .min(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} dependency page {} has {} dependencies but expected {}",
                page.job_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        dependencies.extend(dependency_page.dependency_job_indices);
    }
    if dependencies.len() != explicit_dependency_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} loaded {} explicit dependencies but expected {}",
            page.job_index,
            dependencies.len(),
            explicit_dependency_job_count
        )));
    }
    for range in &page.dependency_job_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} has overflowing dependency range starting at {}",
                page.job_index, range.first_job_index
            )));
        };
        dependencies.extend(indices);
    }
    source_pack_manifest_unique_usize_set(
        &dependencies,
        &format!("schedule job page {} dependencies", page.job_index),
    )?;
    for &dependency_job_index in &dependencies {
        if dependency_job_index >= page.job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior paged job {}",
                page.job_index, dependency_job_index
            )));
        }
    }
    Ok(dependencies)
}

pub(in crate::compiler) fn source_pack_for_each_schedule_job_explicit_dependency_index<F>(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibraryScheduleJobPage,
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    validate_source_pack_library_schedule_job_page(
        page,
        schedule_index.target,
        schedule_index.job_count,
        Some(page.job_index),
    )?;
    if !page.job.dependency_job_indices.is_empty() {
        for &dependency_job_index in &page.job.dependency_job_indices {
            if dependency_job_index >= page.job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior inline job {}",
                    page.job_index, dependency_job_index
                )));
            }
            visit(dependency_job_index)?;
        }
        return Ok(page.job.dependency_job_indices.len());
    }

    let mut dependency_count = 0usize;
    let explicit_dependency_job_count =
        source_pack_schedule_job_page_explicit_dependency_count(page);
    for page_index in 0..page.dependency_page_count {
        let dependency_page = store.load_library_schedule_job_dependency_page_for_target(
            schedule_index.target,
            page.job_index,
            page_index,
            schedule_index.job_count,
        )?;
        if dependency_page.first_dependency_position != dependency_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} dependency page {} starts at {} but streamed {} dependencies",
                page.job_index,
                page_index,
                dependency_page.first_dependency_position,
                dependency_count
            )));
        }
        let remaining_dependency_count = page
            .dependency_job_count
            .checked_sub(dependency_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule job page {} streamed too many dependencies before page {}",
                    page.job_index, page_index
                ))
            })?;
        let expected_page_dependency_count = remaining_dependency_count
            .min(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} dependency page {} has {} dependencies but expected {}",
                page.job_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        for dependency_job_index in dependency_page.dependency_job_indices {
            if dependency_job_index >= page.job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior paged job {}",
                    page.job_index, dependency_job_index
                )));
            }
            visit(dependency_job_index)?;
            dependency_count += 1;
        }
    }
    if dependency_count != explicit_dependency_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} streamed {} explicit dependencies but expected {}",
            page.job_index, dependency_count, explicit_dependency_job_count
        )));
    }
    Ok(dependency_count)
}

pub(in crate::compiler) fn source_pack_schedule_job_first_dependency_index(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibraryScheduleJobPage,
) -> Result<Option<usize>, CompileError> {
    validate_source_pack_library_schedule_job_page(
        page,
        schedule_index.target,
        schedule_index.job_count,
        Some(page.job_index),
    )?;
    if let Some(&dependency_job_index) = page.job.dependency_job_indices.first() {
        if dependency_job_index >= page.job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior inline job {}",
                page.job_index, dependency_job_index
            )));
        }
        return Ok(Some(dependency_job_index));
    }
    if source_pack_schedule_job_page_explicit_dependency_count(page) == 0 {
        if let Some(range) = page.dependency_job_ranges.first() {
            if range.job_count == 0 {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule job page {} has empty first dependency range",
                    page.job_index
                )));
            }
            if range.first_job_index >= page.job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule job page {} depends on non-prior ranged job {}",
                    page.job_index, range.first_job_index
                )));
            }
            return Ok(Some(range.first_job_index));
        }
        return Ok(None);
    }
    let dependency_page = store.load_library_schedule_job_dependency_page_for_target(
        schedule_index.target,
        page.job_index,
        0,
        schedule_index.job_count,
    )?;
    let Some(&dependency_job_index) = dependency_page.dependency_job_indices.first() else {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} records {} dependencies but first dependency page is empty",
            page.job_index, page.dependency_job_count
        )));
    };
    if dependency_job_index >= page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} depends on non-prior paged job {}",
            page.job_index, dependency_job_index
        )));
    }
    Ok(Some(dependency_job_index))
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_stored_schedule_job(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
) -> Result<SourcePackJob, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let locator = store.load_library_schedule_job_locator_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let mut job = job_page.job.clone();
    job.dependency_job_indices =
        source_pack_load_schedule_job_dependencies(store, schedule_index, &job_page)?;
    source_pack_validate_stored_schedule_job_metadata(schedule_index, job_index, &locator, &job)?;
    Ok(job)
}

pub(in crate::compiler) fn source_pack_stored_schedule_job_metadata(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
) -> Result<SourcePackJob, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let locator = store.load_library_schedule_job_locator_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    let mut job = job_page.job;
    job.dependency_job_indices.clear();
    source_pack_validate_stored_schedule_job_metadata(schedule_index, job_index, &locator, &job)?;
    Ok(job)
}

pub(in crate::compiler) fn source_pack_validate_stored_schedule_job_metadata(
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
    locator: &SourcePackLibraryScheduleJobLocatorPage,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    if job.phase != locator.phase {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} has phase {:?} but locator has {:?}",
            job_index, job.phase, locator.phase
        )));
    }
    match locator.phase {
        SourcePackJobPhase::LibraryFrontend => {
            let partition_index = locator.partition_index.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "frontend job locator {} has no partition",
                    locator.job_index
                ))
            })?;
            if job.job_index != job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule locator for frontend job {job_index} points to partition {} but job page has job {}",
                    partition_index, job.job_index
                )));
            }
            Ok(())
        }
        SourcePackJobPhase::Codegen => {
            let partition_index = locator.partition_index.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "codegen job locator {} has no partition",
                    locator.job_index
                ))
            })?;
            let codegen_job_offset = locator.codegen_job_offset.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "codegen job locator {} has no codegen offset",
                    locator.job_index
                ))
            })?;
            if job.job_index != job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} points to job {}",
                    job.job_index
                )));
            }
            let frontend_job_count =
                source_pack_library_schedule_index_frontend_job_count(schedule_index);
            let Some(frontend_job_index) = job.library_job_index else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} has no owning frontend job"
                )));
            };
            if frontend_job_index >= frontend_job_count {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} points to partition {partition_index} but job page owner {} is outside frontend job range 0..{}",
                    frontend_job_index, frontend_job_count
                )));
            }
            let expected_job_index_floor = frontend_job_count;
            if job.job_index < expected_job_index_floor
                || job.job_index >= schedule_index.link_job_index
            {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule locator for codegen job {job_index} offset {codegen_job_offset} points outside codegen job range {}..{}",
                    expected_job_index_floor, schedule_index.link_job_index
                )));
            }
            Ok(())
        }
        SourcePackJobPhase::Link => {
            if job_index != schedule_index.link_job_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "link job locator {} does not match schedule link job {}",
                    job_index, schedule_index.link_job_index
                )));
            }
            Ok(())
        }
    }
}

pub(in crate::compiler) fn source_pack_schedule_job_page_dependency_count(
    page: &SourcePackLibraryScheduleJobPage,
) -> usize {
    source_pack_schedule_job_page_explicit_dependency_count(page).saturating_add(
        source_pack_job_index_range_dependency_count(&page.dependency_job_ranges),
    )
}

pub(in crate::compiler) fn source_pack_for_each_stored_schedule_frontend_job<F>(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize, SourcePackJob, usize) -> Result<(), CompileError>,
{
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_library_schedule_page(
        page,
        schedule_index.target,
        Some(page.partition_index),
    )?;
    if !page.frontend_jobs.is_empty() {
        for (offset, job) in page.frontend_jobs.iter().cloned().enumerate() {
            let dependency_job_count = job.dependency_job_indices.len();
            visit(offset, job, dependency_job_count)?;
        }
        return Ok(());
    }

    for offset in 0..source_pack_library_schedule_page_frontend_job_count(page) {
        let job_index = page.frontend_job_index.checked_add(offset).ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "schedule page {} frontend job offset {} overflows",
                page.partition_index, offset
            ))
        })?;
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let dependency_job_count = source_pack_schedule_job_page_dependency_count(&job_page);
        let mut job = job_page.job;
        job.dependency_job_indices.clear();
        source_pack_validate_stored_schedule_job_metadata(
            schedule_index,
            job_index,
            &locator,
            &job,
        )?;
        if job.phase != SourcePackJobPhase::LibraryFrontend
            || job.phase_unit_index
                != source_pack_library_schedule_page_first_frontend_unit_index(page) + offset
            || job.library_job_index.is_some()
            || job.library_id != page.library_id
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "stored frontend job {} does not match compact schedule page {} offset {}",
                job_index, page.partition_index, offset
            )));
        }
        visit(offset, job, dependency_job_count)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_for_each_stored_schedule_codegen_job<F>(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize, SourcePackJob) -> Result<(), CompileError>,
{
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_library_schedule_page(
        page,
        schedule_index.target,
        Some(page.partition_index),
    )?;
    if !page.codegen_jobs.is_empty() {
        for (offset, job) in page.codegen_jobs.iter().cloned().enumerate() {
            visit(offset, job)?;
        }
        return Ok(());
    }

    for offset in 0..page.codegen_job_count {
        let job_index = page
            .first_codegen_job_index
            .checked_add(offset)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule page {} codegen job offset {} overflows",
                    page.partition_index, offset
                ))
            })?;
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let job_page = store.load_library_schedule_job_page_for_target(
            schedule_index.target,
            job_index,
            schedule_index.job_count,
        )?;
        let first_dependency_job_index =
            source_pack_schedule_job_first_dependency_index(store, schedule_index, &job_page)?;
        let mut job = job_page.job;
        job.dependency_job_indices.clear();
        source_pack_validate_stored_schedule_job_metadata(
            schedule_index,
            job_index,
            &locator,
            &job,
        )?;
        if job.phase != SourcePackJobPhase::Codegen
            || job.phase_unit_index != page.first_codegen_unit_index.saturating_add(offset)
            || !job.library_job_index.is_some_and(|frontend_job_index| {
                source_pack_library_schedule_page_contains_frontend_job(page, frontend_job_index)
                    .unwrap_or(false)
            })
            || job.library_id != page.library_id
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "stored schedule job {} does not match compact schedule page {} offset {}",
                job_index, page.partition_index, offset
            )));
        }
        let owning_frontend_job_index = job
            .library_job_index
            .expect("codegen job owner checked above");
        if first_dependency_job_index != Some(owning_frontend_job_index) {
            return Err(source_pack_library_partition_contract_error(format!(
                "stored schedule job {} first dependency {:?} is not owning frontend job {}",
                job.job_index, first_dependency_job_index, owning_frontend_job_index
            )));
        }
        visit(offset, job)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_execution_shard_job_batch(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<&SourcePackJobBatch, CompileError> {
    execution_shard
        .job_batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job batch {batch_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_execution_shard_batch_dependency(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<&SourcePackJobBatchDependency, CompileError> {
    execution_shard
        .batch_dependencies
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing batch dependency {batch_index}",
                execution_shard.shard.shard_index
            ))
        })
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_execution_shard_batch_dependents(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<&SourcePackJobBatchDependents, CompileError> {
    execution_shard
        .batch_dependents
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing batch dependents {batch_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_execution_shard_job(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job_index: usize,
) -> Result<&SourcePackJob, CompileError> {
    execution_shard
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job {job_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_execution_shard_job_artifact(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job_index: usize,
) -> Result<&SourcePackJobArtifactManifest, CompileError> {
    execution_shard
        .job_artifacts
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} references missing job artifact manifest {job_index}",
                execution_shard.shard.shard_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_execution_shard_source_files_for_job<S>(
    store: &S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    job: &SourcePackJob,
) -> Result<Vec<ExplicitSourcePathFile>, CompileError>
where
    S: SourcePackFilesystemExecutionShardLoader,
{
    if execution_shard.source_files.is_empty() {
        return store.load_source_files_for_range(
            execution_shard.target,
            job.first_source_index,
            job.source_file_count,
        );
    }
    let mut files = Vec::with_capacity(job.source_file_count);
    for source_index in
        job.first_source_index..job.first_source_index.saturating_add(job.source_file_count)
    {
        let source_file = execution_shard
            .source_files
            .iter()
            .find(|source_file| source_file.source_index == source_index)
            .map(|source_file| source_file.file.clone())
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack execution shard {} missing source file {} for job {}",
                    execution_shard.shard.shard_index, source_index, job.job_index
                ))
            })?;
        files.push(source_file);
    }
    validate_explicit_source_path_files_metadata("source-pack job", &files)?;
    Ok(files)
}

pub(in crate::compiler) fn source_pack_for_each_execution_shard_artifact_ref_for_indices<F>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(&SourcePackArtifactRef) -> Result<(), CompileError>,
{
    let mut artifact_count = 0usize;
    for &artifact_index in artifact_indices {
        visit(source_pack_execution_shard_artifact_ref_for_index(
            execution_shard,
            artifact_index,
        )?)?;
        artifact_count += 1;
    }
    Ok(artifact_count)
}

pub(in crate::compiler) fn source_pack_execution_shard_artifact_ref_for_index(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_index: usize,
) -> Result<&SourcePackArtifactRef, CompileError> {
    execution_shard
        .artifact_refs
        .iter()
        .find(|artifact| artifact.artifact_index == artifact_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack execution shard {} missing artifact ref {}",
                execution_shard.shard.shard_index, artifact_index
            ))
        })
}

pub(in crate::compiler) fn load_library_interface_artifacts_from_execution_shard_indices<S>(
    store: &mut S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut artifacts = Vec::new();
    source_pack_for_each_execution_shard_artifact_ref_for_indices(
        execution_shard,
        artifact_indices,
        |artifact| {
            artifacts.push(store.load_library_interface(artifact)?);
            Ok(())
        },
    )?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_codegen_object_artifacts_from_execution_shard_indices<S>(
    store: &mut S,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    artifact_indices: &[usize],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut artifacts = Vec::new();
    source_pack_for_each_execution_shard_artifact_ref_for_indices(
        execution_shard,
        artifact_indices,
        |artifact| {
            artifacts.push(store.load_codegen_object(artifact)?);
            Ok(())
        },
    )?;
    Ok(artifacts)
}

pub(in crate::compiler) fn source_pack_artifact_manifest_batch(
    manifest: &SourcePackBuildArtifactManifest,
    batch_index: usize,
) -> Result<&SourcePackJobBatch, CompileError> {
    if let Some(batch) = manifest.job_batches.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    manifest
        .job_batches
        .batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing job batch {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_job_batch_dependency(
    plan: &crate::codegen::unit::SourcePackJobBatchDependencyPlan,
    batch_index: usize,
) -> Result<&SourcePackJobBatchDependency, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing batch dependency {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_link_interface_batch(
    plan: &crate::codegen::unit::SourcePackLinkInterfaceBatchPlan,
    batch_index: usize,
) -> Result<&SourcePackLinkInterfaceBatch, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing link interface batch {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_link_object_batch(
    plan: &crate::codegen::unit::SourcePackLinkObjectBatchPlan,
    batch_index: usize,
) -> Result<&SourcePackLinkObjectBatch, CompileError> {
    if let Some(batch) = plan.batches.get(batch_index) {
        if batch.batch_index == batch_index {
            return Ok(batch);
        }
    }
    plan.batches
        .iter()
        .find(|batch| batch.batch_index == batch_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing link object batch {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_path_manifest_source_files_for_job<'a>(
    source_pack: &'a ExplicitSourcePackPathManifest,
    job: &SourcePackJob,
) -> Result<&'a [ExplicitSourcePathFile], CompileError> {
    let start = job.first_source_index;
    let end = start.saturating_add(job.source_file_count);
    let source_files = source_pack.files.get(start..end).ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack job {} source range {}..{} exceeds manifest source file count {}",
            job.job_index,
            start,
            end,
            source_pack.files.len()
        ))
    })?;
    validate_explicit_source_path_files_metadata("source-pack job", source_files)?;
    Ok(source_files)
}

pub(in crate::compiler) fn source_pack_job_artifact_manifest(
    manifest: &SourcePackJobArtifactManifestPlan,
    job_index: usize,
) -> Result<&SourcePackJobArtifactManifest, CompileError> {
    if let Some(job) = manifest.jobs.get(job_index) {
        if job.job_index == job_index {
            return Ok(job);
        }
    }
    manifest
        .jobs
        .iter()
        .find(|job| job.job_index == job_index)
        .ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack artifact manifest references missing job {job_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_manifest_job_input_interface_refs(
    manifest: &SourcePackBuildArtifactManifest,
    job_manifest: &SourcePackJobArtifactManifest,
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    let mut input_interfaces = job_manifest.input_interfaces.clone();
    for range in &job_manifest.input_interface_ranges {
        let Some(dependency_job_indices) = range.iter() else {
            return Err(source_pack_manifest_contract_error(format!(
                "job {} input interface job range starting at {} overflows usize",
                job_manifest.job_index, range.first_job_index
            )));
        };
        for dependency_job_index in dependency_job_indices {
            let artifact = source_pack_manifest_library_interface_artifact_for_producing_job(
                &manifest.artifacts,
                dependency_job_index,
                &format!("job {} input interface job range", job_manifest.job_index),
            )?;
            input_interfaces.push(source_pack_artifact_ref_from_manifest_entry(artifact));
        }
    }
    for artifact_index in source_pack_manifest_artifact_index_range_set(
        &job_manifest.input_interface_artifact_ranges,
        &format!(
            "job {} input interface artifact ranges",
            job_manifest.job_index
        ),
    )? {
        let artifact = source_pack_manifest_artifact_entry(
            &manifest.artifacts,
            artifact_index,
            &format!(
                "job {} input interface artifact range",
                job_manifest.job_index
            ),
        )?;
        if artifact.kind != SourcePackArtifactKind::LibraryInterface {
            return Err(source_pack_manifest_contract_error(format!(
                "job {} input interface artifact range references artifact {} with kind {:?}",
                job_manifest.job_index, artifact.artifact_index, artifact.kind
            )));
        }
        input_interfaces.push(SourcePackArtifactRef {
            artifact_index: artifact.artifact_index,
            key: artifact.key.clone(),
            producing_job_index: artifact.producing_job_index,
            kind: artifact.kind,
        });
    }
    if input_interfaces.len() != job_manifest.input_interface_count {
        return Err(source_pack_manifest_contract_error(format!(
            "job {} has {} input interface refs but records {}",
            job_manifest.job_index,
            input_interfaces.len(),
            job_manifest.input_interface_count
        )));
    }
    Ok(input_interfaces)
}

pub(in crate::compiler) fn single_output_artifact_ref(
    job_manifest: &SourcePackJobArtifactManifest,
    kind: SourcePackArtifactKind,
) -> Result<&SourcePackArtifactRef, CompileError> {
    let mut outputs = job_manifest
        .outputs
        .iter()
        .filter(|artifact| artifact.kind == kind);
    let output = outputs.next().ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack job {} has no {:?} output artifact",
            job_manifest.job_index, kind
        ))
    })?;
    if outputs.next().is_some() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack job {} has more than one {:?} output artifact",
            job_manifest.job_index, kind
        )));
    }
    Ok(output)
}

pub(in crate::compiler) fn artifact_refs_for_indices(
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    let mut refs = Vec::new();
    source_pack_for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        refs.push(artifact);
        Ok(())
    })?;
    Ok(refs)
}

pub(in crate::compiler) fn source_pack_for_each_artifact_ref_for_indices<F>(
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
    mut visit: F,
) -> Result<usize, CompileError>
where
    F: FnMut(SourcePackArtifactRef) -> Result<(), CompileError>,
{
    let mut artifact_count = 0usize;
    for &artifact_index in artifact_indices {
        visit(source_pack_artifact_ref_for_index(
            manifest,
            artifact_index,
        )?)?;
        artifact_count += 1;
    }
    Ok(artifact_count)
}

pub(in crate::compiler) fn source_pack_artifact_ref_for_index(
    manifest: &SourcePackArtifactManifest,
    artifact_index: usize,
) -> Result<SourcePackArtifactRef, CompileError> {
    let artifact = manifest.get(artifact_index).ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack artifact manifest missing artifact {artifact_index}"
        ))
    })?;
    Ok(SourcePackArtifactRef {
        artifact_index: artifact.artifact_index,
        key: artifact.key.clone(),
        producing_job_index: artifact.producing_job_index,
        kind: artifact.kind,
    })
}

pub(in crate::compiler) fn load_library_interface_artifacts_for_indices<S>(
    store: &mut S,
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut artifacts = Vec::new();
    source_pack_for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        artifacts.push(store.load_library_interface(&artifact)?);
        Ok(())
    })?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_codegen_object_artifacts_for_indices<S>(
    store: &mut S,
    manifest: &SourcePackArtifactManifest,
    artifact_indices: &[usize],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut artifacts = Vec::new();
    source_pack_for_each_artifact_ref_for_indices(manifest, artifact_indices, |artifact| {
        artifacts.push(store.load_codegen_object(&artifact)?);
        Ok(())
    })?;
    Ok(artifacts)
}

pub(in crate::compiler) fn load_library_interface_artifacts_excluding<S>(
    store: &mut S,
    artifact_refs: &[SourcePackArtifactRef],
    excluded_artifact_index: usize,
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    load_library_interface_artifact_batch_excluding(
        store,
        artifact_refs,
        Some(excluded_artifact_index),
    )
}

pub(in crate::compiler) fn load_library_interface_artifact_batch_excluding<S>(
    store: &mut S,
    artifact_refs: &[SourcePackArtifactRef],
    excluded_artifact_index: Option<usize>,
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    artifact_refs
        .iter()
        .filter(|artifact| Some(artifact.artifact_index) != excluded_artifact_index)
        .map(|artifact| store.load_library_interface(artifact))
        .collect()
}

pub(in crate::compiler) fn load_library_interface_artifacts<S>(
    store: &mut S,
    artifacts: &[SourcePackArtifactRef],
) -> Result<Vec<S::LibraryInterfaceArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    artifacts
        .iter()
        .map(|artifact| store.load_library_interface(artifact))
        .collect()
}

pub(in crate::compiler) fn load_codegen_object_artifacts<S>(
    store: &mut S,
    artifacts: &[SourcePackArtifactRef],
) -> Result<Vec<S::CodegenObjectArtifact>, CompileError>
where
    S: SourcePackPathArtifactStore,
{
    artifacts
        .iter()
        .map(|artifact| store.load_codegen_object(artifact))
        .collect()
}

pub(in crate::compiler) fn load_partial_link_outputs<S>(
    store: &mut S,
    keys: &[String],
) -> Result<Vec<S::PartialLinkArtifact>, CompileError>
where
    S: SourcePackPathHierarchicalLinkArtifactStore,
{
    keys.iter()
        .map(|key| store.load_partial_link_output(key))
        .collect()
}

pub(in crate::compiler) fn release_source_pack_link_input_artifacts<S>(
    artifact_manifest: &SourcePackBuildArtifactManifest,
    store: &mut S,
) -> Result<(), CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut released_interfaces = BTreeSet::new();
    for link_batch in &artifact_manifest.link_interface_batches.batches {
        source_pack_for_each_artifact_ref_for_indices(
            &artifact_manifest.artifacts,
            &link_batch.input_interface_artifact_indices,
            |artifact| {
                if released_interfaces.insert(artifact.artifact_index) {
                    store.release_library_interface(&artifact)?;
                }
                Ok(())
            },
        )?;
    }

    let mut released_objects = BTreeSet::new();
    for link_batch in &artifact_manifest.link_object_batches.batches {
        source_pack_for_each_artifact_ref_for_indices(
            &artifact_manifest.artifacts,
            &link_batch.input_object_artifact_indices,
            |artifact| {
                if released_objects.insert(artifact.artifact_index) {
                    store.release_codegen_object(&artifact)?;
                }
                Ok(())
            },
        )?;
    }

    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_artifact_shard_for_job_batch(
    shards: &[SourcePackBuildArtifactShard],
    batch_index: usize,
) -> Result<&SourcePackBuildArtifactShard, CompileError> {
    shards
        .iter()
        .find(|shard| {
            shard.kind == SourcePackBuildArtifactShardKind::JobBatches
                && shard.batch_indices.contains(&batch_index)
        })
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "no job-batch shard contains batch {batch_index}"
            ))
        })
}

pub(in crate::compiler) fn source_pack_execution_shard_batch_result(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<SourcePackArtifactStoreBatchExecutionResult, CompileError> {
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    let mut linked_output_key = None;
    for &job_index in &batch.job_indices {
        let job = source_pack_execution_shard_job(execution_shard, job_index)?;
        if job.phase != SourcePackJobPhase::Link {
            continue;
        }
        let job_manifest = source_pack_execution_shard_job_artifact(execution_shard, job_index)?;
        let output =
            single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
        if linked_output_key.replace(output.key.clone()).is_some() {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack execution shard batch {} contains more than one linked output",
                batch.batch_index
            )));
        }
    }
    Ok(SourcePackArtifactStoreBatchExecutionResult {
        batch_index: batch.batch_index,
        job_count: batch.job_indices.len(),
        linked_output_key,
    })
}

pub(in crate::compiler) fn source_pack_execution_shard_batch_contains_link_job(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<bool, CompileError> {
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    for &job_index in &batch.job_indices {
        if source_pack_execution_shard_job(execution_shard, job_index)?.phase
            == SourcePackJobPhase::Link
        {
            return Ok(true);
        }
    }
    Ok(false)
}

pub(in crate::compiler) fn release_source_pack_link_input_artifacts_from_execution_shard<S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    store: &mut S,
) -> Result<(usize, usize), CompileError>
where
    S: SourcePackPathArtifactStore,
{
    let mut released_interface_count = 0usize;
    let mut released_object_count = 0usize;
    let mut released_artifact_indices = BTreeSet::new();
    match execution_shard.shard.kind {
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            for artifact in &execution_shard.artifact_refs {
                if artifact.kind == SourcePackArtifactKind::LibraryInterface
                    && released_artifact_indices.insert(artifact.artifact_index)
                {
                    store.release_library_interface(artifact)?;
                    released_interface_count = released_interface_count.saturating_add(1);
                }
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            for artifact in &execution_shard.artifact_refs {
                if artifact.kind == SourcePackArtifactKind::CodegenObject
                    && released_artifact_indices.insert(artifact.artifact_index)
                {
                    store.release_codegen_object(artifact)?;
                    released_object_count = released_object_count.saturating_add(1);
                }
            }
        }
        SourcePackBuildArtifactShardKind::JobBatches => {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} is a job-batch shard, not a link-input shard",
                execution_shard.shard.shard_index
            )));
        }
    }
    Ok((released_interface_count, released_object_count))
}

pub(in crate::compiler) fn collect_interface_handle_clones<T: Clone>(
    library_interfaces: &[Option<T>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
) -> Result<Vec<T>, CompileError> {
    collect_interface_handle_clones_excluding(library_interfaces, schedule, job, None)
}

pub(in crate::compiler) fn collect_interface_handle_clones_excluding<T: Clone>(
    library_interfaces: &[Option<T>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for_each_interface_dependency_job_index(
        schedule,
        job,
        excluded_job_index,
        |dependency_job_index| {
            let handle = library_interfaces
                .get(dependency_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack job {} missing interface dependency from job {}",
                        job.job_index, dependency_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        },
    )?;
    Ok(handles)
}

pub(in crate::compiler) fn collect_link_interface_handle_clones<T: Clone>(
    library_interfaces: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing interface artifact {artifact_index}"
                ))
            })?;
            let handle = library_interfaces
                .get(artifact.producing_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing interface from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        })?;
    Ok(handles)
}

pub(in crate::compiler) fn collect_link_interface_handle_clones_for_batch<T: Clone>(
    library_interfaces: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkInterfaceBatch,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for &artifact_index in &batch.input_interface_artifact_indices {
        let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack link batch references missing interface artifact {artifact_index}"
            ))
        })?;
        let handle = library_interfaces
            .get(artifact.producing_job_index)
            .and_then(|handle| handle.as_ref())
            .cloned()
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link batch missing interface from job {}",
                    artifact.producing_job_index
                ))
            })?;
        handles.push(handle);
    }
    Ok(handles)
}

pub(in crate::compiler) fn collect_link_object_handle_clones<T: Clone>(
    codegen_objects: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing object artifact {artifact_index}"
                ))
            })?;
            let handle = codegen_objects
                .get(artifact.producing_job_index)
                .and_then(|handle| handle.as_ref())
                .cloned()
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing object from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            handles.push(handle);
            Ok(())
        })?;
    Ok(handles)
}

pub(in crate::compiler) fn collect_link_object_handle_clones_for_batch<T: Clone>(
    codegen_objects: &[Option<T>],
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkObjectBatch,
) -> Result<Vec<T>, CompileError> {
    let mut handles = Vec::new();
    for &artifact_index in &batch.input_object_artifact_indices {
        let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
            CompileError::GpuFrontend(format!(
                "source-pack link batch references missing object artifact {artifact_index}"
            ))
        })?;
        let handle = codegen_objects
            .get(artifact.producing_job_index)
            .and_then(|handle| handle.as_ref())
            .cloned()
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link batch missing object from job {}",
                    artifact.producing_job_index
                ))
            })?;
        handles.push(handle);
    }
    Ok(handles)
}

pub(in crate::compiler) fn release_link_input_handles<E>(
    build_plan: &SourcePackBuildPlan,
    library_interfaces: &mut [Option<E::LibraryInterfaceHandle>],
    codegen_objects: &mut [Option<E::CodegenObjectHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: SourcePackPathHandleBuildExecutor,
{
    let mut released_interfaces = BTreeSet::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            if !released_interfaces.insert(artifact_index) {
                return Ok(());
            }
            let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
                return Ok(());
            };
            if artifact.kind != SourcePackArtifactKind::LibraryInterface {
                return Ok(());
            }
            if let Some(handle) = library_interfaces
                .get_mut(artifact.producing_job_index)
                .and_then(Option::take)
            {
                executor.release_library_interface(handle)?;
            }
            Ok::<(), CompileError>(())
        })?;

    let mut released_objects = BTreeSet::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            if !released_objects.insert(artifact_index) {
                return Ok(());
            }
            let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
                return Ok(());
            };
            if artifact.kind != SourcePackArtifactKind::CodegenObject {
                return Ok(());
            }
            if let Some(handle) = codegen_objects
                .get_mut(artifact.producing_job_index)
                .and_then(Option::take)
            {
                executor.release_codegen_object(handle)?;
            }
            Ok::<(), CompileError>(())
        })?;

    Ok(())
}

pub(in crate::compiler) fn release_codegen_object_handles_for_link_batch<E>(
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkObjectBatch,
    codegen_objects: &mut [Option<E::CodegenObjectHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: SourcePackPathHandleBatchedLinkBuildExecutor,
{
    for &artifact_index in &batch.input_object_artifact_indices {
        let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
            continue;
        };
        if artifact.kind != SourcePackArtifactKind::CodegenObject {
            continue;
        }
        if let Some(handle) = codegen_objects
            .get_mut(artifact.producing_job_index)
            .and_then(Option::take)
        {
            executor.release_codegen_object(handle)?;
        }
    }
    Ok(())
}

pub(in crate::compiler) fn release_library_interface_handles_for_link_batch<E>(
    build_plan: &SourcePackBuildPlan,
    batch: &SourcePackLinkInterfaceBatch,
    library_interfaces: &mut [Option<E::LibraryInterfaceHandle>],
    executor: &mut E,
) -> Result<(), CompileError>
where
    E: SourcePackPathHandleBatchedLinkBuildExecutor,
{
    for &artifact_index in &batch.input_interface_artifact_indices {
        let Some(artifact) = build_plan.artifacts.get(artifact_index) else {
            continue;
        };
        if artifact.kind != SourcePackArtifactKind::LibraryInterface {
            continue;
        }
        if let Some(handle) = library_interfaces
            .get_mut(artifact.producing_job_index)
            .and_then(Option::take)
        {
            executor.release_library_interface(handle)?;
        }
    }
    Ok(())
}

pub(in crate::compiler) fn collect_interface_refs<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
) -> Result<Vec<&'a T>, CompileError> {
    collect_interface_refs_excluding(library_interfaces, interface_by_job, schedule, job, None)
}

pub(in crate::compiler) fn collect_interface_refs_excluding<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    for_each_interface_dependency_job_index(
        schedule,
        job,
        excluded_job_index,
        |dependency_job_index| {
            let interface_index = interface_by_job
                .get(dependency_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack job {} missing interface dependency from job {}",
                        job.job_index, dependency_job_index
                    ))
                })?;
            refs.push(&library_interfaces[interface_index]);
            Ok(())
        },
    )?;
    Ok(refs)
}

pub(in crate::compiler) fn for_each_interface_dependency_job_index<F>(
    schedule: &SourcePackJobSchedule,
    job: &SourcePackJob,
    excluded_job_index: Option<usize>,
    mut visit: F,
) -> Result<(), CompileError>
where
    F: FnMut(usize) -> Result<(), CompileError>,
{
    let mut seen = BTreeSet::new();
    for &dependency_job_index in &job.dependency_job_indices {
        if Some(dependency_job_index) != excluded_job_index && seen.insert(dependency_job_index) {
            visit(dependency_job_index)?;
        }
    }
    for dependency_range in schedule.dependency_job_ranges_for_job(job) {
        let Some(dependency_job_indices) = dependency_range.iter() else {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack job {} interface dependency range starting at {} overflows",
                job.job_index, dependency_range.first_job_index
            )));
        };
        for dependency_job_index in dependency_job_indices {
            if Some(dependency_job_index) != excluded_job_index && seen.insert(dependency_job_index)
            {
                visit(dependency_job_index)?;
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn collect_link_interface_refs<'a, T>(
    library_interfaces: &'a [T],
    interface_by_job: &[Option<usize>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    build_plan
        .link
        .try_for_each_input_interface_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing interface artifact {artifact_index}"
                ))
            })?;
            let interface_index = interface_by_job
                .get(artifact.producing_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing interface from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            refs.push(&library_interfaces[interface_index]);
            Ok(())
        })?;
    Ok(refs)
}

pub(in crate::compiler) fn collect_link_object_refs<'a, T>(
    codegen_objects: &'a [T],
    object_by_job: &[Option<usize>],
    build_plan: &SourcePackBuildPlan,
) -> Result<Vec<&'a T>, CompileError> {
    let mut refs = Vec::new();
    build_plan
        .link
        .try_for_each_input_object_artifact_index(|artifact_index| {
            let artifact = build_plan.artifacts.get(artifact_index).ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack link references missing object artifact {artifact_index}"
                ))
            })?;
            let object_index = object_by_job
                .get(artifact.producing_job_index)
                .and_then(|index| *index)
                .ok_or_else(|| {
                    CompileError::GpuFrontend(format!(
                        "source-pack link missing object from job {}",
                        artifact.producing_job_index
                    ))
                })?;
            refs.push(&codegen_objects[object_index]);
            Ok(())
        })?;
    Ok(refs)
}
