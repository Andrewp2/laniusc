use super::*;

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_plan(
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
    limits: SourcePackJobBatchLimits,
) -> Result<
    (
        SourcePackHierarchicalLinkPlanIndex,
        Vec<SourcePackHierarchicalLinkGroupPage>,
    ),
    CompileError,
> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let limits = limits.normalized();
    if schedule_pages.is_empty() {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan has no schedule pages",
        ));
    }
    if schedule_pages.len() != schedule_index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan has {} schedule pages but schedule index partition_count {}",
            schedule_pages.len(),
            schedule_index.partition_count
        )));
    }

    let mut groups = Vec::new();
    for page in schedule_pages {
        validate_source_pack_library_schedule_page(
            page,
            schedule_index.target,
            Some(page.partition_index),
        )?;
        let mut current_codegen_jobs = Vec::<SourcePackJob>::new();
        let mut current_source_bytes = 0usize;
        let mut current_source_file_count = 0usize;
        let mut current_source_line_count = 0usize;

        for job in &page.codegen_jobs {
            let should_flush = !current_codegen_jobs.is_empty()
                && (current_codegen_jobs.len() >= limits.max_jobs_per_batch
                    || current_source_bytes.saturating_add(job.source_bytes)
                        > limits.max_source_bytes_per_batch
                    || current_source_file_count.saturating_add(job.source_file_count)
                        > limits.max_source_files_per_batch);
            if should_flush {
                source_pack_push_leaf_link_group(
                    &mut groups,
                    schedule_index,
                    page,
                    &current_codegen_jobs,
                    current_source_bytes,
                    current_source_file_count,
                    current_source_line_count,
                    limits,
                )?;
                current_codegen_jobs.clear();
                current_source_bytes = 0;
                current_source_file_count = 0;
                current_source_line_count = 0;
            }
            current_source_bytes = current_source_bytes.saturating_add(job.source_bytes);
            current_source_file_count =
                current_source_file_count.saturating_add(job.source_file_count);
            current_source_line_count = current_source_line_count.saturating_add(job.source_lines);
            current_codegen_jobs.push(job.clone());
        }

        if !current_codegen_jobs.is_empty() {
            source_pack_push_leaf_link_group(
                &mut groups,
                schedule_index,
                page,
                &current_codegen_jobs,
                current_source_bytes,
                current_source_file_count,
                current_source_line_count,
                limits,
            )?;
        }
    }

    let mut current_level_group_indices = groups
        .iter()
        .map(|group| group.group_index)
        .collect::<Vec<_>>();
    let reduce_fanout = limits.max_jobs_per_batch.max(2);
    let mut level = 1usize;
    while current_level_group_indices.len() > 1 {
        let mut next_level_group_indices = Vec::new();
        for chunk in current_level_group_indices.chunks(reduce_fanout) {
            let group_index = groups.len();
            let job_index = schedule_index.link_job_index + group_index;
            let mut input_partition_indices = BTreeSet::new();
            let mut source_byte_count = 0usize;
            let mut source_file_count = 0usize;
            let mut source_line_count = 0usize;
            let mut oversized_input = chunk.len() > reduce_fanout;
            for &input_group_index in chunk {
                let input_group = groups.get(input_group_index).ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "hierarchical link reduce group {group_index} references missing input group {input_group_index}"
                    ))
                })?;
                input_partition_indices.extend(input_group.input_partition_indices.iter().copied());
                source_byte_count = source_byte_count.saturating_add(input_group.source_byte_count);
                source_file_count = source_file_count.saturating_add(input_group.source_file_count);
                source_line_count = source_line_count.saturating_add(input_group.source_line_count);
                oversized_input |= input_group.oversized_input;
            }
            let group = SourcePackHierarchicalLinkGroupPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
                target: schedule_index.target,
                group_index,
                kind: SourcePackHierarchicalLinkGroupKind::Reduce,
                level,
                job_index,
                input_partition_count: input_partition_indices.len(),
                input_partition_indices: input_partition_indices.into_iter().collect(),
                input_frontend_job_count: 0,
                input_frontend_job_indices: Vec::new(),
                input_codegen_job_indices: Vec::new(),
                input_link_group_indices: chunk.to_vec(),
                source_byte_count,
                source_file_count,
                source_line_count,
                oversized_input,
            };
            validate_source_pack_hierarchical_link_group_page(
                &group,
                schedule_index.target,
                Some(group_index),
            )?;
            groups.push(group);
            next_level_group_indices.push(group_index);
        }
        current_level_group_indices = next_level_group_indices;
        level += 1;
    }

    let final_link_group_index = current_level_group_indices[0];
    let final_link_job_index = groups[final_link_group_index].job_index;
    let index = SourcePackHierarchicalLinkPlanIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
        target: schedule_index.target,
        limits,
        input_partition_count: schedule_index.partition_count,
        first_link_job_index: schedule_index.link_job_index,
        final_link_group_index,
        final_link_job_index,
        link_group_count: groups.len(),
    };
    validate_source_pack_hierarchical_link_plan_index(&index, schedule_index.target)?;
    Ok((index, groups))
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackHierarchicalLinkPlanPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) limits: SourcePackJobBatchLimits,
    pub(in crate::compiler) schedule_partition_count: usize,
    pub(in crate::compiler) next_partition_index: usize,
    pub(in crate::compiler) leaf_group_count: usize,
    pub(in crate::compiler) reduce_level: usize,
    pub(in crate::compiler) current_level_first_group_index: usize,
    pub(in crate::compiler) current_level_group_count: usize,
    pub(in crate::compiler) next_input_group_index: usize,
    pub(in crate::compiler) next_level_first_group_index: usize,
    pub(in crate::compiler) next_level_group_count: usize,
    pub(in crate::compiler) next_group_index: usize,
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_plan_prepare_progress(
    progress: &SourcePackHierarchicalLinkPlanPrepareProgress,
    target: SourcePackArtifactTarget,
    schedule_partition_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack hierarchical link plan prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.limits != limits.normalized() {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan prepare progress was created with different limits",
        ));
    }
    if progress.schedule_partition_count != schedule_partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress partition count {} does not match schedule partition count {schedule_partition_count}",
            progress.schedule_partition_count
        )));
    }
    if progress.next_partition_index > schedule_partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next partition {} exceeds schedule partition count {schedule_partition_count}",
            progress.next_partition_index
        )));
    }
    if progress.leaf_group_count > progress.next_group_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress leaf group count {} exceeds next group {}",
            progress.leaf_group_count, progress.next_group_index
        )));
    }
    let reduce_state_empty = progress.reduce_level == 0
        && progress.current_level_first_group_index == 0
        && progress.current_level_group_count == 0
        && progress.next_input_group_index == 0
        && progress.next_level_first_group_index == 0
        && progress.next_level_group_count == 0;
    if progress.next_partition_index < schedule_partition_count {
        if !reduce_state_empty {
            return Err(source_pack_library_partition_contract_error(
                "hierarchical link plan prepare progress has reduce state before leaf groups are complete",
            ));
        }
        return Ok(());
    }
    if reduce_state_empty {
        return Ok(());
    }
    if progress.leaf_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan prepare progress has reduce state without leaf groups",
        ));
    }
    if progress.reduce_level == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan prepare progress has reduce groups but no reduce level",
        ));
    }
    if progress.current_level_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan prepare progress has empty current reduce level",
        ));
    }
    let current_level_end = progress
        .current_level_first_group_index
        .checked_add(progress.current_level_group_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link plan prepare progress current level range overflows",
            )
        })?;
    if current_level_end > progress.next_group_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress current level end {current_level_end} exceeds next group {}",
            progress.next_group_index
        )));
    }
    if progress.next_input_group_index < progress.current_level_first_group_index
        || progress.next_input_group_index > current_level_end
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next input group {} is outside current level {}..{}",
            progress.next_input_group_index,
            progress.current_level_first_group_index,
            current_level_end
        )));
    }
    if progress.next_level_first_group_index < current_level_end {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next level starts at {} before current level end {current_level_end}",
            progress.next_level_first_group_index
        )));
    }
    let expected_next_group_index = progress
        .next_level_first_group_index
        .checked_add(progress.next_level_group_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link plan prepare progress next level range overflows",
            )
        })?;
    if expected_next_group_index != progress.next_group_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next level range ends at {expected_next_group_index} but next group is {}",
            progress.next_group_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_initialize_hierarchical_link_reduce_progress(
    progress: &mut SourcePackHierarchicalLinkPlanPrepareProgress,
) -> Result<(), CompileError> {
    if progress.next_partition_index != progress.schedule_partition_count {
        return Err(source_pack_library_partition_contract_error(
            "cannot initialize hierarchical link reduce progress before leaf groups are complete",
        ));
    }
    progress.leaf_group_count = progress.next_group_index;
    if progress.leaf_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link reduce progress has no leaf groups",
        ));
    }
    progress.reduce_level = 1;
    progress.current_level_first_group_index = 0;
    progress.current_level_group_count = progress.leaf_group_count;
    progress.next_input_group_index = 0;
    progress.next_level_first_group_index = progress.next_group_index;
    progress.next_level_group_count = 0;
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_leaf_groups_from_stored_schedule_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    max_new_partitions: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkLeafPrepareStepResult, CompileError> {
    if max_new_partitions == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link leaf chunk max_new_partitions must be greater than zero"
                .into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let limits = limits.normalized();
    let progress_path =
        store.hierarchical_link_plan_prepare_progress_path_for_target(schedule_index.target);
    let mut progress = if progress_path.is_file() {
        source_pack_load_hierarchical_link_plan_prepare_progress(
            store,
            schedule_index.target,
            schedule_index.partition_count,
            limits,
        )?
    } else {
        SourcePackHierarchicalLinkPlanPrepareProgress {
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
    validate_source_pack_hierarchical_link_plan_prepare_progress(
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
        validate_source_pack_library_schedule_page(
            &page,
            schedule_index.target,
            Some(progress.next_partition_index),
        )?;
        let created_groups = store_source_pack_hierarchical_link_leaf_groups_for_schedule_page(
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
                source_pack_library_partition_contract_error(
                    "hierarchical link leaf chunk group count overflows",
                )
            })?;
        progress.next_partition_index =
            progress
                .next_partition_index
                .checked_add(1)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(
                        "hierarchical link leaf chunk partition index overflows",
                    )
                })?;
        new_partition_count = new_partition_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link leaf chunk partition count overflows",
            )
        })?;
        source_pack_store_hierarchical_link_plan_prepare_progress(store, &progress)?;
    }
    Ok(SourcePackFilesystemHierarchicalLinkLeafPrepareStepResult {
        target: schedule_index.target,
        complete: progress.next_partition_index == schedule_index.partition_count,
        schedule_partition_count: schedule_index.partition_count,
        next_partition_index: progress.next_partition_index,
        leaf_group_count: progress.next_group_index,
        new_leaf_group_count,
    })
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_leaf_groups_for_schedule_page(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    limits: SourcePackJobBatchLimits,
    next_group_index: &mut usize,
) -> Result<usize, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_library_schedule_page(
        page,
        schedule_index.target,
        Some(page.partition_index),
    )?;
    let mut created_group_count = 0usize;
    let mut current_codegen_jobs = Vec::<SourcePackJob>::new();
    let mut current_source_bytes = 0usize;
    let mut current_source_file_count = 0usize;
    let mut current_source_line_count = 0usize;
    source_pack_for_each_stored_schedule_codegen_job(
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
                let input_frontend_job_count = source_pack_stored_codegen_job_dependency_count(
                    store,
                    schedule_index,
                    current_codegen_jobs[0].job_index,
                )?;
                let group = source_pack_stored_leaf_link_group(
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
                    source_pack_library_partition_contract_error(
                        "hierarchical link leaf group index overflows",
                    )
                })?;
                created_group_count = created_group_count.checked_add(1).ok_or_else(|| {
                    source_pack_library_partition_contract_error(
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
        let input_frontend_job_count = source_pack_stored_codegen_job_dependency_count(
            store,
            schedule_index,
            current_codegen_jobs[0].job_index,
        )?;
        let group = source_pack_stored_leaf_link_group(
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
            source_pack_library_partition_contract_error(
                "hierarchical link leaf group index overflows",
            )
        })?;
        created_group_count = created_group_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link leaf created group count overflows",
            )
        })?;
    }
    Ok(created_group_count)
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_reduce_groups_from_stored_leaf_groups_chunk(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    max_new_reduce_groups: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult, CompileError> {
    if max_new_reduce_groups == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link reduce chunk max_new_reduce_groups must be greater than zero"
                .into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let limits = limits.normalized();
    if store
        .hierarchical_link_plan_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_hierarchical_link_plan_index_for_target(schedule_index.target)?;
        return Ok(SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult {
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
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link reduce chunks require completed leaf-group progress",
        ));
    }
    let mut progress = source_pack_load_hierarchical_link_plan_prepare_progress(
        store,
        schedule_index.target,
        schedule_index.partition_count,
        limits,
    )?;
    if progress.next_partition_index != schedule_index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link reduce chunks require complete leaf groups; next partition {} of {}",
            progress.next_partition_index, schedule_index.partition_count
        )));
    }
    if progress.reduce_level == 0 {
        source_pack_initialize_hierarchical_link_reduce_progress(&mut progress)?;
        source_pack_store_hierarchical_link_plan_prepare_progress(store, &progress)?;
    }

    let reduce_fanout = limits.max_jobs_per_batch.max(2);
    let mut new_reduce_group_count = 0usize;
    source_pack_advance_completed_hierarchical_link_reduce_levels(store, &mut progress)?;
    while progress.current_level_group_count > 1 && new_reduce_group_count < max_new_reduce_groups {
        let current_level_end = progress
            .current_level_first_group_index
            .checked_add(progress.current_level_group_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(
                    "hierarchical link reduce chunk current level range overflows",
                )
            })?;
        if progress.next_input_group_index >= current_level_end {
            source_pack_advance_completed_hierarchical_link_reduce_levels(store, &mut progress)?;
            continue;
        }
        let input_group_count =
            (current_level_end - progress.next_input_group_index).min(reduce_fanout);
        let group = source_pack_stored_reduce_link_group(
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
            source_pack_library_partition_contract_error(
                "hierarchical link reduce chunk group index overflows",
            )
        })?;
        progress.next_level_group_count = progress
            .next_level_group_count
            .checked_add(1)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(
                    "hierarchical link reduce chunk next level count overflows",
                )
            })?;
        progress.next_input_group_index = progress
            .next_input_group_index
            .checked_add(input_group_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(
                    "hierarchical link reduce chunk input group index overflows",
                )
            })?;
        new_reduce_group_count = new_reduce_group_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link reduce chunk new group count overflows",
            )
        })?;
        source_pack_store_hierarchical_link_plan_prepare_progress(store, &progress)?;
    }
    source_pack_advance_completed_hierarchical_link_reduce_levels(store, &mut progress)?;

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
        validate_source_pack_hierarchical_link_plan_index(&index, schedule_index.target)?;
        hierarchical_link_plan_index_path = Some(
            store_source_pack_hierarchical_link_plan_compact_index(store, &index)?,
        );
        final_link_group_index = Some(index.final_link_group_index);
    }

    Ok(SourcePackFilesystemHierarchicalLinkPlanPrepareStepResult {
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

pub(in crate::compiler) fn source_pack_advance_completed_hierarchical_link_reduce_levels(
    store: &SourcePackFilesystemArtifactStore,
    progress: &mut SourcePackHierarchicalLinkPlanPrepareProgress,
) -> Result<(), CompileError> {
    while progress.current_level_group_count > 1 {
        let current_level_end = progress
            .current_level_first_group_index
            .checked_add(progress.current_level_group_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(
                    "hierarchical link reduce progress current level range overflows",
                )
            })?;
        if progress.next_input_group_index < current_level_end {
            break;
        }
        if progress.next_level_group_count == 0 {
            return Err(source_pack_library_partition_contract_error(
                "hierarchical link reduce progress completed a level without output groups",
            ));
        }
        progress.current_level_first_group_index = progress.next_level_first_group_index;
        progress.current_level_group_count = progress.next_level_group_count;
        progress.next_input_group_index = progress.current_level_first_group_index;
        progress.next_level_first_group_index = progress.next_group_index;
        progress.next_level_group_count = 0;
        progress.reduce_level = progress.reduce_level.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link reduce progress level overflows",
            )
        })?;
        source_pack_store_hierarchical_link_plan_prepare_progress(store, progress)?;
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_stored_reduce_link_group(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    limits: SourcePackJobBatchLimits,
    group_index: usize,
    level: usize,
    first_input_group_index: usize,
    input_group_count: usize,
) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    if level == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has level 0"
        )));
    }
    if input_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has no input groups"
        )));
    }
    let reduce_fanout = limits.normalized().max_jobs_per_batch.max(2);
    if input_group_count > reduce_fanout {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored hierarchical link reduce group {group_index} has {input_group_count} inputs but fanout is {reduce_fanout}"
        )));
    }
    let input_group_end_index = first_input_group_index
        .checked_add(input_group_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "stored hierarchical link reduce input range overflows",
            )
        })?;
    let job_index = schedule_index
        .link_job_index
        .checked_add(group_index)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
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
        if input_group.level + 1 != level {
            return Err(source_pack_library_partition_contract_error(format!(
                "stored hierarchical link reduce group {group_index} level {level} references input group {input_group_index} at level {}",
                input_group.level
            )));
        }
        input_partition_count = input_partition_count
            .checked_add(source_pack_hierarchical_link_group_input_partition_count(
                &input_group,
            ))
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "stored hierarchical link group {group_index} partition count overflows"
                ))
            })?;
        source_byte_count = source_byte_count.saturating_add(input_group.source_byte_count);
        source_file_count = source_file_count.saturating_add(input_group.source_file_count);
        source_line_count = source_line_count.saturating_add(input_group.source_line_count);
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
    validate_source_pack_hierarchical_link_group_page(
        &group,
        schedule_index.target,
        Some(group_index),
    )?;
    Ok(group)
}

