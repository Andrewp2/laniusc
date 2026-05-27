use super::*;

#[cfg(test)]
pub(in crate::compiler) fn source_pack_work_queue(
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    link_group_pages: &[SourcePackHierarchicalLinkGroupPage],
) -> Result<(SourcePackWorkQueueIndex, Vec<SourcePackWorkQueuePage>), CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, schedule_index.target)?;
    if schedule_pages.len() != schedule_index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue has {} schedule pages but schedule index partition_count {}",
            schedule_pages.len(),
            schedule_index.partition_count
        )));
    }
    if link_group_pages.len() != link_plan_index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue has {} link group pages but link plan group count {}",
            link_group_pages.len(),
            link_plan_index.link_group_count
        )));
    }

    let final_item_index = link_plan_index.final_link_job_index;
    let mut pages = vec![None; final_item_index.saturating_add(1)];
    for schedule_page in schedule_pages {
        validate_source_pack_library_schedule_page(
            schedule_page,
            schedule_index.target,
            Some(schedule_page.partition_index),
        )?;
        let frontend_page = SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target: schedule_index.target,
            item_index: schedule_page.frontend_job.job_index,
            kind: SourcePackWorkQueueItemKind::LibraryFrontend,
            job_index: schedule_page.frontend_job.job_index,
            dependency_item_indices: schedule_page.frontend_job.dependency_job_indices.clone(),
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: 1,
            partition_indices: vec![schedule_page.partition_index],
            link_group_index: None,
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_count: 0,
            input_codegen_job_indices: Vec::new(),
            input_link_group_count: 0,
            input_link_group_indices: Vec::new(),
            source_byte_count: schedule_page.frontend_job.source_bytes,
            source_file_count: schedule_page.frontend_job.source_file_count,
            source_line_count: schedule_page.frontend_job.source_lines,
        };
        source_pack_insert_work_queue_page(&mut pages, frontend_page)?;

        for job in &schedule_page.codegen_jobs {
            let codegen_page = SourcePackWorkQueuePage {
                version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
                target: schedule_index.target,
                item_index: job.job_index,
                kind: SourcePackWorkQueueItemKind::Codegen,
                job_index: job.job_index,
                dependency_item_indices: job.dependency_job_indices.clone(),
                dependency_item_count: 0,
                dependency_page_count: 0,
                dependency_item_ranges: Vec::new(),
                dependent_item_indices: Vec::new(),
                dependent_item_count: 0,
                dependent_page_count: 0,
                dependent_item_ranges: Vec::new(),
                artifact_batch_index: None,
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
            source_pack_insert_work_queue_page(&mut pages, codegen_page)?;
        }
    }

    for group in link_group_pages {
        validate_source_pack_hierarchical_link_group_page(
            group,
            link_plan_index.target,
            Some(group.group_index),
        )?;
        let (kind, dependency_item_indices) = match group.kind {
            SourcePackHierarchicalLinkGroupKind::Leaf => {
                let mut dependencies = group.input_frontend_job_indices.clone();
                dependencies.extend(group.input_codegen_job_indices.iter().copied());
                dependencies.sort_unstable();
                dependencies.dedup();
                (SourcePackWorkQueueItemKind::LinkLeaf, dependencies)
            }
            SourcePackHierarchicalLinkGroupKind::Reduce => {
                let dependencies = group
                    .input_link_group_indices
                    .iter()
                    .map(|input_group_index| {
                        link_plan_index
                            .first_link_job_index
                            .checked_add(*input_group_index)
                            .ok_or_else(|| {
                                source_pack_library_partition_contract_error(format!(
                                    "work queue link group {} input group {} overflows job index",
                                    group.group_index, input_group_index
                                ))
                            })
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                (SourcePackWorkQueueItemKind::LinkReduce, dependencies)
            }
        };
        let link_page = SourcePackWorkQueuePage {
            version: SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
            target: link_plan_index.target,
            item_index: group.job_index,
            kind,
            job_index: group.job_index,
            dependency_item_indices,
            dependency_item_count: 0,
            dependency_page_count: 0,
            dependency_item_ranges: Vec::new(),
            dependent_item_indices: Vec::new(),
            dependent_item_count: 0,
            dependent_page_count: 0,
            dependent_item_ranges: Vec::new(),
            artifact_batch_index: None,
            partition_count: source_pack_hierarchical_link_group_input_partition_count(group),
            partition_indices: group.input_partition_indices.clone(),
            link_group_index: Some(group.group_index),
            input_frontend_job_count: group.input_frontend_job_indices.len(),
            input_frontend_job_indices: group.input_frontend_job_indices.clone(),
            input_codegen_job_count: group.input_codegen_job_indices.len(),
            input_codegen_job_indices: group.input_codegen_job_indices.clone(),
            input_link_group_count: group.input_link_group_indices.len(),
            input_link_group_indices: group.input_link_group_indices.clone(),
            source_byte_count: group.source_byte_count,
            source_file_count: group.source_file_count,
            source_line_count: group.source_line_count,
        };
        source_pack_insert_work_queue_page(&mut pages, link_page)?;
    }

    let mut pages = pages
        .into_iter()
        .enumerate()
        .map(|(item_index, page)| {
            page.ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "work queue missing item page {item_index}"
                ))
            })
        })
        .collect::<Result<Vec<_>, _>>()?;
    let dependents_by_item = source_pack_work_queue_dependents_by_item(&pages)?;
    for (page, dependent_item_indices) in pages.iter_mut().zip(dependents_by_item) {
        page.dependent_item_indices = dependent_item_indices;
        validate_source_pack_work_queue_page(page, page.target, Some(page.item_index))?;
    }
    let index = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target: schedule_index.target,
        work_item_count: pages.len(),
        artifact_item_count: source_pack_work_queue_artifact_item_count_from_pages(&pages),
        final_item_index,
        final_job_index: link_plan_index.final_link_job_index,
    };
    validate_source_pack_work_queue_index(&index, schedule_index.target)?;
    Ok((index, pages))
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackWorkQueuePrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) next_item_index: usize,
}

