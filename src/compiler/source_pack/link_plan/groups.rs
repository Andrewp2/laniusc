use super::{
    super::*,
    HierarchicalLinkPlanPrepareProgress,
    initialize_reduce_progress,
    load_link_plan_prepare_progress,
    store_link_plan_index,
    store_link_plan_prepare_progress,
    validate_link_plan_prepare_progress,
};

pub(in crate::compiler) fn store_link_leaf_group_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    max_new_partitions: usize,
) -> Result<FilesystemHierarchicalLinkLeafPrepareStepResult, CompileError> {
    if max_new_partitions == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link leaf chunk max_new_partitions must be greater than zero"
                .into(),
        ));
    }
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    let limits = limits.normalized();
    let progress_path =
        store.hierarchical_link_plan_prepare_progress_path_for_target(schedule_index.target);
    let mut progress = if progress_path.is_file() {
        load_link_plan_prepare_progress(
            store,
            schedule_index.target,
            schedule_index.partition_count,
            limits,
        )?
    } else {
        HierarchicalLinkPlanPrepareProgress {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION,
            target: schedule_index.target,
            limits,
            schedule_partition_count: schedule_index.partition_count,
            next_partition_index: 0,
            leaf_group_count: 0,
            reduce_level: 0,
            current_level_first_group_index: 0,
            current_level_group_count: 0,
            next_input_group_index: 0,
            next_level_first_group_index: 0,
            next_level_group_count: 0,
            next_group_index: 0,
        }
    };
    validate_link_plan_prepare_progress(
        &progress,
        schedule_index.target,
        schedule_index.partition_count,
        limits,
    )?;
    let mut new_partition_count = 0usize;
    let mut new_leaf_group_count = 0usize;
    while progress.next_partition_index < schedule_index.partition_count
        && new_partition_count < max_new_partitions
    {
        let page = store.load_library_schedule_page_for_target(
            schedule_index.target,
            progress.next_partition_index,
        )?;
        validate_library_schedule_page(
            &page,
            schedule_index.target,
            Some(progress.next_partition_index),
        )?;
        let created_groups = store_leaf_groups_for_schedule_page(
            store,
            schedule_index,
            &page,
            limits,
            &mut progress.next_group_index,
        )?;
        progress.leaf_group_count = progress.next_group_index;
        new_leaf_group_count = new_leaf_group_count
            .checked_add(created_groups)
            .ok_or_else(|| {
                library_partition_contract_error(
                    "hierarchical link leaf chunk group count overflows",
                )
            })?;
        progress.next_partition_index =
            progress
                .next_partition_index
                .checked_add(1)
                .ok_or_else(|| {
                    library_partition_contract_error(
                        "hierarchical link leaf chunk partition index overflows",
                    )
                })?;
        new_partition_count = new_partition_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link leaf chunk partition count overflows",
            )
        })?;
        store_link_plan_prepare_progress(store, &progress)?;
    }
    Ok(FilesystemHierarchicalLinkLeafPrepareStepResult {
        target: schedule_index.target,
        complete: progress.next_partition_index == schedule_index.partition_count,
        schedule_partition_count: schedule_index.partition_count,
        next_partition_index: progress.next_partition_index,
        leaf_group_count: progress.next_group_index,
        new_leaf_group_count,
    })
}