pub(in crate::compiler) fn source_pack_store_hierarchical_link_plan_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackHierarchicalLinkPlanPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_hierarchical_link_plan_prepare_progress(
        progress,
        progress.target,
        progress.schedule_partition_count,
        progress.limits,
    )?;
    let path = store.hierarchical_link_plan_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack hierarchical link plan prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack hierarchical link plan prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_hierarchical_link_plan_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_partition_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<SourcePackHierarchicalLinkPlanPrepareProgress, CompileError> {
    let path = store.hierarchical_link_plan_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack hierarchical link plan prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress = serde_json::from_slice::<SourcePackHierarchicalLinkPlanPrepareProgress>(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack hierarchical link plan prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_source_pack_hierarchical_link_plan_prepare_progress(
        &progress,
        target,
        schedule_partition_count,
        limits,
    )?;
    Ok(progress)
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_plan_compact_index(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkPlanIndex,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_hierarchical_link_plan_index(index, index.target)?;
    let path = store.hierarchical_link_plan_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack hierarchical link plan index: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack hierarchical link plan index",
    )?;
    Ok(path)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_push_leaf_link_group(
    groups: &mut Vec<SourcePackHierarchicalLinkGroupPage>,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    codegen_jobs: &[SourcePackJob],
    source_byte_count: usize,
    source_file_count: usize,
    source_line_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    let group_index = groups.len();
    let group = source_pack_leaf_link_group(
        group_index,
        schedule_index,
        page,
        &page.frontend_job,
        source_pack_leaf_link_group_input_frontend_jobs(page, &page.frontend_job),
        codegen_jobs,
        source_byte_count,
        source_file_count,
        source_line_count,
        limits,
    )?;
    groups.push(group);
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_leaf_link_group(
    group_index: usize,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
    frontend_job: &SourcePackJob,
    input_frontend_job_indices: Vec<usize>,
    codegen_jobs: &[SourcePackJob],
    source_byte_count: usize,
    source_file_count: usize,
    source_line_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
    if frontend_job.job_index != page.frontend_job_index
        || frontend_job.phase != SourcePackJobPhase::LibraryFrontend
        || frontend_job.phase_unit_index != page.partition_index
        || frontend_job.library_job_index.is_some()
        || frontend_job.library_id != page.library_id
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "leaf link group {} frontend job {} does not match schedule page {}",
            group_index, frontend_job.job_index, page.partition_index
        )));
    }
    let job_index = schedule_index.link_job_index + group_index;
    let mut input_frontend_job_indices = input_frontend_job_indices;
    input_frontend_job_indices.sort_unstable();
    input_frontend_job_indices.dedup();
    if !input_frontend_job_indices.contains(&page.frontend_job_index) {
        return Err(source_pack_library_partition_contract_error(format!(
            "leaf link group {group_index} does not include frontend job {}",
            page.frontend_job_index
        )));
    }
    let oversized_input = input_frontend_job_indices.len() > limits.max_jobs_per_batch
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
        input_frontend_job_count: input_frontend_job_indices.len(),
        input_frontend_job_indices,
        input_codegen_job_indices: codegen_jobs.iter().map(|job| job.job_index).collect(),
        input_link_group_indices: Vec::new(),
        source_byte_count,
        source_file_count,
        source_line_count,
        oversized_input,
    };
    validate_source_pack_hierarchical_link_group_page(
        &group,
        schedule_index.target,
        Some(group_index),
    )?;
    Ok(group)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_leaf_link_group_input_frontend_jobs(
    page: &SourcePackLibrarySchedulePage,
    frontend_job: &SourcePackJob,
) -> Vec<usize> {
    let mut input_frontend_job_indices = vec![page.frontend_job_index];
    input_frontend_job_indices.extend(frontend_job.dependency_job_indices.iter().copied());
    input_frontend_job_indices
}

