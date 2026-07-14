use super::*;
/// Validates the compact hierarchical link execution index.
pub(in crate::compiler) fn validate_link_execution_index(
    index: &SourcePackHierarchicalLinkExecutionIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution index version {}; expected {}",
            index.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.link_group_count == 0 {
        return Err(library_partition_contract_error(
            "hierarchical link execution has no groups",
        ));
    }
    if index.final_link_group_index >= index.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final group {} exceeds group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    let final_link_group_end = index.final_link_group_index.checked_add(1).ok_or_else(|| {
        library_partition_contract_error(format!(
            "hierarchical link execution final group {} overflows dense group end",
            index.final_link_group_index
        ))
    })?;
    if final_link_group_end != index.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final group {} is not the last dense group for group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    let expected_final_link_job_index = index
        .first_link_job_index
        .checked_add(index.final_link_group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "hierarchical link execution first job {} plus final group {} overflows final job index",
                index.first_link_job_index, index.final_link_group_index
            ))
        })?;
    if index.final_link_job_index != expected_final_link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final job {} does not match first job {} plus group {}",
            index.final_link_job_index, index.first_link_job_index, index.final_link_group_index
        )));
    }
    let (final_output_producer_job_index, final_output_first_source_index, _) =
        parse_linked_output_key(
            target,
            &index.final_output_key,
            "hierarchical link execution final output",
        )?;
    if final_output_producer_job_index != index.first_link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final output key {:?} records producer job {} but the dense final output artifact is owned by first link job {}",
            index.final_output_key, final_output_producer_job_index, index.first_link_job_index
        )));
    }
    if final_output_first_source_index != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final output key {:?} starts at source {}; expected source 0",
            index.final_output_key, final_output_first_source_index
        )));
    }
    Ok(())
}

/// Validates that a link execution index still matches its link plan.
pub(in crate::compiler) fn validate_link_execution_index_for_plan(
    index: &SourcePackHierarchicalLinkExecutionIndex,
    plan: &SourcePackHierarchicalLinkPlanIndex,
) -> Result<(), CompileError> {
    validate_link_plan_index(plan, plan.target)?;
    validate_link_execution_index(index, plan.target)?;
    if index.first_link_job_index != plan.first_link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution index first link job {} does not match current plan first link job {}",
            index.first_link_job_index, plan.first_link_job_index
        )));
    }
    if index.final_link_group_index != plan.final_link_group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution index final group {} does not match current plan final group {}",
            index.final_link_group_index, plan.final_link_group_index
        )));
    }
    if index.final_link_job_index != plan.final_link_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution index final job {} does not match current plan final job {}",
            index.final_link_job_index, plan.final_link_job_index
        )));
    }
    if index.link_group_count != plan.link_group_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution index group count {} does not match current plan group count {}",
            index.link_group_count, plan.link_group_count
        )));
    }
    Ok(())
}

fn parse_linked_output_key(
    target: SourcePackArtifactTarget,
    key: &str,
    label: &str,
) -> Result<(usize, usize, usize), CompileError> {
    validate_artifact_key_kind(
        target,
        key,
        SourcePackArtifactKind::LinkedOutput,
        label,
        library_partition_contract_error,
    )?;
    let expected_prefix = match target.key_prefix() {
        Some(target_prefix) => format!("{target_prefix}/linked-output/job-"),
        None => "linked-output/job-".into(),
    };
    let Some(suffix) = key.strip_prefix(&expected_prefix) else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} does not start with expected prefix {expected_prefix:?}"
        )));
    };
    let Some((producer_job_index, source_range)) = suffix.split_once("/src-") else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} must include a producer job and source range"
        )));
    };
    if producer_job_index.is_empty()
        || !producer_job_index
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit())
    {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has invalid producer job index"
        )));
    }
    let producer_job_index =
        parse_canonical_artifact_key_usize(producer_job_index, key, label, "producer job index")?;
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has invalid source range"
        )));
    };
    let first_source_index =
        parse_canonical_artifact_key_usize(first_source_index, key, label, "first source index")?;
    let source_end = parse_canonical_artifact_key_usize(source_end, key, label, "source end")?;
    if source_end <= first_source_index {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has empty source range {first_source_index}..{source_end}"
        )));
    }
    Ok((producer_job_index, first_source_index, source_end))
}

/// Validation mode for persisted link pages versus store inputs.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(in crate::compiler) enum LinkExecutionPageValidationMode {
    /// Validate the compact page that is already persisted.
    Persisted,
    /// Validate caller-provided data before sidecar pages are split out.
    StoreInput,
}

/// Validates a persisted hierarchical link execution page.
pub(in crate::compiler) fn validate_link_execution_page(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_link_execution_page_with_mode(
        page,
        target,
        expected_group_index,
        LinkExecutionPageValidationMode::Persisted,
    )
}

/// Validates a link execution page before store-time sidecar expansion.
pub(in crate::compiler) fn validate_link_execution_page_store_input(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_link_execution_page_with_mode(
        page,
        target,
        expected_group_index,
        LinkExecutionPageValidationMode::StoreInput,
    )
}