pub(in crate::compiler) fn validate_source_pack_work_queue_prepare_progress(
    progress: &SourcePackWorkQueuePrepareProgress,
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.work_item_count != work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue prepare progress item count {} does not match expected {work_item_count}",
            progress.work_item_count
        )));
    }
    if progress.next_item_index > work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue prepare progress next item {} exceeds item count {work_item_count}",
            progress.next_item_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_work_queue_pages_from_stored_schedule_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    max_new_items: usize,
) -> Result<SourcePackFilesystemWorkQueuePrepareStepResult, CompileError> {
    if max_new_items == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue chunk max_new_items must be greater than zero".into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, schedule_index.target)?;
    if schedule_index.link_job_index != link_plan_index.first_link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue chunk first link job {} does not match schedule link job {}",
            link_plan_index.first_link_job_index, schedule_index.link_job_index
        )));
    }
    let final_item_index = link_plan_index.final_link_job_index;
    let work_item_count = final_item_index.saturating_add(1);
    let artifact_item_count = source_pack_library_schedule_index_frontend_job_count(schedule_index)
        .saturating_add(schedule_index.codegen_job_count);
    if store
        .work_queue_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_work_queue_index_for_target(schedule_index.target)?;
        return Ok(SourcePackFilesystemWorkQueuePrepareStepResult {
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
        source_pack_load_work_queue_prepare_progress(store, schedule_index.target, work_item_count)?
    } else {
        SourcePackWorkQueuePrepareProgress {
            version: SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            work_item_count,
            next_item_index: 0,
        }
    };
    validate_source_pack_work_queue_prepare_progress(
        &progress,
        schedule_index.target,
        work_item_count,
    )?;

    let job_batch_page_index =
        store.load_build_job_batch_page_index_for_target(schedule_index.target)?;
    if job_batch_page_index.scheduled_job_count != schedule_index.job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue chunk job-batch page index records {} scheduled jobs but schedule index records {}",
            job_batch_page_index.scheduled_job_count, schedule_index.job_count
        )));
    }
    let mut new_work_item_count = 0usize;
    while progress.next_item_index < work_item_count && new_work_item_count < max_new_items {
        source_pack_store_work_queue_page_for_stored_item_index(
            store,
            schedule_index,
            link_plan_index,
            &job_batch_page_index,
            progress.next_item_index,
            work_item_count,
        )?;
        progress.next_item_index = progress.next_item_index.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "work queue chunk next item index overflows",
            )
        })?;
        new_work_item_count = new_work_item_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "work queue chunk new item count overflows",
            )
        })?;
        source_pack_store_work_queue_prepare_progress(store, &progress)?;
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
        validate_source_pack_work_queue_index(&index, schedule_index.target)?;
        work_queue_index_path = Some(store_source_pack_work_queue_compact_index(store, &index)?);
    }

    Ok(SourcePackFilesystemWorkQueuePrepareStepResult {
        target: schedule_index.target,
        complete: work_queue_index_path.is_some(),
        work_item_count,
        artifact_item_count,
        next_item_index: progress.next_item_index,
        new_work_item_count,
        work_queue_index_path,
    })
}

pub(in crate::compiler) fn source_pack_store_work_queue_page_for_stored_item_index(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    job_batch_page_index: &SourcePackBuildJobBatchPageIndex,
    item_index: usize,
    work_item_count: usize,
) -> Result<SourcePackWorkQueuePage, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, schedule_index.target)?;
    if item_index < schedule_index.link_job_index {
        let locator = store.load_library_schedule_job_locator_page_for_target(
            schedule_index.target,
            item_index,
            schedule_index.job_count,
        )?;
        let partition_index = locator.partition_index.ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue chunk item {item_index} has no partition"
            ))
        })?;
        let schedule_page =
            store.load_library_schedule_page_for_target(schedule_index.target, partition_index)?;
        validate_source_pack_library_schedule_page(
            &schedule_page,
            schedule_index.target,
            Some(partition_index),
        )?;
        let job = source_pack_stored_schedule_job_metadata(store, schedule_index, item_index)?;
        let kind = match job.phase {
            SourcePackJobPhase::LibraryFrontend => SourcePackWorkQueueItemKind::LibraryFrontend,
            SourcePackJobPhase::Codegen => SourcePackWorkQueueItemKind::Codegen,
            SourcePackJobPhase::Link => {
                return Err(source_pack_library_partition_contract_error(format!(
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
            artifact_batch_index:
                source_pack_singleton_artifact_batch_index_for_job_from_stored_locator(
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
        return store_source_pack_work_queue_page_with_dependency_writer(
            store,
            &page,
            work_item_count,
            |writer| {
                source_pack_write_work_queue_dependencies_from_stored_schedule_job(
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
            source_pack_library_partition_contract_error(format!(
                "work queue chunk item {item_index} precedes first link job {}",
                link_plan_index.first_link_job_index
            ))
        })?;
    let group =
        store.load_hierarchical_link_group_page_for_target(link_plan_index.target, group_index)?;
    validate_source_pack_hierarchical_link_group_page(
        &group,
        link_plan_index.target,
        Some(group_index),
    )?;
    if group.job_index != item_index {
        return Err(source_pack_library_partition_contract_error(format!(
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
        partition_count: source_pack_hierarchical_link_group_input_partition_count(&group),
        partition_indices: if matches!(group.kind, SourcePackHierarchicalLinkGroupKind::Leaf) {
            group.input_partition_indices.clone()
        } else {
            Vec::new()
        },
        link_group_index: Some(group.group_index),
        input_frontend_job_count: source_pack_hierarchical_link_group_input_frontend_job_count(
            &group,
        ),
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_count: group.input_codegen_job_indices.len(),
        input_codegen_job_indices: group.input_codegen_job_indices.clone(),
        input_link_group_count: group.input_link_group_indices.len(),
        input_link_group_indices: group.input_link_group_indices.clone(),
        source_byte_count: group.source_byte_count,
        source_file_count: group.source_file_count,
        source_line_count: group.source_line_count,
    };
    store_source_pack_work_queue_page_with_dependency_writer(
        store,
        &page,
        work_item_count,
        |writer| {
            match group.kind {
                SourcePackHierarchicalLinkGroupKind::Leaf => {
                    let Some(&first_codegen_job_index) = group.input_codegen_job_indices.first()
                    else {
                        return Err(source_pack_library_partition_contract_error(format!(
                            "stored work queue link group {} has no codegen jobs",
                            group.group_index
                        )));
                    };
                    source_pack_write_work_queue_dependencies_from_stored_schedule_job(
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
                            source_pack_library_partition_contract_error(format!(
                                "stored work queue link group {} input group {} overflows job index",
                                group.group_index, input_group_index
                            ))
                        })?;
                        writer.push(input_item_index)?;
                    }
                }
            }
            Ok(())
        },
    )
}

pub(in crate::compiler) fn source_pack_store_work_queue_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackWorkQueuePrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_work_queue_prepare_progress(
        progress,
        progress.target,
        progress.work_item_count,
    )?;
    let path = store.work_queue_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack work queue prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack work queue prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_work_queue_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    work_item_count: usize,
) -> Result<SourcePackWorkQueuePrepareProgress, CompileError> {
    let path = store.work_queue_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack work queue prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<SourcePackWorkQueuePrepareProgress>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack work queue prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_source_pack_work_queue_prepare_progress(&progress, target, work_item_count)?;
    Ok(progress)
}

pub(in crate::compiler) fn source_pack_write_work_queue_dependencies_from_stored_schedule_job(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
    writer: &mut SourcePackWorkQueueDependencyPageWriter<'_>,
) -> Result<(), CompileError> {
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    source_pack_for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| writer.push(dependency_job_index),
    )?;
    for range in &job_page.dependency_job_ranges {
        writer.push_range(range.first_job_index, range.job_count)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_singleton_artifact_batch_index_for_job_from_stored_locator(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    index: &SourcePackBuildJobBatchPageIndex,
    job_index: usize,
) -> Result<Option<usize>, CompileError> {
    validate_source_pack_build_job_batch_page_index(index, target)?;
    if job_index >= index.scheduled_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "work queue job {job_index} locator points at missing batch {}",
            locator.batch_index
        )));
    }
    let page = store.load_build_job_batch_page_for_target(target, locator.batch_index)?;
    if !page.batch.job_indices.contains(&job_index) {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "work queue job {job_index} locator points at batch {} with jobs {:?}",
            locator.batch_index, page.batch.job_indices
        )));
    }
    Ok(match page.batch.job_indices.as_slice() {
        [single_job_index] if *single_job_index == job_index => Some(locator.batch_index),
        _ => None,
    })
}