pub(in crate::compiler) fn source_pack_stored_leaf_link_group(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "stored leaf link group {} has no frontend inputs",
            group_index
        )));
    }
    let job_index = schedule_index.link_job_index + group_index;
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
    validate_source_pack_hierarchical_link_group_page(
        &group,
        schedule_index.target,
        Some(group_index),
    )?;
    Ok(group)
}

pub(in crate::compiler) fn source_pack_stored_codegen_job_dependency_count(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    job_index: usize,
) -> Result<usize, CompileError> {
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        job_index,
        schedule_index.job_count,
    )?;
    Ok(source_pack_schedule_job_page_dependency_count(&job_page))
}

pub(in crate::compiler) fn source_pack_hierarchical_link_group_input_partition_count(
    group: &SourcePackHierarchicalLinkGroupPage,
) -> usize {
    group
        .input_partition_count
        .max(group.input_partition_indices.len())
}

pub(in crate::compiler) fn source_pack_hierarchical_link_group_input_frontend_job_count(
    group: &SourcePackHierarchicalLinkGroupPage,
) -> usize {
    group
        .input_frontend_job_count
        .max(group.input_frontend_job_indices.len())
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_execution_plan(
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    link_group_pages: &[SourcePackHierarchicalLinkGroupPage],
    artifact_manifest: &SourcePackBuildArtifactManifest,
) -> Result<
    (
        SourcePackHierarchicalLinkExecutionIndex,
        Vec<SourcePackHierarchicalLinkExecutionPage>,
    ),
    CompileError,
> {
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, link_plan_index.target)?;
    validate_source_pack_build_artifact_manifest(artifact_manifest)?;
    if artifact_manifest.target != link_plan_index.target {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution target {:?} does not match artifact manifest target {:?}",
            link_plan_index.target, artifact_manifest.target
        )));
    }
    if link_group_pages.len() != link_plan_index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution has {} link group pages but plan records {}",
            link_group_pages.len(),
            link_plan_index.link_group_count
        )));
    }

    let final_output_ref =
        source_pack_hierarchical_link_execution_final_output_ref(artifact_manifest)?;
    let mut output_keys_by_group = vec![String::new(); link_plan_index.link_group_count];
    let mut pages = Vec::with_capacity(link_group_pages.len());

    for group in link_group_pages {
        validate_source_pack_hierarchical_link_group_page(
            group,
            link_plan_index.target,
            Some(pages.len()),
        )?;
        let final_output = group.group_index == link_plan_index.final_link_group_index;
        let output_key = if final_output {
            final_output_ref.key.clone()
        } else {
            source_pack_hierarchical_link_partial_output_key(
                link_plan_index.target,
                group.group_index,
                group.job_index,
            )
        };

        let (input_interfaces, input_objects, input_group_output_keys) = match group.kind {
            SourcePackHierarchicalLinkGroupKind::Leaf => (
                source_pack_hierarchical_link_execution_output_refs_for_jobs(
                    artifact_manifest,
                    &group.input_frontend_job_indices,
                    SourcePackArtifactKind::LibraryInterface,
                )?,
                source_pack_hierarchical_link_execution_output_refs_for_jobs(
                    artifact_manifest,
                    &group.input_codegen_job_indices,
                    SourcePackArtifactKind::CodegenObject,
                )?,
                Vec::new(),
            ),
            SourcePackHierarchicalLinkGroupKind::Reduce => {
                let input_group_output_keys = group
                    .input_link_group_indices
                    .iter()
                    .map(|&input_group_index| {
                        output_keys_by_group
                            .get(input_group_index)
                            .filter(|key| !key.is_empty())
                            .cloned()
                            .ok_or_else(|| {
                                source_pack_library_partition_contract_error(format!(
                                    "hierarchical link execution group {} references missing output key for input group {}",
                                    group.group_index, input_group_index
                                ))
                            })
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                (Vec::new(), Vec::new(), input_group_output_keys)
            }
        };

        let page = SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target: link_plan_index.target,
            group_index: group.group_index,
            kind: group.kind,
            job_index: group.job_index,
            input_interface_count: input_interfaces.len(),
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces,
            input_object_count: input_objects.len(),
            input_object_page_count: 0,
            input_objects,
            input_group_count: group.input_link_group_indices.len(),
            input_group_page_count: 0,
            input_group_indices: group.input_link_group_indices.clone(),
            input_group_output_keys,
            source_byte_count: group.source_byte_count,
            source_file_count: group.source_file_count,
            source_line_count: group.source_line_count,
            output_key,
            final_output,
        };
        validate_source_pack_hierarchical_link_execution_page(
            &page,
            link_plan_index.target,
            Some(group.group_index),
        )?;
        output_keys_by_group[group.group_index] = page.output_key.clone();
        pages.push(page);
    }

    let index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target: link_plan_index.target,
        first_link_job_index: link_plan_index.first_link_job_index,
        final_link_group_index: link_plan_index.final_link_group_index,
        final_link_job_index: link_plan_index.final_link_job_index,
        link_group_count: pages.len(),
        final_output_key: final_output_ref.key.clone(),
    };
    validate_source_pack_hierarchical_link_execution_index(&index, link_plan_index.target)?;
    validate_source_pack_hierarchical_link_execution_pages(&index, &pages)?;
    Ok((index, pages))
}