/// Validates a hierarchical link execution page with the requested mode.
pub(in crate::compiler) fn validate_link_execution_page_with_mode(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
    mode: LinkExecutionPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution page version {}; expected {}",
            page.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution page {} target {:?} does not match requested target {:?}",
            page.group_index, page.target, target
        )));
    }
    if let Some(expected_group_index) = expected_group_index {
        if page.group_index != expected_group_index {
            return Err(library_partition_contract_error(format!(
                "loaded hierarchical link execution page {} but expected {}",
                page.group_index, expected_group_index
            )));
        }
    }
    validate_manifest_artifact_key(
        target,
        &page.output_key,
        &format!(
            "hierarchical link execution group {} output",
            page.group_index
        ),
    )?;
    validate_link_execution_output_key_kind(page, target)?;
    validate_link_execution_dense_job_base(page)?;
    validate_link_execution_source_summary(page)?;
    if page.input_interface_ranges.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline interface range records, exceeding record cap {}",
            page.group_index,
            page.input_interface_ranges.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_interfaces.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        && mode == LinkExecutionPageValidationMode::Persisted
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline interface records, exceeding record cap {}",
            page.group_index,
            page.input_interfaces.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_objects.len() > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
        && mode == LinkExecutionPageValidationMode::Persisted
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline object records, exceeding record cap {}",
            page.group_index,
            page.input_objects.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_group_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        && mode == LinkExecutionPageValidationMode::Persisted
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline partial-link group records, exceeding record cap {}",
            page.group_index,
            page.input_group_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_group_output_keys.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        && mode == LinkExecutionPageValidationMode::Persisted
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline partial-link key records, exceeding record cap {}",
            page.group_index,
            page.input_group_output_keys.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution group {} input groups",
            page.group_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution group {} input groups",
            page.group_index
        ),
        library_partition_contract_error,
    )?;
    validate_link_execution_artifact_refs(
        &page.input_interfaces,
        SourcePackArtifactKind::LibraryInterface,
        target,
        page.job_index,
        &format!(
            "hierarchical link execution group {} interface inputs",
            page.group_index
        ),
    )?;
    validate_link_execution_artifact_refs(
        &page.input_objects,
        SourcePackArtifactKind::CodegenObject,
        target,
        page.job_index,
        &format!(
            "hierarchical link execution group {} object inputs",
            page.group_index
        ),
    )?;
    let explicit_interface_dependency_jobs = page
        .input_interfaces
        .iter()
        .map(|artifact| artifact.producing_job_index)
        .collect::<BTreeSet<_>>();
    validate_job_dependency_ranges(
        &page.input_interface_ranges,
        &explicit_interface_dependency_jobs,
        &format!(
            "hierarchical link execution group {} interface inputs",
            page.group_index
        ),
        page.job_index,
        |message| library_partition_contract_error(message),
    )?;
    let ranged_input_interface_count =
        job_index_range_dependency_count(&page.input_interface_ranges);
    let inline_input_interface_count = page.input_interfaces.len();
    let input_interface_count = hierarchical_link_execution_input_interface_count(page);
    let input_object_count = hierarchical_link_execution_input_object_count(page);
    let input_group_count = hierarchical_link_execution_input_group_count(page);
    validate_store_input_artifact_evidence(
        page,
        input_interface_count,
        input_object_count,
        input_group_count,
        mode,
    )?;
    validate_link_descriptor_summary(
        page,
        input_interface_count,
        input_object_count,
        input_group_count,
    )?;
    if page.input_interface_page_count != 0 && !page.input_interfaces.is_empty() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged interface inputs",
            page.group_index
        )));
    }
    if page.input_interface_count != 0 {
        if page.input_interface_count < ranged_input_interface_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} records interface input count {} below ranged input count {}",
                page.group_index, page.input_interface_count, ranged_input_interface_count
            )));
        }
        if !page.input_interfaces.is_empty() {
            let expected_input_interface_count =
                inline_input_interface_count.saturating_add(ranged_input_interface_count);
            if page.input_interface_count != expected_input_interface_count {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link execution group {} records interface input count {} but stores {} inline refs and {} ranged refs",
                    page.group_index,
                    page.input_interface_count,
                    inline_input_interface_count,
                    ranged_input_interface_count
                )));
            }
        } else if page.input_interface_page_count == 0
            && page.input_interface_count != ranged_input_interface_count
        {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} records interface input count {} but has no explicit interface pages and {} ranged refs",
                page.group_index, page.input_interface_count, ranged_input_interface_count
            )));
        }
    }
    if input_interface_count == 0 {
        if page.input_interface_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has interface page count {} without interface inputs",
                page.group_index, page.input_interface_page_count
            )));
        }
    } else if page.input_interface_page_count != 0 {
        if page.input_interface_count == 0 {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} stores paged interface inputs without recording their total count",
                page.group_index
            )));
        }
        let explicit_input_interface_count = page
            .input_interface_count
            .checked_sub(ranged_input_interface_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link execution group {} records interface input count {} below ranged input count {}",
                    page.group_index, page.input_interface_count, ranged_input_interface_count
                ))
            })?;
        let expected_page_count = explicit_input_interface_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE);
        if page.input_interface_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has interface page count {} but expected {} for {} explicit inputs",
                page.group_index,
                page.input_interface_page_count,
                expected_page_count,
                explicit_input_interface_count
            )));
        }
    }
    if page.input_object_count != 0
        && !page.input_objects.is_empty()
        && page.input_object_count != page.input_objects.len()
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records object input count {} but stores {} object refs",
            page.group_index,
            page.input_object_count,
            page.input_objects.len()
        )));
    }
    if page.input_object_page_count != 0 && !page.input_objects.is_empty() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged object inputs",
            page.group_index
        )));
    }
    if page.input_object_count == 0 {
        if page.input_object_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has object page count {} without object inputs",
                page.group_index, page.input_object_page_count
            )));
        }
    } else if page.input_objects.is_empty() {
        let expected_page_count = page
            .input_object_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE);
        if page.input_object_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has object page count {} but expected {} for {} inputs",
                page.group_index,
                page.input_object_page_count,
                expected_page_count,
                page.input_object_count
            )));
        }
    }
    if page.input_group_count != 0
        && !page.input_group_indices.is_empty()
        && page.input_group_count != page.input_group_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records group input count {} but stores {} input groups",
            page.group_index,
            page.input_group_count,
            page.input_group_indices.len()
        )));
    }
    if page.input_group_page_count != 0
        && (!page.input_group_indices.is_empty() || !page.input_group_output_keys.is_empty())
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged partial-link inputs",
            page.group_index
        )));
    }
    if page.input_group_count == 0 {
        if page.input_group_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has partial-link page count {} without group inputs",
                page.group_index, page.input_group_page_count
            )));
        }
    } else if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
        let expected_page_count = page
            .input_group_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
        if page.input_group_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has partial-link page count {} but expected {} for {} inputs",
                page.group_index,
                page.input_group_page_count,
                expected_page_count,
                page.input_group_count
            )));
        }
    }

    if page.input_group_indices.len() != page.input_group_output_keys.len() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} has {} input groups but {} input output keys",
            page.group_index,
            page.input_group_indices.len(),
            page.input_group_output_keys.len()
        )));
    }
    validate_partial_input_group_output_keys(
        target,
        page.group_index,
        page.job_index,
        &page.input_group_indices,
        &page.input_group_output_keys,
        &format!(
            "hierarchical link execution group {} input groups",
            page.group_index
        ),
    )?;
    let mut input_group_output_keys = BTreeSet::new();
    for key in &page.input_group_output_keys {
        validate_manifest_artifact_key(
            target,
            key,
            &format!(
                "hierarchical link execution group {} input-group output",
                page.group_index
            ),
        )?;
        if !input_group_output_keys.insert(key.clone()) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} repeats input-group output key {:?}",
                page.group_index, key
            )));
        }
    }

    match page.kind {
        SourcePackHierarchicalLinkGroupKind::Leaf => {
            if page.final_output && page.group_index != 0 {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link execution final leaf group {} is invalid; a final leaf can only be dense group 0, and nonzero final groups must reduce prior partial-link outputs before claiming linked-output evidence",
                    page.group_index
                )));
            }
            if input_interface_count == 0
                || input_object_count == 0
                || (page.input_objects.is_empty() && page.input_object_page_count == 0)
                || !page.input_group_indices.is_empty()
                || !page.input_group_output_keys.is_empty()
                || input_group_count != 0
                || page.input_group_page_count != 0
                || page.source_file_count == 0
            {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link execution leaf group {} has invalid page shape",
                    page.group_index
                )));
            }
        }
        SourcePackHierarchicalLinkGroupKind::Reduce => {
            if input_interface_count != 0
                || !page.input_interfaces.is_empty()
                || page.input_interface_page_count != 0
                || input_object_count != 0
                || !page.input_objects.is_empty()
                || page.input_object_page_count != 0
                || input_group_count == 0
                || (page.input_group_indices.is_empty()
                    && page.input_group_output_keys.is_empty()
                    && page.input_group_page_count == 0)
                || page.source_file_count == 0
            {
                return Err(library_partition_contract_error(format!(
                    "hierarchical link execution reduce group {} has invalid page shape",
                    page.group_index
                )));
            }
            for &input_group_index in &page.input_group_indices {
                if input_group_index >= page.group_index {
                    return Err(library_partition_contract_error(format!(
                        "hierarchical link execution reduce group {} depends on non-prior group {}",
                        page.group_index, input_group_index
                    )));
                }
            }
        }
    }
    Ok(())
}

fn validate_link_execution_dense_job_base(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    if page.job_index < page.group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records link job {} before its dense group index; persisted link pages must encode a nonnegative first link job before output artifact evidence is trusted",
            page.group_index, page.job_index
        )));
    }
    Ok(())
}

fn validate_link_execution_source_summary(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    if page.source_file_count == 0 {
        return Ok(());
    }
    if page.source_byte_count == 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} has empty source-byte summary for {} source files; link-execution replay must carry concrete source-byte evidence",
            page.group_index, page.source_file_count
        )));
    }
    if page.source_byte_count < page.source_file_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} source-byte summary {} is smaller than source-file count {}; each replayed source file must contribute concrete bytes",
            page.group_index, page.source_byte_count, page.source_file_count
        )));
    }
    // Path-stream preparation deliberately records line counts as optional so
    // it can plan huge projects from filesystem metadata without rereading all
    // source bytes on the CPU. Zero (or a partial aggregate) therefore means
    // unknown line provenance, while byte counts remain mandatory.
    Ok(())
}

fn validate_link_execution_sidecar_dense_job_base(
    label: &str,
    group_index: usize,
    job_index: usize,
) -> Result<(), CompileError> {
    if job_index < group_index {
        return Err(library_partition_contract_error(format!(
            "{label} records link job {job_index} before dense group index {group_index}; persisted link sidecar pages must encode a nonnegative first link job before input artifact evidence is trusted"
        )));
    }
    Ok(())
}

