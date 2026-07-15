use super::*;
use crate::codegen::unit::artifact_key_for_output;

mod artifact_refs;
mod execution_page;
mod groups;
mod progress;

pub(in crate::compiler) use artifact_refs::*;
pub(in crate::compiler) use execution_page::*;
pub(in crate::compiler) use groups::*;
pub(in crate::compiler) use progress::*;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
/// Persisted cursor for resumable hierarchical link execution-page preparation.
pub(in crate::compiler) struct HierarchicalLinkExecutionPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) link_group_count: usize,
    pub(in crate::compiler) next_group_index: usize,
    pub(in crate::compiler) final_output_seen: bool,
}

/// Validates resumable hierarchical link execution preparation progress.
pub(in crate::compiler) fn validate_link_execution_prepare_progress(
    progress: &HierarchicalLinkExecutionPrepareProgress,
    target: SourcePackArtifactTarget,
    link_group_count: usize,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.link_group_count != link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution prepare progress link group count {} does not match plan link group count {link_group_count}",
            progress.link_group_count
        )));
    }
    if progress.next_group_index > link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution prepare progress next group {} exceeds link group count {link_group_count}",
            progress.next_group_index
        )));
    }
    if progress.final_output_seen && progress.next_group_index < link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution prepare progress records final output before all link groups are prepared; next group {} of {}",
            progress.next_group_index, link_group_count
        )));
    }
    if progress.next_group_index == link_group_count && !progress.final_output_seen {
        return Err(library_partition_contract_error(
            "hierarchical link execution prepare progress completed all link groups without recording a final output page",
        ));
    }
    Ok(())
}

/// Stores a bounded chunk of hierarchical link execution pages from a link plan.
pub(in crate::compiler) fn store_hierarchical_link_execution_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    max_new_groups: usize,
) -> Result<FilesystemHierarchicalLinkExecutionPrepareStepResult, CompileError> {
    if max_new_groups == 0 {
        return Err(source_pack_preparation_limit_invalid_error(
            "source-pack hierarchical link execution chunk max_new_groups must be greater than zero",
        ));
    }
    validate_link_plan_index(link_plan_index, link_plan_index.target)?;
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
    if schedule_index.target != link_plan_index.target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution chunk target {:?} does not match schedule target {:?}",
            link_plan_index.target, schedule_index.target
        )));
    }
    if schedule_index.link_job_index != link_plan_index.first_link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution chunk first link job {} does not match schedule link job {}",
            link_plan_index.first_link_job_index, schedule_index.link_job_index
        )));
    }
    if artifact_ref_index.final_output_artifact_index != schedule_index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution chunk final artifact {} does not match schedule link job {}",
            artifact_ref_index.final_output_artifact_index, schedule_index.link_job_index
        )));
    }
    if store
        .hierarchical_link_execution_index_path_for_target(link_plan_index.target)
        .is_file()
    {
        let index =
            store.load_hierarchical_link_execution_index_for_target(link_plan_index.target)?;
        validate_link_execution_index_for_plan(&index, link_plan_index)?;
        validate_link_execution_index_for_artifact_ref_index(&index, artifact_ref_index)?;
        validate_completed_link_execution_index_evidence(store, &index)?;
        validate_completed_link_execution_final_page_summary_for_artifact_ref_index(
            store,
            &index,
            artifact_ref_index,
        )?;
        validate_completed_link_execution_final_page_matches_plan_group(
            store,
            &index,
            link_plan_index,
            artifact_ref_index,
        )?;
        return Ok(FilesystemHierarchicalLinkExecutionPrepareStepResult {
            target: link_plan_index.target,
            complete: true,
            link_group_count: index.link_group_count,
            next_group_index: index.link_group_count,
            new_execution_page_count: 0,
            final_output_seen: true,
            final_output_key: index.final_output_key,
            hierarchical_link_execution_index_path: Some(
                store.hierarchical_link_execution_index_path_for_target(link_plan_index.target),
            ),
        });
    }

    let progress_path =
        store.link_execution_prepare_progress_path_for_target(link_plan_index.target);
    let mut progress = if progress_path.is_file() {
        load_link_execution_prepare_progress(
            store,
            link_plan_index.target,
            link_plan_index.link_group_count,
        )?
    } else {
        HierarchicalLinkExecutionPrepareProgress {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            target: link_plan_index.target,
            link_group_count: link_plan_index.link_group_count,
            next_group_index: 0,
            final_output_seen: false,
        }
    };
    validate_link_execution_prepare_progress(
        &progress,
        link_plan_index.target,
        link_plan_index.link_group_count,
    )?;
    validate_link_execution_prepare_replay_tail(
        store,
        link_plan_index,
        artifact_ref_index,
        progress.next_group_index,
    )?;

    let mut new_execution_page_count = 0usize;
    while progress.next_group_index < link_plan_index.link_group_count
        && new_execution_page_count < max_new_groups
    {
        let group = store.load_hierarchical_link_group_page_for_target(
            link_plan_index.target,
            progress.next_group_index,
        )?;
        validate_link_group_page_for_plan(
            &group,
            link_plan_index,
            Some(progress.next_group_index),
        )?;
        let page = execution_page_from_artifact_refs(
            store,
            link_plan_index,
            schedule_index,
            &group,
            artifact_ref_index,
        )?;
        progress.final_output_seen |= page.final_output;
        store.store_prepared_hierarchical_link_execution_page(&page)?;
        progress.next_group_index = progress.next_group_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link execution chunk group index overflows",
            )
        })?;
        new_execution_page_count = new_execution_page_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link execution chunk new page count overflows",
            )
        })?;
        store_link_execution_prepare_progress(store, &progress)?;
    }

    let mut hierarchical_link_execution_index_path = None;
    if progress.next_group_index == link_plan_index.link_group_count {
        if !progress.final_output_seen {
            return Err(library_partition_contract_error(
                "hierarchical link execution chunk did not store a final output page",
            ));
        }
        let index = SourcePackHierarchicalLinkExecutionIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
            target: link_plan_index.target,
            first_link_job_index: link_plan_index.first_link_job_index,
            final_link_group_index: link_plan_index.final_link_group_index,
            final_link_job_index: link_plan_index.final_link_job_index,
            link_group_count: link_plan_index.link_group_count,
            final_output_key: artifact_ref_index.final_output_key.clone(),
        };
        validate_link_execution_index_for_plan(&index, link_plan_index)?;
        validate_link_execution_index_for_artifact_ref_index(&index, artifact_ref_index)?;
        validate_completed_link_execution_final_page_summary_for_artifact_ref_index(
            store,
            &index,
            artifact_ref_index,
        )?;
        validate_completed_link_execution_final_page_matches_plan_group(
            store,
            &index,
            link_plan_index,
            artifact_ref_index,
        )?;
        hierarchical_link_execution_index_path =
            Some(store_hierarchical_link_execution_index(store, &index)?);
    }

    Ok(FilesystemHierarchicalLinkExecutionPrepareStepResult {
        target: link_plan_index.target,
        complete: hierarchical_link_execution_index_path.is_some(),
        link_group_count: link_plan_index.link_group_count,
        next_group_index: progress.next_group_index,
        new_execution_page_count,
        final_output_seen: progress.final_output_seen,
        final_output_key: artifact_ref_index.final_output_key.clone(),
        hierarchical_link_execution_index_path,
    })
}

/// Persists hierarchical link execution preparation progress.
pub(in crate::compiler) fn store_link_execution_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &HierarchicalLinkExecutionPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_link_execution_prepare_progress(progress, progress.target, progress.link_group_count)?;
    let path = store.link_execution_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "serialize source-pack hierarchical link execution prepare progress: {err}"
        ))
    })?;
    write_file_atomic(
        &path,
        &bytes,
        "source-pack hierarchical link execution prepare progress",
    )?;
    Ok(path)
}

/// Loads and validates hierarchical link execution preparation progress.
pub(in crate::compiler) fn load_link_execution_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    link_group_count: usize,
) -> Result<HierarchicalLinkExecutionPrepareProgress, CompileError> {
    let path = store.link_execution_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "read source-pack hierarchical link execution prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<HierarchicalLinkExecutionPrepareProgress>(&bytes)
        .map_err(|err| {
            source_pack_store_metadata_error(format!(
                "parse source-pack hierarchical link execution prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_link_execution_prepare_progress(&progress, target, link_group_count)?;
    Ok(progress)
}

/// Builds one executable hierarchical link page from stored artifact references.
pub(in crate::compiler) fn execution_page_from_artifact_refs(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
    validate_link_group_page_for_plan(group, link_plan_index, Some(group.group_index))?;
    validate_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
    let final_output = group.group_index == link_plan_index.final_link_group_index;
    let output_key = if final_output {
        artifact_ref_index.final_output_key.clone()
    } else {
        hierarchical_link_partial_output_key(
            link_plan_index.target,
            group.group_index,
            group.job_index,
        )
    };

    let (
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interfaces,
        input_object_count,
        input_object_page_count,
        input_objects,
        input_group_count,
        input_group_page_count,
        input_group_indices,
        input_group_output_keys,
    ) = match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            let (input_interface_count, input_interface_page_count, input_interface_ranges) =
                store_leaf_interface_pages(
                    store,
                    link_plan_index,
                    schedule_index,
                    group,
                    artifact_ref_index,
                )?;
            let (input_object_count, input_object_page_count) =
                store_leaf_object_pages(store, link_plan_index, group, artifact_ref_index)?;
            (
                input_interface_count,
                input_interface_page_count,
                input_interface_ranges,
                Vec::new(),
                input_object_count,
                input_object_page_count,
                Vec::new(),
                0,
                0,
                Vec::new(),
                Vec::new(),
            )
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            let (input_group_count, input_group_page_count) =
                store_reduce_partial_pages(store, link_plan_index, group, artifact_ref_index)?;
            (
                0,
                0,
                Vec::new(),
                Vec::new(),
                0,
                0,
                Vec::new(),
                input_group_count,
                input_group_page_count,
                Vec::new(),
                Vec::new(),
            )
        }
    };

    let page = SourcePackHierarchicalLinkExecutionPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
        target: link_plan_index.target,
        group_index: group.group_index,
        kind: group.kind,
        job_index: group.job_index,
        input_interface_count,
        input_interface_page_count,
        input_interface_ranges,
        input_interfaces,
        input_object_count,
        input_object_page_count,
        input_objects,
        input_group_count,
        input_group_page_count,
        input_group_indices,
        input_group_output_keys,
        source_byte_count: group.source_byte_count,
        source_file_count: group.source_file_count,
        source_line_count: group.source_line_count,
        output_key,
        final_output,
        descriptor_summary: SourcePackLinkDescriptorSummary::default(),
    };
    validate_link_execution_page(&page, link_plan_index.target, Some(group.group_index))?;
    Ok(page)
}

/// Writer that spills leaf-group interface inputs into execution sidecar pages.
pub(in crate::compiler) struct ExecutionInterfacePageWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) group_index: usize,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_interfaces: Vec<SourcePackArtifactRef>,
}