#[cfg(test)]
#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct SourcePackLibraryScheduleOutputRefs {
    pub(in crate::compiler) interface_refs_by_job_index: BTreeMap<usize, SourcePackArtifactRef>,
    pub(in crate::compiler) object_refs_by_job_index: BTreeMap<usize, SourcePackArtifactRef>,
    pub(in crate::compiler) final_output_ref: SourcePackArtifactRef,
    pub(in crate::compiler) source_metadata_by_artifact_index:
        BTreeMap<usize, SourcePackArtifactSourceMetadata>,
}

#[cfg(test)]
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct SourcePackArtifactSourceMetadata {
    pub(in crate::compiler) source_bytes: usize,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) source_lines: usize,
}

#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct SourcePackHierarchicalLinkExecutionPrepareProgress {
    pub(in crate::compiler) version: u32,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) link_group_count: usize,
    pub(in crate::compiler) next_group_index: usize,
    pub(in crate::compiler) final_output_seen: bool,
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_prepare_progress(
    progress: &SourcePackHierarchicalLinkExecutionPrepareProgress,
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.link_group_count != link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution prepare progress link group count {} does not match plan link group count {link_group_count}",
            progress.link_group_count
        )));
    }
    if progress.next_group_index > link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution prepare progress next group {} exceeds link group count {link_group_count}",
            progress.next_group_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_execution_from_stored_schedule_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    max_new_groups: usize,
) -> Result<SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult, CompileError> {
    if max_new_groups == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack hierarchical link execution chunk max_new_groups must be greater than zero"
                .into(),
        ));
    }
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, link_plan_index.target)?;
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
    if schedule_index.target != link_plan_index.target {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution chunk target {:?} does not match schedule target {:?}",
            link_plan_index.target, schedule_index.target
        )));
    }
    if schedule_index.link_job_index != link_plan_index.first_link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution chunk first link job {} does not match schedule link job {}",
            link_plan_index.first_link_job_index, schedule_index.link_job_index
        )));
    }
    if artifact_ref_index.final_output_artifact_index != schedule_index.link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Ok(
            SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult {
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
            },
        );
    }

    let progress_path =
        store.hierarchical_link_execution_prepare_progress_path_for_target(link_plan_index.target);
    let mut progress = if progress_path.is_file() {
        source_pack_load_hierarchical_link_execution_prepare_progress(
            store,
            link_plan_index.target,
            link_plan_index.link_group_count,
        )?
    } else {
        SourcePackHierarchicalLinkExecutionPrepareProgress {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
            target: link_plan_index.target,
            link_group_count: link_plan_index.link_group_count,
            next_group_index: 0,
            final_output_seen: false,
        }
    };
    validate_source_pack_hierarchical_link_execution_prepare_progress(
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
        validate_source_pack_hierarchical_link_group_page(
            &group,
            link_plan_index.target,
            Some(progress.next_group_index),
        )?;
        let page = source_pack_hierarchical_link_execution_page_from_stored_artifact_refs(
            store,
            link_plan_index,
            schedule_index,
            &group,
            artifact_ref_index,
        )?;
        progress.final_output_seen |= page.final_output;
        store.store_hierarchical_link_execution_page(&page)?;
        progress.next_group_index = progress.next_group_index.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link execution chunk group index overflows",
            )
        })?;
        new_execution_page_count = new_execution_page_count.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link execution chunk new page count overflows",
            )
        })?;
        source_pack_store_hierarchical_link_execution_prepare_progress(store, &progress)?;
    }

    let mut hierarchical_link_execution_index_path = None;
    if progress.next_group_index == link_plan_index.link_group_count {
        if !progress.final_output_seen {
            return Err(source_pack_library_partition_contract_error(
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
        validate_source_pack_hierarchical_link_execution_index(&index, link_plan_index.target)?;
        hierarchical_link_execution_index_path = Some(
            store_source_pack_hierarchical_link_execution_compact_index(store, &index)?,
        );
    }

    Ok(
        SourcePackFilesystemHierarchicalLinkExecutionPrepareStepResult {
            target: link_plan_index.target,
            complete: hierarchical_link_execution_index_path.is_some(),
            link_group_count: link_plan_index.link_group_count,
            next_group_index: progress.next_group_index,
            new_execution_page_count,
            final_output_seen: progress.final_output_seen,
            final_output_key: artifact_ref_index.final_output_key.clone(),
            hierarchical_link_execution_index_path,
        },
    )
}

pub(in crate::compiler) fn source_pack_store_hierarchical_link_execution_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    progress: &SourcePackHierarchicalLinkExecutionPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_hierarchical_link_execution_prepare_progress(
        progress,
        progress.target,
        progress.link_group_count,
    )?;
    let path = store.hierarchical_link_execution_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack hierarchical link execution prepare progress: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack hierarchical link execution prepare progress",
    )?;
    Ok(path)
}

pub(in crate::compiler) fn source_pack_load_hierarchical_link_execution_prepare_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    link_group_count: usize,
) -> Result<SourcePackHierarchicalLinkExecutionPrepareProgress, CompileError> {
    let path = store.hierarchical_link_execution_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack hierarchical link execution prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<SourcePackHierarchicalLinkExecutionPrepareProgress>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution prepare progress {}: {err}",
                    path.display()
                ))
            })?;
    validate_source_pack_hierarchical_link_execution_prepare_progress(
        &progress,
        target,
        link_group_count,
    )?;
    Ok(progress)
}