pub(in crate::compiler) fn store_leaf_groups_for_schedule_page(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    limits: SourcePackJobBatchLimits,
    next_group_index: &mut usize,
) -> Result<usize, CompileError> {
    validate_library_schedule_page_for_index(page, schedule_index)?;
    let mut created_group_count = 0usize;
    let mut current_codegen_jobs = Vec::<SourcePackJob>::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_line_count = 0usize;
    for_each_stored_schedule_codegen_job(
        store,
        schedule_index,
        page,
        |_codegen_job_offset, job| {
            let should_flush = !current_codegen_jobs.is_empty()
                && (current_codegen_jobs.len() >= limits.max_jobs_per_batch
                    || current_source_bytes.saturating_add(job.source_bytes)
                        > limits.max_source_bytes_per_batch
                    || current_source_file_count.saturating_add(job.source_file_count)
                        > limits.max_source_files_per_batch);
            if should_flush {
                let input_frontend_job_count = load_codegen_job_dependency_count(
                    store,
                    schedule_index,
                    current_codegen_jobs[0].job_index,
                )?;
                let group = leaf_link_group(
                    *next_group_index,
                    schedule_index,
                    page,
                    input_frontend_job_count,
                    &current_codegen_jobs,
                    current_source_bytes,
                    current_source_file_count,
                    current_source_line_count,
                    limits,
                )?;
                store.store_hierarchical_link_group_page(&group)?;
                *next_group_index = (*next_group_index).checked_add(1).ok_or_else(|| {
                    library_partition_contract_error("hierarchical link leaf group index overflows")
                })?;
                created_group_count = created_group_count.checked_add(1).ok_or_else(|| {
                    library_partition_contract_error(
                        "hierarchical link leaf created group count overflows",
                    )
                })?;
                current_codegen_jobs.clear();
                current_source_bytes = 0;
                current_source_file_count = 0;
                current_source_line_count = 0;
            }
            current_source_bytes = current_source_bytes.saturating_add(job.source_bytes);
            current_source_file_count =
                current_source_file_count.saturating_add(job.source_file_count);
            current_source_line_count = current_source_line_count.saturating_add(job.source_lines);
            current_codegen_jobs.push(job);
            Ok(())
        },
    )?;
    if !current_codegen_jobs.is_empty() {
        let input_frontend_job_count = load_codegen_job_dependency_count(
            store,
            schedule_index,
            current_codegen_jobs[0].job_index,
        )?;
        let group = leaf_link_group(
            *next_group_index,
            schedule_index,
            page,
            input_frontend_job_count,
            &current_codegen_jobs,
            current_source_bytes,
            current_source_file_count,
            current_source_line_count,
            limits,
        )?;
        store.store_hierarchical_link_group_page(&group)?;
        *next_group_index = (*next_group_index).checked_add(1).ok_or_else(|| {
            library_partition_contract_error("hierarchical link leaf group index overflows")
        })?;
        created_group_count = created_group_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("hierarchical link leaf created group count overflows")
        })?;
    }
    Ok(created_group_count)
}