impl<'a> ExecutionInterfacePageWriter<'a> {
    /// Creates an empty interface-input page writer.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    ) -> Self {
        Self {
            store,
            target,
            group_index,
            job_index,
            artifact_ref_index,
            page_index: 0,
            first_input_position: 0,
            input_count: 0,
            current_input_interfaces: Vec::with_capacity(
                SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Adds the interface artifact produced by a dependency job.
    pub(in crate::compiler) fn push_job(&mut self, job_index: usize) -> Result<(), CompileError> {
        let artifact_ref = artifact_ref_for_index_from_stored_pages(
            self.store,
            self.target,
            self.artifact_ref_index,
            job_index,
            SourcePackArtifactKind::LibraryInterface,
        )?;
        self.current_input_interfaces.push(artifact_ref);
        if self.current_input_interfaces.len()
            == SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    /// Flushes the current interface-input page if it contains any inputs.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_input_interfaces.is_empty() {
            return Ok(());
        }
        let input_interfaces = std::mem::take(&mut self.current_input_interfaces);
        let page = SourcePackHierarchicalLinkExecutionInterfacePage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
            target: self.target,
            group_index: self.group_index,
            job_index: self.job_index,
            page_index: self.page_index,
            first_input_position: self.first_input_position,
            input_count: input_interfaces.len(),
            input_interfaces,
        };
        validate_link_execution_interface_page(
            &page,
            self.target,
            self.group_index,
            self.page_index,
        )?;
        self.store
            .store_hierarchical_link_execution_interface_page(&page)?;
        self.input_count = self.input_count.saturating_add(page.input_count);
        self.first_input_position = self.first_input_position.saturating_add(page.input_count);
        self.page_index += 1;
        Ok(())
    }

    /// Flushes remaining inputs and returns total input/page counts.
    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

/// Stores paged library-interface inputs for a leaf link group.
pub(in crate::compiler) fn store_leaf_interface_pages(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
    validate_link_group_page_for_plan(group, link_plan_index, Some(group.group_index))?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Leaf {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a leaf group",
            group.group_index
        )));
    }
    let [partition_index] = group.input_partition_indices.as_slice() else {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} has partitions {:?}, expected one",
            group.group_index, group.input_partition_indices
        )));
    };
    let _schedule_page =
        store.load_library_schedule_page_for_target(schedule_index.target, *partition_index)?;
    let mut writer = ExecutionInterfacePageWriter::new(
        store,
        link_plan_index.target,
        group.group_index,
        group.job_index,
        artifact_ref_index,
    );
    let Some(&first_codegen_job_index) = group.input_codegen_job_indices.first() else {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} has no codegen jobs",
            group.group_index
        )));
    };
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        first_codegen_job_index,
        schedule_index.job_count,
    )?;
    for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| writer.push_job(dependency_job_index),
    )?;
    let (explicit_input_interface_count, input_interface_page_count) = writer.finish()?;
    let ranged_input_interface_count =
        job_index_range_dependency_count(&job_page.dependency_job_ranges);
    let input_interface_count =
        explicit_input_interface_count.saturating_add(ranged_input_interface_count);
    let expected_input_interface_count = hierarchical_link_group_input_frontend_job_count(group);
    if input_interface_count != expected_input_interface_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} wrote {} interface inputs but expected {}",
            group.group_index, input_interface_count, expected_input_interface_count
        )));
    }
    Ok((
        input_interface_count,
        input_interface_page_count,
        job_page.dependency_job_ranges,
    ))
}

/// Writer that spills leaf-group object inputs into execution sidecar pages.
pub(in crate::compiler) struct ExecutionObjectPageWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) group_index: usize,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_objects: Vec<SourcePackArtifactRef>,
}

impl<'a> ExecutionObjectPageWriter<'a> {
    /// Creates an empty object-input page writer.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    ) -> Self {
        Self {
            store,
            target,
            group_index,
            job_index,
            artifact_ref_index,
            page_index: 0,
            first_input_position: 0,
            input_count: 0,
            current_input_objects: Vec::with_capacity(
                SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Adds the object artifact produced by a codegen job.
    pub(in crate::compiler) fn push_job(&mut self, job_index: usize) -> Result<(), CompileError> {
        let artifact_ref = artifact_ref_for_index_from_stored_pages(
            self.store,
            self.target,
            self.artifact_ref_index,
            job_index,
            SourcePackArtifactKind::CodegenObject,
        )?;
        self.current_input_objects.push(artifact_ref);
        if self.current_input_objects.len()
            == SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    /// Flushes the current object-input page if it contains any inputs.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_input_objects.is_empty() {
            return Ok(());
        }
        let input_objects = std::mem::take(&mut self.current_input_objects);
        let page = SourcePackHierarchicalLinkExecutionObjectPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
            target: self.target,
            group_index: self.group_index,
            job_index: self.job_index,
            page_index: self.page_index,
            first_input_position: self.first_input_position,
            input_count: input_objects.len(),
            input_objects,
        };
        validate_link_execution_object_page(&page, self.target, self.group_index, self.page_index)?;
        self.store
            .store_hierarchical_link_execution_object_page(&page)?;
        self.input_count = self.input_count.saturating_add(page.input_count);
        self.first_input_position = self.first_input_position.saturating_add(page.input_count);
        self.page_index += 1;
        Ok(())
    }

    /// Flushes remaining inputs and returns total input/page counts.
    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

/// Stores paged codegen-object inputs for a leaf link group.
pub(in crate::compiler) fn store_leaf_object_pages(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize), CompileError> {
    validate_link_group_page_for_plan(group, link_plan_index, Some(group.group_index))?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Leaf {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a leaf group",
            group.group_index
        )));
    }
    let mut writer = ExecutionObjectPageWriter::new(
        store,
        link_plan_index.target,
        group.group_index,
        group.job_index,
        artifact_ref_index,
    );
    for &codegen_job_index in &group.input_codegen_job_indices {
        writer.push_job(codegen_job_index)?;
    }
    let (input_object_count, input_object_page_count) = writer.finish()?;
    if input_object_count != group.input_codegen_job_indices.len() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} wrote {} object inputs but expected {}",
            group.group_index,
            input_object_count,
            group.input_codegen_job_indices.len()
        )));
    }
    Ok((input_object_count, input_object_page_count))
}

/// Writer that spills reduce-group partial-link inputs into execution sidecars.
pub(in crate::compiler) struct ExecutionPartialPageWriter<'a> {
    pub(in crate::compiler) store: &'a FilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) group_index: usize,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) link_plan_index: &'a SourcePackHierarchicalLinkPlanIndex,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_group_indices: Vec<usize>,
    pub(in crate::compiler) current_input_group_output_keys: Vec<String>,
}

impl<'a> ExecutionPartialPageWriter<'a> {
    /// Creates an empty partial-link input page writer.
    pub(in crate::compiler) fn new(
        store: &'a FilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        link_plan_index: &'a SourcePackHierarchicalLinkPlanIndex,
        artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    ) -> Self {
        Self {
            store,
            target,
            group_index,
            job_index,
            link_plan_index,
            artifact_ref_index,
            page_index: 0,
            first_input_position: 0,
            input_count: 0,
            current_input_group_indices: Vec::with_capacity(
                SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
            ),
            current_input_group_output_keys: Vec::with_capacity(
                SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    /// Adds the output of a prior hierarchical link group as a reduce input.
    pub(in crate::compiler) fn push_group(
        &mut self,
        input_group_index: usize,
    ) -> Result<(), CompileError> {
        let output_key = hierarchical_link_execution_output_key_for_group(
            self.store,
            self.link_plan_index,
            self.artifact_ref_index,
            input_group_index,
        )?;
        self.current_input_group_indices.push(input_group_index);
        self.current_input_group_output_keys.push(output_key);
        if self.current_input_group_indices.len()
            == SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    /// Flushes the current partial-link input page if it contains inputs.
    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_input_group_indices.is_empty() {
            return Ok(());
        }
        let input_group_indices = std::mem::take(&mut self.current_input_group_indices);
        let input_group_output_keys = std::mem::take(&mut self.current_input_group_output_keys);
        let page = SourcePackHierarchicalLinkExecutionPartialPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
            target: self.target,
            group_index: self.group_index,
            job_index: self.job_index,
            page_index: self.page_index,
            first_input_position: self.first_input_position,
            input_count: input_group_indices.len(),
            input_group_indices,
            input_group_output_keys,
        };
        validate_link_execution_partial_page(
            &page,
            self.target,
            self.group_index,
            self.page_index,
        )?;
        self.store
            .store_hierarchical_link_execution_partial_page(&page)?;
        self.input_count = self.input_count.saturating_add(page.input_count);
        self.first_input_position = self.first_input_position.saturating_add(page.input_count);
        self.page_index += 1;
        Ok(())
    }

    /// Flushes remaining inputs and returns total input/page counts.
    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

/// Stores paged partial-link inputs for a reduce link group.
pub(in crate::compiler) fn store_reduce_partial_pages(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize), CompileError> {
    validate_link_group_page_for_plan(group, link_plan_index, Some(group.group_index))?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a reduce group",
            group.group_index
        )));
    }
    validate_reduce_group_summary_from_inputs(store, link_plan_index, group)?;
    let mut writer = ExecutionPartialPageWriter::new(
        store,
        link_plan_index.target,
        group.group_index,
        group.job_index,
        link_plan_index,
        artifact_ref_index,
    );
    for &input_group_index in &group.input_link_group_indices {
        writer.push_group(input_group_index)?;
    }
    let (input_group_count, input_group_page_count) = writer.finish()?;
    if input_group_count != group.input_link_group_indices.len() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution reduce group {} wrote {} partial inputs but expected {}",
            group.group_index,
            input_group_count,
            group.input_link_group_indices.len()
        )));
    }
    Ok((input_group_count, input_group_page_count))
}

/// Validates that a reduce-group summary matches its input groups.
pub(in crate::compiler) fn validate_reduce_group_summary_from_inputs(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
) -> Result<(), CompileError> {
    validate_link_group_page_for_plan(group, link_plan_index, Some(group.group_index))?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} is not a reduce group",
            group.group_index
        )));
    }

    let mut input_partition_span = None::<(usize, usize)>;
    let mut source_byte_count = 0usize;
    let mut source_file_count = 0usize;
    let mut source_line_count = 0usize;
    let mut oversized_input = false;
    for &input_group_index in &group.input_link_group_indices {
        let input_group = store.load_hierarchical_link_group_page_for_target(
            link_plan_index.target,
            input_group_index,
        )?;
        validate_link_group_page_for_plan(&input_group, link_plan_index, Some(input_group_index))?;
        let expected_level = input_group.level.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(format!(
                "hierarchical link input group {} level overflows reduce group {}",
                input_group_index, group.group_index
            ))
        })?;
        if expected_level != group.level {
            return Err(library_partition_contract_error(format!(
                "hierarchical link reduce group {} level {} does not follow input group {} level {}",
                group.group_index, group.level, input_group_index, input_group.level
            )));
        }
        let child_span =
            hierarchical_link_group_partition_span(store, link_plan_index.target, &input_group)?;
        extend_hierarchical_link_partition_span(
            &mut input_partition_span,
            child_span,
            &format!("hierarchical link reduce group {}", group.group_index),
        )?;
        source_byte_count = source_byte_count
            .checked_add(input_group.source_byte_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link reduce group {} source-byte summary overflows",
                    group.group_index
                ))
            })?;
        source_file_count = source_file_count
            .checked_add(input_group.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link reduce group {} source-file summary overflows",
                    group.group_index
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(input_group.source_line_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link reduce group {} source-line summary overflows",
                    group.group_index
                ))
            })?;
        oversized_input |= input_group.oversized_input;
    }

    let (first_input_partition, last_input_partition) = input_partition_span.ok_or_else(|| {
        library_partition_contract_error(format!(
            "hierarchical link reduce group {} has no input partition span",
            group.group_index
        ))
    })?;
    let input_partition_count = last_input_partition
        .checked_sub(first_input_partition)
        .and_then(|distance| distance.checked_add(1))
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "hierarchical link reduce group {} input partition summary overflows",
                group.group_index
            ))
        })?;

    if group.input_partition_count != input_partition_count
        || group.source_byte_count != source_byte_count
        || group.source_file_count != source_file_count
        || group.source_line_count != source_line_count
        || group.oversized_input != oversized_input
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link reduce group {} summary does not match input groups: got partitions={} bytes={} files={} lines={} oversized={}, expected partitions={} bytes={} files={} lines={} oversized={}",
            group.group_index,
            group.input_partition_count,
            group.source_byte_count,
            group.source_file_count,
            group.source_line_count,
            group.oversized_input,
            input_partition_count,
            source_byte_count,
            source_file_count,
            source_line_count,
            oversized_input
        )));
    }
    Ok(())
}