fn validate_store_input_artifact_evidence(
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_interface_count: usize,
    input_object_count: usize,
    input_group_count: usize,
    mode: LinkExecutionPageValidationMode,
) -> Result<(), CompileError> {
    if mode != LinkExecutionPageValidationMode::StoreInput {
        return Ok(());
    }

    if link_descriptor_summary_carries_evidence(&page.descriptor_summary) {
        let descriptor_only_interface_inputs =
            input_interface_count != 0 && page.input_interfaces.is_empty();
        let descriptor_only_object_inputs =
            input_object_count != 0 && page.input_objects.is_empty();
        let descriptor_only_partial_inputs = input_group_count != 0
            && page.input_group_indices.is_empty()
            && page.input_group_output_keys.is_empty();

        if descriptor_only_interface_inputs
            || descriptor_only_object_inputs
            || descriptor_only_partial_inputs
        {
            let mut missing_records = Vec::new();
            if descriptor_only_interface_inputs {
                if page.input_interface_ranges.is_empty() {
                    missing_records.push("interface artifact refs");
                } else {
                    missing_records.push(
                        "interface artifact refs; dependency ranges are artifact lookups, not persisted interface artifacts",
                    );
                }
            }
            if descriptor_only_object_inputs {
                missing_records.push("object artifact refs");
            }
            if descriptor_only_partial_inputs {
                missing_records.push("partial-link output keys");
            }
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} descriptor summary cannot be persisted from store input without concrete {}; descriptor rows are not link artifact evidence",
                page.group_index,
                missing_records.join(", ")
            )));
        }
    }

    let mut missing_sidecar_inputs = Vec::new();
    if input_interface_count != 0
        && page.input_interface_page_count != 0
        && page.input_interfaces.is_empty()
    {
        missing_sidecar_inputs.push("interface artifact refs");
    }
    if input_object_count != 0 && page.input_object_page_count != 0 && page.input_objects.is_empty()
    {
        missing_sidecar_inputs.push("object artifact refs");
    }
    if input_group_count != 0
        && page.input_group_page_count != 0
        && page.input_group_indices.is_empty()
        && page.input_group_output_keys.is_empty()
    {
        missing_sidecar_inputs.push("partial-link output keys");
    }
    if !missing_sidecar_inputs.is_empty() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} store input references pre-paged {}; store input must carry concrete input records so the store can write sidecar pages rather than persisting missing artifact evidence",
            page.group_index,
            missing_sidecar_inputs.join(", ")
        )));
    }

    Ok(())
}

fn link_descriptor_summary_carries_evidence(summary: &SourcePackLinkDescriptorSummary) -> bool {
    summary.interface_symbol_count != 0
        || summary.object_section_count != 0
        || summary.object_symbol_count != 0
        || summary.unresolved_symbol_count != 0
        || summary.relocation_count != 0
        || summary.export_symbol_count != 0
        || summary.required_runtime_abi_version.is_some()
        || !summary.required_runtime_service_ids.is_empty()
}

fn validate_link_execution_output_key_kind(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if page.final_output {
        validate_final_linked_output_key(target, page)?;
        return Ok(());
    }

    let expected_key =
        hierarchical_link_partial_output_key(target, page.group_index, page.job_index);
    if page.output_key != expected_key {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} partial-link output key {:?} does not match expected key {:?}",
            page.group_index, page.output_key, expected_key
        )));
    }
    Ok(())
}

