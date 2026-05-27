use super::*;

pub(in crate::compiler) fn validate_link_plan_index(
    index: &SourcePackHierarchicalLinkPlanIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack hierarchical link plan version {}; expected {}",
            index.version, SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.limits != index.limits.normalized() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan has unnormalized limits {:?}",
            index.limits
        )));
    }
    if index.input_partition_count == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link plan has no input partitions",
        ));
    }
    if index.link_group_count == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link plan has no groups",
        ));
    }
    if index.final_link_group_index >= index.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan final group {} exceeds group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    if index.final_link_job_index != index.first_link_job_index + index.final_link_group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan final job {} does not match first job {} plus group {}",
            index.final_link_job_index, index.first_link_job_index, index.final_link_group_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_link_group_page(
    group: &SourcePackHierarchicalLinkGroupPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    if group.version != SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack hierarchical link group version {}; expected {}",
            group.version, SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION
        )));
    }
    if group.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} target {:?} does not match requested target {:?}",
            group.group_index, group.target, target
        )));
    }
    if let Some(expected_group_index) = expected_group_index {
        if group.group_index != expected_group_index {
            return Err(library_partition_contract_error(format!(
                "loaded hierarchical link group {} but expected {}",
                group.group_index, expected_group_index
            )));
        }
    }
    if group.input_partition_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline partition records, exceeding record cap {}",
            group.group_index,
            group.input_partition_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_frontend_job_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline frontend-job records, exceeding record cap {}",
            group.group_index,
            group.input_frontend_job_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_codegen_job_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline codegen-job records, exceeding record cap {}",
            group.group_index,
            group.input_codegen_job_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_link_group_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline input-group records, exceeding record cap {}",
            group.group_index,
            group.input_link_group_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &group.input_partition_indices,
        &format!("hierarchical link group {} partitions", group.group_index),
    )?;
    unique_usize_set(
        &group.input_frontend_job_indices,
        &format!(
            "hierarchical link group {} frontend jobs",
            group.group_index
        ),
    )?;
    unique_usize_set(
        &group.input_codegen_job_indices,
        &format!("hierarchical link group {} codegen jobs", group.group_index),
    )?;
    unique_usize_set(
        &group.input_link_group_indices,
        &format!("hierarchical link group {} input groups", group.group_index),
    )?;
    let input_partition_count = hierarchical_link_group_input_partition_count(group);
    let input_frontend_job_count = hierarchical_link_group_input_frontend_job_count(group);
    if group.input_partition_count != 0
        && !group.input_partition_indices.is_empty()
        && group.input_partition_count != group.input_partition_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} records partition count {} but stores {} partition indices",
            group.group_index,
            group.input_partition_count,
            group.input_partition_indices.len()
        )));
    }
    if group.input_frontend_job_count != 0
        && !group.input_frontend_job_indices.is_empty()
        && group.input_frontend_job_count != group.input_frontend_job_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} records frontend input count {} but stores {} frontend job indices",
            group.group_index,
            group.input_frontend_job_count,
            group.input_frontend_job_indices.len()
        )));
    }
    match group.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            if group.level != 0
                || group.input_partition_indices.is_empty()
                || input_partition_count != group.input_partition_indices.len()
                || input_frontend_job_count == 0
                || group.input_codegen_job_indices.is_empty()
                || !group.input_link_group_indices.is_empty()
            {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link leaf group {} has invalid page shape",
                    group.group_index
                )));
            }
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            if group.level == 0
                || group.input_link_group_indices.is_empty()
                || input_frontend_job_count != 0
                || !group.input_codegen_job_indices.is_empty()
                || input_partition_count == 0
            {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link reduce group {} has invalid page shape",
                    group.group_index
                )));
            }
            for &input_group_index in &group.input_link_group_indices {
                if input_group_index >= group.group_index {
                    return Err(library_partition_contract_error(format!(
                        "hierarchical link reduce group {} depends on non-prior group {}",
                        group.group_index, input_group_index
                    )));
                }
            }
        }
    }
    Ok(())
}