/// Returns the artifact output key for a hierarchical link group.
pub(in crate::compiler) fn hierarchical_link_execution_output_key_for_group(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    group_index: usize,
) -> Result<String, CompileError> {
    if group_index == link_plan_index.final_link_group_index {
        validate_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
        return Ok(artifact_ref_index.final_output_key.clone());
    }
    let group =
        store.load_hierarchical_link_group_page_for_target(link_plan_index.target, group_index)?;
    validate_link_group_page_for_plan(&group, link_plan_index, Some(group_index))?;
    Ok(hierarchical_link_partial_output_key(
        link_plan_index.target,
        group.group_index,
        group.job_index,
    ))
}

fn validate_link_execution_prepare_replay_tail(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    next_group_index: usize,
) -> Result<(), CompileError> {
    if next_group_index == 0 {
        return Ok(());
    }
    let replay_group_index = next_group_index.checked_sub(1).ok_or_else(|| {
        library_partition_contract_error(
            "hierarchical link execution replay tail group index underflows",
        )
    })?;
    let group = store
        .load_hierarchical_link_group_page_for_target(link_plan_index.target, replay_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} requires current link group evidence for prepared group {replay_group_index}: {err}"
            ))
        })?;
    validate_link_group_page_for_plan(&group, link_plan_index, Some(replay_group_index))?;
    let page = store
        .load_hierarchical_link_execution_page_for_target(
            link_plan_index.target,
            replay_group_index,
        )
        .map_err(|err| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} requires execution page evidence for prepared group {replay_group_index}: {err}"
            ))
        })?;
    validate_link_execution_page_matches_group(&page, &group, link_plan_index, artifact_ref_index)?;
    validate_link_execution_replay_tail_input_sidecars(store, &page, next_group_index)?;
    validate_link_execution_page_inputs_match_current_group(
        store,
        &page,
        &group,
        &format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared group"
        ),
    )?;
    validate_link_execution_replay_tail_partial_input_producer_evidence(
        store,
        &page,
        link_plan_index,
        artifact_ref_index,
        next_group_index,
    )?;
    Ok(())
}

fn validate_link_execution_replay_tail_partial_input_producer_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    next_group_index: usize,
) -> Result<(), CompileError> {
    if page.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Ok(());
    }

    for (&input_group_index, input_group_output_key) in page
        .input_group_indices
        .iter()
        .zip(page.input_group_output_keys.iter())
    {
        validate_link_execution_replay_tail_partial_input_producer_page(
            store,
            page,
            link_plan_index,
            artifact_ref_index,
            next_group_index,
            input_group_index,
            input_group_output_key,
            "inline partial-link input",
        )?;
    }

    for page_index in 0..page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "resumable source-pack link execution progress at group {next_group_index} prepared reduce group {} requires partial-link input sidecar evidence page {page_index} before validating producer execution pages: {err}",
                    page.group_index
                ))
            })?;
        let label = format!("partial-link input sidecar page {page_index}");
        for (&input_group_index, input_group_output_key) in sidecar
            .input_group_indices
            .iter()
            .zip(sidecar.input_group_output_keys.iter())
        {
            validate_link_execution_replay_tail_partial_input_producer_page(
                store,
                page,
                link_plan_index,
                artifact_ref_index,
                next_group_index,
                input_group_index,
                input_group_output_key,
                &label,
            )?;
        }
    }

    Ok(())
}

fn validate_link_execution_replay_tail_partial_input_producer_page(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    next_group_index: usize,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<(), CompileError> {
    let input_group = store
        .load_hierarchical_link_group_page_for_target(page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared reduce group {} {label} requires current link group evidence for input group {}: {err}",
                page.group_index, input_group_index
            ))
        })?;
    validate_link_group_page_for_plan(&input_group, link_plan_index, Some(input_group_index))?;
    let input_page = store
        .load_hierarchical_link_execution_page_for_target(page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared reduce group {} {label} requires partial-link producer execution page evidence for input group {}: {err}",
                page.group_index, input_group_index
            ))
        })?;
    if input_page.output_key != input_group_output_key {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared reduce group {} {label} input group {} consumes partial-link key {:?} but producer execution page records {:?}",
            page.group_index, input_group_index, input_group_output_key, input_page.output_key
        )));
    }
    validate_link_execution_page_matches_group(
        &input_page,
        &input_group,
        link_plan_index,
        artifact_ref_index,
    )?;
    validate_link_execution_replay_tail_input_sidecars(store, &input_page, next_group_index)?;
    validate_link_execution_page_inputs_match_current_group(
        store,
        &input_page,
        &input_group,
        &format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared reduce group {} {label} producer group",
            page.group_index
        ),
    )?;
    validate_link_execution_replay_tail_partial_input_producer_evidence(
        store,
        &input_page,
        link_plan_index,
        artifact_ref_index,
        next_group_index,
    )
}

fn validate_link_execution_replay_tail_input_sidecars(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    next_group_index: usize,
) -> Result<(), CompileError> {
    let ranged_interface_count = job_index_range_dependency_count(&page.input_interface_ranges);
    let total_interface_count = hierarchical_link_execution_input_interface_count(page);
    let expected_paged_interface_count = total_interface_count
        .checked_sub(ranged_interface_count)
        .and_then(|count| count.checked_sub(page.input_interfaces.len()))
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {} interface input summary underflows sidecar evidence",
                page.group_index
            ))
        })?;
    let actual_paged_interface_count =
        link_execution_replay_tail_interface_sidecar_input_count(store, page, next_group_index)?;
    validate_link_execution_replay_tail_sidecar_input_count(
        next_group_index,
        page.group_index,
        "interface",
        actual_paged_interface_count,
        expected_paged_interface_count,
    )?;

    let total_object_count = hierarchical_link_execution_input_object_count(page);
    let expected_paged_object_count = total_object_count
        .checked_sub(page.input_objects.len())
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {} object input summary underflows sidecar evidence",
                page.group_index
            ))
        })?;
    let actual_paged_object_count =
        link_execution_replay_tail_object_sidecar_input_count(store, page, next_group_index)?;
    validate_link_execution_replay_tail_sidecar_input_count(
        next_group_index,
        page.group_index,
        "object",
        actual_paged_object_count,
        expected_paged_object_count,
    )?;

    let total_group_count = hierarchical_link_execution_input_group_count(page);
    let expected_paged_group_count =
        total_group_count
            .checked_sub(page.input_group_indices.len())
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "resumable source-pack link execution progress at group {next_group_index} prepared group {} partial-link input summary underflows sidecar evidence",
                    page.group_index
                ))
            })?;
    let actual_paged_group_count =
        link_execution_replay_tail_partial_sidecar_input_count(store, page, next_group_index)?;
    validate_link_execution_replay_tail_sidecar_input_count(
        next_group_index,
        page.group_index,
        "partial-link",
        actual_paged_group_count,
        expected_paged_group_count,
    )?;

    Ok(())
}

fn link_execution_replay_tail_interface_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    next_group_index: usize,
) -> Result<usize, CompileError> {
    let mut input_count = 0usize;
    let mut previous_producer_job_index = None;
    for page_index in 0..page.input_interface_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_interface_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "resumable source-pack link execution progress at group {next_group_index} requires interface input sidecar evidence for prepared group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_link_execution_replay_tail_sidecar_job_index(
            next_group_index,
            page.group_index,
            "interface",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_link_execution_replay_tail_sidecar_page_fill(
            next_group_index,
            page.group_index,
            "interface",
            page_index,
            page.input_interface_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
        )?;
        validate_link_execution_replay_tail_artifact_sidecar_order(
            next_group_index,
            page.group_index,
            "interface",
            page_index,
            &sidecar.input_interfaces,
            &mut previous_producer_job_index,
        )?;
        input_count = input_count.checked_add(sidecar.input_count).ok_or_else(|| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {} interface sidecar input count overflows",
                page.group_index
            ))
        })?;
    }
    Ok(input_count)
}

fn link_execution_replay_tail_object_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    next_group_index: usize,
) -> Result<usize, CompileError> {
    let mut input_count = 0usize;
    let mut previous_producer_job_index = None;
    for page_index in 0..page.input_object_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_object_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "resumable source-pack link execution progress at group {next_group_index} requires object input sidecar evidence for prepared group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_link_execution_replay_tail_sidecar_job_index(
            next_group_index,
            page.group_index,
            "object",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_link_execution_replay_tail_sidecar_page_fill(
            next_group_index,
            page.group_index,
            "object",
            page_index,
            page.input_object_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
        )?;
        validate_link_execution_replay_tail_artifact_sidecar_order(
            next_group_index,
            page.group_index,
            "object",
            page_index,
            &sidecar.input_objects,
            &mut previous_producer_job_index,
        )?;
        input_count = input_count.checked_add(sidecar.input_count).ok_or_else(|| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {} object sidecar input count overflows",
                page.group_index
            ))
        })?;
    }
    Ok(input_count)
}

fn link_execution_replay_tail_partial_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    next_group_index: usize,
) -> Result<usize, CompileError> {
    let mut input_count = 0usize;
    let mut previous_input_group_index = None;
    for page_index in 0..page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "resumable source-pack link execution progress at group {next_group_index} requires partial-link input sidecar evidence for prepared group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_link_execution_replay_tail_sidecar_job_index(
            next_group_index,
            page.group_index,
            "partial-link",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_link_execution_replay_tail_sidecar_page_fill(
            next_group_index,
            page.group_index,
            "partial-link",
            page_index,
            page.input_group_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
        )?;
        validate_link_execution_replay_tail_partial_sidecar_order(
            next_group_index,
            page.group_index,
            "partial-link",
            page_index,
            &sidecar.input_group_indices,
            &mut previous_input_group_index,
        )?;
        input_count = input_count.checked_add(sidecar.input_count).ok_or_else(|| {
            library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {} partial-link sidecar input count overflows",
                page.group_index
            ))
        })?;
    }
    Ok(input_count)
}

fn validate_link_execution_replay_tail_sidecar_job_index(
    next_group_index: usize,
    group_index: usize,
    label: &str,
    page_index: usize,
    sidecar_job_index: usize,
    execution_page_job_index: usize,
) -> Result<(), CompileError> {
    if sidecar_job_index != execution_page_job_index {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared group {group_index} {label} sidecar page {page_index} records job {sidecar_job_index} but execution page records job {execution_page_job_index}"
        )));
    }
    Ok(())
}