pub(in crate::compiler) fn store_link_reduce_group_chunk(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    max_new_reduce_groups: usize,
) -> Result<FilesystemHierarchicalLinkPlanPrepareStepResult, CompileError> {
    if max_new_reduce_groups == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link reduce chunk max_new_reduce_groups must be greater than zero"
                .into(),
        ));
    }
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    let limits = limits.normalized();
    if store
        .hierarchical_link_plan_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_hierarchical_link_plan_index_for_target(schedule_index.target)?;
        return Ok(FilesystemHierarchicalLinkPlanPrepareStepResult {
            target: schedule_index.target,
            complete: true,
            input_partition_count: index.input_partition_count,
            reduce_level: 0,
            current_level_first_group_index: index.final_link_group_index,
            current_level_group_count: 1,
            next_input_group_index: index.final_link_group_index,
            link_group_count: index.link_group_count,
            new_reduce_group_count: 0,
            final_link_group_index: Some(index.final_link_group_index),
            hierarchical_link_plan_index_path: Some(
                store.hierarchical_link_plan_index_path_for_target(schedule_index.target),
            ),
        });
    }

    let progress_path =
        store.hierarchical_link_plan_prepare_progress_path_for_target(schedule_index.target);
    if !progress_path.is_file() {
        return Err(library_partition_contract_error(
            "hierarchical link reduce chunks require completed leaf-group progress",
        ));
    }
    let mut progress = load_link_plan_prepare_progress(
        store,
        schedule_index.target,
        schedule_index.partition_count,
        limits,
    )?;
    if progress.next_partition_index != schedule_index.partition_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link reduce chunks require complete leaf groups; next partition {} of {}",
            progress.next_partition_index, schedule_index.partition_count
        )));
    }
    if progress.reduce_level == 0 {
        initialize_reduce_progress(&mut progress)?;
        store_link_plan_prepare_progress(store, &progress)?;
    }

    let reduce_fanout = limits.max_jobs_per_batch.max(2);
    let mut new_reduce_group_count = 0usize;
    advance_completed_reduce_levels(store, &mut progress)?;
    while progress.current_level_group_count > 1 && new_reduce_group_count < max_new_reduce_groups {
        let current_level_end = progress
            .current_level_first_group_index
            .checked_add(progress.current_level_group_count)
            .ok_or_else(|| {
                library_partition_contract_error(
                    "hierarchical link reduce chunk current level range overflows",
                )
            })?;
        if progress.next_input_group_index >= current_level_end {
            advance_completed_reduce_levels(store, &mut progress)?;
            continue;
        }
        let input_group_count =
            (current_level_end - progress.next_input_group_index).min(reduce_fanout);
        let group = reduce_link_group(
            store,
            schedule_index,
            limits,
            progress.next_group_index,
            progress.reduce_level,
            progress.next_input_group_index,
            input_group_count,
        )?;
        store.store_hierarchical_link_group_page(&group)?;
        progress.next_group_index = progress.next_group_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("hierarchical link reduce chunk group index overflows")
        })?;
        progress.next_level_group_count = progress
            .next_level_group_count
            .checked_add(1)
            .ok_or_else(|| {
                library_partition_contract_error(
                    "hierarchical link reduce chunk next level count overflows",
                )
            })?;
        progress.next_input_group_index = progress
            .next_input_group_index
            .checked_add(input_group_count)
            .ok_or_else(|| {
                library_partition_contract_error(
                    "hierarchical link reduce chunk input group index overflows",
                )
            })?;
        new_reduce_group_count = new_reduce_group_count.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link reduce chunk new group count overflows",
            )
        })?;
        store_link_plan_prepare_progress(store, &progress)?;
    }
    advance_completed_reduce_levels(store, &mut progress)?;

    let mut final_link_group_index = None;
    let mut hierarchical_link_plan_index_path = None;
    if progress.current_level_group_count == 1 {
        let final_group = store.load_hierarchical_link_group_page_for_target(
            schedule_index.target,
            progress.current_level_first_group_index,
        )?;
        let index = SourcePackHierarchicalLinkPlanIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
            target: schedule_index.target,
            limits,
            input_partition_count: schedule_index.partition_count,
            first_link_job_index: schedule_index.link_job_index,
            final_link_group_index: final_group.group_index,
            final_link_job_index: final_group.job_index,
            link_group_count: progress.next_group_index,
        };
        validate_link_plan_index(&index, schedule_index.target)?;
        hierarchical_link_plan_index_path = Some(store_link_plan_index(store, &index)?);
        final_link_group_index = Some(index.final_link_group_index);
    }

    Ok(FilesystemHierarchicalLinkPlanPrepareStepResult {
        target: schedule_index.target,
        complete: hierarchical_link_plan_index_path.is_some(),
        input_partition_count: schedule_index.partition_count,
        reduce_level: progress.reduce_level,
        current_level_first_group_index: progress.current_level_first_group_index,
        current_level_group_count: progress.current_level_group_count,
        next_input_group_index: progress.next_input_group_index,
        link_group_count: progress.next_group_index,
        new_reduce_group_count,
        final_link_group_index,
        hierarchical_link_plan_index_path,
    })
}

pub(in crate::compiler) fn advance_completed_reduce_levels(
    store: &FilesystemArtifactStore,
    progress: &mut HierarchicalLinkPlanPrepareProgress,
) -> Result<(), CompileError> {
    while progress.current_level_group_count > 1 {
        let current_level_end = progress
            .current_level_first_group_index
            .checked_add(progress.current_level_group_count)
            .ok_or_else(|| {
                library_partition_contract_error(
                    "hierarchical link reduce progress current level range overflows",
                )
            })?;
        if progress.next_input_group_index < current_level_end {
            break;
        }
        if progress.next_level_group_count == 0 {
            return Err(library_partition_contract_error(
                "hierarchical link reduce progress completed a level without output groups",
            ));
        }
        progress.current_level_first_group_index = progress.next_level_first_group_index;
        progress.current_level_group_count = progress.next_level_group_count;
        progress.next_input_group_index = progress.current_level_first_group_index;
        progress.next_level_first_group_index = progress.next_group_index;
        progress.next_level_group_count = 0;
        progress.reduce_level = progress.reduce_level.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("hierarchical link reduce progress level overflows")
        })?;
        store_link_plan_prepare_progress(store, progress)?;
    }
    Ok(())
}

