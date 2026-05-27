use super::*;

pub(in crate::compiler) fn validate_link_execution_index(
    index: &SourcePackHierarchicalLinkExecutionIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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
    if index.final_link_job_index != index.first_link_job_index + index.final_link_group_index {
        return Err(library_partition_contract_error(format!(
            "hierarchical link execution final job {} does not match first job {} plus group {}",
            index.final_link_job_index, index.first_link_job_index, index.final_link_group_index
        )));
    }
    validate_manifest_artifact_key(
        target,
        &index.final_output_key,
        "hierarchical link execution final output",
    )?;
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(in crate::compiler) enum LinkExecutionPageValidationMode {
    Persisted,
    StoreInput,
}

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

pub(in crate::compiler) fn validate_link_execution_page_with_mode(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
    mode: LinkExecutionPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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

pub(in crate::compiler) fn validate_link_execution_artifact_refs(
    artifacts: &[SourcePackArtifactRef],
    expected_kind: SourcePackArtifactKind,
    target: SourcePackArtifactTarget,
    consumer_job_index: usize,
    label: &str,
) -> Result<(), CompileError> {
    artifact_ref_index_set(artifacts, label)?;
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
        validate_manifest_artifact_key(
            target,
            &artifact.key,
            &format!("{label} artifact {}", artifact.artifact_index),
        )?;
    }
    Ok(())
}

pub(in crate::compiler) fn validate_link_execution_interface_page(
    page: &SourcePackHierarchicalLinkExecutionInterfacePage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE);
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

pub(in crate::compiler) fn validate_link_execution_object_page(
    page: &SourcePackHierarchicalLinkExecutionObjectPage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE);
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

pub(in crate::compiler) fn validate_link_execution_partial_page(
    page: &SourcePackHierarchicalLinkExecutionPartialPage,
    target: SourcePackArtifactTarget,
    expected_group_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
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
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
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
    unique_usize_set(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution partial page {}:{} input groups",
            page.group_index, page.page_index
        ),
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