pub(in crate::compiler) fn source_pack_hierarchical_link_execution_page_from_stored_artifact_refs(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
    validate_source_pack_hierarchical_link_group_page(
        group,
        link_plan_index.target,
        Some(group.group_index),
    )?;
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
    let final_output = group.group_index == link_plan_index.final_link_group_index;
    let output_key = if final_output {
        artifact_ref_index.final_output_key.clone()
    } else {
        source_pack_hierarchical_link_partial_output_key(
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
                store_source_pack_hierarchical_link_execution_interface_pages_from_stored_leaf_group(
                    store,
                    link_plan_index,
                    schedule_index,
                    group,
                    artifact_ref_index,
                )?;
            let (input_object_count, input_object_page_count) =
                store_source_pack_hierarchical_link_execution_object_pages_from_stored_leaf_group(
                    store,
                    link_plan_index,
                    group,
                    artifact_ref_index,
                )?;
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
                store_source_pack_hierarchical_link_execution_partial_pages_from_stored_reduce_group(
                    store,
                    link_plan_index,
                    group,
                    artifact_ref_index,
                )?;
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
    };
    validate_source_pack_hierarchical_link_execution_page(
        &page,
        link_plan_index.target,
        Some(group.group_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) struct SourcePackHierarchicalLinkExecutionInterfacePageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) group_index: usize,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_interfaces: Vec<SourcePackArtifactRef>,
}

impl<'a> SourcePackHierarchicalLinkExecutionInterfacePageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
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
        let artifact_ref = source_pack_artifact_ref_for_index_from_stored_pages(
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
        validate_source_pack_hierarchical_link_execution_interface_page(
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

pub(in crate::compiler) fn store_source_pack_hierarchical_link_execution_interface_pages_from_stored_leaf_group(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    schedule_index: &SourcePackLibraryScheduleIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
    validate_source_pack_hierarchical_link_group_page(
        group,
        link_plan_index.target,
        Some(group.group_index),
    )?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Leaf {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a leaf group",
            group.group_index
        )));
    }
    let [partition_index] = group.input_partition_indices.as_slice() else {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} has partitions {:?}, expected one",
            group.group_index, group.input_partition_indices
        )));
    };
    let _schedule_page =
        store.load_library_schedule_page_for_target(schedule_index.target, *partition_index)?;
    let mut writer = SourcePackHierarchicalLinkExecutionInterfacePageWriter::new(
        store,
        link_plan_index.target,
        group.group_index,
        group.job_index,
        artifact_ref_index,
    );
    let Some(&first_codegen_job_index) = group.input_codegen_job_indices.first() else {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} has no codegen jobs",
            group.group_index
        )));
    };
    let job_page = store.load_library_schedule_job_page_for_target(
        schedule_index.target,
        first_codegen_job_index,
        schedule_index.job_count,
    )?;
    source_pack_for_each_schedule_job_explicit_dependency_index(
        store,
        schedule_index,
        &job_page,
        |dependency_job_index| writer.push_job(dependency_job_index),
    )?;
    let (explicit_input_interface_count, input_interface_page_count) = writer.finish()?;
    let ranged_input_interface_count =
        source_pack_job_index_range_dependency_count(&job_page.dependency_job_ranges);
    let input_interface_count =
        explicit_input_interface_count.saturating_add(ranged_input_interface_count);
    let expected_input_interface_count =
        source_pack_hierarchical_link_group_input_frontend_job_count(group);
    if input_interface_count != expected_input_interface_count {
        return Err(source_pack_library_partition_contract_error(format!(
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

pub(in crate::compiler) struct SourcePackHierarchicalLinkExecutionObjectPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) group_index: usize,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) artifact_ref_index: &'a SourcePackBuildArtifactRefIndex,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_input_position: usize,
    pub(in crate::compiler) input_count: usize,
    pub(in crate::compiler) current_input_objects: Vec<SourcePackArtifactRef>,
}

impl<'a> SourcePackHierarchicalLinkExecutionObjectPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
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
        let artifact_ref = source_pack_artifact_ref_for_index_from_stored_pages(
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
        validate_source_pack_hierarchical_link_execution_object_page(
            &page,
            self.target,
            self.group_index,
            self.page_index,
        )?;
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

pub(in crate::compiler) fn store_source_pack_hierarchical_link_execution_object_pages_from_stored_leaf_group(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize), CompileError> {
    validate_source_pack_hierarchical_link_group_page(
        group,
        link_plan_index.target,
        Some(group.group_index),
    )?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Leaf {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a leaf group",
            group.group_index
        )));
    }
    let mut writer = SourcePackHierarchicalLinkExecutionObjectPageWriter::new(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution leaf group {} wrote {} object inputs but expected {}",
            group.group_index,
            input_object_count,
            group.input_codegen_job_indices.len()
        )));
    }
    Ok((input_object_count, input_object_page_count))
}

pub(in crate::compiler) struct SourcePackHierarchicalLinkExecutionPartialPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
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

impl<'a> SourcePackHierarchicalLinkExecutionPartialPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
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
        let output_key = source_pack_hierarchical_link_execution_output_key_for_group(
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
        validate_source_pack_hierarchical_link_execution_partial_page(
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

pub(in crate::compiler) fn store_source_pack_hierarchical_link_execution_partial_pages_from_stored_reduce_group(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    group: &SourcePackHierarchicalLinkGroupPage,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
) -> Result<(usize, usize), CompileError> {
    validate_source_pack_hierarchical_link_group_page(
        group,
        link_plan_index.target,
        Some(group.group_index),
    )?;
    if group.kind != SourcePackHierarchicalLinkGroupKind::Reduce {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} is not a reduce group",
            group.group_index
        )));
    }
    let mut writer = SourcePackHierarchicalLinkExecutionPartialPageWriter::new(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution reduce group {} wrote {} partial inputs but expected {}",
            group.group_index,
            input_group_count,
            group.input_link_group_indices.len()
        )));
    }
    Ok((input_group_count, input_group_page_count))
}

pub(in crate::compiler) fn source_pack_hierarchical_link_execution_output_key_for_group(
    store: &SourcePackFilesystemArtifactStore,
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    group_index: usize,
) -> Result<String, CompileError> {
    if group_index == link_plan_index.final_link_group_index {
        validate_source_pack_build_artifact_ref_index(artifact_ref_index, link_plan_index.target)?;
        return Ok(artifact_ref_index.final_output_key.clone());
    }
    let group =
        store.load_hierarchical_link_group_page_for_target(link_plan_index.target, group_index)?;
    Ok(source_pack_hierarchical_link_partial_output_key(
        link_plan_index.target,
        group.group_index,
        group.job_index,
    ))
}

pub(in crate::compiler) fn store_source_pack_hierarchical_link_execution_compact_index(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkExecutionIndex,
) -> Result<PathBuf, CompileError> {
    validate_source_pack_hierarchical_link_execution_index(index, index.target)?;
    let path = store.hierarchical_link_execution_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "serialize source-pack hierarchical link execution index: {err}"
        ))
    })?;
    write_source_pack_filesystem_file_atomically(
        &path,
        &bytes,
        "source-pack hierarchical link execution index",
    )?;
    Ok(path)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_execution_plan_from_schedule_pages(
    link_plan_index: &SourcePackHierarchicalLinkPlanIndex,
    link_group_pages: &[SourcePackHierarchicalLinkGroupPage],
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
) -> Result<
    (
        SourcePackHierarchicalLinkExecutionIndex,
        Vec<SourcePackHierarchicalLinkExecutionPage>,
    ),
    CompileError,