pub(in crate::compiler) fn reduce_link_group(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    group_index: usize,
    level: usize,
    first_input_group_index: usize,
    input_group_count: usize,
) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
    validate_library_schedule_index(schedule_index, schedule_index.target)?;
    if level == 0 {
        return Err(library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has level 0"
        )));
    }
    if input_group_count == 0 {
        return Err(library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has no input groups"
        )));
    }
    let reduce_fanout = limits.normalized().max_jobs_per_batch.max(2);
    if input_group_count > reduce_fanout {
        return Err(library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has {input_group_count} inputs but fanout is {reduce_fanout}"
        )));
    }
    let input_group_end_index = first_input_group_index
        .checked_add(input_group_count)
        .ok_or_else(|| {
            library_partition_contract_error(
                "stored hierarchical link reduce input range overflows",
            )
        })?;
    let job_index = schedule_index
        .link_job_index
        .checked_add(group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "stored hierarchical link group {group_index} job index overflows"
            ))
        })?;
    let mut input_partition_count = 0usize;
    let mut source_byte_count = 0usize;
    let mut source_file_count = 0usize;
    let mut source_line_count = 0usize;
    let mut oversized_input = input_group_count > reduce_fanout;
    for input_group_index in first_input_group_index..input_group_end_index {
        let input_group = store.load_hierarchical_link_group_page_for_target(
            schedule_index.target,
            input_group_index,
        )?;
        let expected_level = input_group.level.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(format!(
                "stored hierarchical link reduce group {group_index} input group {input_group_index} level overflows"
            ))
        })?;
        if expected_level != level {
            return Err(library_partition_contract_error(format!(
                "stored hierarchical link reduce group {group_index} level {level} references input group {input_group_index} at level {}",
                input_group.level
            )));
        }
        input_partition_count = input_partition_count
            .checked_add(hierarchical_link_group_input_partition_count(&input_group))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored hierarchical link group {group_index} partition count overflows"
                ))
            })?;
        source_byte_count = source_byte_count
            .checked_add(input_group.source_byte_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored hierarchical link reduce group {group_index} source-byte summary overflows"
                ))
            })?;
        source_file_count = source_file_count
            .checked_add(input_group.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored hierarchical link reduce group {group_index} source-file summary overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(input_group.source_line_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored hierarchical link reduce group {group_index} source-line summary overflows"
                ))
            })?;
        oversized_input |= input_group.oversized_input;
    }
    let input_link_group_indices =
        (first_input_group_index..input_group_end_index).collect::<Vec<_>>();
    let group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target: schedule_index.target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Reduce,
        level,
        job_index,
        input_partition_count,
        input_partition_indices: Vec::new(),
        input_frontend_job_count: 0,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_indices: Vec::new(),
        input_link_group_indices,
        source_byte_count,
        source_file_count,
        source_line_count,
        oversized_input,
    };
    validate_link_group_page(&group, schedule_index.target, Some(group_index))?;
    Ok(group)
}

pub(in crate::compiler) fn leaf_link_group(
    group_index: usize,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    input_frontend_job_count: usize,
    codegen_jobs: &[SourcePackJob],
    source_byte_count: usize,
    source_file_count: usize,
    source_line_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
    if input_frontend_job_count == 0 {
        return Err(library_partition_contract_error(format!(
            "stored leaf link group {} has no frontend inputs",
            group_index
        )));
    }
    let job_index = schedule_index
        .link_job_index
        .checked_add(group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "stored hierarchical link leaf group {group_index} job index overflows"
            ))
        })?;
    let oversized_input = input_frontend_job_count > limits.max_jobs_per_batch
        || codegen_jobs.len() > limits.max_jobs_per_batch
        || source_byte_count > limits.max_source_bytes_per_batch
        || source_file_count > limits.max_source_files_per_batch;
    let group = SourcePackHierarchicalLinkGroupPage {
        version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
        target: schedule_index.target,
        group_index,
        kind: SourcePackHierarchicalLinkGroupKind::Leaf,
        level: 0,
        job_index,
        input_partition_count: 1,
        input_partition_indices: vec![page.partition_index],
        input_frontend_job_count,
        input_frontend_job_indices: Vec::new(),
        input_codegen_job_indices: codegen_jobs.iter().map(|job| job.job_index).collect(),
        input_link_group_indices: Vec::new(),
        source_byte_count,
        source_file_count,
        source_line_count,
        oversized_input,
    };
    validate_link_group_page(&group, schedule_index.target, Some(group_index))?;
    Ok(group)
}

pub(in crate::compiler) fn load_codegen_job_dependency_count(
    store: &FilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
) -> Result<usize, CompileError> {
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    Ok(schedule_job_page_dependency_count(&job_page))
}