pub(in crate::compiler) fn source_pack_work_queue_append_dependent_page(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency_item_index: usize,
    dependent_item_index: usize,
    work_item_count: usize,
) -> Result<(), CompileError> {
    if dependency_item_index >= work_item_count || dependent_item_index >= work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent edge {dependency_item_index}->{dependent_item_index} exceeds item count {work_item_count}"
        )));
    }
    if dependent_item_index <= dependency_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent edge {dependency_item_index}->{dependent_item_index} is not forward"
        )));
    }
    let mut dependency_page =
        store.load_work_queue_page_for_target(target, dependency_item_index)?;
    if !dependency_page.dependent_item_indices.is_empty() {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {dependency_item_index} mixes inline dependents with stored dependent pages"
        )));
    }
    if dependency_page.dependent_item_ranges.iter().any(|range| {
        range
            .iter()
            .is_some_and(|indices| indices.contains(&dependent_item_index))
    }) {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {dependency_item_index} contains duplicate ranged dependent item {dependent_item_index}"
        )));
    }

    let dependent_position = dependency_page.dependent_item_count;
    let page_index = dependent_position / SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE;
    let is_new_dependents_page =
        dependent_position % SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE == 0;
    let mut dependents_page = if is_new_dependents_page {
        SourcePackWorkQueueDependentsPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
            target,
            item_index: dependency_item_index,
            page_index,
            first_dependent_position: page_index
                .saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE),
            dependent_count: 0,
            dependent_item_indices: Vec::new(),
        }
    } else {
        store.load_work_queue_dependents_page_for_target(
            target,
            dependency_item_index,
            page_index,
        )?
    };

    dependents_page
        .dependent_item_indices
        .push(dependent_item_index);
    dependents_page.dependent_count = dependents_page.dependent_item_indices.len();
    validate_source_pack_work_queue_dependents_page(
        &dependents_page,
        target,
        dependency_item_index,
        page_index,
    )?;
    store.store_work_queue_dependents_page(&dependents_page)?;

    dependency_page.dependent_item_count = dependency_page.dependent_item_count.saturating_add(1);
    dependency_page.dependent_page_count = dependency_page
        .dependent_item_count
        .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
    validate_source_pack_work_queue_page(&dependency_page, target, Some(dependency_item_index))?;
    store.store_work_queue_page(&dependency_page)?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_work_queue_try_append_dependent_range(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    dependency_item_index: usize,
    first_dependent_item_index: usize,
    dependent_item_count: usize,
    work_item_count: usize,
) -> Result<bool, CompileError> {
    if dependent_item_count == 0 {
        return Ok(true);
    }
    let end_dependent_item_index =
        first_dependent_item_index
            .checked_add(dependent_item_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "work queue dependent range {dependency_item_index}->{first_dependent_item_index}+{dependent_item_count} overflows"
                ))
            })?;
    if dependency_item_index >= work_item_count || end_dependent_item_index > work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent range {dependency_item_index}->{first_dependent_item_index}..{end_dependent_item_index} exceeds item count {work_item_count}"
        )));
    }
    if first_dependent_item_index <= dependency_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependent range {dependency_item_index}->{first_dependent_item_index}..{end_dependent_item_index} is not forward"
        )));
    }
    let mut dependency_page =
        store.load_work_queue_page_for_target(target, dependency_item_index)?;
    if !dependency_page.dependent_item_indices.is_empty() {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {dependency_item_index} mixes inline dependents with stored dependent ranges"
        )));
    }
    if let Some(range) = dependency_page.dependent_item_ranges.iter().find(|range| {
        range.end_job_index().is_some_and(|range_end| {
            first_dependent_item_index < range_end
                && range.first_job_index < end_dependent_item_index
        })
    }) {
        let duplicate_end = range
            .end_job_index()
            .unwrap_or(range.first_job_index.saturating_add(range.job_count));
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {dependency_item_index} dependent range {first_dependent_item_index}..{end_dependent_item_index} overlaps existing range {}..{}",
            range.first_job_index, duplicate_end
        )));
    }
    if !source_pack_try_push_dependent_item_range(
        &mut dependency_page.dependent_item_ranges,
        dependency_item_index,
        first_dependent_item_index,
        dependent_item_count,
    )? {
        return Ok(false);
    }
    validate_source_pack_work_queue_page(&dependency_page, target, Some(dependency_item_index))?;
    store.store_work_queue_page(&dependency_page)?;
    Ok(true)
}

pub(in crate::compiler) fn source_pack_append_work_queue_dependent_range_to_dependency_range(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    first_dependency_item_index: usize,
    dependency_item_count: usize,
    first_dependent_item_index: usize,
    dependent_item_count: usize,
    work_item_count: usize,
) -> Result<(), CompileError> {
    if dependency_item_count == 0 || dependent_item_count == 0 {
        return Ok(());
    }
    let dependency_end = first_dependency_item_index
        .checked_add(dependency_item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue reverse dependency range {first_dependency_item_index}+{dependency_item_count} overflows"
            ))
        })?;
    let dependent_end = first_dependent_item_index
        .checked_add(dependent_item_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue reverse dependent range {first_dependent_item_index}+{dependent_item_count} overflows"
            ))
        })?;
    if dependency_end > work_item_count || dependent_end > work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue reverse range dependencies {}..{} dependents {}..{} exceed item count {}",
            first_dependency_item_index,
            dependency_end,
            first_dependent_item_index,
            dependent_end,
            work_item_count
        )));
    }

    for dependency_item_index in first_dependency_item_index..dependency_end {
        if source_pack_work_queue_try_append_dependent_range(
            store,
            target,
            dependency_item_index,
            first_dependent_item_index,
            dependent_item_count,
            work_item_count,
        )? {
            continue;
        }
        for dependent_item_index in first_dependent_item_index..dependent_end {
            source_pack_work_queue_append_dependent_page(
                store,
                target,
                dependency_item_index,
                dependent_item_index,
                work_item_count,
            )?;
        }
    }
    Ok(())
}