> {
    validate_source_pack_hierarchical_link_plan_index(link_plan_index, link_plan_index.target)?;
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    if schedule_index.target != link_plan_index.target {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution target {:?} does not match schedule target {:?}",
            link_plan_index.target, schedule_index.target
        )));
    }
    if schedule_index.link_job_index != link_plan_index.first_link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution first link job {} does not match schedule link job {}",
            link_plan_index.first_link_job_index, schedule_index.link_job_index
        )));
    }
    if link_group_pages.len() != link_plan_index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution has {} link group pages but plan records {}",
            link_group_pages.len(),
            link_plan_index.link_group_count
        )));
    }

    let output_refs = source_pack_library_schedule_output_refs(schedule_index, schedule_pages)?;
    let mut output_keys_by_group = vec![String::new(); link_plan_index.link_group_count];
    let mut pages = Vec::with_capacity(link_group_pages.len());

    for group in link_group_pages {
        validate_source_pack_hierarchical_link_group_page(
            group,
            link_plan_index.target,
            Some(pages.len()),
        )?;
        let final_output = group.group_index == link_plan_index.final_link_group_index;
        let output_key = if final_output {
            output_refs.final_output_ref.key.clone()
        } else {
            source_pack_hierarchical_link_partial_output_key(
                link_plan_index.target,
                group.group_index,
                group.job_index,
            )
        };

        let (input_interfaces, input_objects, input_group_output_keys) = match group.kind {
            SourcePackHierarchicalLinkGroupKind::Leaf => (
                source_pack_hierarchical_link_execution_output_refs_from_schedule(
                    &output_refs.interface_refs_by_job_index,
                    &group.input_frontend_job_indices,
                    SourcePackArtifactKind::LibraryInterface,
                )?,
                source_pack_hierarchical_link_execution_output_refs_from_schedule(
                    &output_refs.object_refs_by_job_index,
                    &group.input_codegen_job_indices,
                    SourcePackArtifactKind::CodegenObject,
                )?,
                Vec::new(),
            ),
            SourcePackHierarchicalLinkGroupKind::Reduce => {
                let input_group_output_keys = group
                    .input_link_group_indices
                    .iter()
                    .map(|&input_group_index| {
                        output_keys_by_group
                            .get(input_group_index)
                            .filter(|key| !key.is_empty())
                            .cloned()
                            .ok_or_else(|| {
                                source_pack_library_partition_contract_error(format!(
                                    "hierarchical link execution group {} references missing output key for input group {}",
                                    group.group_index, input_group_index
                                ))
                            })
                    })
                    .collect::<Result<Vec<_>, _>>()?;
                (Vec::new(), Vec::new(), input_group_output_keys)
            }
        };

        let page = SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target: link_plan_index.target,
            group_index: group.group_index,
            kind: group.kind,
            job_index: group.job_index,
            input_interface_count: input_interfaces.len(),
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces,
            input_object_count: input_objects.len(),
            input_object_page_count: 0,
            input_objects,
            input_group_count: group.input_link_group_indices.len(),
            input_group_page_count: 0,
            input_group_indices: group.input_link_group_indices.clone(),
            input_group_output_keys,
            source_byte_count: group.source_byte_count,
            source_file_count: group.source_file_count,
            source_line_count: group.source_line_count,
            output_key,
            final_output,
        };
        validate_source_pack_hierarchical_link_execution_page(
            &page,
            link_plan_index.target,
            Some(group.group_index),
        )?;
        output_keys_by_group[group.group_index] = page.output_key.clone();
        pages.push(page);
    }

    let index = SourcePackHierarchicalLinkExecutionIndex {
        version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
        target: link_plan_index.target,
        first_link_job_index: link_plan_index.first_link_job_index,
        final_link_group_index: link_plan_index.final_link_group_index,
        final_link_job_index: link_plan_index.final_link_job_index,
        link_group_count: pages.len(),
        final_output_key: output_refs.final_output_ref.key.clone(),
    };
    validate_source_pack_hierarchical_link_execution_index(&index, link_plan_index.target)?;
    validate_source_pack_hierarchical_link_execution_pages(&index, &pages)?;
    Ok((index, pages))
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_schedule_output_refs(
    schedule_index: &SourcePackLibraryScheduleIndex,
    schedule_pages: &[SourcePackLibrarySchedulePage],
) -> Result<SourcePackLibraryScheduleOutputRefs, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    if schedule_pages.len() != schedule_index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule output refs have {} schedule pages but schedule index partition_count {}",
            schedule_pages.len(),
            schedule_index.partition_count
        )));
    }

    let mut interface_refs_by_job_index = BTreeMap::new();
    let mut object_refs_by_job_index = BTreeMap::new();
    let mut source_metadata_by_artifact_index = BTreeMap::new();
    let mut total_source_file_count = 0usize;
    let mut total_source_byte_count = 0usize;
    let mut total_source_line_count = 0usize;

    for page in schedule_pages {
        validate_source_pack_library_schedule_page(
            page,
            schedule_index.target,
            Some(page.partition_index),
        )?;
        let frontend_jobs = if page.frontend_jobs.is_empty() {
            vec![page.frontend_job.clone()]
        } else {
            page.frontend_jobs.clone()
        };
        for frontend_job in frontend_jobs {
            total_source_file_count = total_source_file_count.max(
                frontend_job
                    .first_source_index
                    .saturating_add(frontend_job.source_file_count),
            );
            total_source_byte_count =
                total_source_byte_count.saturating_add(frontend_job.source_bytes);
            total_source_line_count =
                total_source_line_count.saturating_add(frontend_job.source_lines);
            let frontend_ref = source_pack_scheduled_job_output_ref(
                &frontend_job,
                SourcePackArtifactKind::LibraryInterface,
                schedule_index.target,
            )?;
            source_metadata_by_artifact_index.insert(
                frontend_ref.artifact_index,
                SourcePackArtifactSourceMetadata {
                    source_bytes: frontend_job.source_bytes,
                    source_file_count: frontend_job.source_file_count,
                    source_lines: frontend_job.source_lines,
                },
            );
            if interface_refs_by_job_index
                .insert(frontend_ref.producing_job_index, frontend_ref)
                .is_some()
            {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule output refs duplicate frontend job {}",
                    frontend_job.job_index
                )));
            }
        }

        for job in &page.codegen_jobs {
            let object_ref = source_pack_scheduled_job_output_ref(
                job,
                SourcePackArtifactKind::CodegenObject,
                schedule_index.target,
            )?;
            source_metadata_by_artifact_index.insert(
                object_ref.artifact_index,
                SourcePackArtifactSourceMetadata {
                    source_bytes: job.source_bytes,
                    source_file_count: job.source_file_count,
                    source_lines: job.source_lines,
                },
            );
            if object_refs_by_job_index
                .insert(object_ref.producing_job_index, object_ref)
                .is_some()
            {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule output refs duplicate codegen job {}",
                    job.job_index
                )));
            }
        }
    }

    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if interface_refs_by_job_index.len() != frontend_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule output refs recorded {} interface outputs but schedule index frontend_job_count {}",
            interface_refs_by_job_index.len(),
            frontend_job_count
        )));
    }
    if object_refs_by_job_index.len() != schedule_index.codegen_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule output refs recorded {} object outputs but schedule index codegen_job_count {}",
            object_refs_by_job_index.len(),
            schedule_index.codegen_job_count
        )));
    }

    let final_output_ref = SourcePackArtifactRef {
        artifact_index: schedule_index.link_job_index,
        key: source_pack_artifact_key_for_output(
            schedule_index.target,
            SourcePackArtifactKind::LinkedOutput,
            u32::MAX,
            schedule_index.link_job_index,
            0,
            total_source_file_count,
        ),
        producing_job_index: schedule_index.link_job_index,
        kind: SourcePackArtifactKind::LinkedOutput,
    };
    source_metadata_by_artifact_index.insert(
        final_output_ref.artifact_index,
        SourcePackArtifactSourceMetadata {
            source_bytes: total_source_byte_count,
            source_file_count: total_source_file_count,
            source_lines: total_source_line_count,
        },
    );

    Ok(SourcePackLibraryScheduleOutputRefs {
        interface_refs_by_job_index,
        object_refs_by_job_index,
        final_output_ref,
        source_metadata_by_artifact_index,
    })
}