fn validate_link_execution_replay_tail_sidecar_page_fill(
    next_group_index: usize,
    group_index: usize,
    label: &str,
    page_index: usize,
    page_count: usize,
    input_count: usize,
    page_capacity: usize,
) -> Result<(), CompileError> {
    if page_index < page_count.saturating_sub(1) && input_count != page_capacity {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared group {group_index} {label} sidecar page {page_index} records {input_count} inputs before later sidecar pages; non-final sidecar pages must contain {page_capacity} inputs so resumed progress cannot hide missing link input evidence"
        )));
    }
    Ok(())
}

fn validate_link_execution_replay_tail_artifact_sidecar_order(
    next_group_index: usize,
    group_index: usize,
    label: &str,
    page_index: usize,
    artifacts: &[SourcePackArtifactRef],
    previous_producer_job_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(first_artifact) = artifacts.first() else {
        return Ok(());
    };
    if let Some(previous_producer_job_index) = *previous_producer_job_index {
        if first_artifact.producing_job_index <= previous_producer_job_index {
            return Err(library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {group_index} {label} sidecar page {page_index} starts at producer job {} after prior page ended at producer job {previous_producer_job_index}; resumed sidecar artifact refs must be globally strictly ascending so replay cannot hide duplicate or missing link input evidence",
                first_artifact.producing_job_index
            )));
        }
    }
    if let Some(last_artifact) = artifacts.last() {
        *previous_producer_job_index = Some(last_artifact.producing_job_index);
    }
    Ok(())
}

fn validate_link_execution_replay_tail_partial_sidecar_order(
    next_group_index: usize,
    group_index: usize,
    label: &str,
    page_index: usize,
    input_group_indices: &[usize],
    previous_input_group_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(&first_input_group_index) = input_group_indices.first() else {
        return Ok(());
    };
    if let Some(previous_input_group_index) = *previous_input_group_index {
        if first_input_group_index <= previous_input_group_index {
            return Err(library_partition_contract_error(format!(
                "resumable source-pack link execution progress at group {next_group_index} prepared group {group_index} {label} sidecar page {page_index} starts at input group {first_input_group_index} after prior page ended at input group {previous_input_group_index}; resumed partial-link sidecars must be globally strictly ascending by input group so replay cannot hide duplicate or missing partial-link evidence"
            )));
        }
    }
    if let Some(&last_input_group_index) = input_group_indices.last() {
        *previous_input_group_index = Some(last_input_group_index);
    }
    Ok(())
}

fn validate_link_execution_replay_tail_sidecar_input_count(
    next_group_index: usize,
    group_index: usize,
    label: &str,
    actual: usize,
    expected: usize,
) -> Result<(), CompileError> {
    if actual != expected {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution progress at group {next_group_index} prepared group {group_index} {label} sidecar evidence covers {actual} inputs but execution page records {expected} paged inputs"
        )));
    }
    Ok(())
}

fn validate_link_execution_page_matches_group(
    page: &SourcePackHierarchicalLinkExecutionPage,
    group: &SourcePackHierarchicalLinkGroupPage,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    let expected_final_output = group.group_index == link_plan_index.final_link_group_index;
    let expected_output_key = if expected_final_output {
        artifact_ref_index.final_output_key.clone()
    } else {
        hierarchical_link_partial_output_key(
            link_plan_index.target,
            group.group_index,
            group.job_index,
        )
    };
    if page.kind != group.kind {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} records kind {:?} but current link group is {:?}",
            group.group_index, page.kind, group.kind
        )));
    }
    if page.job_index != group.job_index {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} records job {} but current link group records job {}",
            group.group_index, page.job_index, group.job_index
        )));
    }
    if page.final_output != expected_final_output {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} final-output flag {} does not match current link plan final group {}",
            group.group_index, page.final_output, link_plan_index.final_link_group_index
        )));
    }
    if page.output_key != expected_output_key {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} output key {:?} does not match current link-plan output key {:?}",
            group.group_index, page.output_key, expected_output_key
        )));
    }
    if page.source_byte_count != group.source_byte_count
        || page.source_file_count != group.source_file_count
        || page.source_line_count != group.source_line_count
    {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} source summary bytes/files/lines {}/{}/{} does not match current link group {}/{}/{}",
            group.group_index,
            page.source_byte_count,
            page.source_file_count,
            page.source_line_count,
            group.source_byte_count,
            group.source_file_count,
            group.source_line_count
        )));
    }
    let expected_interface_count = match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            hierarchical_link_group_input_frontend_job_count(group)
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => 0,
    };
    let expected_object_count = match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => group.input_codegen_job_indices.len(),
        SourcePackHierarchicalLinkGroupKind::Reduce => 0,
    };
    let expected_group_count = match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => 0,
        SourcePackHierarchicalLinkGroupKind::Reduce => group.input_link_group_indices.len(),
    };
    let actual_interface_count = hierarchical_link_execution_input_interface_count(page);
    let actual_object_count = hierarchical_link_execution_input_object_count(page);
    let actual_group_count = hierarchical_link_execution_input_group_count(page);
    if actual_interface_count != expected_interface_count
        || actual_object_count != expected_object_count
        || actual_group_count != expected_group_count
    {
        return Err(library_partition_contract_error(format!(
            "resumable source-pack link execution group {} input summary interfaces/objects/groups {}/{}/{} does not match current link group {}/{}/{}",
            group.group_index,
            actual_interface_count,
            actual_object_count,
            actual_group_count,
            expected_interface_count,
            expected_object_count,
            expected_group_count
        )));
    }
    Ok(())
}

fn validate_link_execution_page_partial_inputs_match_current_group(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    group: &SourcePackHierarchicalLinkGroupPage,
    context: &str,
) -> Result<(), CompileError> {
    if group.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Ok(());
    }

    let actual_input_group_indices =
        link_execution_page_input_group_indices_from_artifacts(store, page, context)?;
    let expected_input_group_indices = group.input_link_group_indices.as_slice();
    if actual_input_group_indices.as_slice() == expected_input_group_indices {
        return Ok(());
    }

    let mismatch_index = actual_input_group_indices
        .iter()
        .zip(expected_input_group_indices)
        .position(|(actual, expected)| actual != expected)
        .unwrap_or_else(|| {
            actual_input_group_indices
                .len()
                .min(expected_input_group_indices.len())
        });
    let actual_value = actual_input_group_indices
        .get(mismatch_index)
        .map(|value| value.to_string())
        .unwrap_or_else(|| "missing".into());
    let expected_value = expected_input_group_indices
        .get(mismatch_index)
        .map(|value| value.to_string())
        .unwrap_or_else(|| "missing".into());

    Err(library_partition_contract_error(format!(
        "{context} {} partial-link input groups do not match current link group at offset {mismatch_index}: persisted {actual_value}, current {expected_value}; persisted link execution must match current dense link-group evidence before claiming link completion",
        group.group_index
    )))
}

fn validate_link_execution_page_inputs_match_current_group(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    group: &SourcePackHierarchicalLinkGroupPage,
    context: &str,
) -> Result<(), CompileError> {
    match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            validate_link_execution_page_leaf_inputs_match_current_group(
                store, page, group, context,
            )
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            validate_link_execution_page_partial_inputs_match_current_group(
                store, page, group, context,
            )
        }
    }
}

fn validate_link_execution_page_leaf_inputs_match_current_group(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    group: &SourcePackHierarchicalLinkGroupPage,
    context: &str,
) -> Result<(), CompileError> {
    let actual_object_job_indices =
        link_execution_page_input_object_job_indices_from_artifacts(store, page, context)?;
    validate_link_execution_input_jobs_match_current_group(
        context,
        group.group_index,
        "object",
        actual_object_job_indices,
        group.input_codegen_job_indices.as_slice(),
    )?;

    if !group.input_frontend_job_indices.is_empty() {
        let actual_interface_job_indices =
            link_execution_page_input_interface_job_indices_from_artifacts(store, page, context)?;
        validate_link_execution_input_jobs_match_current_group(
            context,
            group.group_index,
            "interface",
            actual_interface_job_indices,
            group.input_frontend_job_indices.as_slice(),
        )?;
    }

    Ok(())
}

fn link_execution_page_input_object_job_indices_from_artifacts(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    context: &str,
) -> Result<Vec<usize>, CompileError> {
    let mut object_job_indices =
        Vec::with_capacity(hierarchical_link_execution_input_object_count(page));
    object_job_indices.extend(
        page.input_objects
            .iter()
            .map(|artifact| artifact.producing_job_index),
    );
    for page_index in 0..page.input_object_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_object_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "{context} {} requires object input sidecar evidence page {page_index} before comparing current link group inputs: {err}",
                    page.group_index
                ))
            })?;
        object_job_indices.extend(
            sidecar
                .input_objects
                .iter()
                .map(|artifact| artifact.producing_job_index),
        );
    }
    object_job_indices.sort_unstable();
    Ok(object_job_indices)
}

fn link_execution_page_input_interface_job_indices_from_artifacts(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    context: &str,
) -> Result<Vec<usize>, CompileError> {
    let mut interface_job_indices =
        Vec::with_capacity(hierarchical_link_execution_input_interface_count(page));
    for (range_index, range) in page.input_interface_ranges.iter().enumerate() {
        let Some(range_jobs) = range.iter() else {
            return Err(library_partition_contract_error(format!(
                "{context} {} interface input range {range_index} overflows while comparing current link group inputs",
                page.group_index
            )));
        };
        interface_job_indices.extend(range_jobs);
    }
    interface_job_indices.extend(
        page.input_interfaces
            .iter()
            .map(|artifact| artifact.producing_job_index),
    );
    for page_index in 0..page.input_interface_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_interface_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "{context} {} requires interface input sidecar evidence page {page_index} before comparing current link group inputs: {err}",
                    page.group_index
                ))
            })?;
        interface_job_indices.extend(
            sidecar
                .input_interfaces
                .iter()
                .map(|artifact| artifact.producing_job_index),
        );
    }
    interface_job_indices.sort_unstable();
    Ok(interface_job_indices)
}

fn validate_link_execution_input_jobs_match_current_group(
    context: &str,
    group_index: usize,
    label: &str,
    actual_job_indices: Vec<usize>,
    expected_job_indices: &[usize],
) -> Result<(), CompileError> {
    if actual_job_indices.as_slice() == expected_job_indices {
        return Ok(());
    }

    let mismatch_index = actual_job_indices
        .iter()
        .zip(expected_job_indices)
        .position(|(actual, expected)| actual != expected)
        .unwrap_or_else(|| actual_job_indices.len().min(expected_job_indices.len()));
    let actual_value = actual_job_indices
        .get(mismatch_index)
        .map(|value| value.to_string())
        .unwrap_or_else(|| "missing".into());
    let expected_value = expected_job_indices
        .get(mismatch_index)
        .map(|value| value.to_string())
        .unwrap_or_else(|| "missing".into());

    Err(library_partition_contract_error(format!(
        "{context} {group_index} {label} input jobs do not match current link group at offset {mismatch_index}: persisted {actual_value}, current {expected_value}; persisted link execution must match current dense link-group evidence before claiming link completion"
    )))
}