pub(in crate::compiler) struct SourcePackWorkQueueDependencyPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) item_index: usize,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_item_count: usize,
    pub(in crate::compiler) dependency_item_ranges: Vec<SourcePackJobIndexRange>,
    pub(in crate::compiler) seen_dependency_item_indices: BTreeSet<usize>,
    pub(in crate::compiler) current_dependency_item_indices: Vec<usize>,
}

impl<'a> SourcePackWorkQueueDependencyPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        item_index: usize,
        work_item_count: usize,
    ) -> Self {
        Self {
            store,
            target,
            item_index,
            work_item_count,
            page_index: 0,
            first_dependency_position: 0,
            dependency_item_count: 0,
            dependency_item_ranges: Vec::new(),
            seen_dependency_item_indices: BTreeSet::new(),
            current_dependency_item_indices: Vec::with_capacity(
                SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    pub(in crate::compiler) fn push(
        &mut self,
        dependency_item_index: usize,
    ) -> Result<(), CompileError> {
        self.push_impl(dependency_item_index, true)
    }

    pub(in crate::compiler) fn push_impl(
        &mut self,
        dependency_item_index: usize,
        record_reverse_dependent: bool,
    ) -> Result<(), CompileError> {
        if dependency_item_index >= self.item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} depends on non-prior item {}",
                self.item_index, dependency_item_index
            )));
        }
        if self.dependency_item_ranges.iter().any(|range| {
            range
                .iter()
                .is_some_and(|indices| indices.contains(&dependency_item_index))
        }) {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} contains duplicate ranged dependency item {}",
                self.item_index, dependency_item_index
            )));
        }
        if !self
            .seen_dependency_item_indices
            .insert(dependency_item_index)
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} contains duplicate dependency item {}",
                self.item_index, dependency_item_index
            )));
        }
        self.current_dependency_item_indices
            .push(dependency_item_index);
        if self.current_dependency_item_indices.len()
            == SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        if record_reverse_dependent {
            source_pack_work_queue_append_dependent_page(
                self.store,
                self.target,
                dependency_item_index,
                self.item_index,
                self.work_item_count,
            )?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_item_indices.is_empty() {
            return Ok(());
        }
        let dependency_item_indices = std::mem::take(&mut self.current_dependency_item_indices);
        let dependency_page = SourcePackWorkQueueDependenciesPage {
            version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
            target: self.target,
            item_index: self.item_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_item_indices.len(),
            dependency_item_indices,
        };
        validate_source_pack_work_queue_dependencies_page(
            &dependency_page,
            self.target,
            self.item_index,
            self.page_index,
        )?;
        self.store
            .store_work_queue_dependencies_page(&dependency_page)?;
        self.dependency_item_count = self
            .dependency_item_count
            .saturating_add(dependency_page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(dependency_page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    pub(in crate::compiler) fn push_range(
        &mut self,
        first_item_index: usize,
        item_count: usize,
    ) -> Result<(), CompileError> {
        self.push_range_impl(first_item_index, item_count, true)
    }

    pub(in crate::compiler) fn push_range_impl(
        &mut self,
        first_item_index: usize,
        item_count: usize,
        record_reverse_dependents: bool,
    ) -> Result<(), CompileError> {
        if item_count == 0 {
            return Ok(());
        }
        let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "work queue page {} dependency item range {}+{} overflows",
                self.item_index, first_item_index, item_count
            ))
        })?;
        if end_item_index > self.item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} depends on non-prior item range {}..{}",
                self.item_index, first_item_index, end_item_index
            )));
        }
        if let Some(duplicate) = self
            .seen_dependency_item_indices
            .range(first_item_index..end_item_index)
            .next()
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} dependency range {}..{} duplicates explicit dependency item {}",
                self.item_index, first_item_index, end_item_index, duplicate
            )));
        }
        if source_pack_try_push_dependency_item_range(
            &mut self.dependency_item_ranges,
            self.item_index,
            first_item_index,
            item_count,
        )? {
            if record_reverse_dependents {
                source_pack_append_work_queue_dependent_range_to_dependency_range(
                    self.store,
                    self.target,
                    first_item_index,
                    item_count,
                    self.item_index,
                    1,
                    self.work_item_count,
                )?;
            }
            return Ok(());
        }

        for dependency_item_index in first_item_index..end_item_index {
            self.push_impl(dependency_item_index, record_reverse_dependents)?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        mut self,
    ) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
        self.flush()?;
        Ok((
            self.dependency_item_count,
            self.page_index,
            self.dependency_item_ranges,
        ))
    }
}

pub(in crate::compiler) fn source_pack_try_push_dependency_item_range(
    dependency_item_ranges: &mut Vec<SourcePackJobIndexRange>,
    item_index: usize,
    first_item_index: usize,
    item_count: usize,
) -> Result<bool, CompileError> {
    let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue page {item_index} dependency item range {first_item_index}+{item_count} overflows"
        ))
    })?;
    if end_item_index > item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {item_index} depends on non-prior item range {first_item_index}..{end_item_index}"
        )));
    }

    let mut merged_ranges = dependency_item_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index: first_item_index,
        job_count: item_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {item_index} dependency item range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue page {item_index} dependency item range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependency_item_ranges = compact_ranges;
    Ok(true)
}

pub(in crate::compiler) fn source_pack_try_push_dependent_item_range(
    dependent_item_ranges: &mut Vec<SourcePackJobIndexRange>,
    item_index: usize,
    first_item_index: usize,
    item_count: usize,
) -> Result<bool, CompileError> {
    let end_item_index = first_item_index.checked_add(item_count).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue page {item_index} dependent item range {first_item_index}+{item_count} overflows"
        ))
    })?;
    if first_item_index <= item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {item_index} has non-later dependent item range {first_item_index}..{end_item_index}"
        )));
    }

    let mut merged_ranges = dependent_item_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index: first_item_index,
        job_count: item_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {item_index} dependent item range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue page {item_index} dependent item range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependent_item_ranges = compact_ranges;
    Ok(true)
}