pub(in crate::compiler) fn source_pack_scheduled_job_output_ref(
    job: &SourcePackJob,
    kind: SourcePackArtifactKind,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackArtifactRef, CompileError> {
    let expected_kind = match job.phase {
        SourcePackJobPhase::LibraryFrontend => SourcePackArtifactKind::LibraryInterface,
        SourcePackJobPhase::Codegen => SourcePackArtifactKind::CodegenObject,
        SourcePackJobPhase::Link => {
            return Err(source_pack_library_partition_contract_error(format!(
                "link job {} output refs require total source metadata",
                job.job_index
            )));
        }
    };
    if kind != expected_kind {
        return Err(source_pack_library_partition_contract_error(format!(
            "job {} phase {:?} cannot produce {:?}",
            job.job_index, job.phase, kind
        )));
    }
    Ok(SourcePackArtifactRef {
        artifact_index: job.job_index,
        key: source_pack_artifact_key_for_output(
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

#[cfg(test)]
pub(in crate::compiler) fn store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
) -> Result<SourcePackBuildArtifactRefIndex, CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let mut interface_artifact_count = 0usize;
    let mut object_artifact_count = 0usize;
    let mut total_source_file_count = 0usize;
    let mut total_source_byte_count = 0usize;
    let mut total_source_line_count = 0usize;

    for partition_index in 0..schedule_index.partition_count {
        let page =
            store.load_library_schedule_page_for_target(schedule_index.target, partition_index)?;
        validate_source_pack_library_schedule_page(
            &page,
            schedule_index.target,
            Some(partition_index),
        )?;
        source_pack_for_each_stored_schedule_frontend_job(
            store,
            schedule_index,
            &page,
            |_frontend_job_offset, frontend_job, _dependency_job_count| {
                total_source_file_count = total_source_file_count.max(
                    frontend_job
                        .first_source_index
                        .saturating_add(frontend_job.source_file_count),
                );
                total_source_byte_count =
                    total_source_byte_count.saturating_add(frontend_job.source_bytes);
                total_source_line_count =
                    total_source_line_count.saturating_add(frontend_job.source_lines);

                let frontend_ref = source_pack_scheduled_job_output_ref(
                    &frontend_job,
                    SourcePackArtifactKind::LibraryInterface,
                    schedule_index.target,
                )?;
                let frontend_page = source_pack_build_artifact_ref_page(
                    schedule_index.target,
                    frontend_ref,
                    frontend_job.source_bytes,
                    frontend_job.source_file_count,
                    frontend_job.source_lines,
                )?;
                store.store_build_artifact_ref_page(&frontend_page, schedule_index.job_count)?;
                interface_artifact_count += 1;
                Ok(())
            },
        )?;

        source_pack_for_each_stored_schedule_codegen_job(
            store,
            schedule_index,
            &page,
            |_codegen_job_offset, job| {
                let object_ref = source_pack_scheduled_job_output_ref(
                    &job,
                    SourcePackArtifactKind::CodegenObject,
                    schedule_index.target,
                )?;
                let object_page = source_pack_build_artifact_ref_page(
                    schedule_index.target,
                    object_ref,
                    job.source_bytes,
                    job.source_file_count,
                    job.source_lines,
                )?;
                store.store_build_artifact_ref_page(&object_page, schedule_index.job_count)?;
                object_artifact_count += 1;
                Ok(())
            },
        )?;
    }

    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if interface_artifact_count != frontend_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "stored artifact refs recorded {} interface artifacts but schedule index frontend_job_count {}",
            interface_artifact_count, frontend_job_count
        )));
    }
    if object_artifact_count != schedule_index.codegen_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "stored artifact refs recorded {} object artifacts but schedule index codegen_job_count {}",
            object_artifact_count, schedule_index.codegen_job_count
        )));
    }

    let final_output_ref = SourcePackArtifactRef {
        artifact_index: schedule_index.link_job_index,
        key: source_pack_artifact_key_for_output(
            schedule_index.target,
            SourcePackArtifactKind::LinkedOutput,
            u32::MAX,
            schedule_index.link_job_index,
            0,
            total_source_file_count,
        ),
        producing_job_index: schedule_index.link_job_index,
        kind: SourcePackArtifactKind::LinkedOutput,
    };
    let final_output_page = source_pack_build_artifact_ref_page(
        schedule_index.target,
        final_output_ref.clone(),
        total_source_byte_count,
        total_source_file_count,
        total_source_line_count,
    )?;
    store.store_build_artifact_ref_page(&final_output_page, schedule_index.job_count)?;

    let index = SourcePackBuildArtifactRefIndex {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
        target: schedule_index.target,
        artifact_count: schedule_index.job_count,
        interface_artifact_count,
        object_artifact_count,
        final_output_artifact_index: final_output_ref.artifact_index,
        final_output_key: final_output_ref.key,
        total_source_file_count,
        total_source_byte_count,
        total_source_line_count,
    };
    validate_source_pack_build_artifact_ref_index(&index, schedule_index.target)?;
    store.store_build_artifact_ref_index(&index)?;
    Ok(index)
}