fn link_execution_page_input_group_indices_from_artifacts(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    context: &str,
) -> Result<Vec<usize>, CompileError> {
    let input_group_count = hierarchical_link_execution_input_group_count(page);
    if page.input_group_page_count == 0 {
        return Ok(page.input_group_indices.clone());
    }

    let mut input_group_indices = Vec::with_capacity(input_group_count);
    input_group_indices.extend(page.input_group_indices.iter().copied());
    for page_index in 0..page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "{context} {} requires partial-link input sidecar evidence page {page_index} before comparing current link group inputs: {err}",
                    page.group_index
                ))
            })?;
        input_group_indices.extend(sidecar.input_group_indices.iter().copied());
    }
    Ok(input_group_indices)
}

/// Stores the completed hierarchical link execution index.
pub(in crate::compiler) fn store_hierarchical_link_execution_index(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
) -> Result<PathBuf, CompileError> {
    validate_link_execution_index(index, index.target)?;
    validate_completed_link_execution_index_evidence(store, index)?;
    let path = store.hierarchical_link_execution_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "serialize source-pack hierarchical link execution index: {err}"
        ))
    })?;
    write_file_atomic(
        &path,
        &bytes,
        "source-pack hierarchical link execution index",
    )?;
    Ok(path)
}

fn validate_link_execution_index_for_artifact_ref_index(
    index: &SourcePackHierarchicalLinkExecutionIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    validate_link_execution_index(index, index.target)?;
    validate_artifact_ref_index(artifact_ref_index, index.target)?;
    if artifact_ref_index.final_output_artifact_index != index.first_link_job_index {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index first link job {} does not match current artifact-ref index final output artifact {}",
            index.first_link_job_index, artifact_ref_index.final_output_artifact_index
        )));
    }
    if index.final_output_key != artifact_ref_index.final_output_key {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index final output {:?} does not match current artifact-ref index final output {:?}",
            index.final_output_key, artifact_ref_index.final_output_key
        )));
    }
    Ok(())
}

fn validate_completed_link_execution_final_page_summary_for_artifact_ref_index(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    validate_link_execution_index_for_artifact_ref_index(index, artifact_ref_index)?;
    let final_page = store
        .load_hierarchical_link_execution_page_for_target(
            index.target,
            index.final_link_group_index,
        )
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution index requires final execution page source-summary evidence for group {}: {err}",
                index.final_link_group_index
            ))
        })?;
    if final_page.source_byte_count != artifact_ref_index.total_source_byte_count
        || final_page.source_file_count != artifact_ref_index.total_source_file_count
        || final_page.source_line_count != artifact_ref_index.total_source_line_count
    {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index final page source summary bytes/files/lines {}/{}/{} does not match current artifact-ref totals {}/{}/{}; completed replay must not trust stale linked-output source evidence",
            final_page.source_byte_count,
            final_page.source_file_count,
            final_page.source_line_count,
            artifact_ref_index.total_source_byte_count,
            artifact_ref_index.total_source_file_count,
            artifact_ref_index.total_source_line_count
        )));
    }
    Ok(())
}

fn validate_completed_link_execution_final_page_matches_plan_group(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    validate_link_execution_index_for_plan(index, link_plan_index)?;
    let group = store
        .load_hierarchical_link_group_page_for_target(index.target, index.final_link_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution index requires current final link group evidence for group {}: {err}",
                index.final_link_group_index
            ))
        })?;
    validate_link_group_page_for_plan(&group, link_plan_index, Some(index.final_link_group_index))?;
    let final_page = store
        .load_hierarchical_link_execution_page_for_target(
            index.target,
            index.final_link_group_index,
        )
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution index requires final execution page evidence for current final group {}: {err}",
                index.final_link_group_index
            ))
        })?;
    validate_link_execution_page_matches_group(
        &final_page,
        &group,
        link_plan_index,
        artifact_ref_index,
    )?;
    validate_link_execution_page_inputs_match_current_group(
        store,
        &final_page,
        &group,
        "completed source-pack link execution index final group",
    )?;
    validate_completed_link_partial_input_pages_match_current_groups(
        store,
        &final_page,
        link_plan_index,
        artifact_ref_index,
    )
}

/// Validates that a completed link execution index is backed by final-page evidence.
pub(in crate::compiler) fn validate_completed_link_execution_index_evidence(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
) -> Result<(), CompileError> {
    validate_link_execution_index(index, index.target)?;
    let final_page = store
        .load_hierarchical_link_execution_page_for_target(
            index.target,
            index.final_link_group_index,
        )
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution index requires final execution page evidence for group {}: {err}",
                index.final_link_group_index
            ))
        })?;
    if !final_page.final_output {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index final group {} is backed by a non-final execution page",
            index.final_link_group_index
        )));
    }
    if final_page.job_index != index.final_link_job_index {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index final job {} does not match final execution page job {}",
            index.final_link_job_index, final_page.job_index
        )));
    }
    if final_page.output_key != index.final_output_key {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution index final output {:?} does not match final execution page output {:?}",
            index.final_output_key, final_page.output_key
        )));
    }
    validate_completed_link_execution_input_sidecars(store, &final_page)?;
    validate_completed_link_final_output_artifact_evidence(store, &final_page)?;
    Ok(())
}

fn validate_completed_link_final_output_artifact_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    if page.descriptor_summary.export_symbol_count == 0 {
        return Ok(());
    }

    store
        .require_artifact_key_file(&page.output_key, "linked output")
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} descriptor summary requires concrete linked-output artifact {:?} for {} export symbol records; descriptor summaries are not link artifact evidence: {err}",
                page.group_index, page.output_key, page.descriptor_summary.export_symbol_count
            ))
        })?;
    Ok(())
}

fn validate_completed_link_execution_input_sidecars(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    let ranged_interface_count = job_index_range_dependency_count(&page.input_interface_ranges);
    let total_interface_count = hierarchical_link_execution_input_interface_count(page);
    let expected_paged_interface_count = total_interface_count
        .checked_sub(ranged_interface_count)
        .and_then(|count| count.checked_sub(page.input_interfaces.len()))
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} interface input summary underflows sidecar evidence",
                page.group_index
            ))
        })?;
    let actual_paged_interface_count = completed_link_interface_sidecar_input_count(store, page)?;
    validate_completed_link_sidecar_input_count(
        page.group_index,
        "interface",
        actual_paged_interface_count,
        expected_paged_interface_count,
    )?;

    let total_object_count = hierarchical_link_execution_input_object_count(page);
    let expected_paged_object_count = total_object_count
        .checked_sub(page.input_objects.len())
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} object input summary underflows sidecar evidence",
                page.group_index
            ))
        })?;
    let actual_paged_object_count = completed_link_object_sidecar_input_count(store, page)?;
    validate_completed_link_sidecar_input_count(
        page.group_index,
        "object",
        actual_paged_object_count,
        expected_paged_object_count,
    )?;

    let total_group_count = hierarchical_link_execution_input_group_count(page);
    let expected_paged_group_count = total_group_count
        .checked_sub(page.input_group_indices.len())
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} partial-link input summary underflows sidecar evidence",
                page.group_index
            ))
        })?;
    let (actual_paged_group_count, paged_partial_source_summary) =
        completed_link_partial_sidecar_input_count(store, page)?;
    validate_completed_link_sidecar_input_count(
        page.group_index,
        "partial-link",
        actual_paged_group_count,
        expected_paged_group_count,
    )?;
    let inline_partial_source_summary =
        validate_completed_link_inline_partial_input_group_evidence(store, page)?;
    let partial_input_source_summary = inline_partial_source_summary
        .checked_add(paged_partial_source_summary, page.group_index)?;
    validate_completed_link_partial_input_source_summary(page, partial_input_source_summary)?;
    validate_completed_link_partial_input_descriptor_evidence(store, page)?;

    Ok(())
}

fn completed_link_interface_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<usize, CompileError> {
    let mut input_count = 0usize;
    let mut previous_producer_job_index = None;
    for page_index in 0..page.input_interface_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_interface_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution index requires interface input sidecar evidence for final group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_completed_link_sidecar_job_index(
            page.group_index,
            "interface",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_completed_link_sidecar_page_fill(
            page.group_index,
            "interface",
            page_index,
            page.input_interface_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
        )?;
        validate_completed_link_artifact_sidecar_order(
            page.group_index,
            "interface",
            page_index,
            &sidecar.input_interfaces,
            &mut previous_producer_job_index,
        )?;
        input_count = input_count
            .checked_add(sidecar.input_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {} interface sidecar input count overflows",
                    page.group_index
                ))
            })?;
    }
    Ok(input_count)
}

fn completed_link_object_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<usize, CompileError> {
    let mut input_count = 0usize;
    let mut previous_producer_job_index = None;
    for page_index in 0..page.input_object_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_object_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution index requires object input sidecar evidence for final group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_completed_link_sidecar_job_index(
            page.group_index,
            "object",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_completed_link_sidecar_page_fill(
            page.group_index,
            "object",
            page_index,
            page.input_object_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
        )?;
        validate_completed_link_artifact_sidecar_order(
            page.group_index,
            "object",
            page_index,
            &sidecar.input_objects,
            &mut previous_producer_job_index,
        )?;
        input_count = input_count
            .checked_add(sidecar.input_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {} object sidecar input count overflows",
                    page.group_index
                ))
            })?;
    }
    Ok(input_count)
}

fn completed_link_partial_sidecar_input_count(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(usize, CompletedLinkInputSourceSummary), CompileError> {
    let mut input_count = 0usize;
    let mut previous_input_group_index = None;
    let mut input_source_summary = CompletedLinkInputSourceSummary::default();
    for page_index in 0..page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution index requires partial-link input sidecar evidence for final group {} page {}: {err}",
                    page.group_index, page_index
                ))
            })?;
        validate_completed_link_sidecar_job_index(
            page.group_index,
            "partial-link",
            page_index,
            sidecar.job_index,
            page.job_index,
        )?;
        validate_completed_link_sidecar_page_fill(
            page.group_index,
            "partial-link",
            page_index,
            page.input_group_page_count,
            sidecar.input_count,
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
        )?;
        validate_completed_link_partial_sidecar_order(
            page.group_index,
            "partial-link",
            page_index,
            &sidecar.input_group_indices,
            &mut previous_input_group_index,
        )?;
        let label = format!("partial-link input sidecar page {page_index}");
        for (&input_group_index, input_group_output_key) in sidecar
            .input_group_indices
            .iter()
            .zip(sidecar.input_group_output_keys.iter())
        {
            let input_summary = validate_completed_link_partial_input_group_execution_page(
                store,
                page,
                input_group_index,
                input_group_output_key,
                &label,
            )?;
            input_source_summary =
                input_source_summary.checked_add(input_summary, page.group_index)?;
        }
        input_count = input_count
            .checked_add(sidecar.input_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {} partial-link sidecar input count overflows",
                    page.group_index
                ))
            })?;
    }
    Ok((input_count, input_source_summary))
}

fn validate_completed_link_inline_partial_input_group_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<CompletedLinkInputSourceSummary, CompileError> {
    let mut input_source_summary = CompletedLinkInputSourceSummary::default();
    for (&input_group_index, input_group_output_key) in page
        .input_group_indices
        .iter()
        .zip(page.input_group_output_keys.iter())
    {
        let input_summary = validate_completed_link_partial_input_group_execution_page(
            store,
            page,
            input_group_index,
            input_group_output_key,
            "inline partial-link input",
        )?;
        input_source_summary = input_source_summary.checked_add(input_summary, page.group_index)?;
    }
    Ok(input_source_summary)
}

