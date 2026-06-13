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
    let output = single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?;
    let linked_output_key = output.key.clone();
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
    store.store_linked_output(output, linked_output)?;

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
    S: HierarchicalLinkArtifactStore + ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    validate_link_execution_page(page, page.target, Some(page.group_index))?;
    validate_hierarchical_link_reduce_inputs_before_begin(page, store)?;
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
                let mut previous_interface_producer_job_index = None;
                for page_index in 0..page.input_interface_page_count {
                    let interface_page = store.load_hierarchical_link_execution_interface_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_interface_page(
                        &interface_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "interface",
                        page_index,
                        page.input_interface_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                        interface_page.input_count,
                        interface_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_artifact_order(
                        page.group_index,
                        "interface",
                        page_index,
                        &interface_page.input_interfaces,
                        &mut previous_interface_producer_job_index,
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
                let mut previous_object_producer_job_index = None;
                for page_index in 0..page.input_object_page_count {
                    let object_page = store.load_hierarchical_link_execution_object_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_object_page(
                        &object_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "object",
                        page_index,
                        page.input_object_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
                        object_page.input_count,
                        object_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_artifact_order(
                        page.group_index,
                        "object",
                        page_index,
                        &object_page.input_objects,
                        &mut previous_object_producer_job_index,
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
            let mut partial_source_summary = LinkExecutionPartialSourceSummary::default();
            if page.input_group_page_count == 0 {
                partial_source_summary = validate_link_execution_partial_producer_pages(
                    store.as_ref(),
                    page,
                    &page.input_group_indices,
                    &page.input_group_output_keys,
                    "inline partial-link inputs",
                )?;
                streamed_partial_count =
                    streamed_partial_count.saturating_add(page.input_group_output_keys.len());
            } else {
                let mut previous_partial_input_group_index = None;
                for page_index in 0..page.input_group_page_count {
                    let partial_page = store.load_hierarchical_link_execution_partial_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_partial_page(
                        &partial_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "partial-link",
                        page_index,
                        page.input_group_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
                        partial_page.input_count,
                        partial_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_group_order(
                        page.group_index,
                        "partial-link",
                        page_index,
                        &partial_page.input_group_indices,
                        &mut previous_partial_input_group_index,
                    )?;
                    streamed_partial_count =
                        streamed_partial_count.saturating_add(partial_page.input_count);
                    let page_source_summary = validate_link_execution_partial_producer_pages(
                        store.as_ref(),
                        page,
                        &partial_page.input_group_indices,
                        &partial_page.input_group_output_keys,
                        &format!("partial-link sidecar page {page_index}"),
                    )?;
                    partial_source_summary = partial_source_summary.checked_add(
                        page_source_summary,
                        page.group_index,
                        &format!("partial-link sidecar page {page_index}"),
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
            validate_link_execution_partial_source_summary(page, partial_source_summary)?;
            if page.input_group_page_count == 0 {
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
                    validate_link_execution_partial_page(
                        &partial_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    let partial_links =
                        load_partial_link_outputs(store, &partial_page.input_group_output_keys)?;
                    executor.link_hierarchical_partial_links(
                        page,
                        &mut link_handle,
                        &partial_links,
                    )?;
                }
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
    S: HierarchicalLinkArtifactStore + ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    validate_link_execution_page(page, page.target, Some(page.group_index))?;
    validate_hierarchical_link_reduce_inputs_before_begin(page, store)?;
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
                let mut previous_interface_producer_job_index = None;
                for page_index in 0..page.input_interface_page_count {
                    let interface_page = store.load_hierarchical_link_execution_interface_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_interface_page(
                        &interface_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "interface",
                        page_index,
                        page.input_interface_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                        interface_page.input_count,
                        interface_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_artifact_order(
                        page.group_index,
                        "interface",
                        page_index,
                        &interface_page.input_interfaces,
                        &mut previous_interface_producer_job_index,
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
                let mut previous_object_producer_job_index = None;
                for page_index in 0..page.input_object_page_count {
                    let object_page = store.load_hierarchical_link_execution_object_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_object_page(
                        &object_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "object",
                        page_index,
                        page.input_object_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
                        object_page.input_count,
                        object_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_artifact_order(
                        page.group_index,
                        "object",
                        page_index,
                        &object_page.input_objects,
                        &mut previous_object_producer_job_index,
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
            let mut partial_source_summary = LinkExecutionPartialSourceSummary::default();
            if page.input_group_page_count == 0 {
                partial_source_summary = validate_link_execution_partial_producer_pages(
                    store.as_ref(),
                    page,
                    &page.input_group_indices,
                    &page.input_group_output_keys,
                    "inline partial-link inputs",
                )?;
                streamed_partial_count =
                    streamed_partial_count.saturating_add(page.input_group_output_keys.len());
            } else {
                let mut previous_partial_input_group_index = None;
                for page_index in 0..page.input_group_page_count {
                    let partial_page = store.load_hierarchical_link_execution_partial_page(
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_partial_page(
                        &partial_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    validate_link_execution_sidecar_page(
                        page.group_index,
                        "partial-link",
                        page_index,
                        page.input_group_page_count,
                        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
                        partial_page.input_count,
                        partial_page.job_index,
                        page.job_index,
                    )?;
                    validate_link_execution_sidecar_group_order(
                        page.group_index,
                        "partial-link",
                        page_index,
                        &partial_page.input_group_indices,
                        &mut previous_partial_input_group_index,
                    )?;
                    streamed_partial_count =
                        streamed_partial_count.saturating_add(partial_page.input_count);
                    let page_source_summary = validate_link_execution_partial_producer_pages(
                        store.as_ref(),
                        page,
                        &partial_page.input_group_indices,
                        &partial_page.input_group_output_keys,
                        &format!("partial-link sidecar page {page_index}"),
                    )?;
                    partial_source_summary = partial_source_summary.checked_add(
                        page_source_summary,
                        page.group_index,
                        &format!("partial-link sidecar page {page_index}"),
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
            validate_link_execution_partial_source_summary(page, partial_source_summary)?;
            if page.input_group_page_count == 0 {
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
                    validate_link_execution_partial_page(
                        &partial_page,
                        page.target,
                        page.group_index,
                        page_index,
                    )?;
                    let partial_links =
                        load_partial_link_outputs(store, &partial_page.input_group_output_keys)?;
                    executor
                        .link_hierarchical_partial_links(page, &mut link_handle, &partial_links)
                        .await?;
                }
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

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct LinkExecutionPartialSourceSummary {
    source_byte_count: usize,
    source_file_count: usize,
    source_line_count: usize,
}

impl LinkExecutionPartialSourceSummary {
    fn from_page(page: &SourcePackHierarchicalLinkExecutionPage) -> Self {
        Self {
            source_byte_count: page.source_byte_count,
            source_file_count: page.source_file_count,
            source_line_count: page.source_line_count,
        }
    }

    fn checked_add(self, rhs: Self, group_index: usize, label: &str) -> Result<Self, CompileError> {
        Ok(Self {
            source_byte_count: self.source_byte_count.checked_add(rhs.source_byte_count).ok_or_else(
                || {
                    artifact_shard_contract_error(format!(
                        "source-pack hierarchical link execution group {group_index} {label} partial-link producer source-byte summary overflows"
                    ))
                },
            )?,
            source_file_count: self.source_file_count.checked_add(rhs.source_file_count).ok_or_else(
                || {
                    artifact_shard_contract_error(format!(
                        "source-pack hierarchical link execution group {group_index} {label} partial-link producer source-file summary overflows"
                    ))
                },
            )?,
            source_line_count: self.source_line_count.checked_add(rhs.source_line_count).ok_or_else(
                || {
                    artifact_shard_contract_error(format!(
                        "source-pack hierarchical link execution group {group_index} {label} partial-link producer source-line summary overflows"
                    ))
                },
            )?,
        })
    }
}

fn validate_hierarchical_link_reduce_inputs_before_begin<S>(
    page: &SourcePackHierarchicalLinkExecutionPage,
    store: &S,
) -> Result<(), CompileError>
where
    S: ExecutionShardLoader + AsRef<FilesystemArtifactStore>,
{
    if page.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Ok(());
    }

    let mut streamed_partial_count = 0usize;
    if page.input_group_page_count == 0 {
        streamed_partial_count =
            checked_add_pre_begin_partial_input_count(page, 0, page.input_group_output_keys.len())?;
    } else {
        let mut previous_partial_input_group_index = None;
        for page_index in 0..page.input_group_page_count {
            let partial_page = store.load_hierarchical_link_execution_partial_page(
                page.target,
                page.group_index,
                page_index,
            )?;
            validate_link_execution_partial_page(
                &partial_page,
                page.target,
                page.group_index,
                page_index,
            )?;
            validate_link_execution_sidecar_page(
                page.group_index,
                "partial-link",
                page_index,
                page.input_group_page_count,
                SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
                partial_page.input_count,
                partial_page.job_index,
                page.job_index,
            )?;
            validate_link_execution_sidecar_group_order(
                page.group_index,
                "partial-link",
                page_index,
                &partial_page.input_group_indices,
                &mut previous_partial_input_group_index,
            )?;
            streamed_partial_count = checked_add_pre_begin_partial_input_count(
                page,
                streamed_partial_count,
                partial_page.input_count,
            )?;
        }
    }

    let expected_partial_count = hierarchical_link_execution_input_group_count(page);
    if streamed_partial_count != expected_partial_count {
        return Err(artifact_shard_contract_error(format!(
            "hierarchical link execution group {} pre-begin validation streamed {} partial-link refs but expected {}; link executors must not begin before persisted partial-link evidence is complete",
            page.group_index, streamed_partial_count, expected_partial_count
        )));
    }

    let mut partial_source_summary = LinkExecutionPartialSourceSummary::default();
    if page.input_group_page_count == 0 {
        partial_source_summary = validate_link_execution_partial_producer_pages(
            store.as_ref(),
            page,
            &page.input_group_indices,
            &page.input_group_output_keys,
            "inline partial-link inputs",
        )?;
    } else {
        for page_index in 0..page.input_group_page_count {
            let partial_page = store.load_hierarchical_link_execution_partial_page(
                page.target,
                page.group_index,
                page_index,
            )?;
            validate_link_execution_partial_page(
                &partial_page,
                page.target,
                page.group_index,
                page_index,
            )?;
            let page_source_summary = validate_link_execution_partial_producer_pages(
                store.as_ref(),
                page,
                &partial_page.input_group_indices,
                &partial_page.input_group_output_keys,
                &format!("partial-link sidecar page {page_index}"),
            )?;
            partial_source_summary = partial_source_summary.checked_add(
                page_source_summary,
                page.group_index,
                &format!("partial-link sidecar page {page_index}"),
            )?;
        }
    }
    validate_link_execution_partial_source_summary(page, partial_source_summary)
}

fn checked_add_pre_begin_partial_input_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
    current: usize,
    additional: usize,
) -> Result<usize, CompileError> {
    current.checked_add(additional).ok_or_else(|| {
        artifact_shard_contract_error(format!(
            "hierarchical link execution group {} pre-begin partial-link input count overflows; link executors must not begin from unbounded partial-link evidence",
            page.group_index
        ))
    })
}

fn validate_link_execution_partial_source_summary(
    page: &SourcePackHierarchicalLinkExecutionPage,
    partial_source_summary: LinkExecutionPartialSourceSummary,
) -> Result<(), CompileError> {
    let page_source_summary = LinkExecutionPartialSourceSummary::from_page(page);
    if partial_source_summary == page_source_summary {
        return Ok(());
    }
    Err(artifact_shard_contract_error(format!(
        "source-pack hierarchical link execution group {} partial-link producer source summary bytes/files/lines {}/{}/{} does not match reduce page {}/{}/{}; live reduce-link execution must not write stale partial-link source evidence",
        page.group_index,
        partial_source_summary.source_byte_count,
        partial_source_summary.source_file_count,
        partial_source_summary.source_line_count,
        page.source_byte_count,
        page.source_file_count,
        page.source_line_count
    )))
}

fn validate_link_execution_sidecar_artifact_order(
    group_index: usize,
    label: &str,
    page_index: usize,
    artifacts: &[SourcePackArtifactRef],
    previous_producer_job_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(first_artifact) = artifacts.first() else {
        return Ok(());
    };
    if let Some(previous_producer_job_index) = *previous_producer_job_index
        && first_artifact.producing_job_index <= previous_producer_job_index
    {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {group_index} {label} sidecar page {page_index} starts at producer job {} after prior page ended at producer job {previous_producer_job_index}; paged sidecar artifact refs must be globally strictly ascending so link replay cannot hide duplicate or missing artifact evidence",
            first_artifact.producing_job_index
        )));
    }
    if let Some(last_artifact) = artifacts.last() {
        *previous_producer_job_index = Some(last_artifact.producing_job_index);
    }
    Ok(())
}

fn validate_link_execution_partial_producer_pages(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_group_indices: &[usize],
    input_group_output_keys: &[String],
    label: &str,
) -> Result<LinkExecutionPartialSourceSummary, CompileError> {
    let mut source_summary = LinkExecutionPartialSourceSummary::default();
    for (&input_group_index, input_group_output_key) in input_group_indices
        .iter()
        .zip(input_group_output_keys.iter())
    {
        let producer_page = validate_link_execution_partial_producer_page(
            store,
            page,
            input_group_index,
            input_group_output_key,
            label,
        )?;
        source_summary = source_summary.checked_add(
            LinkExecutionPartialSourceSummary::from_page(&producer_page),
            page.group_index,
            label,
        )?;
    }
    Ok(source_summary)
}

fn validate_link_execution_partial_producer_page(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
    let producer_page = store
        .load_hierarchical_link_execution_page_for_target(page.target, input_group_index)
        .map_err(|err| {
            artifact_shard_contract_error(format!(
                "source-pack hierarchical link execution group {} {label} requires partial-link producer execution page evidence for input group {input_group_index} before consuming partial-link artifact {input_group_output_key:?}: {err}",
                page.group_index
            ))
        })?;
    if producer_page.final_output {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {} {label} input group {input_group_index} is backed by a final execution page before consuming partial-link artifact {input_group_output_key:?}",
            page.group_index
        )));
    }
    let first_link_job_index = page.job_index.checked_sub(page.group_index).ok_or_else(|| {
        artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {} link job {} precedes dense group index before validating partial-link producer evidence",
            page.group_index, page.job_index
        ))
    })?;
    let expected_producer_job_index =
        first_link_job_index
            .checked_add(input_group_index)
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "source-pack hierarchical link execution group {} {label} input group {input_group_index} dense producer job overflows",
                    page.group_index
                ))
            })?;
    if producer_page.job_index != expected_producer_job_index {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {} {label} input group {input_group_index} records producer job {} but dense producer job is {expected_producer_job_index}",
            page.group_index, producer_page.job_index
        )));
    }
    if producer_page.output_key != input_group_output_key {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {} {label} input group {input_group_index} consumes partial-link key {input_group_output_key:?} but producer execution page records {:?}",
            page.group_index, producer_page.output_key
        )));
    }
    store
        .require_artifact_key_file(input_group_output_key, "partial link output")
        .map_err(|err| {
            artifact_shard_contract_error(format!(
                "source-pack hierarchical link execution group {} {label} input group {input_group_index} requires concrete partial-link output artifact {input_group_output_key:?} before beginning reduce link execution; producer execution-page metadata is not link artifact evidence: {err}",
                page.group_index
            ))
        })?;
    Ok(producer_page)
}

fn validate_link_execution_sidecar_group_order(
    group_index: usize,
    label: &str,
    page_index: usize,
    input_group_indices: &[usize],
    previous_input_group_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(&first_input_group_index) = input_group_indices.first() else {
        return Ok(());
    };
    if let Some(previous_input_group_index) = *previous_input_group_index
        && first_input_group_index <= previous_input_group_index
    {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {group_index} {label} sidecar page {page_index} starts at input group {first_input_group_index} after prior page ended at input group {previous_input_group_index}; paged partial-link sidecars must be globally strictly ascending by input group so link replay cannot hide duplicate or missing partial-link evidence"
        )));
    }
    if let Some(&last_input_group_index) = input_group_indices.last() {
        *previous_input_group_index = Some(last_input_group_index);
    }
    Ok(())
}

fn validate_link_execution_sidecar_page(
    group_index: usize,
    label: &str,
    page_index: usize,
    page_count: usize,
    page_capacity: usize,
    input_count: usize,
    sidecar_job_index: usize,
    execution_job_index: usize,
) -> Result<(), CompileError> {
    if sidecar_job_index != execution_job_index {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {group_index} {label} sidecar page {page_index} records job {sidecar_job_index} but execution page records job {execution_job_index}; live link execution sidecars must belong to the same dense link job"
        )));
    }
    if page_index < page_count.saturating_sub(1) && input_count != page_capacity {
        return Err(artifact_shard_contract_error(format!(
            "source-pack hierarchical link execution group {group_index} {label} sidecar page {page_index} records {input_count} inputs before later sidecar pages; non-final sidecar pages must contain {page_capacity} inputs so live link execution cannot hide missing link input evidence"
        )));
    }
    Ok(())
}
