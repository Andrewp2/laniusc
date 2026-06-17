use super::*;

mod dependency_edges;
pub(in crate::compiler) use dependency_edges::*;

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct WorkQueuePrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) next_item_index: usize,
}

pub(in crate::compiler) fn validate_work_queue_prepare_progress(
    progress: &WorkQueuePrepareProgress,
    target: SourcePackArtifactTarget,
    work_item_count: usize,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.work_item_count != work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue prepare progress item count {} does not match expected {work_item_count}",
            progress.work_item_count
        )));
    }
    if progress.next_item_index > work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue prepare progress next item {} exceeds item count {work_item_count}",
            progress.next_item_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_work_queue_pages_from_schedule_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    max_new_items: usize,
) -> Result<FilesystemWorkQueuePrepareStepResult, CompileError> {
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue chunk max_new_items must be greater than zero".into(),
        ));
    }
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_link_plan_index(link_plan_index, schedule_index.target)?;
    if schedule_index.link_job_index != link_plan_index.first_link_job_index {
        return Err(library_partition_contract_error(format!(
            "work queue chunk first link job {} does not match schedule link job {}",
            link_plan_index.first_link_job_index, schedule_index.link_job_index
        )));
    }
    let final_item_index = link_plan_index.final_link_job_index;
    let work_item_count = final_item_index.saturating_add(1);
    let artifact_item_count = library_schedule_index_frontend_job_count(schedule_index)
        .saturating_add(schedule_index.codegen_job_count);
    if store
        .work_queue_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_work_queue_index_for_target(schedule_index.target)?;
        return Ok(FilesystemWorkQueuePrepareStepResult {
            target: schedule_index.target,
            complete: true,
            work_item_count: index.work_item_count,
            artifact_item_count: index.artifact_item_count,
            next_item_index: index.work_item_count,
            new_work_item_count: 0,
            work_queue_index_path: Some(
                store.work_queue_index_path_for_target(schedule_index.target),
            ),
        });
    }

    let progress_path = store.work_queue_prepare_progress_path_for_target(schedule_index.target);
    let mut progress = if progress_path.is_file() {
        load_work_queue_prepare_progress(store, schedule_index.target, work_item_count)?
    } else {
        WorkQueuePrepareProgress {
            version: SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            work_item_count,
            next_item_index: 0,
        }
    };
    validate_work_queue_prepare_progress(&progress, schedule_index.target, work_item_count)?;

    let job_batch_page_index =
        store.load_build_job_batch_page_index_for_target(schedule_index.target)?;
    if job_batch_page_index.scheduled_job_count != schedule_index.job_count {
        return Err(library_partition_contract_error(format!(
            "work queue chunk job-batch page index records {} scheduled jobs but schedule index records {}",
            job_batch_page_index.scheduled_job_count, schedule_index.job_count
        )));
    }
    let mut new_work_item_count = 0usize;
    while progress.next_item_index < work_item_count && new_work_item_count < max_new_items {
        store_work_queue_page_for_stored_item_index(
            store,
            schedule_index,
            link_plan_index,
            &job_batch_page_index,
            progress.next_item_index,
            work_item_count,
        )?;
        progress.next_item_index = progress.next_item_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("work queue chunk next item index overflows")
        })?;
        new_work_item_count = new_work_item_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("work queue chunk new item count overflows")
        })?;
        store_work_queue_prepare_progress(store, &progress)?;
    }

    let mut work_queue_index_path = None;
    if progress.next_item_index == work_item_count {
        let index = SourcePackWorkQueueIndex {
            version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
            target: schedule_index.target,
            work_item_count,
            artifact_item_count,
            final_item_index,
            final_job_index: link_plan_index.final_link_job_index,
        };
        validate_work_queue_index(&index, schedule_index.target)?;
        work_queue_index_path = Some(store_work_queue_compact_index(store, &index)?);
    }

    Ok(FilesystemWorkQueuePrepareStepResult {
        target: schedule_index.target,
        complete: work_queue_index_path.is_some(),
        work_item_count,
        artifact_item_count,
        next_item_index: progress.next_item_index,
        new_work_item_count,
        work_queue_index_path,
    })
}

