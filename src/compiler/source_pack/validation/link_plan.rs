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
    let final_link_group_end = index.final_link_group_index.checked_add(1).ok_or_else(|| {
        library_partition_contract_error(format!(
            "hierarchical link plan final group {} overflows dense group end",
            index.final_link_group_index
        ))
    })?;
    if final_link_group_end != index.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link plan final group {} is not the last dense group for group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    let expected_final_link_job_index = index
        .first_link_job_index
        .checked_add(index.final_link_group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "hierarchical link plan first job {} plus final group {} overflows final job index",
                index.first_link_job_index, index.final_link_group_index
            ))
        })?;
    if index.final_link_job_index != expected_final_link_job_index {
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
    validate_link_group_source_summary(group)?;
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
    validate_usize_values_strictly_ascending(
        &group.input_partition_indices,
        &format!("hierarchical link group {} partitions", group.group_index),
        library_partition_contract_error,
    )?;
    unique_usize_set(
        &group.input_frontend_job_indices,
        &format!(
            "hierarchical link group {} frontend jobs",
            group.group_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &group.input_frontend_job_indices,
        &format!(
            "hierarchical link group {} frontend jobs",
            group.group_index
        ),
        library_partition_contract_error,
    )?;
    unique_usize_set(
        &group.input_codegen_job_indices,
        &format!("hierarchical link group {} codegen jobs", group.group_index),
    )?;
    validate_usize_values_strictly_ascending(
        &group.input_codegen_job_indices,
        &format!("hierarchical link group {} codegen jobs", group.group_index),
        library_partition_contract_error,
    )?;
    unique_usize_set(
        &group.input_link_group_indices,
        &format!("hierarchical link group {} input groups", group.group_index),
    )?;
    validate_usize_values_strictly_ascending(
        &group.input_link_group_indices,
        &format!("hierarchical link group {} input groups", group.group_index),
        library_partition_contract_error,
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
            if input_frontend_job_count < group.input_codegen_job_indices.len() {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link leaf group {} records {} frontend inputs for {} codegen inputs",
                    group.group_index,
                    input_frontend_job_count,
                    group.input_codegen_job_indices.len()
                )));
            }
            for &frontend_job_index in &group.input_frontend_job_indices {
                if frontend_job_index >= group.job_index {
                    return Err(library_partition_contract_error(format!(
                        "hierarchical link leaf group {} has non-prior frontend input job {} for link job {}",
                        group.group_index, frontend_job_index, group.job_index
                    )));
                }
            }
            for &codegen_job_index in &group.input_codegen_job_indices {
                if codegen_job_index >= group.job_index {
                    return Err(library_partition_contract_error(format!(
                        "hierarchical link leaf group {} has non-prior codegen input job {} for link job {}",
                        group.group_index, codegen_job_index, group.job_index
                    )));
                }
            }
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            if group.level == 0
                || group.input_link_group_indices.is_empty()
                || !group.input_partition_indices.is_empty()
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