pub(in crate::compiler) fn store_source_pack_work_queue_page_with_dependency_writer<F>(
    store: &SourcePackFilesystemArtifactStore,
    page: &SourcePackWorkQueuePage,
    work_item_count: usize,
    mut write_dependencies: F,
) -> Result<SourcePackWorkQueuePage, CompileError>
where
    F: FnMut(&mut SourcePackWorkQueueDependencyPageWriter<'_>) -> Result<(), CompileError>,
{
    validate_source_pack_work_queue_page(page, page.target, Some(page.item_index))?;
    if page.item_index >= work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored work queue page {} exceeds item count {}",
            page.item_index, work_item_count
        )));
    }
    let mut writer = SourcePackWorkQueueDependencyPageWriter::new(
        store,
        page.target,
        page.item_index,
        work_item_count,
    );
    write_dependencies(&mut writer)?;
    let (dependency_item_count, dependency_page_count, dependency_item_ranges) = writer.finish()?;
    let mut stored_page = page.clone();
    stored_page.dependency_item_indices.clear();
    stored_page.dependency_item_count = dependency_item_count;
    stored_page.dependency_page_count = dependency_page_count;
    stored_page.dependency_item_ranges = dependency_item_ranges;
    stored_page.dependent_item_indices.clear();
    stored_page.dependent_item_count = 0;
    stored_page.dependent_page_count = 0;
    stored_page.dependent_item_ranges.clear();
    validate_source_pack_work_queue_page(&stored_page, page.target, Some(page.item_index))?;
    store.store_work_queue_page(&stored_page)?;
    Ok(stored_page)
}

#[cfg(test)]
pub(in crate::compiler) struct SourcePackInitialWorkQueueProgressPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) page_size: usize,
    pub(in crate::compiler) next_item_index: usize,
    pub(in crate::compiler) current_page_index: usize,
    pub(in crate::compiler) current_first_item_index: usize,
    pub(in crate::compiler) current_artifact_item_indices: Vec<usize>,
    pub(in crate::compiler) current_ready_item_indices: Vec<usize>,
    pub(in crate::compiler) current_ready_artifact_item_indices: Vec<usize>,
    pub(in crate::compiler) current_remaining_dependency_counts:
        Vec<SourcePackWorkQueueRemainingDependencyCount>,
    pub(in crate::compiler) current_remaining_dependent_counts:
        Vec<SourcePackWorkQueueRemainingDependentCount>,
    pub(in crate::compiler) artifact_item_count: usize,
    pub(in crate::compiler) ready_item_count: usize,
    pub(in crate::compiler) ready_artifact_item_count: usize,
    pub(in crate::compiler) first_ready_item_index: Option<usize>,
    pub(in crate::compiler) first_ready_artifact_item_index: Option<usize>,
}

#[cfg(test)]
impl<'a> SourcePackInitialWorkQueueProgressPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        work_item_count: usize,
        page_size: usize,
    ) -> Self {
        Self {
            store,
            target,
            work_item_count,
            page_size: page_size.max(1),
            next_item_index: 0,
            current_page_index: 0,
            current_first_item_index: 0,
            current_artifact_item_indices: Vec::new(),
            current_ready_item_indices: Vec::new(),
            current_ready_artifact_item_indices: Vec::new(),
            current_remaining_dependency_counts: Vec::new(),
            current_remaining_dependent_counts: Vec::new(),
            artifact_item_count: 0,
            ready_item_count: 0,
            ready_artifact_item_count: 0,
            first_ready_item_index: None,
            first_ready_artifact_item_index: None,
        }
    }

    pub(in crate::compiler) fn record_item(
        &mut self,
        item: &SourcePackWorkQueuePage,
    ) -> Result<(), CompileError> {
        validate_source_pack_work_queue_page(item, self.target, Some(item.item_index))?;
        if item.item_index != self.next_item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "initial work queue progress expected item {} but saw {}",
                self.next_item_index, item.item_index
            )));
        }
        let dependency_count = source_pack_work_queue_page_dependency_count(item);
        let artifact_backed = source_pack_work_queue_item_kind_is_artifact_backed(item.kind);
        if artifact_backed {
            self.current_artifact_item_indices.push(item.item_index);
            self.artifact_item_count = self.artifact_item_count.saturating_add(1);
        }
        if dependency_count == 0 {
            self.current_ready_item_indices.push(item.item_index);
            self.ready_item_count = self.ready_item_count.saturating_add(1);
            self.first_ready_item_index = self.first_ready_item_index.or(Some(item.item_index));
            if artifact_backed {
                self.current_ready_artifact_item_indices
                    .push(item.item_index);
                self.ready_artifact_item_count = self.ready_artifact_item_count.saturating_add(1);
                self.first_ready_artifact_item_index = self
                    .first_ready_artifact_item_index
                    .or(Some(item.item_index));
            }
        } else {
            self.current_remaining_dependency_counts.push(
                SourcePackWorkQueueRemainingDependencyCount {
                    item_index: item.item_index,
                    remaining_dependency_count: dependency_count,
                },
            );
        }
        let dependent_count = source_pack_work_queue_page_dependent_count(item);
        if dependent_count != 0 {
            self.current_remaining_dependent_counts.push(
                SourcePackWorkQueueRemainingDependentCount {
                    item_index: item.item_index,
                    remaining_dependent_count: dependent_count,
                },
            );
        }
        self.next_item_index += 1;
        if self.next_item_index == self.current_page_end_index() {
            self.flush_current_page()?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        self,
    ) -> Result<SourcePackWorkQueueProgressIndex, CompileError> {
        if self.next_item_index != self.work_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "initial work queue progress saw {} items but expected {}",
                self.next_item_index, self.work_item_count
            )));
        }
        if !self.current_ready_item_indices.is_empty() {
            return Err(source_pack_library_partition_contract_error(
                "initial work queue progress has unflushed ready items",
            ));
        }
        if !self.current_artifact_item_indices.is_empty() {
            return Err(source_pack_library_partition_contract_error(
                "initial work queue progress has unflushed artifact items",
            ));
        }
        if !self.current_ready_artifact_item_indices.is_empty() {
            return Err(source_pack_library_partition_contract_error(
                "initial work queue progress has unflushed ready artifact items",
            ));
        }
        if !self.current_remaining_dependency_counts.is_empty() {
            return Err(source_pack_library_partition_contract_error(
                "initial work queue progress has unflushed dependency counters",
            ));
        }
        if !self.current_remaining_dependent_counts.is_empty() {
            return Err(source_pack_library_partition_contract_error(
                "initial work queue progress has unflushed dependent counters",
            ));
        }
        let index = SourcePackWorkQueueProgressIndex {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
            target: self.target,
            work_item_count: self.work_item_count,
            page_size: self.page_size,
            page_count: self.work_item_count.div_ceil(self.page_size),
            artifact_item_count: self.artifact_item_count,
            completed_item_count: 0,
            ready_item_count: self.ready_item_count,
            ready_artifact_item_count: self.ready_artifact_item_count,
            claimed_item_count: 0,
            first_ready_item_index: self.first_ready_item_index,
            first_ready_artifact_item_index: self.first_ready_artifact_item_index,
        };
        validate_source_pack_work_queue_progress_index(&index, self.target)?;
        self.store
            .store_work_queue_progress_directory_pages_for_index(&index)?;
        self.store.store_work_queue_progress_index(&index)?;
        Ok(index)
    }

    pub(in crate::compiler) fn current_page_item_count(&self) -> usize {
        self.page_size
            .min(self.work_item_count - self.current_first_item_index)
    }

    pub(in crate::compiler) fn current_page_end_index(&self) -> usize {
        self.current_first_item_index + self.current_page_item_count()
    }

    pub(in crate::compiler) fn flush_current_page(&mut self) -> Result<(), CompileError> {
        let item_count = self.current_page_item_count();
        let artifact_item_indices = std::mem::take(&mut self.current_artifact_item_indices);
        let ready_item_indices = std::mem::take(&mut self.current_ready_item_indices);
        let ready_artifact_item_indices =
            std::mem::take(&mut self.current_ready_artifact_item_indices);
        let remaining_dependency_counts =
            std::mem::take(&mut self.current_remaining_dependency_counts);
        let remaining_dependent_counts =
            std::mem::take(&mut self.current_remaining_dependent_counts);
        let page = SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target: self.target,
            page_index: self.current_page_index,
            first_item_index: self.current_first_item_index,
            item_count,
            artifact_item_indices,
            remaining_dependency_counts,
            remaining_dependent_counts,
            completed_item_indices: Vec::new(),
            ready_item_indices,
            ready_artifact_item_indices,
            claimed_items: Vec::new(),
        };
        validate_source_pack_work_queue_progress_page(
            &page,
            self.target,
            Some(self.current_page_index),
        )?;
        self.store.store_work_queue_progress_page(&page)?;
        self.current_page_index += 1;
        self.current_first_item_index = self.current_page_index * self.page_size;
        Ok(())
    }
}