fn validate_final_linked_output_key(
    target: SourcePackArtifactTarget,
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    validate_artifact_key_kind(
        target,
        &page.output_key,
        SourcePackArtifactKind::LinkedOutput,
        "hierarchical link execution final linked output",
        library_partition_contract_error,
    )?;
    let expected_prefix = match target.key_prefix() {
        Some(target_prefix) => format!("{target_prefix}/linked-output/job-"),
        None => "linked-output/job-".into(),
    };
    let Some(suffix) = page.output_key.strip_prefix(&expected_prefix) else {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} does not start with expected prefix {:?}",
            page.group_index, page.output_key, expected_prefix
        )));
    };
    let Some((producer_job_index, source_range)) = suffix.split_once("/src-") else {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} must include a producer job and source range",
            page.group_index, page.output_key
        )));
    };
    if producer_job_index.is_empty()
        || !producer_job_index
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit())
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} has invalid producer job index",
            page.group_index, page.output_key
        )));
    }
    let producer_job_index = parse_canonical_artifact_key_usize(
        producer_job_index,
        &page.output_key,
        &format!(
            "hierarchical link execution group {} final linked output",
            page.group_index
        ),
        "producer job index",
    )?;
    let expected_producer_job_index = page.job_index.checked_sub(page.group_index).ok_or_else(|| {
        library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output job {} precedes dense group index",
            page.group_index, page.job_index
        ))
    })?;
    if producer_job_index != expected_producer_job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} records producer job {} but dense final output artifact is owned by first link job {}",
            page.group_index, page.output_key, producer_job_index, expected_producer_job_index
        )));
    }
    if producer_job_index > page.job_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} records future producer job {} after execution job {}",
            page.group_index, page.output_key, producer_job_index, page.job_index
        )));
    }
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} has invalid source range",
            page.group_index, page.output_key
        )));
    };
    if first_source_index != "0" {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} must start at source 0",
            page.group_index, page.output_key
        )));
    }
    let source_end = parse_canonical_artifact_key_usize(
        source_end,
        &page.output_key,
        &format!(
            "hierarchical link execution group {} final linked output",
            page.group_index
        ),
        "source end",
    )?;
    if source_end == 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} has empty source range 0..0; final linked-output pages must cover at least one source file",
            page.group_index, page.output_key
        )));
    }
    if source_end != page.source_file_count {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output key {:?} source end {} does not match source file count {}",
            page.group_index, page.output_key, source_end, page.source_file_count
        )));
    }
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    fn artifact_ref(
        target: SourcePackArtifactTarget,
        kind: SourcePackArtifactKind,
        artifact_index: usize,
        producing_job_index: usize,
    ) -> SourcePackArtifactRef {
        let target_prefix = target
            .key_prefix()
            .map(|prefix| format!("{prefix}/"))
            .unwrap_or_default();
        SourcePackArtifactRef {
            artifact_index,
            key: match kind {
                SourcePackArtifactKind::LibraryInterface => {
                    format!(
                        "{target_prefix}library-interface/lib-0/job-{producing_job_index}/src-0-1"
                    )
                }
                SourcePackArtifactKind::CodegenObject => {
                    format!("{target_prefix}codegen-object/lib-0/job-{producing_job_index}/src-0-1")
                }
                SourcePackArtifactKind::LinkedOutput => {
                    format!("{target_prefix}linked-output/job-{producing_job_index}/src-0-1")
                }
            },
            producing_job_index,
            kind,
        }
    }

    fn leaf_page(
        final_output: bool,
        output_key: impl Into<String>,
    ) -> SourcePackHierarchicalLinkExecutionPage {
        let target = SourcePackArtifactTarget::Wasm;
        SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 0,
            kind: SourcePackHierarchicalLinkGroupKind::Leaf,
            job_index: 50,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: vec![artifact_ref(
                target,
                SourcePackArtifactKind::LibraryInterface,
                1,
                1,
            )],
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: vec![artifact_ref(
                target,
                SourcePackArtifactKind::CodegenObject,
                2,
                2,
            )],
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: Vec::new(),
            input_group_output_keys: Vec::new(),
            source_byte_count: 4,
            source_file_count: 1,
            source_line_count: 1,
            output_key: output_key.into(),
            final_output,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        }
    }

    fn reduce_page(
        input_group_index: usize,
        input_group_output_key: impl Into<String>,
    ) -> SourcePackHierarchicalLinkExecutionPage {
        let target = SourcePackArtifactTarget::Wasm;
        SourcePackHierarchicalLinkExecutionPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
            target,
            group_index: 3,
            kind: SourcePackHierarchicalLinkGroupKind::Reduce,
            job_index: 53,
            input_interface_count: 0,
            input_interface_page_count: 0,
            input_interface_ranges: Vec::new(),
            input_interfaces: Vec::new(),
            input_object_count: 0,
            input_object_page_count: 0,
            input_objects: Vec::new(),
            input_group_count: 0,
            input_group_page_count: 0,
            input_group_indices: vec![input_group_index],
            input_group_output_keys: vec![input_group_output_key.into()],
            source_byte_count: 4,
            source_file_count: 1,
            source_line_count: 1,
            output_key: hierarchical_link_partial_output_key(target, 3, 53),
            final_output: false,
            descriptor_summary: SourcePackLinkDescriptorSummary::default(),
        }
    }

    #[test]
    fn link_execution_output_key_must_match_partial_or_final_kind() {
        validate_link_execution_page(
            &leaf_page(false, "wasm/partial-link/group-00000000/job-00000050"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect("partial link output key is accepted");

        validate_link_execution_page(
            &leaf_page(true, "wasm/linked-output/job-50/src-0-1"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect("final linked output key is accepted");

        let err = validate_link_execution_page(
            &leaf_page(true, "wasm/partial-link/group-00000000/job-00000050"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("final output must not use a partial-link key");
        assert!(err.to_string().contains("final linked output key"));

        let err = validate_link_execution_page(
            &leaf_page(true, "wasm/linked-output/job-50/src-0-2"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("final output must match the source-count key");
        assert!(err.to_string().contains("source end 2"));
        assert!(err.to_string().contains("source file count 1"));

        let err = validate_link_execution_page(
            &leaf_page(true, "wasm/linked-output/job-51/src-0-1"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("final output must use the dense final output producer job");
        assert!(err.to_string().contains("dense final output artifact"));

        let err = validate_link_execution_page(
            &leaf_page(false, "wasm/linked-output/job-50/src-0-1"),
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("partial output must not use a linked-output key");
        assert!(err.to_string().contains("partial-link output key"));
    }

    #[test]
    fn final_leaf_execution_must_be_the_single_dense_group() {
        let mut page = leaf_page(true, "wasm/linked-output/job-49/src-0-1");
        page.group_index = 1;
        let err = validate_link_execution_page(&page, SourcePackArtifactTarget::Wasm, Some(1))
            .expect_err("nonzero final leaf groups cannot claim linked-output evidence");
        let message = err.to_string();
        assert!(message.contains("final leaf group 1"));
        assert!(message.contains("dense group 0"));
        assert!(message.contains("reduce prior partial-link outputs"));
    }

    #[test]
    fn reduce_inputs_must_reference_their_own_partial_link_group_key() {
        let target = SourcePackArtifactTarget::Wasm;
        validate_link_execution_page(
            &reduce_page(1, hierarchical_link_partial_output_key(target, 1, 51)),
            target,
            Some(3),
        )
        .expect("matching partial-link group key is accepted");

        let err = validate_link_execution_page(
            &reduce_page(1, hierarchical_link_partial_output_key(target, 2, 52)),
            target,
            Some(3),
        )
        .expect_err("reduce input key must match the referenced group index");
        assert!(err.to_string().contains("input group 1"));
        assert!(err.to_string().contains("group-00000001"));

        let stale_job_key = "wasm/partial-link/group-00000001/job-00000050";
        let err = validate_link_execution_page(&reduce_page(1, stale_job_key), target, Some(3))
            .expect_err("partial-link input key must match the dense producer job");
        assert!(err.to_string().contains("producer job 50"));
        assert!(err.to_string().contains("dense producer job 51"));

        let partial_page = SourcePackHierarchicalLinkExecutionPartialPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
            target,
            group_index: 3,
            job_index: 53,
            page_index: 0,
            first_input_position: 0,
            input_count: 1,
            input_group_indices: vec![1],
            input_group_output_keys: vec![hierarchical_link_partial_output_key(target, 2, 52)],
        };
        let err = validate_link_execution_partial_page(&partial_page, target, 3, 0)
            .expect_err("paged partial-link input key must match the referenced group index");
        assert!(err.to_string().contains("partial page 3:0"));
        assert!(err.to_string().contains("group-00000001"));
    }

    #[test]
    fn partial_link_input_keys_accept_wide_dense_job_indices() {
        let target = SourcePackArtifactTarget::Wasm;
        let input_group_index = 100_000_000usize;
        let consumer_group_index = input_group_index + 1;
        let first_link_job_index = 3usize;
        let producer_job_index = first_link_job_index + input_group_index;
        let consumer_job_index = first_link_job_index + consumer_group_index;

        validate_link_execution_partial_page(
            &SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index: consumer_group_index,
                job_index: consumer_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_group_indices: vec![input_group_index],
                input_group_output_keys: vec![hierarchical_link_partial_output_key(
                    target,
                    input_group_index,
                    producer_job_index,
                )],
            },
            target,
            consumer_group_index,
            0,
        )
        .expect("partial-link keys should treat eight digits as a minimum width");

        let padded_key =
            format!("wasm/partial-link/group-{input_group_index:08}/job-0{producer_job_index}");
        let err = validate_link_execution_partial_page(
            &SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index: consumer_group_index,
                job_index: consumer_job_index,
                page_index: 0,
                first_input_position: 0,
                input_count: 1,
                input_group_indices: vec![input_group_index],
                input_group_output_keys: vec![padded_key],
            },
            target,
            consumer_group_index,
            0,
        )
        .expect_err("wider partial-link producer job indices must not be padded");
        assert!(err.to_string().contains("non-canonical producer job index"));
    }

    #[test]
    fn partial_link_input_pages_reject_overflowed_first_record_positions() {
        let target = SourcePackArtifactTarget::Wasm;
        let page_index = usize::MAX;
        let partial_page = SourcePackHierarchicalLinkExecutionPartialPage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
            target,
            group_index: 3,
            job_index: 53,
            page_index,
            first_input_position: usize::MAX,
            input_count: 1,
            input_group_indices: vec![1],
            input_group_output_keys: vec![hierarchical_link_partial_output_key(target, 1, 51)],
        };
        let err = validate_link_execution_partial_page(&partial_page, target, 3, page_index)
            .expect_err("overflowed partial-link input page positions must be rejected");
        assert!(
            err.to_string().contains("overflows first record position"),
            "unexpected partial-link page validation error: {err}"
        );
    }

    #[test]
    fn link_execution_sidecar_pages_reject_overflowed_record_spans() {
        let target = SourcePackArtifactTarget::Wasm;
        let page_capacity = SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE;
        let page_index = usize::MAX / page_capacity;
        let first_input_position = page_index * page_capacity;
        let input_count = usize::MAX % page_capacity + 1;
        let input_interfaces = (0..input_count)
            .map(|producer_job_index| {
                artifact_ref(
                    target,
                    SourcePackArtifactKind::LibraryInterface,
                    producer_job_index,
                    producer_job_index,
                )
            })
            .collect::<Vec<_>>();

        let interface_page = SourcePackHierarchicalLinkExecutionInterfacePage {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
            target,
            group_index: 3,
            job_index: input_count + 10,
            page_index,
            first_input_position,
            input_count,
            input_interfaces,
        };
        let err = validate_link_execution_interface_page(&interface_page, target, 3, page_index)
            .expect_err("sidecar page record span end must not overflow");
        assert!(err.to_string().contains("overflows its exclusive end"));
        assert!(err.to_string().contains("bounded dense input range"));
    }

    #[test]
    fn link_execution_rejects_unbound_runtime_services_in_final_output() {
        let mut partial = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        partial.descriptor_summary.set_required_runtime_services([
            GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ]);
        validate_link_execution_page(&partial, SourcePackArtifactTarget::Wasm, Some(0))
            .expect("partial-link pages may carry runtime service requirements forward");

        let mut final_page = leaf_page(true, "wasm/linked-output/job-50/src-0-1");
        final_page
            .descriptor_summary
            .set_required_runtime_services([GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID]);
        let err =
            validate_link_execution_page(&final_page, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("final linked output must not claim unbound runtime services");
        assert!(err.to_string().contains("unbound runtime services"));
        assert!(err.to_string().contains("executable output"));
    }

    #[test]
    fn link_execution_runtime_service_requirements_are_canonical() {
        let mut canonical = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        canonical.descriptor_summary.set_required_runtime_services([
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ]);
        assert_eq!(
            canonical.descriptor_summary.required_runtime_service_ids,
            vec![
                GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
                GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            ],
            "link summary builders should persist one sorted requirement per runtime service"
        );
        validate_link_execution_page(&canonical, SourcePackArtifactTarget::Wasm, Some(0))
            .expect("builder-canonical runtime service requirements are accepted");

        let mut duplicate = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        duplicate.descriptor_summary.required_runtime_abi_version =
            Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
        duplicate.descriptor_summary.required_runtime_service_ids = vec![
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
        ];
        let err = validate_link_execution_page(&duplicate, SourcePackArtifactTarget::Wasm, Some(0))
            .expect_err("persisted duplicate runtime service requirements must be rejected");
        assert!(err.to_string().contains("more than once"));

        let mut unsorted = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        unsorted.descriptor_summary.required_runtime_abi_version =
            Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
        unsorted.descriptor_summary.required_runtime_service_ids = vec![
            GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
            GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
        ];
        let err = validate_link_execution_page(&unsorted, SourcePackArtifactTarget::Wasm, Some(0))
            .expect_err("runtime service requirements must be persisted canonically");
        assert!(err.to_string().contains("strictly ascending"));

        let mut unknown = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        unknown
            .descriptor_summary
            .set_required_runtime_services([99]);
        let err = validate_link_execution_page(&unknown, SourcePackArtifactTarget::Wasm, Some(0))
            .expect_err("unknown runtime service requirements must be rejected");
        assert!(err.to_string().contains("unknown runtime service id 99"));
    }

    #[test]
    fn link_execution_runtime_service_requirements_pin_abi_version() {
        let mut missing_abi = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        missing_abi.descriptor_summary.required_runtime_service_ids =
            vec![GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID];
        let err =
            validate_link_execution_page(&missing_abi, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("runtime service requirements must pin the ABI version");
        assert!(
            err.to_string()
                .contains("must declare runtime ABI version 1")
        );

        let mut unknown_abi = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        unknown_abi.descriptor_summary.required_runtime_abi_version =
            Some(GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION);
        unknown_abi.descriptor_summary.required_runtime_service_ids =
            vec![GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID];
        let err =
            validate_link_execution_page(&unknown_abi, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("unknown runtime ABI version is not a bound runtime contract");
        assert!(err.to_string().contains("unknown runtime ABI version 0"));

        let mut unsupported_abi = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        unsupported_abi
            .descriptor_summary
            .required_runtime_abi_version = Some(99);
        unsupported_abi
            .descriptor_summary
            .required_runtime_service_ids = vec![GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID];
        let err =
            validate_link_execution_page(&unsupported_abi, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("unsupported runtime ABI versions must be rejected");
        assert!(
            err.to_string()
                .contains("unsupported runtime ABI version 99")
        );

        let mut abi_without_services =
            leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        abi_without_services
            .descriptor_summary
            .required_runtime_abi_version = Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION);
        let err = validate_link_execution_page(
            &abi_without_services,
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("runtime ABI version without services must be rejected");
        assert!(
            err.to_string()
                .contains("without required runtime service ids")
        );
    }

    #[test]
    fn link_execution_index_rejects_empty_final_output_source_range() {
        let index = SourcePackHierarchicalLinkExecutionIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            first_link_job_index: 20,
            final_link_group_index: 0,
            final_link_job_index: 20,
            link_group_count: 1,
            final_output_key: "wasm/linked-output/job-20/src-0-0".into(),
        };

        let err = validate_link_execution_index(&index, SourcePackArtifactTarget::Wasm)
            .expect_err("persisted final output indexes must cover at least one source");
        assert!(err.to_string().contains("empty source range 0..0"));
    }

    #[test]
    fn validate_link_execution_index_for_plan_rejects_stale_plan_metadata() {
        let index = SourcePackHierarchicalLinkExecutionIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            first_link_job_index: 20,
            final_link_group_index: 2,
            final_link_job_index: 22,
            link_group_count: 3,
            final_output_key: "wasm/linked-output/job-20/src-0-3".into(),
        };
        let matching_plan = SourcePackHierarchicalLinkPlanIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            limits: SourcePackJobBatchLimits::default().normalized(),
            input_partition_count: 1,
            first_link_job_index: 20,
            final_link_group_index: 2,
            final_link_job_index: 22,
            link_group_count: 3,
        };
        validate_link_execution_index_for_plan(&index, &matching_plan)
            .expect("execution index matching the current dense link plan should validate");

        let mut stale_plan = matching_plan;
        stale_plan.first_link_job_index = 30;
        stale_plan.final_link_job_index = 32;
        let err = validate_link_execution_index_for_plan(&index, &stale_plan)
            .expect_err("resumed execution indexes must match the current link plan");
        let message = err.to_string();
        assert!(
            message.contains("first link job 20")
                && message.contains("current plan first link job 30"),
            "unexpected stale link execution plan validation error: {message}"
        );
    }

    #[test]
    fn link_execution_index_rejects_unrepresentable_dense_final_job_slot() {
        let index = SourcePackHierarchicalLinkExecutionIndex {
            version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
            target: SourcePackArtifactTarget::Wasm,
            first_link_job_index: 2,
            final_link_group_index: usize::MAX - 1,
            final_link_job_index: usize::MAX,
            link_group_count: usize::MAX,
            final_output_key: "wasm/linked-output/job-2/src-0-1".into(),
        };

        let err = validate_link_execution_index(&index, SourcePackArtifactTarget::Wasm)
            .expect_err("dense final link execution job slots must be representable");
        let message = err.to_string();
        assert!(
            message.contains("first job 2")
                && message.contains("final group")
                && message.contains("overflows final job index"),
            "unexpected overflow validation error: {message}"
        );
    }

    #[test]
    fn link_execution_input_artifact_refs_must_match_persisted_key_jobs() {
        let mut forged_key = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        forged_key.input_interfaces[0].key = "wasm/library-interface/lib-0/job-7/src-0-1".into();
        let err =
            validate_link_execution_page(&forged_key, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("input artifact keys must match the persisted producer job");
        assert!(err.to_string().contains("producer job 7"));
        assert!(err.to_string().contains("artifact ref producer job 1"));

        let mut empty_range = leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        empty_range.input_objects[0].key = "wasm/codegen-object/lib-0/job-2/src-4-4".into();
        let err =
            validate_link_execution_page(&empty_range, SourcePackArtifactTarget::Wasm, Some(0))
                .expect_err("input artifact keys must cover at least one source");
        assert!(err.to_string().contains("empty source range 4..4"));
    }

    #[test]
    fn link_execution_artifact_keys_must_use_canonical_decimal_segments() {
        let mut padded_input_job =
            leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        padded_input_job.input_objects[0].key = "wasm/codegen-object/lib-0/job-002/src-0-1".into();
        let err = validate_link_execution_page(
            &padded_input_job,
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("input object keys must not use padded producer job segments");
        assert!(err.to_string().contains("non-canonical producer job index"));

        let mut padded_input_range =
            leaf_page(false, "wasm/partial-link/group-00000000/job-00000050");
        padded_input_range.input_interfaces[0].key =
            "wasm/library-interface/lib-0/job-1/src-00-1".into();
        let err = validate_link_execution_page(
            &padded_input_range,
            SourcePackArtifactTarget::Wasm,
            Some(0),
        )
        .expect_err("input interface keys must not use padded source range segments");
        assert!(err.to_string().contains("non-canonical first source index"));

        let err = validate_link_execution_index(
            &SourcePackHierarchicalLinkExecutionIndex {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
                target: SourcePackArtifactTarget::Wasm,
                first_link_job_index: 20,
                final_link_group_index: 0,
                final_link_job_index: 20,
                link_group_count: 1,
                final_output_key: "wasm/linked-output/job-020/src-0-1".into(),
            },
            SourcePackArtifactTarget::Wasm,
        )
        .expect_err("final output index keys must use canonical producer job segments");
        assert!(err.to_string().contains("non-canonical producer job index"));
    }
}

fn validate_link_descriptor_summary(
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_interface_count: usize,
    input_object_count: usize,
    input_group_count: usize,
) -> Result<(), CompileError> {
    let summary = &page.descriptor_summary;
    if summary.total_symbol_count().is_none() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} descriptor symbol counts overflow",
            page.group_index
        )));
    }
    if summary.total_descriptor_record_count().is_none() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} descriptor record counts overflow",
            page.group_index
        )));
    }
    validate_link_record_contracts(page)?;
    validate_link_descriptor_summary_interface_evidence(page, input_interface_count)?;
    let has_partial_link_inputs = input_group_count != 0;
    if input_interface_count == 0 && !has_partial_link_inputs && summary.interface_symbol_count != 0
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} interface symbols without interface or partial-link inputs",
            page.group_index, summary.interface_symbol_count
        )));
    }
    if input_object_count == 0 && !has_partial_link_inputs && summary.object_symbol_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} object symbols without object or partial-link inputs",
            page.group_index, summary.object_symbol_count
        )));
    }
    if input_object_count == 0 && !has_partial_link_inputs && summary.object_section_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} object sections without object or partial-link inputs",
            page.group_index, summary.object_section_count
        )));
    }
    if input_object_count == 0 && !has_partial_link_inputs && summary.relocation_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} relocation descriptors without object or partial-link inputs",
            page.group_index, summary.relocation_count
        )));
    }
    if input_object_count == 0 && !has_partial_link_inputs && summary.unresolved_symbol_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} unresolved symbol descriptors without object or partial-link inputs",
            page.group_index, summary.unresolved_symbol_count
        )));
    }
    if page.final_output && summary.relocation_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output records {} unresolved relocation descriptors",
            page.group_index, summary.relocation_count
        )));
    }
    if page.final_output && summary.unresolved_symbol_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output records {} unresolved symbol descriptors",
            page.group_index, summary.unresolved_symbol_count
        )));
    }
    if page.final_output && summary.interface_symbol_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output records interface-domain symbol descriptor contracts; interface records must remain link inputs and final artifact evidence must use linked-output records",
            page.group_index
        )));
    }
    if page.final_output && (summary.object_section_count != 0 || summary.object_symbol_count != 0)
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output records object-domain section/symbol descriptor contracts; object records must remain link inputs and final artifact evidence must use linked-output records",
            page.group_index
        )));
    }
    if !page.final_output && summary.export_symbol_count != 0 {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} partial-link output records linked-output symbol descriptor contracts; linked-output records require final linked-output artifact evidence",
            page.group_index
        )));
    }
    if summary.object_section_count == 0
        && (summary.object_symbol_count != 0
            || summary.unresolved_symbol_count != 0
            || summary.relocation_count != 0)
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records object symbol, unresolved-symbol, or relocation contracts without object section record contracts",
            page.group_index
        )));
    }
    if input_interface_count == 0
        && input_object_count == 0
        && input_group_count == 0
        && summary.export_symbol_count != 0
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records {} export symbols without link inputs",
            page.group_index, summary.export_symbol_count
        )));
    }
    validate_runtime_service_summary(page)?;
    validate_link_descriptor_contract(
        page,
        input_interface_count,
        input_object_count,
        input_group_count,
    )?;
    Ok(())
}