fn validate_completed_link_partial_input_group_execution_page(
    store: &FilesystemArtifactStore,
    final_page: &SourcePackHierarchicalLinkExecutionPage,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<CompletedLinkInputSourceSummary, CompileError> {
    let first_link_job_index = final_page
        .job_index
        .checked_sub(final_page.group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} job {} precedes dense group index",
                final_page.group_index, final_page.job_index
            ))
        })?;
    let expected_input_job_index = first_link_job_index
        .checked_add(input_group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} input group {} dense job overflows",
                final_page.group_index, input_group_index
            ))
        })?;
    let input_page = store
        .load_hierarchical_link_execution_page_for_target(final_page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} {label} requires partial-link producer execution page evidence for input group {}: {err}",
                final_page.group_index, input_group_index
            ))
        })?;

    if input_page.final_output {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} {label} input group {} is backed by a final execution page",
            final_page.group_index, input_group_index
        )));
    }
    if input_page.job_index != expected_input_job_index {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} {label} input group {} records job {} but dense producer job is {}",
            final_page.group_index,
            input_group_index,
            input_page.job_index,
            expected_input_job_index
        )));
    }
    if input_page.output_key != input_group_output_key {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} {label} input group {} consumes partial-link key {:?} but producer execution page records {:?}",
            final_page.group_index,
            input_group_index,
            input_group_output_key,
            input_page.output_key
        )));
    }
    if !input_page
        .descriptor_summary
        .required_runtime_service_ids
        .is_empty()
    {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} {label} input group {} consumes partial-link producer execution page with unbound runtime services {:?}; completed final output replay requires runtime binding evidence before those requirements can be cleared",
            final_page.group_index,
            input_group_index,
            input_page.descriptor_summary.required_runtime_service_ids
        )));
    }
    validate_completed_link_execution_input_sidecars(store, &input_page)?;
    Ok(CompletedLinkInputSourceSummary::from_page(&input_page))
}

fn validate_completed_link_partial_input_pages_match_current_groups(
    store: &FilesystemArtifactStore,
    final_page: &SourcePackHierarchicalLinkExecutionPage,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    validate_link_plan_index(link_plan_index, final_page.target)?;
    validate_artifact_ref_index(artifact_ref_index, final_page.target)?;
    if hierarchical_link_execution_input_group_count(final_page) == 0 {
        return Ok(());
    }

    for (&input_group_index, input_group_output_key) in final_page
        .input_group_indices
        .iter()
        .zip(final_page.input_group_output_keys.iter())
    {
        validate_completed_link_partial_input_page_matches_current_group(
            store,
            final_page,
            link_plan_index,
            artifact_ref_index,
            input_group_index,
            input_group_output_key,
            "inline partial-link input",
        )?;
    }

    for page_index in 0..final_page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                final_page.target,
                final_page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {} requires partial-link input sidecar evidence page {page_index} before validating current producer groups: {err}",
                    final_page.group_index
                ))
            })?;
        let label = format!("partial-link input sidecar page {page_index}");
        for (&input_group_index, input_group_output_key) in sidecar
            .input_group_indices
            .iter()
            .zip(sidecar.input_group_output_keys.iter())
        {
            validate_completed_link_partial_input_page_matches_current_group(
                store,
                final_page,
                link_plan_index,
                artifact_ref_index,
                input_group_index,
                input_group_output_key,
                &label,
            )?;
        }
    }

    Ok(())
}

fn validate_completed_link_partial_input_page_matches_current_group(
    store: &FilesystemArtifactStore,
    final_page: &SourcePackHierarchicalLinkExecutionPage,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<(), CompileError> {
    let input_group = store
        .load_hierarchical_link_group_page_for_target(final_page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} {label} requires current link group evidence for input group {}: {err}",
                final_page.group_index, input_group_index
            ))
        })?;
    validate_link_group_page_for_plan(&input_group, link_plan_index, Some(input_group_index))?;
    let input_page = store
        .load_hierarchical_link_execution_page_for_target(final_page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution final group {} {label} requires partial-link producer execution page evidence for input group {} before comparing current link-group evidence: {err}",
                final_page.group_index, input_group_index
            ))
        })?;
    if input_page.output_key != input_group_output_key {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} {label} input group {} consumes partial-link key {:?} but producer execution page records {:?}",
            final_page.group_index,
            input_group_index,
            input_group_output_key,
            input_page.output_key
        )));
    }
    validate_link_execution_page_matches_group(
        &input_page,
        &input_group,
        link_plan_index,
        artifact_ref_index,
    )?;
    validate_link_execution_replay_tail_input_sidecars(store, &input_page, final_page.group_index)?;
    validate_link_execution_page_inputs_match_current_group(
        store,
        &input_page,
        &input_group,
        &format!(
            "completed source-pack link execution final group {} {label} producer group",
            final_page.group_index
        ),
    )?;
    validate_completed_link_partial_input_pages_match_current_groups(
        store,
        &input_page,
        link_plan_index,
        artifact_ref_index,
    )
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct CompletedLinkInputSourceSummary {
    byte_count: usize,
    file_count: usize,
    line_count: usize,
}

impl CompletedLinkInputSourceSummary {
    fn from_page(page: &SourcePackHierarchicalLinkExecutionPage) -> Self {
        Self {
            byte_count: page.source_byte_count,
            file_count: page.source_file_count,
            line_count: page.source_line_count,
        }
    }

    fn checked_add(self, rhs: Self, final_group_index: usize) -> Result<Self, CompileError> {
        Ok(Self {
            byte_count: self.byte_count.checked_add(rhs.byte_count).ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {final_group_index} partial input source-byte summary overflows"
                ))
            })?,
            file_count: self.file_count.checked_add(rhs.file_count).ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {final_group_index} partial input source-file summary overflows"
                ))
            })?,
            line_count: self.line_count.checked_add(rhs.line_count).ok_or_else(|| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution final group {final_group_index} partial input source-line summary overflows"
                ))
            })?,
        })
    }
}

fn validate_completed_link_partial_input_source_summary(
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_source_summary: CompletedLinkInputSourceSummary,
) -> Result<(), CompileError> {
    if hierarchical_link_execution_input_group_count(page) == 0 {
        return Ok(());
    }

    let final_source_summary = CompletedLinkInputSourceSummary::from_page(page);
    if input_source_summary != final_source_summary {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {} partial input source summary bytes/files/lines {}/{}/{} does not match final page {}/{}/{}; completed replay must not trust stale partial-link source evidence",
            page.group_index,
            input_source_summary.byte_count,
            input_source_summary.file_count,
            input_source_summary.line_count,
            final_source_summary.byte_count,
            final_source_summary.file_count,
            final_source_summary.line_count
        )));
    }
    Ok(())
}

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
struct CompletedLinkDescriptorEvidence {
    interface_symbol_count: usize,
    object_section_count: usize,
    object_symbol_count: usize,
    unresolved_symbol_count: usize,
    relocation_count: usize,
}

impl CompletedLinkDescriptorEvidence {
    fn from_summary(summary: &SourcePackLinkDescriptorSummary) -> Self {
        Self {
            interface_symbol_count: summary.interface_symbol_count,
            object_section_count: summary.object_section_count,
            object_symbol_count: summary.object_symbol_count,
            unresolved_symbol_count: summary.unresolved_symbol_count,
            relocation_count: summary.relocation_count,
        }
    }

    fn is_empty(self) -> bool {
        self.interface_symbol_count == 0
            && self.object_section_count == 0
            && self.object_symbol_count == 0
            && self.unresolved_symbol_count == 0
            && self.relocation_count == 0
    }

    fn checked_add(
        self,
        rhs: Self,
        group_index: usize,
    ) -> Result<CompletedLinkDescriptorEvidence, CompileError> {
        Ok(Self {
            interface_symbol_count: self
                .interface_symbol_count
                .checked_add(rhs.interface_symbol_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "completed source-pack link execution group {group_index} partial-link producer interface-symbol descriptor evidence overflows"
                    ))
                })?,
            object_section_count: self
                .object_section_count
                .checked_add(rhs.object_section_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "completed source-pack link execution group {group_index} partial-link producer object-section descriptor evidence overflows"
                    ))
                })?,
            object_symbol_count: self
                .object_symbol_count
                .checked_add(rhs.object_symbol_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "completed source-pack link execution group {group_index} partial-link producer object-symbol descriptor evidence overflows"
                    ))
                })?,
            unresolved_symbol_count: self
                .unresolved_symbol_count
                .checked_add(rhs.unresolved_symbol_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "completed source-pack link execution group {group_index} partial-link producer unresolved-symbol descriptor evidence overflows"
                    ))
                })?,
            relocation_count: self
                .relocation_count
                .checked_add(rhs.relocation_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "completed source-pack link execution group {group_index} partial-link producer relocation descriptor evidence overflows"
                    ))
                })?,
        })
    }
}

fn validate_completed_link_partial_input_descriptor_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    if hierarchical_link_execution_input_group_count(page) == 0 {
        return Ok(());
    }
    let required = CompletedLinkDescriptorEvidence::from_summary(&page.descriptor_summary);
    let producer_evidence = completed_link_partial_input_descriptor_evidence(store, page)?;
    if required.is_empty() && producer_evidence.is_empty() {
        return Ok(());
    }
    validate_completed_link_descriptor_count(
        page.group_index,
        "interface symbol",
        required.interface_symbol_count,
        producer_evidence.interface_symbol_count,
    )?;
    validate_completed_link_descriptor_count(
        page.group_index,
        "object section",
        required.object_section_count,
        producer_evidence.object_section_count,
    )?;
    validate_completed_link_descriptor_count(
        page.group_index,
        "object symbol",
        required.object_symbol_count,
        producer_evidence.object_symbol_count,
    )?;
    validate_completed_link_descriptor_count(
        page.group_index,
        "unresolved symbol",
        required.unresolved_symbol_count,
        producer_evidence.unresolved_symbol_count,
    )?;
    validate_completed_link_descriptor_count(
        page.group_index,
        "relocation",
        required.relocation_count,
        producer_evidence.relocation_count,
    )?;
    Ok(())
}

fn completed_link_partial_input_descriptor_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<CompletedLinkDescriptorEvidence, CompileError> {
    let mut evidence = CompletedLinkDescriptorEvidence::default();
    for (&input_group_index, input_group_output_key) in page
        .input_group_indices
        .iter()
        .zip(page.input_group_output_keys.iter())
    {
        evidence = evidence.checked_add(
            completed_link_partial_input_group_descriptor_evidence(
                store,
                page,
                input_group_index,
                input_group_output_key,
                "inline partial-link input",
            )?,
            page.group_index,
        )?;
    }

    for page_index in 0..page.input_group_page_count {
        let sidecar = store
            .load_hierarchical_link_execution_partial_page_for_target(
                page.target,
                page.group_index,
                page_index,
            )
            .map_err(|err| {
                library_partition_contract_error(format!(
                    "completed source-pack link execution group {} requires partial-link input sidecar evidence page {page_index} before validating descriptor-summary producer evidence: {err}",
                    page.group_index
                ))
            })?;
        let label = format!("partial-link input sidecar page {page_index}");
        for (&input_group_index, input_group_output_key) in sidecar
            .input_group_indices
            .iter()
            .zip(sidecar.input_group_output_keys.iter())
        {
            evidence = evidence.checked_add(
                completed_link_partial_input_group_descriptor_evidence(
                    store,
                    page,
                    input_group_index,
                    input_group_output_key,
                    &label,
                )?,
                page.group_index,
            )?;
        }
    }

    Ok(evidence)
}

