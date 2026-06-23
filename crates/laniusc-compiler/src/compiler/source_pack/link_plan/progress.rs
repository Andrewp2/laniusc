use super::super::*;

/// Resumable checkpoint for hierarchical link-plan construction.
///
/// Leaf groups are prepared from schedule partitions first. Once every leaf is
/// written, reduce progress tracks the current tree level, the next input group
/// to consume, and the next output group index to assign.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub(in crate::compiler) struct HierarchicalLinkPlanPrepareProgress {
    /// Serialization version for this checkpoint.
    pub(in crate::compiler) version: u32,
    /// Artifact target whose link plan is being prepared.
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    /// Normalized batching limits used to build leaf and reduce groups.
    pub(in crate::compiler) limits: SourcePackJobBatchLimits,
    /// Number of schedule partitions that must produce leaf groups.
    pub(in crate::compiler) schedule_partition_count: usize,
    /// Next schedule partition to scan for leaf groups.
    pub(in crate::compiler) next_partition_index: usize,
    /// Number of leaf groups recorded before reduce processing began.
    pub(in crate::compiler) leaf_group_count: usize,
    /// Current reduce tree level, with zero meaning reduce state is not initialized.
    pub(in crate::compiler) reduce_level: usize,
    /// First group index in the current reduce level.
    pub(in crate::compiler) current_level_first_group_index: usize,
    /// Number of groups in the current reduce level.
    pub(in crate::compiler) current_level_group_count: usize,
    /// Next current-level group to consume into a reduce group.
    pub(in crate::compiler) next_input_group_index: usize,
    /// First group index reserved for the next reduce level.
    pub(in crate::compiler) next_level_first_group_index: usize,
    /// Number of groups already written into the next reduce level.
    pub(in crate::compiler) next_level_group_count: usize,
    /// Next link group index to assign.
    pub(in crate::compiler) next_group_index: usize,
}

/// Validates hierarchical link-plan preparation progress.
///
/// Before leaf groups are complete, reduce state must be empty. After leaf
/// completion, the current-level and next-level ranges must form a consistent
/// prefix of the written group table.
pub(in crate::compiler) fn validate_link_plan_prepare_progress(
    progress: &HierarchicalLinkPlanPrepareProgress,
    target: SourcePackArtifactTarget,
    schedule_partition_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link plan prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.limits != limits.normalized() {
        return Err(library_partition_contract_error(
            "hierarchical link plan prepare progress was created with different limits",
        ));
    }
    if progress.schedule_partition_count != schedule_partition_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress partition count {} does not match schedule partition count {schedule_partition_count}",
            progress.schedule_partition_count
        )));
    }
    if progress.next_partition_index > schedule_partition_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next partition {} exceeds schedule partition count {schedule_partition_count}",
            progress.next_partition_index
        )));
    }
    if progress.leaf_group_count > progress.next_group_index {
        return Err(library_partition_contract_error(format!(
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
            return Err(library_partition_contract_error(
                "hierarchical link plan prepare progress has reduce state before leaf groups are complete",
            ));
        }
        return Ok(());
    }
    if reduce_state_empty {
        return Ok(());
    }
    if progress.leaf_group_count == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link plan prepare progress has reduce state without leaf groups",
        ));
    }
    if progress.reduce_level == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link plan prepare progress has reduce groups but no reduce level",
        ));
    }
    if progress.current_level_group_count == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link plan prepare progress has empty current reduce level",
        ));
    }
    let current_level_end = progress
        .current_level_first_group_index
        .checked_add(progress.current_level_group_count)
        .ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link plan prepare progress current level range overflows",
            )
        })?;
    if current_level_end > progress.next_group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress current level end {current_level_end} exceeds next group {}",
            progress.next_group_index
        )));
    }
    if progress.next_input_group_index < progress.current_level_first_group_index
        || progress.next_input_group_index > current_level_end
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next input group {} is outside current level {}..{}",
            progress.next_input_group_index,
            progress.current_level_first_group_index,
            current_level_end
        )));
    }
    if progress.next_level_first_group_index < current_level_end {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next level starts at {} before current level end {current_level_end}",
            progress.next_level_first_group_index
        )));
    }
    let expected_next_group_index = progress
        .next_level_first_group_index
        .checked_add(progress.next_level_group_count)
        .ok_or_else(|| {
            library_partition_contract_error(
                "hierarchical link plan prepare progress next level range overflows",
            )
        })?;
    if expected_next_group_index != progress.next_group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan prepare progress next level range ends at {expected_next_group_index} but next group is {}",
            progress.next_group_index
        )));
    }
    Ok(())
}

/// Initializes reduce-tree progress after all leaf groups are written.
///
/// The first reduce level consumes the complete leaf range and writes output
/// groups starting at the next unused group index.
pub(in crate::compiler) fn initialize_reduce_progress(
    progress: &mut HierarchicalLinkPlanPrepareProgress,
) -> Result<(), CompileError> {
    if progress.next_partition_index != progress.schedule_partition_count {
        return Err(library_partition_contract_error(
            "cannot initialize hierarchical link reduce progress before leaf groups are complete",
        ));
    }
    progress.leaf_group_count = progress.next_group_index;
    if progress.leaf_group_count == 0 {
        return Err(library_partition_contract_error(
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

/// Stores the resumable hierarchical link-plan checkpoint.
pub(in crate::compiler) fn store_link_plan_prepare_progress(
    store: &FilesystemArtifactStore,
    progress: &HierarchicalLinkPlanPrepareProgress,
) -> Result<PathBuf, CompileError> {
    validate_link_plan_prepare_progress(
        progress,
        progress.target,
        progress.schedule_partition_count,
        progress.limits,
    )?;
    let path = store.hierarchical_link_plan_prepare_progress_path_for_target(progress.target);
    let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "serialize source-pack hierarchical link plan prepare progress: {err}"
        ))
    })?;
    write_file_atomic(
        &path,
        &bytes,
        "source-pack hierarchical link plan prepare progress",
    )?;
    Ok(path)
}

/// Loads and validates hierarchical link-plan preparation progress.
pub(in crate::compiler) fn load_link_plan_prepare_progress(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    schedule_partition_count: usize,
    limits: SourcePackJobBatchLimits,
) -> Result<HierarchicalLinkPlanPrepareProgress, CompileError> {
    let path = store.hierarchical_link_plan_prepare_progress_path_for_target(target);
    let bytes = fs::read(&path).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "read source-pack hierarchical link plan prepare progress {}: {err}",
            path.display()
        ))
    })?;
    let progress =
        serde_json::from_slice::<HierarchicalLinkPlanPrepareProgress>(&bytes).map_err(|err| {
            source_pack_store_metadata_error(format!(
                "parse source-pack hierarchical link plan prepare progress {}: {err}",
                path.display()
            ))
        })?;
    validate_link_plan_prepare_progress(&progress, target, schedule_partition_count, limits)?;
    Ok(progress)
}

/// Stores the final hierarchical link-plan index.
///
/// The index identifies the first link job, final link group/job, and total
/// number of link groups used by the execution plan.
pub(in crate::compiler) fn store_link_plan_index(
    store: &FilesystemArtifactStore,
    index: &SourcePackHierarchicalLinkPlanIndex,
) -> Result<PathBuf, CompileError> {
    validate_link_plan_index(index, index.target)?;
    let path = store.hierarchical_link_plan_index_path_for_target(index.target);
    let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
        source_pack_store_metadata_error(format!(
            "serialize source-pack hierarchical link plan index: {err}"
        ))
    })?;
    write_file_atomic(&path, &bytes, "source-pack hierarchical link plan index")?;
    Ok(path)
}