#[cfg(test)]
pub(in crate::compiler) fn store_initial_work_queue_progress_from_stored_work_queue_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    work_item_count: usize,
    page_size: usize,
) -> Result<SourcePackWorkQueueProgressIndex, CompileError> {
    let mut progress_writer = SourcePackInitialWorkQueueProgressPageWriter::new(
        store,
        target,
        work_item_count,
        page_size,
    );
    for item_index in 0..work_item_count {
        let item = store.load_work_queue_page_for_target(target, item_index)?;
        progress_writer.record_item(&item)?;
    }
    progress_writer.finish()
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackInitialWorkQueueProgressPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) work_item_count: usize,
    pub(in crate::compiler) page_size: usize,
    pub(in crate::compiler) page_count: usize,
    pub(in crate::compiler) next_page_index: usize,
    pub(in crate::compiler) artifact_item_count: usize,
    pub(in crate::compiler) ready_item_count: usize,
    pub(in crate::compiler) ready_artifact_item_count: usize,
    pub(in crate::compiler) first_ready_item_index: Option<usize>,
    pub(in crate::compiler) first_ready_artifact_item_index: Option<usize>,
}

pub(in crate::compiler) fn validate_source_pack_initial_work_queue_progress_prepare_progress(
    progress: &SourcePackInitialWorkQueueProgressPrepareProgress,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_index(queue, queue.target)?;
    if progress.version != SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue progress prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != queue.target {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare target {:?} does not match queue target {:?}",
            progress.target, queue.target
        )));
    }
    if page_size == 0 {
        return Err(source_pack_library_partition_contract_error(
            "work queue progress prepare page_size is zero",
        ));
    }
    if page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare page_size {page_size} exceeds record cap {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let page_count = queue.work_item_count.div_ceil(page_size);
    if progress.work_item_count != queue.work_item_count
        || progress.page_size != page_size
        || progress.page_count != page_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare shape item/page-size/page-count {}/{}/{} does not match expected {}/{}/{}",
            progress.work_item_count,
            progress.page_size,
            progress.page_count,
            queue.work_item_count,
            page_size,
            page_count
        )));
    }
    if progress.next_page_index > progress.page_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare next page {} exceeds page count {}",
            progress.next_page_index, progress.page_count
        )));
    }
    if progress.artifact_item_count > queue.artifact_item_count
        || progress.ready_item_count > queue.work_item_count
        || progress.ready_artifact_item_count > progress.ready_item_count
        || progress.ready_artifact_item_count > progress.artifact_item_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare counts artifact/ready/ready-artifact {}/{}/{} exceed queue item counts {}/{}",
            progress.artifact_item_count,
            progress.ready_item_count,
            progress.ready_artifact_item_count,
            queue.artifact_item_count,
            queue.work_item_count
        )));
    }
    if let Some(first_ready_item_index) = progress.first_ready_item_index {
        if first_ready_item_index >= queue.work_item_count || progress.ready_item_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress prepare first ready item {first_ready_item_index} is invalid"
            )));
        }
    } else if progress.ready_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare has {} ready items but no first ready item",
            progress.ready_item_count
        )));
    }
    if let Some(first_ready_artifact_item_index) = progress.first_ready_artifact_item_index {
        if first_ready_artifact_item_index >= queue.work_item_count
            || progress.ready_artifact_item_count == 0
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress prepare first ready artifact item {first_ready_artifact_item_index} is invalid"
            )));
        }
    } else if progress.ready_artifact_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare has {} ready artifact items but no first ready artifact item",
            progress.ready_artifact_item_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_initial_work_queue_progress_index_from_prepare_progress(
    progress: &SourcePackInitialWorkQueueProgressPrepareProgress,
) -> SourcePackWorkQueueProgressIndex {
    SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: progress.target,
        work_item_count: progress.work_item_count,
        page_size: progress.page_size,
        page_count: progress.page_count,
        artifact_item_count: progress.artifact_item_count,
        completed_item_count: 0,
        ready_item_count: progress.ready_item_count,
        ready_artifact_item_count: progress.ready_artifact_item_count,
        claimed_item_count: 0,
        first_ready_item_index: progress.first_ready_item_index,
        first_ready_artifact_item_index: progress.first_ready_artifact_item_index,
    }
}