fn validate_link_descriptor_summary_interface_evidence(
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_interface_count: usize,
) -> Result<(), CompileError> {
    let summary = &page.descriptor_summary;
    if summary.interface_symbol_count == 0 || page.input_interface_ranges.is_empty() {
        return Ok(());
    }

    let ranged_input_interface_count =
        job_index_range_dependency_count(&page.input_interface_ranges);
    let concrete_input_interface_count =
        input_interface_count
            .checked_sub(ranged_input_interface_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "hierarchical link execution group {} interface descriptor evidence underflows dependency-range interface inputs",
                    page.group_index
                ))
            })?;
    return Err(library_partition_contract_error(format!(
        "hierarchical link execution group {} records {} interface symbol descriptor contracts while {} interface inputs are dependency ranges and {} are concrete refs; dependency ranges are artifact lookup cursors, not concrete interface artifact refs for resumable link descriptor evidence",
        page.group_index,
        summary.interface_symbol_count,
        ranged_input_interface_count,
        concrete_input_interface_count
    )));
}

fn validate_link_record_contracts(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    let summary = &page.descriptor_summary;
    let expected_contracts = summary.record_contracts_from_counts();
    let expected_contract_sequence = expected_contracts.clone();
    if expected_contracts.is_empty() {
        if !summary.record_contracts.is_empty() {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} records explicit link record contracts without matching descriptor counts",
                page.group_index
            )));
        }
        return Ok(());
    }
    if summary.record_contracts.is_empty() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} records descriptor counts without explicit interface/object/section/symbol/relocation record contracts",
            page.group_index
        )));
    }

    let mut actual = BTreeMap::new();
    for contract in &summary.record_contracts {
        if contract.record_count == 0 {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has zero-count explicit {:?} {:?} record contract",
                page.group_index, contract.domain, contract.kind
            )));
        }
        if !link_record_contract_shape_is_supported(contract.domain, contract.kind) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} has unsupported explicit {:?} {:?} record contract",
                page.group_index, contract.domain, contract.kind
            )));
        }
        if actual
            .insert((contract.domain, contract.kind), contract.record_count)
            .is_some()
        {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} records duplicate explicit {:?} {:?} record contracts",
                page.group_index, contract.domain, contract.kind
            )));
        }
    }

    let expected = expected_contracts
        .into_iter()
        .map(|contract| ((contract.domain, contract.kind), contract.record_count))
        .collect::<BTreeMap<_, _>>();
    for (contract_key, actual_count) in &actual {
        if !expected.contains_key(contract_key) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} records explicit {:?} {:?} contract with no matching descriptor count",
                page.group_index, contract_key.0, contract_key.1
            )));
        }
        let expected_count = expected[contract_key];
        if *actual_count != expected_count {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} explicit {:?} {:?} contract count {} does not match descriptor count {}",
                page.group_index, contract_key.0, contract_key.1, actual_count, expected_count
            )));
        }
    }
    for (contract_key, expected_count) in &expected {
        if !actual.contains_key(contract_key) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} descriptor count {} for {:?} {:?} has no explicit record contract",
                page.group_index, expected_count, contract_key.0, contract_key.1
            )));
        }
    }
    if summary.record_contracts != expected_contract_sequence {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} explicit link record contracts are not the canonical counts-derived sequence; persisted descriptor summaries must replay exact record contracts rather than descriptor-only link evidence",
            page.group_index
        )));
    }

    Ok(())
}