fn completed_link_partial_input_group_descriptor_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<CompletedLinkDescriptorEvidence, CompileError> {
    let input_page = store
        .load_hierarchical_link_execution_page_for_target(page.target, input_group_index)
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution group {} {label} requires partial-link producer execution page evidence for input group {} before validating descriptor-summary producer evidence: {err}",
                page.group_index, input_group_index
            ))
        })?;
    if input_page.final_output {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution group {} {label} input group {} is backed by a final execution page while validating descriptor-summary producer evidence",
            page.group_index, input_group_index
        )));
    }
    if input_page.output_key != input_group_output_key {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution group {} {label} input group {} consumes partial-link key {:?} but producer execution page records {:?} while validating descriptor-summary producer evidence",
            page.group_index, input_group_index, input_group_output_key, input_page.output_key
        )));
    }
    let evidence = CompletedLinkDescriptorEvidence::from_summary(&input_page.descriptor_summary);
    if !evidence.is_empty() {
        validate_completed_partial_link_output_artifact_evidence(
            store,
            page,
            input_group_index,
            &input_page.output_key,
            label,
        )?;
    }
    Ok(evidence)
}

fn validate_completed_partial_link_output_artifact_evidence(
    store: &FilesystemArtifactStore,
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_group_index: usize,
    input_group_output_key: &str,
    label: &str,
) -> Result<(), CompileError> {
    store
        .require_artifact_key_file(input_group_output_key, "partial link output")
        .map_err(|err| {
            library_partition_contract_error(format!(
                "completed source-pack link execution group {} {label} input group {} descriptor summary requires concrete partial-link output artifact {:?}; descriptor summaries are not link artifact evidence: {err}",
                page.group_index, input_group_index, input_group_output_key
            ))
        })?;
    Ok(())
}

fn validate_completed_link_descriptor_count(
    group_index: usize,
    label: &str,
    required: usize,
    available: usize,
) -> Result<(), CompileError> {
    if required > available {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution group {group_index} descriptor summary records {required} {label} records but partial-link producer execution pages carry {available}; descriptor metadata cannot substitute for producer partial-link/object record evidence"
        )));
    }
    if required < available {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution group {group_index} descriptor summary records {required} {label} records but partial-link producer execution pages carry {available}; completed replay cannot drop producer partial-link/object record evidence without explicit link resolution artifacts"
        )));
    }
    Ok(())
}

fn validate_completed_link_sidecar_job_index(
    group_index: usize,
    label: &str,
    page_index: usize,
    sidecar_job_index: usize,
    final_page_job_index: usize,
) -> Result<(), CompileError> {
    if sidecar_job_index != final_page_job_index {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {group_index} {label} input sidecar page {page_index} records job {sidecar_job_index} but final execution page records job {final_page_job_index}"
        )));
    }
    Ok(())
}

fn validate_completed_link_sidecar_page_fill(
    group_index: usize,
    label: &str,
    page_index: usize,
    page_count: usize,
    input_count: usize,
    page_capacity: usize,
) -> Result<(), CompileError> {
    if page_index < page_count.saturating_sub(1) && input_count != page_capacity {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {group_index} {label} input sidecar page {page_index} records {input_count} inputs before later sidecar pages; non-final sidecar pages must contain {page_capacity} inputs so completed indexes cannot hide missing link input evidence"
        )));
    }
    Ok(())
}

fn validate_completed_link_artifact_sidecar_order(
    group_index: usize,
    label: &str,
    page_index: usize,
    artifacts: &[SourcePackArtifactRef],
    previous_producer_job_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(first_artifact) = artifacts.first() else {
        return Ok(());
    };
    if let Some(previous_producer_job_index) = *previous_producer_job_index {
        if first_artifact.producing_job_index <= previous_producer_job_index {
            return Err(library_partition_contract_error(format!(
                "completed source-pack link execution final group {group_index} {label} input sidecar page {page_index} starts at producer job {} after prior page ended at producer job {previous_producer_job_index}; completed sidecar artifact refs must be globally strictly ascending so completed indexes cannot hide duplicate or missing link input evidence",
                first_artifact.producing_job_index
            )));
        }
    }
    if let Some(last_artifact) = artifacts.last() {
        *previous_producer_job_index = Some(last_artifact.producing_job_index);
    }
    Ok(())
}

fn validate_completed_link_partial_sidecar_order(
    group_index: usize,
    label: &str,
    page_index: usize,
    input_group_indices: &[usize],
    previous_input_group_index: &mut Option<usize>,
) -> Result<(), CompileError> {
    let Some(&first_input_group_index) = input_group_indices.first() else {
        return Ok(());
    };
    if let Some(previous_input_group_index) = *previous_input_group_index {
        if first_input_group_index <= previous_input_group_index {
            return Err(library_partition_contract_error(format!(
                "completed source-pack link execution final group {group_index} {label} input sidecar page {page_index} starts at input group {first_input_group_index} after prior page ended at input group {previous_input_group_index}; completed partial-link sidecars must be globally strictly ascending by input group so completed indexes cannot hide duplicate or missing partial-link evidence"
            )));
        }
    }
    if let Some(&last_input_group_index) = input_group_indices.last() {
        *previous_input_group_index = Some(last_input_group_index);
    }
    Ok(())
}

fn validate_completed_link_sidecar_input_count(
    group_index: usize,
    label: &str,
    actual: usize,
    expected: usize,
) -> Result<(), CompileError> {
    if actual != expected {
        return Err(library_partition_contract_error(format!(
            "completed source-pack link execution final group {group_index} {label} input sidecar evidence covers {actual} inputs but execution page records {expected} paged inputs"
        )));
    }
    Ok(())
}

/// Builds the artifact reference produced by a scheduled frontend or codegen job.
pub(in crate::compiler) fn scheduled_job_output_ref(
    job: &SourcePackJob,
    kind: SourcePackArtifactKind,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackArtifactRef, CompileError> {
    let expected_kind = match job.phase {
        SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
        SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
        SourcePackJobPhase::Link => {
            return Err(library_partition_contract_error(format!(
                "link job {} output refs require total source metadata",
                job.job_index
            )));
        }
    };
    if kind != expected_kind {
        return Err(library_partition_contract_error(format!(
            "job {} phase {:?} cannot produce {:?}",
            job.job_index, job.phase, kind
        )));
    }
    Ok(SourcePackArtifactRef {
        artifact_index: job.job_index,
        key: artifact_key_for_output(
            target,
            kind,
            job.library_id,
            job.job_index,
            job.first_source_index,
            job.source_file_count,
        ),
        producing_job_index: job.job_index,
        kind,
    })
}

/// Validates resumable artifact-reference preparation progress.
pub(in crate::compiler) fn validate_build_artifact_ref_prepare_progress(
    progress: &ArtifactRefPrepareProgress,
    schedule_index: &SourcePackLibraryScheduleIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<(), CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_library_partition_index(library_partition_index, schedule_index.target)?;
    if progress.version != SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION {
        return Err(artifact_shard_contract_error(format!(
            "unsupported source-pack artifact-ref prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != schedule_index.target {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress target {:?} does not match schedule target {:?}",
            progress.target, schedule_index.target
        )));
    }
    if progress.partition_count != schedule_index.partition_count
        || progress.partition_count != library_partition_index.partition_count
    {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress partition count {} does not match schedule/metadata counts {}/{}",
            progress.partition_count,
            schedule_index.partition_count,
            library_partition_index.partition_count
        )));
    }
    if progress.artifact_count != schedule_index.job_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress artifact count {} does not match schedule job count {}",
            progress.artifact_count, schedule_index.job_count
        )));
    }
    if progress.next_partition_index > progress.partition_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress next partition {} exceeds partition count {}",
            progress.next_partition_index, progress.partition_count
        )));
    }
    let frontend_job_count = library_schedule_index_frontend_job_count(schedule_index);
    if progress.interface_artifact_count > frontend_job_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress interface artifact count {} exceeds schedule frontend job count {frontend_job_count}",
            progress.interface_artifact_count
        )));
    }
    if progress.object_artifact_count > schedule_index.codegen_job_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress object artifact count {} exceeds schedule codegen job count {}",
            progress.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    let expected_page_count = progress
        .interface_artifact_count
        .checked_add(progress.object_artifact_count)
        .ok_or_else(|| {
            artifact_shard_contract_error("artifact-ref prepare progress page count overflows")
        })?;
    if progress.artifact_ref_page_count != expected_page_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress page count {} does not match interface/object count {}",
            progress.artifact_ref_page_count, expected_page_count
        )));
    }
    if progress.total_source_file_count != library_partition_index.source_file_count
        || progress.total_source_byte_count != library_partition_index.source_byte_count
        || progress.total_source_line_count != library_partition_index.source_line_count
    {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref prepare progress source totals {}/{}/{} do not match metadata totals {}/{}/{}",
            progress.total_source_file_count,
            progress.total_source_byte_count,
            progress.total_source_line_count,
            library_partition_index.source_file_count,
            library_partition_index.source_byte_count,
            library_partition_index.source_line_count
        )));
    }
    Ok(())
}

