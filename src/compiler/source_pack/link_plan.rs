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
pub(in crate::compiler) struct HierarchicalLinkExecutionPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) link_group_count: usize,
    pub(in crate::compiler) next_group_index: usize,
    pub(in crate::compiler) final_output_seen: bool,
}

pub(in crate::compiler) fn validate_link_execution_prepare_progress(
    progress: &HierarchicalLinkExecutionPrepareProgress,
    target: SourcePackArtifactTarget,
    link_group_count: usize,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) fn store_hierarchical_link_execution_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    max_new_groups: usize,
) -> Result<FilesystemHierarchicalLinkExecutionPrepareStepResult, CompileError> {
    if max_new_groups == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link execution chunk max_new_groups must be greater than zero"
                .into(),
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
        validate_completed_link_execution_index_evidence(store, &index)?;
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
        store.store_hierarchical_link_execution_page(&page)?;
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

pub(in crate::compiler) fn store_link_execution_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &HierarchicalLinkExecutionPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_link_execution_prepare_progress(progress, progress.target, progress.link_group_count)?;
    let path = store.link_execution_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) fn load_link_execution_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    link_group_count: usize,
) -> Result<HierarchicalLinkExecutionPrepareProgress, CompileError> {
    let path = store.link_execution_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack hierarchical link execution prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<HierarchicalLinkExecutionPrepareProgress>(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack hierarchical link execution prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_link_execution_prepare_progress(&progress, target, link_group_count)?;
    Ok(progress)
}

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

    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

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

    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

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

    pub(in crate::compiler) fn finish(mut self) -> Result<(usize, usize), CompileError> {
        self.flush()?;
        Ok((self.input_count, self.page_index))
    }
}

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

    let mut input_partition_count = 0usize;
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
        input_partition_count = input_partition_count
            .checked_add(hierarchical_link_group_input_partition_count(&input_group))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link reduce group {} input partition summary overflows",
                    group.group_index
                ))
            })?;
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

pub(in crate::compiler) fn store_hierarchical_link_execution_index(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
) -> Result<PathBuf, CompileError> {
    validate_link_execution_index(index, index.target)?;
    validate_completed_link_execution_index_evidence(store, index)?;
    let path = store.hierarchical_link_execution_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        CompileError::GpuFrontend(format!(
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
    Ok(())
}

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

pub(in crate::compiler) fn validate_build_artifact_ref_prepare_progress(
    progress: &ArtifactRefPrepareProgress,
    schedule_index: &SourcePackLibraryScheduleIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<(), CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_library_partition_index(library_partition_index, schedule_index.target)?;
    if progress.version != SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) fn store_artifact_ref_pages_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    max_new_libraries: usize,
) -> Result<FilesystemArtifactRefPrepareStepResult, CompileError> {
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact-ref chunk max_new_libraries must be greater than zero".into(),
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
            job.source_bytes,
            job.source_file_count,
            job.source_lines,
        )?;
        store.store_build_artifact_ref_page(&object_page, schedule_index.job_count)?;
        Ok(())
    })
}