fn link_record_contract_shape_is_supported(
    domain: SourcePackLinkRecordDomain,
    kind: SourcePackLinkRecordKind,
) -> bool {
    matches!(
        (domain, kind),
        (
            SourcePackLinkRecordDomain::Interface,
            SourcePackLinkRecordKind::Symbol
        ) | (
            SourcePackLinkRecordDomain::Object,
            SourcePackLinkRecordKind::Section
                | SourcePackLinkRecordKind::Symbol
                | SourcePackLinkRecordKind::UnresolvedSymbol
                | SourcePackLinkRecordKind::Relocation
        ) | (
            SourcePackLinkRecordDomain::LinkedOutput,
            SourcePackLinkRecordKind::Symbol
        )
    )
}

fn validate_runtime_service_summary(
    page: &SourcePackHierarchicalLinkExecutionPage,
) -> Result<(), CompileError> {
    let summary = &page.descriptor_summary;
    let service_ids = &summary.required_runtime_service_ids;
    if service_ids.is_empty() {
        if let Some(runtime_abi_version) = summary.required_runtime_abi_version {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} declares runtime ABI version {runtime_abi_version} without required runtime service ids",
                page.group_index
            )));
        }
        return Ok(());
    }

    match summary.required_runtime_abi_version {
        Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION) => {}
        Some(GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION) => {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} must not use unknown runtime ABI version {}; expected {}",
                page.group_index,
                GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION,
                GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
            )));
        }
        Some(runtime_abi_version) => {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} requires unsupported runtime ABI version {runtime_abi_version}; expected {}",
                page.group_index, GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
            )));
        }
        None => {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} must declare runtime ABI version {} when runtime service ids are required",
                page.group_index, GPU_SOURCE_PACK_RUNTIME_ABI_VERSION
            )));
        }
    }

    let mut seen_service_ids = BTreeSet::new();
    let mut previous_service_id = None;
    for service_id in service_ids.iter().copied() {
        if !GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS.contains(&service_id) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} requires unknown runtime service id {service_id}",
                page.group_index
            )));
        }
        if !seen_service_ids.insert(service_id) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} requires runtime service id {service_id} more than once",
                page.group_index
            )));
        }
        if let Some(previous_service_id) = previous_service_id
            && service_id <= previous_service_id
        {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution group {} runtime service ids must be strictly ascending; service id {service_id} follows {previous_service_id}",
                page.group_index
            )));
        }
        previous_service_id = Some(service_id);
    }

    if page.final_output {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution group {} final linked output requires unbound runtime services {:?}; link execution must bind runtime services before claiming executable output",
            page.group_index, service_ids
        )));
    }

    Ok(())
}