pub(in crate::compiler) fn source_pack_update_initial_work_queue_progress_prepare_progress_from_page(
    progress: &mut SourcePackInitialWorkQueueProgressPrepareProgress,
    page: &SourcePackWorkQueueProgressPage,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_progress_page(page, progress.target, Some(page.page_index))?;
    if page.page_index != progress.next_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress prepare expected page {} but saw {}",
            progress.next_page_index, page.page_index
        )));
    }
    let summary = source_pack_work_queue_progress_page_summary(page);
    progress.artifact_item_count = progress
        .artifact_item_count
        .saturating_add(summary.artifact_item_count);
    progress.ready_item_count = progress
        .ready_item_count
        .saturating_add(summary.ready_item_count);
    progress.ready_artifact_item_count = progress
        .ready_artifact_item_count
        .saturating_add(summary.ready_artifact_item_count);
    progress.first_ready_item_index = progress
        .first_ready_item_index
        .or(summary.first_ready_item_index);
    progress.first_ready_artifact_item_index = progress
        .first_ready_artifact_item_index
        .or(summary.first_ready_artifact_item_index);
    progress.next_page_index = progress.next_page_index.checked_add(1).ok_or_else(|| {
        source_pack_library_partition_contract_error(
            "work queue progress prepare next page index overflows",
        )
    })?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_initial_work_queue_progress_page_from_stored_work_queue_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    page_index: usize,
    page_size: usize,
    work_item_count: usize,
) -> Result<SourcePackWorkQueueProgressPage, CompileError> {
    if page_size == 0 || page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page_size {page_size} exceeds bounds 1..={}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let first_item_index = page_index.checked_mul(page_size).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} first item index overflows"
        ))
    })?;
    if first_item_index >= work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue progress page {page_index} starts at {first_item_index} but work item count is {work_item_count}"
        )));
    }
    let item_count = page_size.min(work_item_count - first_item_index);
    let mut artifact_item_indices = Vec::new();
    let mut ready_item_indices = Vec::new();
    let mut ready_artifact_item_indices = Vec::new();
    let mut remaining_dependency_counts = Vec::new();
    let mut remaining_dependent_counts = Vec::new();
    let item_end = first_item_index + item_count;
    for item_index in first_item_index..item_end {
        let item = store.load_work_queue_page_for_target(target, item_index)?;
        validate_source_pack_work_queue_page(&item, target, Some(item_index))?;
        let artifact_backed = source_pack_work_queue_item_kind_is_artifact_backed(item.kind);
        if artifact_backed {
            artifact_item_indices.push(item_index);
        }
        let dependency_count = source_pack_work_queue_page_dependency_count(&item);
        if dependency_count == 0 {
            ready_item_indices.push(item_index);
            if artifact_backed {
                ready_artifact_item_indices.push(item_index);
            }
        } else {
            remaining_dependency_counts.push(SourcePackWorkQueueRemainingDependencyCount {
                item_index,
                remaining_dependency_count: dependency_count,
            });
        }
        let dependent_count = source_pack_work_queue_page_dependent_count(&item);
        if dependent_count != 0 {
            remaining_dependent_counts.push(SourcePackWorkQueueRemainingDependentCount {
                item_index,
                remaining_dependent_count: dependent_count,
            });
        }
    }
    let page = SourcePackWorkQueueProgressPage {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
        target,
        page_index,
        first_item_index,
        item_count,
        artifact_item_indices,
        remaining_dependency_counts,
        remaining_dependent_counts,
        completed_item_indices: Vec::new(),
        ready_item_indices,
        ready_artifact_item_indices,
        claimed_items: Vec::new(),
    };
    validate_source_pack_work_queue_progress_page(&page, target, Some(page_index))?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_store_initial_work_queue_progress_directory_pages_after_progress_page(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackWorkQueueProgressIndex,
    progress_page_index: usize,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_progress_index(index, index.target)?;
    let directory_page_index =
        source_pack_work_queue_progress_directory_page_index_for_progress_page(progress_page_index);
    let (first_progress_page_index, progress_page_count) =
        source_pack_work_queue_progress_directory_page_range(index, directory_page_index)?;
    if progress_page_index + 1 != first_progress_page_index + progress_page_count {
        return Ok(());
    }
    let directory_page = source_pack_work_queue_progress_directory_page_from_summaries(
        store,
        index.target,
        index,
        &[],
        directory_page_index,
    )?;
    store.store_work_queue_progress_directory_page_for_target(index.target, &directory_page)?;

    let directory_index_page_index =
        source_pack_work_queue_progress_directory_index_page_index_for_directory_page(
            directory_page_index,
        );
    let (first_directory_page_index, directory_page_count) =
        source_pack_work_queue_progress_directory_index_page_range(
            index,
            directory_index_page_index,
        )?;
    if directory_page_index + 1 != first_directory_page_index + directory_page_count {
        return Ok(());
    }
    let directory_index_page =
        source_pack_work_queue_progress_directory_index_page_from_directory_pages(
            store,
            index.target,
            index,
            &[],
            directory_index_page_index,
        )?;
    store.store_work_queue_progress_directory_index_page_for_target(
        index.target,
        &directory_index_page,
        index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn store_initial_work_queue_progress_from_stored_work_queue_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
    max_new_pages: usize,
) -> Result<SourcePackFilesystemWorkQueueProgressPrepareStepResult, CompileError> {
    if max_new_pages == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue progress chunk max_new_pages must be greater than zero".into(),
        ));
    }
    validate_source_pack_work_queue_index(queue, queue.target)?;
    if page_size == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack work queue progress chunk page_size must be greater than zero".into(),
        ));
    }
    if page_size > SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-pack work queue progress chunk page_size {page_size} exceeds record cap {}",
            SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE
        )));
    }
    let page_count = queue.work_item_count.div_ceil(page_size);
    if store
        .work_queue_progress_index_path_for_target(queue.target)
        .is_file()
    {
        let index = store.load_work_queue_progress_index_for_target(queue.target)?;
        return Ok(SourcePackFilesystemWorkQueueProgressPrepareStepResult {
            target: queue.target,
            complete: true,
            work_item_count: index.work_item_count,
            page_size: index.page_size,
            page_count: index.page_count,
            next_page_index: index.page_count,
            new_progress_page_count: 0,
            artifact_item_count: index.artifact_item_count,
            ready_item_count: index.ready_item_count,
            ready_artifact_item_count: index.ready_artifact_item_count,
            first_ready_item_index: index.first_ready_item_index,
            first_ready_artifact_item_index: index.first_ready_artifact_item_index,
            work_queue_progress_index_path: Some(
                store.work_queue_progress_index_path_for_target(queue.target),
            ),
        });
    }

    let progress_path = store.work_queue_progress_prepare_progress_path_for_target(queue.target);
    let mut progress = if progress_path.is_file() {
        source_pack_load_initial_work_queue_progress_prepare_progress(store, queue, page_size)?
    } else {
        SourcePackInitialWorkQueueProgressPrepareProgress {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION,
            target: queue.target,
            work_item_count: queue.work_item_count,
            page_size,
            page_count,
            next_page_index: 0,
            artifact_item_count: 0,
            ready_item_count: 0,
            ready_artifact_item_count: 0,
            first_ready_item_index: None,
            first_ready_artifact_item_index: None,
        }
    };
    validate_source_pack_initial_work_queue_progress_prepare_progress(&progress, queue, page_size)?;

    let mut new_progress_page_count = 0usize;
    while progress.next_page_index < page_count && new_progress_page_count < max_new_pages {
        let progress_page =
            source_pack_initial_work_queue_progress_page_from_stored_work_queue_pages(
                store,
                queue.target,
                progress.next_page_index,
                page_size,
                queue.work_item_count,
            )?;
        store.store_work_queue_progress_page(&progress_page)?;
        source_pack_update_initial_work_queue_progress_prepare_progress_from_page(
            &mut progress,
            &progress_page,
        )?;
        let progress_index =
            source_pack_initial_work_queue_progress_index_from_prepare_progress(&progress);
        source_pack_store_initial_work_queue_progress_directory_pages_after_progress_page(
            store,
            &progress_index,
            progress_page.page_index,
        )?;
        source_pack_store_initial_work_queue_progress_prepare_progress(store, &progress)?;
        new_progress_page_count = new_progress_page_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "work queue progress chunk new page count overflows",
            )
        })?;
    }

    let mut work_queue_progress_index_path = None;
    if progress.next_page_index == page_count {
        if progress.artifact_item_count != queue.artifact_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress prepared {} artifact-backed items but queue index records {}",
                progress.artifact_item_count, queue.artifact_item_count
            )));
        }
        let index = source_pack_initial_work_queue_progress_index_from_prepare_progress(&progress);
        validate_source_pack_work_queue_progress_index(&index, queue.target)?;
        work_queue_progress_index_path = Some(store.store_work_queue_progress_index(&index)?);
    }

    Ok(SourcePackFilesystemWorkQueueProgressPrepareStepResult {
        target: queue.target,
        complete: work_queue_progress_index_path.is_some(),
        work_item_count: progress.work_item_count,
        page_size: progress.page_size,
        page_count: progress.page_count,
        next_page_index: progress.next_page_index,
        new_progress_page_count,
        artifact_item_count: progress.artifact_item_count,
        ready_item_count: progress.ready_item_count,
        ready_artifact_item_count: progress.ready_artifact_item_count,
        first_ready_item_index: progress.first_ready_item_index,
        first_ready_artifact_item_index: progress.first_ready_artifact_item_index,
        work_queue_progress_index_path,
    })
}