pub(in crate::compiler) fn hierarchical_link_group_input_partition_count(
    group: &SourcePackHierarchicalLinkGroupPage,
) -> usize {
    group
        .input_partition_count
        .max(group.input_partition_indices.len())
}

pub(in crate::compiler) fn hierarchical_link_group_input_frontend_job_count(
    group: &SourcePackHierarchicalLinkGroupPage,
) -> usize {
    group
        .input_frontend_job_count
        .max(group.input_frontend_job_indices.len())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn temp_store(stem: &str) -> (PathBuf, FilesystemArtifactStore) {
        let nanos = std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .expect("system time should be after Unix epoch")
            .as_nanos();
        let root = std::env::temp_dir().join(format!(
            "laniusc_link_plan_groups_{stem}_{}_{}",
            std::process::id(),
            nanos
        ));
        let _ = std::fs::remove_dir_all(&root);
        std::fs::create_dir_all(&root).expect("create link-plan group test store");
        let store = FilesystemArtifactStore::new(&root);
        (root, store)
    }

    fn schedule_index() -> SourcePackLibraryScheduleIndex {
        SourcePackLibraryScheduleIndex {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
            target: SourcePackArtifactTarget::Generic,
            partition_count: 2,
            frontend_job_count: 2,
            codegen_job_count: 2,
            link_job_index: 4,
            job_count: 5,
        }
    }

    fn leaf_group(
        group_index: usize,
        job_index: usize,
        partition_index: usize,
        source_byte_count: usize,
    ) -> SourcePackHierarchicalLinkGroupPage {
        SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            group_index,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index,
            input_partition_count: 1,
            input_partition_indices: vec![partition_index],
            input_frontend_job_count: 2,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: vec![2, 3],
            input_link_group_indices: Vec::new(),
            source_byte_count,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        }
    }

    #[test]
    fn reduce_link_group_rejects_overflowed_input_source_summary() {
        let (root, store) = temp_store("source_summary_overflow");
        store
            .store_hierarchical_link_group_page(&leaf_group(0, 4, 0, usize::MAX))
            .expect("store first leaf input group");
        store
            .store_hierarchical_link_group_page(&leaf_group(1, 5, 1, 1))
            .expect("store second leaf input group");

        let result = reduce_link_group(
            &store,
            &schedule_index(),
            SourcePackJobBatchLimits::default().normalized(),
            2,
            1,
            0,
            2,
        );

        assert!(result.is_err());
        std::fs::remove_dir_all(root).expect("remove link-plan group test store");
    }

    #[test]
    fn leaf_link_group_rejects_unrepresentable_dense_job_slot() {
        let mut schedule_index = schedule_index();
        schedule_index.link_job_index = usize::MAX;

        let page = SourcePackLibrarySchedulePage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
            target: SourcePackArtifactTarget::Generic,
            partition_index: 0,
            library_id: 1,
            dependency_library_ids: Vec::new(),
            frontend_job_index: 0,
            first_frontend_unit_index: 0,
            frontend_job_count: 1,
            first_codegen_unit_index: 0,
            first_codegen_job_index: 1,
            codegen_job_count: 1,
            link_job_index: usize::MAX,
            frontend_job: source_pack_job(0, SourcePackJobPhase::LibraryFrontend),
            frontend_jobs: Vec::new(),
            codegen_jobs: Vec::new(),
        };
        let codegen_jobs = vec![source_pack_job(1, SourcePackJobPhase::Codegen)];

        let err = leaf_link_group(
            1,
            &schedule_index,
            &page,
            1,
            &codegen_jobs,
            8,
            1,
            1,
            SourcePackJobBatchLimits::default().normalized(),
        )
        .expect_err("leaf link groups must fail closed when dense job slots overflow");
        let message = err.to_string();
        assert!(
            message.contains("leaf group 1") && message.contains("job index overflows"),
            "unexpected leaf dense job overflow error: {message}"
        );
    }

    fn source_pack_job(job_index: usize, phase: SourcePackJobPhase) -> SourcePackJob {
        SourcePackJob {
            job_index,
            phase,
            phase_unit_index: job_index,
            library_job_index: Some(job_index),
            library_id: 1,
            first_source_index: 0,
            source_file_count: 1,
            source_bytes: 8,
            source_lines: 1,
            oversized_source_file: false,
            dependency_job_indices: Vec::new(),
        }
    }
}