fn validate_link_descriptor_contract(
    page: &SourcePackHierarchicalLinkExecutionPage,
    input_interface_count: usize,
    input_object_count: usize,
    input_group_count: usize,
) -> Result<(), CompileError> {
    let descriptor = if page.final_output {
        GpuSourcePackArtifactDescriptor::hierarchical_linked_output_contract_for_page(
            page,
            input_interface_count,
            input_object_count,
            input_group_count,
        )
    } else {
        GpuSourcePackArtifactDescriptor::partial_link_contract_for_page(
            page,
            input_interface_count,
            input_object_count,
            input_group_count,
        )
    };
    descriptor.validate_contract().map_err(|err| {
        library_partition_contract_error(format!(
            "hierarchical link execution group {} {:?} descriptor contract is inconsistent: {err}",
            page.group_index, descriptor.stage
        ))
    })
}

/// Validates artifact refs used by a hierarchical link execution page.
pub(in crate::compiler) fn validate_link_execution_artifact_refs(
    artifacts: &[SourcePackArtifactRef],
    expected_kind: SourcePackArtifactKind,
    target: SourcePackArtifactTarget,
    consumer_job_index: usize,
    label: &str,
) -> Result<(), CompileError> {
    artifact_ref_index_set(artifacts, label)?;
    let mut producer_jobs = BTreeSet::new();
    let mut artifact_keys = BTreeSet::new();
    let mut previous_producer_job_index = None;
    for artifact in artifacts {
        if artifact.kind != expected_kind {
            return Err(library_partition_contract_error(format!(
                "{label} artifact {} has kind {:?}, expected {:?}",
                artifact.artifact_index, artifact.kind, expected_kind
            )));
        }
        if artifact.producing_job_index >= consumer_job_index {
            return Err(library_partition_contract_error(format!(
                "{label} artifact {} producer job {} is not before consumer link job {}",
                artifact.artifact_index, artifact.producing_job_index, consumer_job_index
            )));
        }
        let (key_producer_job_index, _, _) = parse_input_artifact_ref_key(
            target,
            &artifact.key,
            expected_kind,
            &format!("{label} artifact {}", artifact.artifact_index),
        )?;
        if key_producer_job_index != artifact.producing_job_index {
            return Err(library_partition_contract_error(format!(
                "{label} artifact {} key {:?} records producer job {} but artifact ref producer job {}",
                artifact.artifact_index,
                artifact.key,
                key_producer_job_index,
                artifact.producing_job_index
            )));
        }
        if artifact.artifact_index != artifact.producing_job_index {
            return Err(library_partition_contract_error(format!(
                "{label} artifact index {} records producer job {}; link input artifact refs must use the dense producer job as artifact index so descriptor/link replay cannot overstate stale producer-owned {:?} evidence",
                artifact.artifact_index, artifact.producing_job_index, expected_kind
            )));
        }
        if !producer_jobs.insert(artifact.producing_job_index) {
            return Err(library_partition_contract_error(format!(
                "{label} records producer job {} more than once; distinct artifact indices cannot forge duplicate {:?} inputs",
                artifact.producing_job_index, expected_kind
            )));
        }
        if let Some(previous_producer_job_index) = previous_producer_job_index {
            if artifact.producing_job_index < previous_producer_job_index {
                return Err(library_partition_contract_error(format!(
                    "{label} producer jobs must be strictly ascending; producer job {} follows {}",
                    artifact.producing_job_index, previous_producer_job_index
                )));
            }
        }
        previous_producer_job_index = Some(artifact.producing_job_index);
        if !artifact_keys.insert(artifact.key.clone()) {
            return Err(library_partition_contract_error(format!(
                "{label} records artifact key {:?} more than once; link inputs must reference unique persisted artifacts",
                artifact.key
            )));
        }
    }
    Ok(())
}

fn parse_input_artifact_ref_key(
    target: SourcePackArtifactTarget,
    key: &str,
    kind: SourcePackArtifactKind,
    label: &str,
) -> Result<(usize, usize, usize), CompileError> {
    validate_artifact_key_kind(target, key, kind, label, library_partition_contract_error)?;
    if kind == SourcePackArtifactKind::LinkedOutput {
        return parse_linked_output_key(target, key, label);
    }

    let expected_prefix = match target.key_prefix() {
        Some(target_prefix) => format!("{target_prefix}/{}/lib-", kind.key_segment()),
        None => format!("{}/lib-", kind.key_segment()),
    };
    let Some(suffix) = key.strip_prefix(&expected_prefix) else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} does not start with expected prefix {expected_prefix:?}"
        )));
    };
    let Some((library_id, job_suffix)) = suffix.split_once("/job-") else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} must include a library id and producer job"
        )));
    };
    if library_id.is_empty()
        || !library_id
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit())
    {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has invalid library id"
        )));
    }
    parse_canonical_artifact_key_usize(library_id, key, label, "library id")?;
    let Some((producer_job_index, source_range)) = job_suffix.split_once("/src-") else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} must include a source range"
        )));
    };
    if producer_job_index.is_empty()
        || !producer_job_index
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit())
    {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has invalid producer job index"
        )));
    }
    let producer_job_index =
        parse_canonical_artifact_key_usize(producer_job_index, key, label, "producer job index")?;
    let Some((first_source_index, source_end)) = source_range.split_once('-') else {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has invalid source range"
        )));
    };
    let first_source_index =
        parse_canonical_artifact_key_usize(first_source_index, key, label, "first source index")?;
    let source_end = parse_canonical_artifact_key_usize(source_end, key, label, "source end")?;
    if source_end <= first_source_index {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has empty source range {first_source_index}..{source_end}"
        )));
    }
    Ok((producer_job_index, first_source_index, source_end))
}

fn parse_canonical_artifact_key_usize(
    value: &str,
    key: &str,
    label: &str,
    field: &str,
) -> Result<usize, CompileError> {
    if value.len() > 1 && value.starts_with('0') {
        return Err(library_partition_contract_error(format!(
            "{label} key {key:?} has non-canonical {field} {value:?}; expected no leading zeroes"
        )));
    }
    value.parse::<usize>().map_err(|err| {
        library_partition_contract_error(format!("{label} key {key:?} has invalid {field}: {err}"))
    })
}

/// Validates one hierarchical link interface-input sidecar page.
pub(in crate::compiler) fn validate_link_execution_interface_page(
    page: &SourcePackHierarchicalLinkExecutionInterfacePage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution interface page version {}; expected {}",
            page.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded hierarchical link execution interface page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = checked_first_record_position(
        &format!(
            "hierarchical link execution interface page {expected_group_index}:{expected_page_index}"
        ),
        expected_page_index,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
    )?;
    if page.first_input_position != expected_first_input_position {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} starts at {} but expected {}",
            page.group_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_interfaces.len() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} count {} does not match {} refs",
            page.group_index,
            page.page_index,
            page.input_count,
            page.input_interfaces.len()
        )));
    }
    if page.input_count == 0
        || page.input_count > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    validate_link_execution_sidecar_record_span(
        &format!(
            "hierarchical link execution interface page {}:{}",
            page.group_index, page.page_index
        ),
        page.first_input_position,
        page.input_count,
    )?;
    validate_link_execution_sidecar_dense_job_base(
        &format!(
            "hierarchical link execution interface page {}:{}",
            page.group_index, page.page_index
        ),
        page.group_index,
        page.job_index,
    )?;
    validate_link_execution_artifact_refs(
        &page.input_interfaces,
        SourcePackArtifactKind::LibraryInterface,
        target,
        page.job_index,
        &format!(
            "hierarchical link execution interface page {}:{} inputs",
            page.group_index, page.page_index
        ),
    )?;
    Ok(())
}