/// Stores a bounded chunk of artifact-reference pages from the library schedule.
pub(in crate::compiler) fn store_artifact_ref_pages_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    max_new_libraries: usize,
) -> Result<FilesystemArtifactRefPrepareStepResult, CompileError> {
    if max_new_libraries == 0 {
        return Err(source_pack_preparation_limit_invalid_error(
            "source-pack artifact-ref chunk max_new_libraries must be greater than zero",
        ));
    }
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    let metadata_index = store.load_library_partition_index_for_target(schedule_index.target)?;
    validate_library_partition_index(&metadata_index, schedule_index.target)?;
    if metadata_index.partition_count != schedule_index.partition_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref chunk schedule has {} partitions but metadata has {}",
            schedule_index.partition_count, metadata_index.partition_count
        )));
    }
    if store
        .build_artifact_ref_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_build_artifact_ref_index_for_target(schedule_index.target)?;
        validate_completed_artifact_ref_index_for_current_inputs(
            &index,
            schedule_index,
            &metadata_index,
        )?;
        validate_completed_artifact_ref_index_final_page_evidence(store, &index)?;
        return Ok(FilesystemArtifactRefPrepareStepResult {
            target: schedule_index.target,
            complete: true,
            artifact_count: index.artifact_count,
            artifact_ref_page_count: index.artifact_count,
            new_library_count: 0,
            interface_artifact_count: index.interface_artifact_count,
            object_artifact_count: index.object_artifact_count,
            final_output_artifact_index: index.final_output_artifact_index,
            final_output_key: Some(index.final_output_key),
            artifact_ref_index_path: Some(
                store.build_artifact_ref_index_path_for_target(schedule_index.target),
            ),
            total_source_file_count: index.total_source_file_count,
            total_source_byte_count: index.total_source_byte_count,
            total_source_line_count: index.total_source_line_count,
        });
    }

    let progress_path =
        store.build_artifact_ref_prepare_progress_path_for_target(schedule_index.target);
    let mut progress = if progress_path.is_file() {
        store.load_build_artifact_ref_prepare_progress_for_target(
            schedule_index.target,
            schedule_index,
            &metadata_index,
        )?
    } else {
        ArtifactRefPrepareProgress {
            version: SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            partition_count: schedule_index.partition_count,
            artifact_count: schedule_index.job_count,
            next_partition_index: 0,
            artifact_ref_page_count: 0,
            interface_artifact_count: 0,
            object_artifact_count: 0,
            total_source_file_count: metadata_index.source_file_count,
            total_source_byte_count: metadata_index.source_byte_count,
            total_source_line_count: metadata_index.source_line_count,
        }
    };
    validate_build_artifact_ref_prepare_progress(&progress, schedule_index, &metadata_index)?;

    let mut new_library_count = 0usize;
    while progress.next_partition_index < schedule_index.partition_count
        && new_library_count < max_new_libraries
    {
        let partition_index = progress.next_partition_index;
        let page =
            store.load_library_schedule_page_for_target(schedule_index.target, partition_index)?;
        validate_library_schedule_page(&page, schedule_index.target, Some(partition_index))?;
        let frontend_job_count = library_schedule_page_frontend_job_count(&page);
        let partition_artifact_ref_count = frontend_job_count
            .checked_add(page.codegen_job_count)
            .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "artifact-ref page count overflows at partition {partition_index}"
            ))
        })?;
        store_artifact_ref_pages_for_schedule_partition(store, schedule_index, &page)?;
        progress.interface_artifact_count = progress
            .interface_artifact_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "artifact-ref interface count overflows at partition {partition_index}"
                ))
            })?;
        progress.object_artifact_count = progress
            .object_artifact_count
            .checked_add(page.codegen_job_count)
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "artifact-ref object count overflows at partition {partition_index}"
                ))
            })?;
        progress.artifact_ref_page_count = progress
            .artifact_ref_page_count
            .checked_add(partition_artifact_ref_count)
            .ok_or_else(|| {
                artifact_shard_contract_error(format!(
                    "artifact-ref page count overflows at partition {partition_index}"
                ))
            })?;
        progress.next_partition_index =
            progress
                .next_partition_index
                .checked_add(1)
                .ok_or_else(|| {
                    artifact_shard_contract_error("artifact-ref next partition index overflows")
                })?;
        new_library_count = new_library_count.checked_add(1).ok_or_else(|| {
            artifact_shard_contract_error("artifact-ref new library count overflows")
        })?;
        store.store_build_artifact_ref_prepare_progress(
            &progress,
            schedule_index,
            &metadata_index,
        )?;
    }

    let total_interface_artifact_count = library_schedule_index_frontend_job_count(schedule_index);
    if progress.next_partition_index < schedule_index.partition_count {
        return Ok(FilesystemArtifactRefPrepareStepResult {
            target: schedule_index.target,
            complete: false,
            artifact_count: schedule_index.job_count,
            artifact_ref_page_count: progress.artifact_ref_page_count,
            new_library_count,
            interface_artifact_count: total_interface_artifact_count,
            object_artifact_count: schedule_index.codegen_job_count,
            final_output_artifact_index: schedule_index.link_job_index,
            final_output_key: None,
            artifact_ref_index_path: None,
            total_source_file_count: metadata_index.source_file_count,
            total_source_byte_count: metadata_index.source_byte_count,
            total_source_line_count: metadata_index.source_line_count,
        });
    }

    if progress.interface_artifact_count != total_interface_artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref chunk recorded {} interface artifacts but schedule index frontend_job_count {}",
            progress.interface_artifact_count, total_interface_artifact_count
        )));
    }
    if progress.object_artifact_count != schedule_index.codegen_job_count {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref chunk recorded {} object artifacts but schedule index codegen_job_count {}",
            progress.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    if progress.artifact_ref_page_count != schedule_index.link_job_index {
        return Err(artifact_shard_contract_error(format!(
            "artifact-ref chunk stored {} non-link artifact pages but schedule link job starts at {}",
            progress.artifact_ref_page_count, schedule_index.link_job_index
        )));
    }
    let final_output_ref = SourcePackArtifactRef {
        artifact_index: schedule_index.link_job_index,
        key: artifact_key_for_output(
            schedule_index.target,
            SourcePackArtifactKind::LinkedOutput,
            u32::MAX,
            schedule_index.link_job_index,
            0,
            metadata_index.source_file_count,
        ),
        producing_job_index: schedule_index.link_job_index,
        kind: SourcePackArtifactKind::LinkedOutput,
    };
    let final_output_page = build_artifact_ref_page(
        schedule_index.target,
        final_output_ref.clone(),
        schedule_index.job_count,
        metadata_index.source_byte_count,
        metadata_index.source_file_count,
        metadata_index.source_line_count,
    )?;
    store.store_build_artifact_ref_page(&final_output_page, schedule_index.job_count)?;
    let artifact_ref_page_count = progress
        .artifact_ref_page_count
        .checked_add(1)
        .ok_or_else(|| artifact_shard_contract_error("artifact-ref page count overflows"))?;

    let index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target: schedule_index.target,
        artifact_count: schedule_index.job_count,
        interface_artifact_count: total_interface_artifact_count,
        object_artifact_count: schedule_index.codegen_job_count,
        final_output_artifact_index: final_output_ref.artifact_index,
        final_output_key: final_output_ref.key.clone(),
        total_source_file_count: metadata_index.source_file_count,
        total_source_byte_count: metadata_index.source_byte_count,
        total_source_line_count: metadata_index.source_line_count,
    };
    validate_artifact_ref_index(&index, schedule_index.target)?;
    let artifact_ref_index_path = store.store_build_artifact_ref_index(&index)?;
    Ok(FilesystemArtifactRefPrepareStepResult {
        target: schedule_index.target,
        complete: true,
        artifact_count: index.artifact_count,
        artifact_ref_page_count,
        new_library_count,
        interface_artifact_count: index.interface_artifact_count,
        object_artifact_count: index.object_artifact_count,
        final_output_artifact_index: index.final_output_artifact_index,
        final_output_key: Some(index.final_output_key),
        artifact_ref_index_path: Some(artifact_ref_index_path),
        total_source_file_count: index.total_source_file_count,
        total_source_byte_count: index.total_source_byte_count,
        total_source_line_count: index.total_source_line_count,
    })
}

fn validate_completed_artifact_ref_index_for_current_inputs(
    index: &SourcePackBuildArtifactRefIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    metadata_index: &SourcePackLibraryPartitionIndex,
) -> Result<(), CompileError> {
    validate_artifact_ref_index(index, schedule_index.target)?;
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_library_partition_index(metadata_index, schedule_index.target)?;
    if metadata_index.partition_count != schedule_index.partition_count {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index cannot replay against schedule with {} partitions because metadata has {} partitions",
            schedule_index.partition_count, metadata_index.partition_count
        )));
    }

    let expected_interface_artifact_count =
        library_schedule_index_frontend_job_count(schedule_index);
    if index.artifact_count != schedule_index.job_count {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index artifact count {} does not match current schedule job count {}; completed artifact-ref replay must be tied to the current dense job schedule",
            index.artifact_count, schedule_index.job_count
        )));
    }
    if index.interface_artifact_count != expected_interface_artifact_count {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index interface count {} does not match current schedule frontend count {}",
            index.interface_artifact_count, expected_interface_artifact_count
        )));
    }
    if index.object_artifact_count != schedule_index.codegen_job_count {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index object count {} does not match current schedule codegen count {}",
            index.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    if index.final_output_artifact_index != schedule_index.link_job_index {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index final output artifact {} does not match current schedule link job {}",
            index.final_output_artifact_index, schedule_index.link_job_index
        )));
    }
    if index.total_source_file_count != metadata_index.source_file_count
        || index.total_source_byte_count != metadata_index.source_byte_count
        || index.total_source_line_count != metadata_index.source_line_count
    {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index totals files/bytes/lines {}/{}/{} do not match current source metadata {}/{}/{}; completed artifact-ref replay must not trust stale source summaries",
            index.total_source_file_count,
            index.total_source_byte_count,
            index.total_source_line_count,
            metadata_index.source_file_count,
            metadata_index.source_byte_count,
            metadata_index.source_line_count
        )));
    }

    let expected_final_output_key = artifact_key_for_output(
        schedule_index.target,
        SourcePackArtifactKind::LinkedOutput,
        u32::MAX,
        schedule_index.link_job_index,
        0,
        metadata_index.source_file_count,
    );
    if index.final_output_key != expected_final_output_key {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index final output {:?} does not match current schedule final output {:?}; completed artifact-ref replay must not trust stale linked-output keys",
            index.final_output_key, expected_final_output_key
        )));
    }

    Ok(())
}

fn validate_completed_artifact_ref_index_final_page_evidence(
    store: &FilesystemArtifactStore,
    index: &SourcePackBuildArtifactRefIndex,
) -> Result<(), CompileError> {
    validate_artifact_ref_index(index, index.target)?;
    let final_page = store
        .load_build_artifact_ref_page_for_target(
            index.target,
            index.final_output_artifact_index,
            index.artifact_count,
        )
        .map_err(|err| {
            artifact_shard_contract_error(format!(
                "completed source-pack artifact-ref index requires final linked-output artifact-ref page evidence for artifact {}: {err}",
                index.final_output_artifact_index
            ))
        })?;
    if final_page.artifact_ref.key != index.final_output_key {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index final output {:?} does not match final linked-output artifact-ref page key {:?}; completed artifact-ref replay must not trust stale linked-output keys",
            index.final_output_key, final_page.artifact_ref.key
        )));
    }
    if final_page.source_file_count != index.total_source_file_count
        || final_page.source_bytes != index.total_source_byte_count
        || final_page.source_lines != index.total_source_line_count
    {
        return Err(artifact_shard_contract_error(format!(
            "completed source-pack artifact-ref index totals files/bytes/lines {}/{}/{} do not match final linked-output artifact-ref page totals {}/{}/{}; completed artifact-ref replay must be backed by current linked-output evidence",
            index.total_source_file_count,
            index.total_source_byte_count,
            index.total_source_line_count,
            final_page.source_file_count,
            final_page.source_bytes,
            final_page.source_lines
        )));
    }
    Ok(())
}

/// Stores artifact-reference pages for all jobs owned by one schedule partition.
pub(in crate::compiler) fn store_artifact_ref_pages_for_schedule_partition(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
) -> Result<(), CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_library_schedule_page(page, schedule_index.target, Some(page.partition_index))?;
    for_each_stored_schedule_frontend_job(
        store,
        schedule_index,
        page,
        |_frontend_job_offset, frontend_job, _dependency_job_count| {
            let frontend_ref = scheduled_job_output_ref(
                &frontend_job,
                SourcePackArtifactKind::LibraryInterface,
                schedule_index.target,
            )?;
            let frontend_page = build_artifact_ref_page(
                schedule_index.target,
                frontend_ref,
                schedule_index.job_count,
                frontend_job.source_bytes,
                frontend_job.source_file_count,
                frontend_job.source_lines,
            )?;
            store.store_build_artifact_ref_page(&frontend_page, schedule_index.job_count)?;
            Ok(())
        },
    )?;

    for_each_stored_schedule_codegen_job(store, schedule_index, page, |_codegen_job_offset, job| {
        let object_ref = scheduled_job_output_ref(
            &job,
            SourcePackArtifactKind::CodegenObject,
            schedule_index.target,
        )?;
        let object_page = build_artifact_ref_page(
            schedule_index.target,
            object_ref,
            schedule_index.job_count,
            job.source_bytes,
            job.source_file_count,
            job.source_lines,
        )?;
        store.store_build_artifact_ref_page(&object_page, schedule_index.job_count)?;
        Ok(())
    })
}