fn validate_link_group_source_summary(
    group: &SourcePackHierarchicalLinkGroupPage,
) -> Result<(), CompileError> {
    if group.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} has empty source summary; link-plan replay must carry source-file evidence for every link group",
            group.group_index
        )));
    }
    if group.source_byte_count == 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} has empty source-byte summary for {} source files; link-plan replay must carry concrete source-byte evidence",
            group.group_index, group.source_file_count
        )));
    }
    if group.source_byte_count < group.source_file_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} source-byte summary {} is smaller than source-file count {}; each replayed source file must contribute concrete bytes",
            group.group_index, group.source_byte_count, group.source_file_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_link_group_page_for_plan(
    group: &SourcePackHierarchicalLinkGroupPage,
    index: &SourcePackHierarchicalLinkPlanIndex,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_link_plan_index(index, index.target)?;
    validate_link_group_page(group, index.target, expected_group_index)?;
    if group.group_index >= index.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} exceeds plan group count {}",
            group.group_index, index.link_group_count
        )));
    }
    let expected_job_index = index
        .first_link_job_index
        .checked_add(group.group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "hierarchical link group {} dense job index overflows first link job {}",
                group.group_index, index.first_link_job_index
            ))
        })?;
    if group.job_index != expected_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} records job {} but plan dense link slot is {}",
            group.group_index, group.job_index, expected_job_index
        )));
    }
    if group.group_index == index.final_link_group_index
        && group.job_index != index.final_link_job_index
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link final group {} records job {} but plan final link job is {}",
            group.group_index, group.job_index, index.final_link_job_index
        )));
    }
    let group_input_partition_count = hierarchical_link_group_input_partition_count(group);
    if group.group_index == index.final_link_group_index
        && group_input_partition_count != index.input_partition_count
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link final group {} records {} input partitions but plan has {} input partitions; final link-plan groups must cover the complete input partition range before completion metadata is published",
            group.group_index, group_input_partition_count, index.input_partition_count
        )));
    }
    if group_input_partition_count > index.input_partition_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link group {} records {} input partitions but plan has {} partitions",
            group.group_index, group_input_partition_count, index.input_partition_count
        )));
    }
    for &partition_index in &group.input_partition_indices {
        if partition_index >= index.input_partition_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link group {} references partition {} outside plan partition count {}",
                group.group_index, partition_index, index.input_partition_count
            )));
        }
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn leaf_group(input_frontend_job_count: usize) -> SourcePackHierarchicalLinkGroupPage {
        SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            group_index: 2,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            level: 0,
            job_index: 32,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: vec![20, 21],
            input_link_group_indices: Vec::new(),
            source_byte_count: 8,
            source_file_count: 2,
            source_line_count: 2,
            oversized_input: false,
        }
    }

    #[test]
    fn hierarchical_link_leaf_group_requires_frontend_input_for_each_codegen_input() {
        validate_link_group_page(&leaf_group(2), SourcePackArtifactTarget::Wasm, Some(2))
            .expect("leaf group with matching frontend/codegen inputs should validate");

        let err = validate_link_group_page(&leaf_group(1), SourcePackArtifactTarget::Wasm, Some(2))
            .expect_err("leaf groups must not claim fewer frontend inputs than codegen inputs");
        let message = err.to_string();
        assert!(message.contains("frontend inputs for 2 codegen inputs"));
    }

    #[test]
    fn hierarchical_link_plan_index_requires_final_group_to_be_last() {
        let index = SourcePackHierarchicalLinkPlanIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            limits: SourcePackJobBatchLimits::default().normalized(),
            input_partition_count: 2,
            first_link_job_index: 20,
            final_link_group_index: 1,
            final_link_job_index: 21,
            link_group_count: 3,
        };

        let err = validate_link_plan_index(&index, SourcePackArtifactTarget::Wasm)
            .expect_err("link plans must finish on the last dense group");
        let message = err.to_string();
        assert!(
            message.contains("final group 1") && message.contains("group count 3"),
            "unexpected final group validation error: {message}"
        );
    }

    #[test]
    fn hierarchical_link_group_plan_validation_rejects_stale_dense_job_slot() {
        let index = SourcePackHierarchicalLinkPlanIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            limits: SourcePackJobBatchLimits::default().normalized(),
            input_partition_count: 1,
            first_link_job_index: 20,
            final_link_group_index: 2,
            final_link_job_index: 22,
            link_group_count: 3,
        };

        let mut valid = leaf_group(2);
        valid.job_index = 22;
        validate_link_group_page_for_plan(&valid, &index, Some(2))
            .expect("link group with the dense plan job slot should validate");

        let mut stale = valid;
        stale.job_index = 24;
        let err = validate_link_group_page_for_plan(&stale, &index, Some(2))
            .expect_err("persisted link groups must not use stale job slots");
        let message = err.to_string();
        assert!(
            message.contains("group 2") && message.contains("job 24") && message.contains("22"),
            "unexpected dense link slot validation error: {message}"
        );
    }

    #[test]
    fn hierarchical_link_group_rejects_empty_source_summary() {
        let mut no_files = leaf_group(2);
        no_files.source_file_count = 0;
        let err = validate_link_group_page(&no_files, SourcePackArtifactTarget::Wasm, Some(2))
            .expect_err("link groups must carry source-file provenance");
        let message = err.to_string();
        assert!(
            message.contains("empty source summary") && message.contains("source-file evidence"),
            "unexpected empty source summary error: {message}"
        );

        let mut no_bytes = leaf_group(2);
        no_bytes.source_byte_count = 0;
        let err = validate_link_group_page(&no_bytes, SourcePackArtifactTarget::Wasm, Some(2))
            .expect_err("link groups must carry concrete source-byte provenance");
        let message = err.to_string();
        assert!(
            message.contains("empty source-byte summary")
                && message.contains("concrete source-byte evidence"),
            "unexpected empty source-byte summary error: {message}"
        );

        let mut fewer_bytes_than_files = leaf_group(2);
        fewer_bytes_than_files.source_file_count = 4;
        fewer_bytes_than_files.source_byte_count = 3;
        let err = validate_link_group_page(
            &fewer_bytes_than_files,
            SourcePackArtifactTarget::Wasm,
            Some(2),
        )
        .expect_err("link groups must not report fewer source bytes than source files");
        let message = err.to_string();
        assert!(
            message.contains("source-byte summary 3") && message.contains("source-file count 4"),
            "unexpected source byte/file count error: {message}"
        );
    }

    #[test]
    fn hierarchical_link_plan_index_rejects_unrepresentable_dense_final_job_slot() {
        let index = SourcePackHierarchicalLinkPlanIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            limits: SourcePackJobBatchLimits::default().normalized(),
            input_partition_count: 1,
            first_link_job_index: 2,
            final_link_group_index: usize::MAX - 1,
            final_link_job_index: usize::MAX,
            link_group_count: usize::MAX,
        };

        let err = validate_link_plan_index(&index, SourcePackArtifactTarget::Wasm)
            .expect_err("dense final link job slots must be representable");
        let message = err.to_string();
        assert!(
            message.contains("first job 2")
                && message.contains("final group")
                && message.contains("overflows final job index"),
            "unexpected overflow validation error: {message}"
        );
    }

    #[test]
    fn hierarchical_link_reduce_group_rejects_inline_partition_indices() {
        let group = SourcePackHierarchicalLinkGroupPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            group_index: 2,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            level: 1,
            job_index: 32,
            input_partition_count: 1,
            input_partition_indices: vec![0],
            input_frontend_job_count: 0,
            input_frontend_job_indices: Vec::new(),
            input_codegen_job_indices: Vec::new(),
            input_link_group_indices: vec![0],
            source_byte_count: 8,
            source_file_count: 1,
            source_line_count: 1,
            oversized_input: false,
        };

        let err = validate_link_group_page(&group, SourcePackArtifactTarget::Wasm, Some(2))
            .expect_err("reduce groups must summarize partitions through input groups only");
        let message = err.to_string();
        assert!(
            message.contains("reduce group 2") && message.contains("invalid page shape"),
            "unexpected reduce group validation error: {message}"
        );
    }
}