pub(in crate::compiler) fn store_work_queue_page_for_stored_item_index(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    item_index: usize,
    work_item_count: usize,
) -> Result<SourcePackWorkQueuePage, CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_link_plan_index(link_plan_index, schedule_index.target)?;
    if item_index < schedule_index.link_job_index {
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            item_index,
            schedule_index.job_count,
        )?;
        let partition_index = locator.partition_index.ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue chunk item {item_index} has no partition"
            ))
        })?;
        let schedule_page =
            store.load_library_schedule_page_for_target(schedule_index.target, partition_index)?;
        validate_library_schedule_page(
            &schedule_page,
            schedule_index.target,
            Some(partition_index),
        )?;
        let job = stored_schedule_job_metadata(store, schedule_index, item_index)?;
        let kind = match job.phase {
            SourcePackJobPhase::LibraryFrontend => SourcePackWorkQueueItemKind::LibraryFrontend,
            SourcePackJobPhase::Codegen => SourcePackWorkQueueItemKind::Codegen,
            SourcePackJobPhase::Link => {
                return Err(library_partition_contract_error(format!(
                    "work queue chunk item {item_index} is link job before link group range"
                )));
            }
        };
        let page = SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target: schedule_index.target,
            item_index: job.job_index,
            kind,
            job_index: job.job_index,
            dependency_item_indices: Vec::new(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: singleton_batch_for_job(
                store,
                schedule_index.target,
                job_batch_page_index,
                job.job_index,
            )?,
            partition_count: 1,
            partition_indices: vec![schedule_page.partition_index],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: job.source_bytes,
            source_file_count: job.source_file_count,
            source_line_count: job.source_lines,
        };
        return store_work_queue_page_with_dependency_writer(
            store,
            &page,
            work_item_count,
            |writer| {
                write_work_queue_dependencies_from_stored_schedule_job(
                    store,
                    schedule_index,
                    job.job_index,
                    writer,
                )
            },
        );
    }

    let group_index = item_index
        .checked_sub(link_plan_index.first_link_job_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "work queue chunk item {item_index} precedes first link job {}",
                link_plan_index.first_link_job_index
            ))
        })?;
    let group =
        store.load_hierarchical_link_group_page_for_target(link_plan_index.target, group_index)?;
    validate_link_group_page(&group, link_plan_index.target, Some(group_index))?;
    if group.job_index != item_index {
        return Err(library_partition_contract_error(format!(
            "work queue chunk link group {group_index} has job {} but item is {item_index}",
            group.job_index
        )));
    }
    let kind = match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => SourcePackWorkQueueItemKind::LinkLeaf,
        SourcePackHierarchicalLinkGroupKind::Reduce => SourcePackWorkQueueItemKind::LinkReduce,
    };
    let page = SourcePackWorkQueuePage {
        version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
        target: link_plan_index.target,
        item_index: group.job_index,
        kind,
        job_index: group.job_index,
        dependency_item_indices: Vec::new(),
        dependency_item_count: 0,
        dependency_page_count: 0,
        dependency_item_ranges: Vec::new(),
        dependent_item_indices: Vec::new(),
        dependent_item_count: 0,
        dependent_page_count: 0,
        dependent_item_ranges: Vec::new(),
        artifact_batch_index: None,
        partition_count: hierarchical_link_group_input_partition_count(&group),
        partition_indices: if matches!(group.kind, SourcePackHierarchicalLinkGroupKind::Leaf) {
            group.input_partition_indices.clone()
        } else {
            Vec::new()
        },
        link_group_index: Some(group.group_index),
        input_frontend_job_count: hierarchical_link_group_input_frontend_job_count(&group),
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: group.input_codegen_job_indices.len(),
        input_codegen_job_indices: group.input_codegen_job_indices.clone(),
        input_link_group_count: group.input_link_group_indices.len(),
        input_link_group_indices: group.input_link_group_indices.clone(),
        source_byte_count: group.source_byte_count,
        source_file_count: group.source_file_count,
        source_line_count: group.source_line_count,
    };
    store_work_queue_page_with_dependency_writer(store, &page, work_item_count, |writer| {
        match group.kind {
            SourcePackHierarchicalLinkGroupKind::Leaf => {
                let Some(&first_codegen_job_index) = group.input_codegen_job_indices.first() else {
                    return Err(library_partition_contract_error(format!(
                        "stored work queue link group {} has no codegen jobs",
                        group.group_index
                    )));
                };
                write_work_queue_dependencies_from_stored_schedule_job(
                    store,
                    schedule_index,
                    first_codegen_job_index,
                    writer,
                )?;
                for &codegen_job_index in &group.input_codegen_job_indices {
                    writer.push(codegen_job_index)?;
                }
            }
            SourcePackHierarchicalLinkGroupKind::Reduce => {
                for &input_group_index in &group.input_link_group_indices {
                    let input_item_index = link_plan_index
                        .first_link_job_index
                        .checked_add(input_group_index)
                        .ok_or_else(|| {
                            library_partition_contract_error(format!(
                                "stored work queue link group {} input group {} overflows job index",
                                group.group_index, input_group_index
                            ))
                        })?;
                    writer.push(input_item_index)?;
                }
            }
        }
        Ok(())
    })
}

pub(in crate::compiler) fn store_work_queue_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &WorkQueuePrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_work_queue_prepare_progress(progress, progress.target, progress.work_item_count)?;
    let path = store.work_queue_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack work queue prepare progress: {err}"
        ))
    })?;
    write_file_atomic(&path, &bytes, "source-pack work queue prepare progress")?;
    Ok(path)
}

pub(in crate::compiler) fn load_work_queue_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    work_item_count: usize,
) -> Result<WorkQueuePrepareProgress, CompileError> {
    let path = store.work_queue_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack work queue prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<WorkQueuePrepareProgress>(&bytes).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "parse source-pack work queue prepare progress {}: {err}",
            path.display()
        ))
    })?;
    validate_work_queue_prepare_progress(&progress, target, work_item_count)?;
    Ok(progress)
}

pub(in crate::compiler) fn singleton_batch_for_job(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildJobBatchPageIndex,
    job_index: usize,
) -> Result<Option<usize>, CompileError> {
    validate_job_batch_page_index(index, target)?;
    if job_index >= index.scheduled_job_count {
        return Err(artifact_shard_contract_error(format!(
            "work queue job {job_index} exceeds scheduled job count {}",
            index.scheduled_job_count
        )));
    }
    let locator = store.load_build_job_batch_job_locator_page_for_target(
        target,
        job_index,
        index.scheduled_job_count,
    )?;
    if locator.batch_index >= index.batch_count {
        return Err(artifact_shard_contract_error(format!(
            "work queue job {job_index} locator points at missing batch {}",
            locator.batch_index
        )));
    }
    let page = store.load_build_job_batch_page_for_target(target, locator.batch_index)?;
    if !page.batch.job_indices.contains(&job_index) {
        return Err(artifact_shard_contract_error(format!(
            "work queue job {job_index} locator points at batch {} with jobs {:?}",
            locator.batch_index, page.batch.job_indices
        )));
    }
    Ok(match page.batch.job_indices.as_slice() {
        [single_job_index] if *single_job_index == job_index => Some(locator.batch_index),
        _ => None,
    })
}