/// Validates one hierarchical link object-input sidecar page.
pub(in crate::compiler) fn validate_link_execution_object_page(
    page: &SourcePackHierarchicalLinkExecutionObjectPage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution object page version {}; expected {}",
            page.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded hierarchical link execution object page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = checked_first_record_position(
        &format!(
            "hierarchical link execution object page {expected_group_index}:{expected_page_index}"
        ),
        expected_page_index,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
    )?;
    if page.first_input_position != expected_first_input_position {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} starts at {} but expected {}",
            page.group_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_objects.len() {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} count {} does not match {} refs",
            page.group_index,
            page.page_index,
            page.input_count,
            page.input_objects.len()
        )));
    }
    if page.input_count == 0
        || page.input_count > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    validate_link_execution_sidecar_record_span(
        &format!(
            "hierarchical link execution object page {}:{}",
            page.group_index, page.page_index
        ),
        page.first_input_position,
        page.input_count,
    )?;
    validate_link_execution_sidecar_dense_job_base(
        &format!(
            "hierarchical link execution object page {}:{}",
            page.group_index, page.page_index
        ),
        page.group_index,
        page.job_index,
    )?;
    validate_link_execution_artifact_refs(
        &page.input_objects,
        SourcePackArtifactKind::CodegenObject,
        target,
        page.job_index,
        &format!(
            "hierarchical link execution object page {}:{} inputs",
            page.group_index, page.page_index
        ),
    )?;
    Ok(())
}

/// Validates one hierarchical link partial-input sidecar page.
pub(in crate::compiler) fn validate_link_execution_partial_page(
    page: &SourcePackHierarchicalLinkExecutionPartialPage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION {
        return Err(library_partition_contract_error(format!(
            "unsupported source-pack hierarchical link execution partial page version {}; expected {}",
            page.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded hierarchical link execution partial page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = checked_first_record_position(
        &format!(
            "hierarchical link execution partial page {expected_group_index}:{expected_page_index}"
        ),
        expected_page_index,
        SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
    )?;
    if page.first_input_position != expected_first_input_position {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} starts at {} but expected {}",
            page.group_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_group_indices.len()
        || page.input_count != page.input_group_output_keys.len()
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} count {} does not match {} groups and {} keys",
            page.group_index,
            page.page_index,
            page.input_count,
            page.input_group_indices.len(),
            page.input_group_output_keys.len()
        )));
    }
    if page.input_count == 0
        || page.input_count > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
    {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    validate_link_execution_sidecar_record_span(
        &format!(
            "hierarchical link execution partial page {}:{}",
            page.group_index, page.page_index
        ),
        page.first_input_position,
        page.input_count,
    )?;
    validate_link_execution_sidecar_dense_job_base(
        &format!(
            "hierarchical link execution partial page {}:{}",
            page.group_index, page.page_index
        ),
        page.group_index,
        page.job_index,
    )?;
    validate_partial_input_group_output_keys(
        target,
        page.group_index,
        page.job_index,
        &page.input_group_indices,
        &page.input_group_output_keys,
        &format!(
            "hierarchical link execution partial page {}:{} input groups",
            page.group_index, page.page_index
        ),
    )?;
    unique_usize_set(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution partial page {}:{} input groups",
            page.group_index, page.page_index
        ),
    )?;
    validate_usize_values_strictly_ascending(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution partial page {}:{} input groups",
            page.group_index, page.page_index
        ),
        library_partition_contract_error,
    )?;
    let mut input_group_output_keys = BTreeSet::new();
    for &input_group_index in &page.input_group_indices {
        if input_group_index >= page.group_index {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution partial page {}:{} depends on non-prior group {}",
                page.group_index, page.page_index, input_group_index
            )));
        }
    }
    for key in &page.input_group_output_keys {
        validate_manifest_artifact_key(
            target,
            key,
            &format!(
                "hierarchical link execution partial page {}:{} input-group output",
                page.group_index, page.page_index
            ),
        )?;
        if !input_group_output_keys.insert(key.clone()) {
            return Err(library_partition_contract_error(format!(
                "hierarchical link execution partial page {}:{} repeats input-group output key {:?}",
                page.group_index, page.page_index, key
            )));
        }
    }
    Ok(())
}

fn validate_link_execution_sidecar_record_span(
    label: &str,
    first_input_position: usize,
    input_count: usize,
) -> Result<(), CompileError> {
    first_input_position.checked_add(input_count).ok_or_else(|| {
        library_partition_contract_error(format!(
            "{label} record span starts at {first_input_position} with {input_count} inputs and overflows its exclusive end; persisted sidecar pages must encode a bounded dense input range"
        ))
    })?;
    Ok(())
}

fn validate_partial_input_group_output_keys(
    target: SourcePackArtifactTarget,
    consumer_group_index: usize,
    consumer_job_index: usize,
    input_group_indices: &[usize],
    input_group_output_keys: &[String],
    label: &str,
) -> Result<(), CompileError> {
    for (&input_group_index, key) in input_group_indices.iter().zip(input_group_output_keys) {
        validate_partial_input_group_output_key(
            target,
            consumer_group_index,
            consumer_job_index,
            input_group_index,
            key,
            label,
        )?;
    }
    Ok(())
}

fn validate_partial_input_group_output_key(
    target: SourcePackArtifactTarget,
    consumer_group_index: usize,
    consumer_job_index: usize,
    input_group_index: usize,
    key: &str,
    label: &str,
) -> Result<(), CompileError> {
    let expected_prefix = match target.key_prefix() {
        Some(target_prefix) => {
            format!("{target_prefix}/partial-link/group-{input_group_index:08}/job-")
        }
        None => format!("partial-link/group-{input_group_index:08}/job-"),
    };
    let Some(job_index_suffix) = key.strip_prefix(&expected_prefix) else {
        return Err(library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?}, expected partial-link key prefix {expected_prefix:?}"
        )));
    };
    if job_index_suffix.len() < 8
        || !job_index_suffix
            .as_bytes()
            .iter()
            .all(|byte| byte.is_ascii_digit())
    {
        return Err(library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?}, expected at least eight job-index digits after prefix {expected_prefix:?}"
        )));
    }
    if job_index_suffix.len() > 8 && job_index_suffix.starts_with('0') {
        return Err(library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?} with non-canonical producer job index {job_index_suffix:?}; widened partial-link job indices must not carry leading zeroes"
        )));
    }
    let producer_job_index = job_index_suffix.parse::<usize>().map_err(|err| {
        library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?} with invalid producer job index: {err}"
        ))
    })?;
    let first_link_job_index = consumer_job_index
        .checked_sub(consumer_group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "{label} consumer group {consumer_group_index} link job {consumer_job_index} precedes dense group index"
            ))
        })?;
    let expected_producer_job_index = first_link_job_index
        .checked_add(input_group_index)
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "{label} input group {input_group_index} dense producer job overflows"
            ))
        })?;
    if producer_job_index != expected_producer_job_index {
        return Err(library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?} with producer job {producer_job_index}, expected dense producer job {expected_producer_job_index}"
        )));
    }
    if producer_job_index > consumer_job_index {
        return Err(library_partition_contract_error(format!(
            "{label} input group {input_group_index} for consumer group {consumer_group_index} has output key {key:?} with future producer job {producer_job_index} after consumer link job {consumer_job_index}"
        )));
    }
    Ok(())
}
