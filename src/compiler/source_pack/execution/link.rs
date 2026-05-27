use super::*;

pub(in crate::compiler) fn execute_execution_shard_link_job<E, S>(
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    link_input_shard_index: &SourcePackBuildLinkInputShardIndex,
    target: SourcePackArtifactTarget,
    job: &SourcePackJob,
    job_manifest: &SourcePackJobArtifactManifest,
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
    validate_link_input_shard_index(link_input_shard_index, target)?;
    let mut link_handle = executor.begin_link_codegen_objects(job)?;
    for_each_link_input_shard_index(
        link_input_shard_index,
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches,
        |shard_index| {
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
    for_each_link_input_shard_index(
        link_input_shard_index,
        SourcePackBuildArtifactShardKind::LinkObjectBatches,
        |shard_index| {
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
        return Err(artifact_shard_contract_error(format!(
            "link job {} output artifact {} is not listed in execution shard {}",
            job.job_index, output.artifact_index, execution_shard.shard.shard_index
        )));
    }

    Ok(Some(linked_output_key))
}

pub(in crate::compiler) fn execute_hierarchical_link_page<E, S>(
    page: &SourcePackHierarchicalLinkExecutionPage,
    executor: &mut E,
    store: &mut S,
) -> Result<(), CompileError>
where
    E: HierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: HierarchicalLinkArtifactStore + ExecutionShardLoader,
{
    validate_link_execution_page(page, page.target, Some(page.group_index))?;
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
                        return Err(artifact_shard_contract_error(format!(
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
                            return Err(artifact_shard_contract_error(format!(
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
            let expected_interface_count = hierarchical_link_execution_input_interface_count(page);
            if streamed_interface_count != expected_interface_count {
                return Err(artifact_shard_contract_error(format!(
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
            let expected_object_count = hierarchical_link_execution_input_object_count(page);
            if streamed_object_count != expected_object_count {
                return Err(artifact_shard_contract_error(format!(
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
            let expected_partial_count = hierarchical_link_execution_input_group_count(page);
            if streamed_partial_count != expected_partial_count {
                return Err(artifact_shard_contract_error(format!(
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

pub(in crate::compiler) async fn execute_hierarchical_link_page_async<E, S>(
    page: &SourcePackHierarchicalLinkExecutionPage,
    executor: &mut E,
    store: &mut S,
) -> Result<(), CompileError>
where
    E: AsyncPagedHierarchicalLinkExecutor<
            LibraryInterfaceArtifact = S::LibraryInterfaceArtifact,
            CodegenObjectArtifact = S::CodegenObjectArtifact,
            LinkedOutputArtifact = S::LinkedOutputArtifact,
            PartialLinkArtifact = S::PartialLinkArtifact,
        >,
    S: HierarchicalLinkArtifactStore + ExecutionShardLoader,
{
    validate_link_execution_page(page, page.target, Some(page.group_index))?;
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
                        return Err(artifact_shard_contract_error(format!(
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
                            return Err(artifact_shard_contract_error(format!(
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
            let expected_interface_count = hierarchical_link_execution_input_interface_count(page);
            if streamed_interface_count != expected_interface_count {
                return Err(artifact_shard_contract_error(format!(
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
            let expected_object_count = hierarchical_link_execution_input_object_count(page);
            if streamed_object_count != expected_object_count {
                return Err(artifact_shard_contract_error(format!(
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
            let expected_partial_count = hierarchical_link_execution_input_group_count(page);
            if streamed_partial_count != expected_partial_count {
                return Err(artifact_shard_contract_error(format!(
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