pub(in crate::compiler) fn validate_source_pack_build_artifact_ref_prepare_progress(
    progress: &SourcePackBuildArtifactRefPrepareProgress,
    schedule_index: &SourcePackLibraryScheduleIndex,
    library_partition_index: &SourcePackLibraryPartitionIndex,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_library_partition_index(library_partition_index, schedule_index.target)?;
    if progress.version != SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack artifact-ref prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != schedule_index.target {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress target {:?} does not match schedule target {:?}",
            progress.target, schedule_index.target
        )));
    }
    if progress.partition_count != schedule_index.partition_count
        || progress.partition_count != library_partition_index.partition_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress partition count {} does not match schedule/metadata counts {}/{}",
            progress.partition_count,
            schedule_index.partition_count,
            library_partition_index.partition_count
        )));
    }
    if progress.artifact_count != schedule_index.job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress artifact count {} does not match schedule job count {}",
            progress.artifact_count, schedule_index.job_count
        )));
    }
    if progress.next_partition_index > progress.partition_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress next partition {} exceeds partition count {}",
            progress.next_partition_index, progress.partition_count
        )));
    }
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if progress.interface_artifact_count > frontend_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress interface artifact count {} exceeds schedule frontend job count {frontend_job_count}",
            progress.interface_artifact_count
        )));
    }
    if progress.object_artifact_count > schedule_index.codegen_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress object artifact count {} exceeds schedule codegen job count {}",
            progress.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    let expected_page_count = progress
        .interface_artifact_count
        .checked_add(progress.object_artifact_count)
        .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(
                "artifact-ref prepare progress page count overflows",
            )
        })?;
    if progress.artifact_ref_page_count != expected_page_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref prepare progress page count {} does not match interface/object count {}",
            progress.artifact_ref_page_count, expected_page_count
        )));
    }
    if progress.total_source_file_count != library_partition_index.source_file_count
        || progress.total_source_byte_count != library_partition_index.source_byte_count
        || progress.total_source_line_count != library_partition_index.source_line_count
    {
        return Err(source_pack_artifact_shard_contract_error(format!(
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

pub(in crate::compiler) fn store_source_pack_build_artifact_ref_pages_from_stored_schedule_pages_chunk(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    max_new_libraries: usize,
) -> Result<SourcePackFilesystemArtifactRefPrepareStepResult, CompileError> {
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact-ref chunk max_new_libraries must be greater than zero".into(),
        ));
    }
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    let metadata_index = store.load_library_partition_index_for_target(schedule_index.target)?;
    validate_source_pack_library_partition_index(&metadata_index, schedule_index.target)?;
    if metadata_index.partition_count != schedule_index.partition_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref chunk schedule has {} partitions but metadata has {}",
            schedule_index.partition_count, metadata_index.partition_count
        )));
    }
    if store
        .build_artifact_ref_index_path_for_target(schedule_index.target)
        .is_file()
    {
        let index = store.load_build_artifact_ref_index_for_target(schedule_index.target)?;
        return Ok(SourcePackFilesystemArtifactRefPrepareStepResult {
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
        SourcePackBuildArtifactRefPrepareProgress {
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
    validate_source_pack_build_artifact_ref_prepare_progress(
        &progress,
        schedule_index,
        &metadata_index,
    )?;

    let mut new_library_count = 0usize;
    while progress.next_partition_index < schedule_index.partition_count
        && new_library_count < max_new_libraries
    {
        let partition_index = progress.next_partition_index;
        let page =
            store.load_library_schedule_page_for_target(schedule_index.target, partition_index)?;
        validate_source_pack_library_schedule_page(
            &page,
            schedule_index.target,
            Some(partition_index),
        )?;
        let frontend_job_count = source_pack_library_schedule_page_frontend_job_count(&page);
        let partition_artifact_ref_count = frontend_job_count
            .checked_add(page.codegen_job_count)
            .ok_or_else(|| {
            source_pack_artifact_shard_contract_error(format!(
                "artifact-ref page count overflows at partition {partition_index}"
            ))
        })?;
        source_pack_store_artifact_ref_pages_for_schedule_partition(store, schedule_index, &page)?;
        progress.interface_artifact_count = progress
            .interface_artifact_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "artifact-ref interface count overflows at partition {partition_index}"
                ))
            })?;
        progress.object_artifact_count = progress
            .object_artifact_count
            .checked_add(page.codegen_job_count)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "artifact-ref object count overflows at partition {partition_index}"
                ))
            })?;
        progress.artifact_ref_page_count = progress
            .artifact_ref_page_count
            .checked_add(partition_artifact_ref_count)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "artifact-ref page count overflows at partition {partition_index}"
                ))
            })?;
        progress.next_partition_index =
            progress
                .next_partition_index
                .checked_add(1)
                .ok_or_else(|| {
                    source_pack_artifact_shard_contract_error(
                        "artifact-ref next partition index overflows",
                    )
                })?;
        new_library_count = new_library_count.checked_add(1).ok_or_else(|| {
            source_pack_artifact_shard_contract_error("artifact-ref new library count overflows")
        })?;
        store.store_build_artifact_ref_prepare_progress(
            &progress,
            schedule_index,
            &metadata_index,
        )?;
    }

    let total_interface_artifact_count =
        source_pack_library_schedule_index_frontend_job_count(schedule_index);
    if progress.next_partition_index < schedule_index.partition_count {
        return Ok(SourcePackFilesystemArtifactRefPrepareStepResult {
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
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref chunk recorded {} interface artifacts but schedule index frontend_job_count {}",
            progress.interface_artifact_count, total_interface_artifact_count
        )));
    }
    if progress.object_artifact_count != schedule_index.codegen_job_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref chunk recorded {} object artifacts but schedule index codegen_job_count {}",
            progress.object_artifact_count, schedule_index.codegen_job_count
        )));
    }
    if progress.artifact_ref_page_count != schedule_index.link_job_index {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref chunk stored {} non-link artifact pages but schedule link job starts at {}",
            progress.artifact_ref_page_count, schedule_index.link_job_index
        )));
    }
    let final_output_ref = SourcePackArtifactRef {
        artifact_index: schedule_index.link_job_index,
        key: source_pack_artifact_key_for_output(
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
    let final_output_page = source_pack_build_artifact_ref_page(
        schedule_index.target,
        final_output_ref.clone(),
        metadata_index.source_byte_count,
        metadata_index.source_file_count,
        metadata_index.source_line_count,
    )?;
    store.store_build_artifact_ref_page(&final_output_page, schedule_index.job_count)?;
    let artifact_ref_page_count =
        progress
            .artifact_ref_page_count
            .checked_add(1)
            .ok_or_else(|| {
                source_pack_artifact_shard_contract_error("artifact-ref page count overflows")
            })?;

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
    validate_source_pack_build_artifact_ref_index(&index, schedule_index.target)?;
    let artifact_ref_index_path = store.store_build_artifact_ref_index(&index)?;
    Ok(SourcePackFilesystemArtifactRefPrepareStepResult {
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

pub(in crate::compiler) fn source_pack_store_artifact_ref_pages_for_schedule_partition(
    store: &SourcePackFilesystemArtifactStore,
    schedule_index: &SourcePackLibraryScheduleIndex,
    page: &SourcePackLibrarySchedulePage,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(schedule_index, schedule_index.target)?;
    validate_source_pack_library_schedule_page(
        page,
        schedule_index.target,
        Some(page.partition_index),
    )?;
    source_pack_for_each_stored_schedule_frontend_job(
        store,
        schedule_index,
        page,
        |_frontend_job_offset, frontend_job, _dependency_job_count| {
            let frontend_ref = source_pack_scheduled_job_output_ref(
                &frontend_job,
                SourcePackArtifactKind::LibraryInterface,
                schedule_index.target,
            )?;
            let frontend_page = source_pack_build_artifact_ref_page(
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

    source_pack_for_each_stored_schedule_codegen_job(
        store,
        schedule_index,
        page,
        |_codegen_job_offset, job| {
            let object_ref = source_pack_scheduled_job_output_ref(
                &job,
                SourcePackArtifactKind::CodegenObject,
                schedule_index.target,
            )?;
            let object_page = source_pack_build_artifact_ref_page(
                schedule_index.target,
                object_ref,
                job.source_bytes,
                job.source_file_count,
                job.source_lines,
            )?;
            store.store_build_artifact_ref_page(&object_page, schedule_index.job_count)?;
            Ok(())
        },
    )
}

pub(in crate::compiler) fn source_pack_build_artifact_ref_page(
    target: SourcePackArtifactTarget,
    artifact_ref: SourcePackArtifactRef,
    source_bytes: usize,
    source_file_count: usize,
    source_lines: usize,
) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
    let page = SourcePackBuildArtifactRefPage {
        version: SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
        target,
        artifact_index: artifact_ref.artifact_index,
        artifact_ref,
        source_bytes,
        source_file_count,
        source_lines,
    };
    validate_source_pack_build_artifact_ref_page(
        &page,
        target,
        page.artifact_index.saturating_add(1),
        Some(page.artifact_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_load_artifact_ref_page_for_index(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_index: usize,
) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
    validate_source_pack_build_artifact_ref_index(artifact_ref_index, target)?;
    store.load_build_artifact_ref_page_for_target(
        target,
        artifact_index,
        artifact_ref_index.artifact_count,
    )
}

pub(in crate::compiler) fn source_pack_artifact_ref_for_index_from_stored_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_index: usize,
    kind: SourcePackArtifactKind,
) -> Result<SourcePackArtifactRef, CompileError> {
    let page = source_pack_load_artifact_ref_page_for_index(
        store,
        target,
        artifact_ref_index,
        artifact_index,
    )?;
    if page.artifact_ref.kind != kind {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "artifact-ref page {} has kind {:?}; expected {:?}",
            artifact_index, page.artifact_ref.kind, kind
        )));
    }
    Ok(page.artifact_ref)
}

pub(in crate::compiler) fn source_pack_artifact_refs_for_indices_from_stored_pages(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    artifact_ref_index: &SourcePackBuildArtifactRefIndex,
    artifact_indices: &[usize],
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    artifact_indices
        .iter()
        .map(|&artifact_index| {
            Ok(source_pack_load_artifact_ref_page_for_index(
                store,
                target,
                artifact_ref_index,
                artifact_index,
            )?
            .artifact_ref)
        })
        .collect()
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_execution_output_refs_from_schedule(
    refs_by_job_index: &BTreeMap<usize, SourcePackArtifactRef>,
    job_indices: &[usize],
    kind: SourcePackArtifactKind,
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    job_indices
        .iter()
        .map(|&job_index| {
            refs_by_job_index.get(&job_index).cloned().ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "hierarchical link execution references missing {:?} output for job {}",
                    kind, job_index
                ))
            })
        })
        .collect()
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_execution_final_output_ref(
    artifact_manifest: &SourcePackBuildArtifactManifest,
) -> Result<SourcePackArtifactRef, CompileError> {
    let link_job = artifact_manifest
        .job_schedule
        .jobs
        .iter()
        .find(|job| job.phase == SourcePackJobPhase::Link)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "hierarchical link execution artifact manifest has no link job",
            )
        })?;
    let job_manifest =
        source_pack_job_artifact_manifest(&artifact_manifest.job_artifacts, link_job.job_index)?;
    Ok(single_output_artifact_ref(job_manifest, SourcePackArtifactKind::LinkedOutput)?.clone())
}

pub(in crate::compiler) fn source_pack_hierarchical_link_partial_output_key(
    target: SourcePackArtifactTarget,
    group_index: usize,
    job_index: usize,
) -> String {
    let key = format!("partial-link/group-{group_index:08}/job-{job_index:08}");
    match target.key_prefix() {
        Some(prefix) => format!("{prefix}/{key}"),
        None => key,
    }
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_hierarchical_link_execution_output_refs_for_jobs(
    artifact_manifest: &SourcePackBuildArtifactManifest,
    job_indices: &[usize],
    kind: SourcePackArtifactKind,
) -> Result<Vec<SourcePackArtifactRef>, CompileError> {
    job_indices
        .iter()
        .map(|&job_index| {
            let job_manifest =
                source_pack_job_artifact_manifest(&artifact_manifest.job_artifacts, job_index)?;
            Ok(single_output_artifact_ref(job_manifest, kind)?.clone())
        })
        .collect()
}

pub(in crate::compiler) fn source_pack_hierarchical_link_execution_input_interface_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_interface_count
        .max(page.input_interfaces.len().saturating_add(
            source_pack_job_index_range_dependency_count(&page.input_interface_ranges),
        ))
}

pub(in crate::compiler) fn source_pack_hierarchical_link_execution_input_object_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_object_count.max(page.input_objects.len())
}

pub(in crate::compiler) fn source_pack_hierarchical_link_execution_input_group_count(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> usize {
    page.input_group_count.max(page.input_group_indices.len())
}
