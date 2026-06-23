use super::*;

/// Executes every job in one execution-shard batch with the async paged executor.
///
/// The batch is looked up inside the execution shard, each job is dispatched by
/// phase, and the batch result records the single linked output key if the batch
/// happened to contain the final link job.
pub(in crate::compiler) async fn execute_execution_shard_batch_paged_async<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    batch_index: usize,
    target: SourcePackArtifactTarget,
    executor: &mut E,
    store: &mut S,
) -> Result<ArtifactStoreBatchExecutionResult, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
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
        if let Some(job_linked_output_key) = execute_execution_shard_job_paged_async(
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
                return Err(duplicate_linked_output_error(
                    format!(
                        "source-pack async execution shard batch {}",
                        batch.batch_index
                    ),
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

/// Executes one job from an artifact execution shard.
///
/// Frontend jobs build and store library interfaces, codegen jobs load their
/// owning interface before storing objects, and link jobs stream link-input
/// shards before storing the linked output.
pub(in crate::compiler) async fn execute_execution_shard_job_paged_async<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: Option<&SourcePackBuildLinkInputShardIndex>,
    target: SourcePackArtifactTarget,
    job_index: usize,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
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
            let mut handle = executor.begin_library_interface(job, &source_files).await?;
            add_library_interface_dependency_batches_async(
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
            let library_job_index = codegen_library_job_index(job)?;
            let library_interface_ref = execution_shard_job_input_interface_ref(
                store,
                target,
                job_manifest,
                library_job_index,
            )?;
            let library_interface = store.load_library_interface(&library_interface_ref)?;
            let source_files = execution_shard_source_files_for_job(store, execution_shard, job)?;
            let mut handle = executor
                .begin_codegen_object(job, &source_files, &library_interface)
                .await?;
            add_codegen_object_dependency_batches_async(
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
            execute_execution_shard_link_job_async(
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
            )
            .await
        }
    }
}

/// Streams library-interface dependency batches into a frontend build handle.
///
/// Input interfaces may be inline, paged, job-index ranges, or artifact-index
/// ranges. The function loads artifacts in bounded batches and verifies that the
/// number of streamed references matches the job artifact manifest summary.
pub(in crate::compiler) async fn add_library_interface_dependency_batches_async<E, S>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    executor: &mut E,
    job: &SourcePackJob,
    handle: &mut E::LibraryInterfaceBuildHandle,
) -> Result<usize, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<LibraryInterfaceArtifact = S::LibraryInterfaceArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
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
        return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                    return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                    return Err(artifact_shard_contract_error(format!(
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
        return Err(artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}

/// Streams library-interface dependency batches into a codegen build handle.
///
/// This follows the same manifest forms as frontend dependency loading, but may
/// exclude the codegen job's owning interface artifact so it is not passed back
/// to the executor as an ordinary dependency.
pub(in crate::compiler) async fn add_codegen_object_dependency_batches_async<E, S>(
    store: &mut S,
    target: SourcePackArtifactTarget,
    job_manifest: &SourcePackJobArtifactManifest,
    excluded_artifact_index: Option<usize>,
    executor: &mut E,
    job: &SourcePackJob,
    handle: &mut E::CodegenObjectBuildHandle,
) -> Result<usize, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<LibraryInterfaceArtifact = S::LibraryInterfaceArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
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
        return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                    return Err(artifact_shard_contract_error(format!(
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
                return Err(artifact_shard_contract_error(format!(
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
                    return Err(artifact_shard_contract_error(format!(
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
        return Err(artifact_shard_contract_error(format!(
            "job artifact manifest {} streamed {} interface refs but expected {}",
            job_manifest.job_index, seen_input_count, job_manifest.input_interface_count
        )));
    }
    Ok(loaded_input_count)
}

/// Executes the async link job for an execution shard.
///
/// The link job loads all interface and object input shards listed by the link
/// input shard index, feeds their batches into the link handle, stores the final
/// linked output, and verifies that output is declared by the execution shard.
pub(in crate::compiler) async fn execute_execution_shard_link_job_async<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    job_manifest: &SourcePackJobArtifactManifest,
    executor: &mut E,
    store: &mut S,
) -> Result<Option<String>, CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
        >,
    S: ArtifactStore + ExecutionShardLoader,
{
    validate_link_input_shard_index(link_input_shard_index, target)?;
    let mut link_handle = executor.begin_link_codegen_objects(job).await?;
    execute_link_input_interface_shards_async(
        link_input_shard_index,
        target,
        job,
        executor,
        store,
        &mut link_handle,
    )
    .await?;
    execute_link_input_object_shards_async(
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
        return Err(artifact_shard_contract_error(format!(
            "link job {} output artifact {} is not listed in execution shard {}",
            job.job_index, output.artifact_index, execution_shard.shard.shard_index
        )));
    }

    Ok(Some(linked_output_key))
}

/// Streams all interface-input shards listed for a link job.
///
/// The shard index stores the interface shard range compactly; each shard in
/// the range is loaded and replayed into the active link handle.
pub(in crate::compiler) async fn execute_link_input_interface_shards_async<E, S>(
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<LibraryInterfaceArtifact = S::LibraryInterfaceArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
{
    if let Some(range) = link_input_shard_index.link_interface_shard_range.as_ref() {
        let Some(indices) = range.iter() else {
            return Err(artifact_shard_contract_error(
                "interface link input shard range overflows",
            ));
        };
        for shard_index in indices {
            execute_link_input_interface_shard_async(
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

/// Loads one interface-input shard and feeds its batches into the link handle.
///
/// The shard kind is checked before any artifacts are loaded so object shards
/// cannot be consumed through the interface path.
pub(in crate::compiler) async fn execute_link_input_interface_shard_async<E, S>(
    shard_index: usize,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<LibraryInterfaceArtifact = S::LibraryInterfaceArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
{
    let link_shard = store.load_execution_shard(target, shard_index)?;
    validate_execution_shard(&link_shard, target)?;
    if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkInterfaceBatches {
        return Err(artifact_shard_contract_error(format!(
            "link input shard index lists shard {shard_index} as an interface shard, but it is {:?}",
            link_shard.shard.kind
        )));
    }
    for link_batch in &link_shard.link_interface_batches {
        let interfaces = load_interface_artifacts_from_shards(
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

/// Streams all object-input shards listed for a link job.
///
/// The shard index stores the object shard range compactly; each shard in the
/// range is loaded and replayed into the active link handle.
pub(in crate::compiler) async fn execute_link_input_object_shards_async<E, S>(
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<CodegenObjectArtifact = S::CodegenObjectArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
{
    if let Some(range) = link_input_shard_index.link_object_shard_range.as_ref() {
        let Some(indices) = range.iter() else {
            return Err(artifact_shard_contract_error(
                "object link input shard range overflows",
            ));
        };
        for shard_index in indices {
            execute_link_input_object_shard_async(
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

/// Loads one object-input shard and feeds its batches into the link handle.
///
/// The shard kind is checked before any artifacts are loaded so interface shards
/// cannot be consumed through the object path.
pub(in crate::compiler) async fn execute_link_input_object_shard_async<E, S>(
    shard_index: usize,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    executor: &mut E,
    store: &mut S,
    link_handle: &mut E::LinkHandle,
) -> Result<(), CompileError>
where
    E: AsyncPagedArtifactBuildExecutor<CodegenObjectArtifact = S::CodegenObjectArtifact>,
    S: ArtifactStore + ExecutionShardLoader,
{
    let link_shard = store.load_execution_shard(target, shard_index)?;
    validate_execution_shard(&link_shard, target)?;
    if link_shard.shard.kind != SourcePackBuildArtifactShardKind::LinkObjectBatches {
        return Err(artifact_shard_contract_error(format!(
            "link input shard index lists shard {shard_index} as an object shard, but it is {:?}",
            link_shard.shard.kind
        )));
    }
    for link_batch in &link_shard.link_object_batches {
        let objects = load_codegen_objects_from_shard(
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