pub(in crate::compiler) fn source_pack_store_initial_work_queue_progress_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackInitialWorkQueueProgressPrepareProgress,
) -> Result<PathBuf, CompileError> {
    let queue_shape = SourcePackWorkQueueIndex {
        version: SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
        target: progress.target,
        work_item_count: progress.work_item_count,
        artifact_item_count: progress.artifact_item_count,
        final_item_index: progress.work_item_count.saturating_sub(1),
        final_job_index: progress.work_item_count.saturating_sub(1),
    };
    validate_source_pack_initial_work_queue_progress_prepare_progress(
        progress,
        &queue_shape,
        progress.page_size,
    )?;
    let path = store.work_queue_progress_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack work queue progress prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack work queue progress prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_initial_work_queue_progress_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    queue: &SourcePackWorkQueueIndex,
    page_size: usize,
) -> Result<SourcePackInitialWorkQueueProgressPrepareProgress, CompileError> {
    let path = store.work_queue_progress_prepare_progress_path_for_target(queue.target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack work queue progress prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<SourcePackInitialWorkQueueProgressPrepareProgress>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress prepare progress {}: {err}",
                    path.display()
                ))
            })?;
    validate_source_pack_initial_work_queue_progress_prepare_progress(&progress, queue, page_size)?;
    Ok(progress)
}

pub(in crate::compiler) fn store_source_pack_work_queue_compact_index(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackWorkQueueIndex,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_work_queue_index(index, index.target)?;
    let path = store.work_queue_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        CompileError::GpuFrontend(format!("serialize source-pack work queue index: {err}"))
    })?;
    write_source_pack_filesystem_file_atomically(&path, &bytes, "source-pack work queue index")?;
    Ok(path)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_insert_work_queue_page(
    pages: &mut [Option<SourcePackWorkQueuePage>],
    page: SourcePackWorkQueuePage,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_page(&page, page.target, Some(page.item_index))?;
    let Some(slot) = pages.get_mut(page.item_index) else {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue item {} exceeds page capacity {}",
            page.item_index,
            pages.len()
        )));
    };
    if slot.is_some() {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue item {} appears more than once",
            page.item_index
        )));
    }
    *slot = Some(page);
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_work_queue_dependents_by_item(
    pages: &[SourcePackWorkQueuePage],
) -> Result<Vec<Vec<usize>>, CompileError> {
    let mut dependents_by_item = vec![Vec::new(); pages.len()];
    for page in pages {
        if page.item_index >= pages.len() {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue item {} exceeds page count {}",
                page.item_index,
                pages.len()
            )));
        }
        for &dependency_item_index in &page.dependency_item_indices {
            let Some(dependents) = dependents_by_item.get_mut(dependency_item_index) else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue item {} depends on missing item {}",
                    page.item_index, dependency_item_index
                )));
            };
            dependents.push(page.item_index);
        }
        for range in &page.dependency_item_ranges {
            let Some(indices) = range.iter() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue item {} dependency range starting at {} overflows",
                    page.item_index, range.first_job_index
                )));
            };
            for dependency_item_index in indices {
                let Some(dependents) = dependents_by_item.get_mut(dependency_item_index) else {
                    return Err(source_pack_library_partition_contract_error(format!(
                        "work queue item {} depends on missing ranged item {}",
                        page.item_index, dependency_item_index
                    )));
                };
                dependents.push(page.item_index);
            }
        }
    }
    for dependents in &mut dependents_by_item {
        dependents.sort_unstable();
        dependents.dedup();
    }
    Ok(dependents_by_item)
}

#[cfg(test)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct SourcePackBuildArtifactPageMetadata {
    pub(in crate::compiler) artifact_count: usize,
    pub(in crate::compiler) scheduled_job_count: usize,
    pub(in crate::compiler) link_interface_batches: Vec<SourcePackLinkInterfaceBatch>,
    pub(in crate::compiler) link_object_batches: Vec<SourcePackLinkObjectBatch>,
    pub(in crate::compiler) output_refs: SourcePackLibraryScheduleOutputRefs,
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_build_artifact_page_metadata(
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
    batch_limits: SourcePackJobBatchLimits,
) -> Result<SourcePackBuildArtifactPageMetadata, CompileError> {
    let job_schedule =
        source_pack_job_schedule_from_library_schedule_pages(schedule_index, schedule_pages)?;
    let output_refs = source_pack_library_schedule_output_refs(schedule_index, schedule_pages)?;
    let link_interface_batches = source_pack_link_interface_batches_from_output_refs(
        output_refs.interface_refs_by_job_index.values(),
        &output_refs.source_metadata_by_artifact_index,
        batch_limits,
    )?;
    let link_object_batches = source_pack_link_object_batches_from_output_refs(
        output_refs.object_refs_by_job_index.values(),
        &output_refs.source_metadata_by_artifact_index,
        batch_limits,
    )?;
    let scheduled_job_count = job_schedule.jobs.len();
    Ok(SourcePackBuildArtifactPageMetadata {
        artifact_count: schedule_index.job_count,
        scheduled_job_count,
        link_interface_batches,
        link_object_batches,
        output_refs,
    })
}
