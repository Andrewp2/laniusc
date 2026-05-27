use super::*;

pub(in crate::compiler) fn validate_work_queue_index(
    index: &SourcePackWorkQueueIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_WORK_QUEUE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue index version {}; expected {}",
            index.version, SOURCE_PACK_WORK_QUEUE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.work_item_count == 0 {
        return Err(library_partition_contract_error(format!(
            "work queue item count {} is invalid",
            index.work_item_count
        )));
    }
    if index.artifact_item_count > index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue artifact item count {} exceeds item count {}",
            index.artifact_item_count, index.work_item_count
        )));
    }
    if index.final_item_index >= index.work_item_count {
        return Err(library_partition_contract_error(format!(
            "work queue final item {} exceeds item count {}",
            index.final_item_index, index.work_item_count
        )));
    }
    if index.final_job_index != index.final_item_index {
        return Err(library_partition_contract_error(format!(
            "work queue final job {} does not match final item {}",
            index.final_job_index, index.final_item_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_work_queue_page(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_work_queue_page_with_mode(
        page,
        target,
        expected_item_index,
        WorkQueuePageValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_work_queue_page_store_input(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_work_queue_page_with_mode(
        page,
        target,
        expected_item_index,
        WorkQueuePageValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum WorkQueuePageValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_work_queue_inline_record_count(
    page: &SourcePackWorkQueuePage,
    label: &str,
    count: usize,
    cap: usize,
    allow_unbounded_store_input: bool,
) -> Result<bool, CompileError> {
    if count > cap {
        if allow_unbounded_store_input {
            return Ok(false);
        }
        return Err(library_partition_contract_error(format!(
            "work queue page {} stores {} inline {} records, exceeding record cap {}",
            page.item_index, count, label, cap
        )));
    }
    Ok(true)
}

pub(in crate::compiler) fn validate_work_queue_page_with_mode(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
    mode: WorkQueuePageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if let Some(expected_item_index) = expected_item_index {
        if page.item_index != expected_item_index {
            return Err(library_partition_contract_error(format!(
                "loaded work queue page {} but expected {}",
                page.item_index, expected_item_index
            )));
        }
    }
    if page.item_index != page.job_index {
        return Err(library_partition_contract_error(format!(
            "work queue page {} job index {} does not match item index",
            page.item_index, page.job_index
        )));
    }
    let scan_dependency_item_indices = validate_work_queue_inline_record_count(
        page,
        "dependency",
        page.dependency_item_indices.len(),
        SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
        mode == WorkQueuePageValidationMode::StoreInput,
    )?;
    let scan_dependent_item_indices = validate_work_queue_inline_record_count(
        page,
        "dependent",
        page.dependent_item_indices.len(),
        SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
        mode == WorkQueuePageValidationMode::StoreInput,
    )?;
    let scan_partition_indices = validate_work_queue_inline_record_count(
        page,
        "partition",
        page.partition_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        mode == WorkQueuePageValidationMode::StoreInput
            && matches!(page.kind, SourcePackWorkQueueItemKind::LinkReduce),
    )?;
    let scan_input_frontend_job_indices = validate_work_queue_inline_record_count(
        page,
        "frontend input",
        page.input_frontend_job_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        mode == WorkQueuePageValidationMode::StoreInput,
    )?;
    validate_work_queue_inline_record_count(
        page,
        "codegen input",
        page.input_codegen_job_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        false,
    )?;
    validate_work_queue_inline_record_count(
        page,
        "link-group input",
        page.input_link_group_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        false,
    )?;
    if scan_dependency_item_indices {
        let explicit_dependencies = unique_usize_set(
            &page.dependency_item_indices,
            &format!("work queue page {} dependencies", page.item_index),
        )?;
        for &dependency_item_index in &page.dependency_item_indices {
            if dependency_item_index >= page.item_index {
                return Err(library_partition_contract_error(format!(
                    "work queue page {} depends on non-prior item {}",
                    page.item_index, dependency_item_index
                )));
            }
        }
        validate_job_dependency_ranges(
            &page.dependency_item_ranges,
            &explicit_dependencies,
            &format!("work queue page {}", page.item_index),
            page.item_index,
            |message| library_partition_contract_error(message),
        )?;
    }
    if page.dependency_item_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue page {} stores {} inline dependency range records, exceeding record cap {}",
            page.item_index,
            page.dependency_item_ranges.len(),
            SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        )));
    }
    if !page.dependency_item_indices.is_empty() && page.dependency_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records both inline and paged dependencies",
            page.item_index
        )));
    }
    if page.dependency_item_count == 0 {
        if page.dependency_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "work queue page {} has dependency page count {} without dependencies",
                page.item_index, page.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency_item_count
            .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
        if page.dependency_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "work queue page {} has dependency page count {} but expected {} for {} dependencies",
                page.item_index,
                page.dependency_page_count,
                expected_page_count,
                page.dependency_item_count
            )));
        }
    }
    if scan_dependent_item_indices {
        let explicit_dependents = unique_usize_set(
            &page.dependent_item_indices,
            &format!("work queue page {} dependents", page.item_index),
        )?;
        for &dependent_item_index in &page.dependent_item_indices {
            if dependent_item_index <= page.item_index {
                return Err(library_partition_contract_error(format!(
                    "work queue page {} has non-later dependent item {}",
                    page.item_index, dependent_item_index
                )));
            }
        }
        validate_job_dependent_ranges(
            &page.dependent_item_ranges,
            &explicit_dependents,
            &format!("work queue page {}", page.item_index),
            page.item_index,
            |message| library_partition_contract_error(message),
        )?;
    }
    if page.dependent_item_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue page {} stores {} inline dependent range records, exceeding record cap {}",
            page.item_index,
            page.dependent_item_ranges.len(),
            SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE
        )));
    }
    if !page.dependent_item_indices.is_empty() && page.dependent_item_count != 0 {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records both inline and paged dependents",
            page.item_index
        )));
    }
    if page.dependent_item_count == 0 {
        if page.dependent_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "work queue page {} has dependent page count {} without dependents",
                page.item_index, page.dependent_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependent_item_count
            .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
        if page.dependent_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "work queue page {} has dependent page count {} but expected {} for {} dependents",
                page.item_index,
                page.dependent_page_count,
                expected_page_count,
                page.dependent_item_count
            )));
        }
    }
    if let Some(artifact_batch_index) = page.artifact_batch_index {
        if !matches!(
            page.kind,
            SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen
        ) {
            return Err(library_partition_contract_error(format!(
                "work queue page {} kind {:?} cannot map directly to artifact batch {}",
                page.item_index, page.kind, artifact_batch_index
            )));
        }
    }
    if scan_partition_indices {
        unique_usize_set(
            &page.partition_indices,
            &format!("work queue page {} partitions", page.item_index),
        )?;
    }
    if scan_input_frontend_job_indices {
        unique_usize_set(
            &page.input_frontend_job_indices,
            &format!("work queue page {} frontend inputs", page.item_index),
        )?;
    }
    unique_usize_set(
        &page.input_codegen_job_indices,
        &format!("work queue page {} codegen inputs", page.item_index),
    )?;
    unique_usize_set(
        &page.input_link_group_indices,
        &format!("work queue page {} link-group inputs", page.item_index),
    )?;
    let partition_count = page.partition_count.max(page.partition_indices.len());
    let input_frontend_job_count = page
        .input_frontend_job_count
        .max(page.input_frontend_job_indices.len());
    let input_codegen_job_count = page
        .input_codegen_job_count
        .max(page.input_codegen_job_indices.len());
    let input_link_group_count = page
        .input_link_group_count
        .max(page.input_link_group_indices.len());
    if page.partition_count != 0
        && !page.partition_indices.is_empty()
        && page.partition_count != page.partition_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records partition count {} but stores {} partition indices",
            page.item_index,
            page.partition_count,
            page.partition_indices.len()
        )));
    }
    if page.input_frontend_job_count != 0
        && !page.input_frontend_job_indices.is_empty()
        && page.input_frontend_job_count != page.input_frontend_job_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records frontend input count {} but stores {} frontend job indices",
            page.item_index,
            page.input_frontend_job_count,
            page.input_frontend_job_indices.len()
        )));
    }
    if page.input_codegen_job_count != 0
        && !page.input_codegen_job_indices.is_empty()
        && page.input_codegen_job_count != page.input_codegen_job_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records codegen input count {} but stores {} codegen job indices",
            page.item_index,
            page.input_codegen_job_count,
            page.input_codegen_job_indices.len()
        )));
    }
    if page.input_link_group_count != 0
        && !page.input_link_group_indices.is_empty()
        && page.input_link_group_count != page.input_link_group_indices.len()
    {
        return Err(library_partition_contract_error(format!(
            "work queue page {} records link-group input count {} but stores {} link-group indices",
            page.item_index,
            page.input_link_group_count,
            page.input_link_group_indices.len()
        )));
    }
    match page.kind {
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen => {
            if page.partition_indices.len() != 1
                || partition_count != 1
                || page.link_group_index.is_some()
                || input_frontend_job_count != 0
                || input_codegen_job_count != 0
                || input_link_group_count != 0
                || page.source_file_count == 0
            {
                return Err(library_partition_contract_error(format!(
                    "work queue compile page {} has invalid shape",
                    page.item_index
                )));
            }
        }
        SourcePackWorkQueueItemKind::LinkLeaf => {
            if page.link_group_index.is_none()
                || page.partition_indices.is_empty()
                || partition_count != page.partition_indices.len()
                || input_frontend_job_count == 0
                || input_codegen_job_count == 0
                || input_link_group_count != 0
            {
                return Err(library_partition_contract_error(format!(
                    "work queue link leaf page {} has invalid shape",
                    page.item_index
                )));
            }
        }
        SourcePackWorkQueueItemKind::LinkReduce => {
            if page.link_group_index.is_none()
                || partition_count == 0
                || input_frontend_job_count != 0
                || input_codegen_job_count != 0
                || input_link_group_count == 0
            {
                return Err(library_partition_contract_error(format!(
                    "work queue link reduce page {} has invalid shape",
                    page.item_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_work_queue_dependencies_page(
    page: &SourcePackWorkQueueDependenciesPage,
    target: SourcePackArtifactTarget,
    expected_item_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue dependencies page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue dependencies page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if page.item_index != expected_item_index {
        return Err(library_partition_contract_error(format!(
            "loaded work queue dependencies page for item {} but expected {}",
            page.item_index, expected_item_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded work queue dependencies page {} for item {} but expected page {}",
            page.page_index, page.item_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} starts at {} but expected {}",
            page.page_index,
            page.item_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_item_indices.len() {
        return Err(library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} records {} dependencies but stores {}",
            page.page_index,
            page.item_index,
            page.dependency_count,
            page.dependency_item_indices.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} exceeds page size {}",
            page.page_index, page.item_index, SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.dependency_item_indices,
        &format!(
            "work queue dependencies page {} for item {} dependencies",
            page.page_index, page.item_index
        ),
    )?;
    for &dependency_item_index in &page.dependency_item_indices {
        if dependency_item_index >= page.item_index {
            return Err(library_partition_contract_error(format!(
                "work queue dependencies page {} for item {} has non-prior dependency item {}",
                page.page_index, page.item_index, dependency_item_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_work_queue_dependents_page(
    page: &SourcePackWorkQueueDependentsPage,
    target: SourcePackArtifactTarget,
    expected_item_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue dependents page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(library_partition_contract_error(format!(
            "work queue dependents page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if page.item_index != expected_item_index {
        return Err(library_partition_contract_error(format!(
            "loaded work queue dependents page for item {} but expected {}",
            page.item_index, expected_item_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded work queue dependents page {} for item {} but expected page {}",
            page.page_index, page.item_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
    if page.first_dependent_position != expected_first_position {
        return Err(library_partition_contract_error(format!(
            "work queue dependents page {} for item {} starts at {} but expected {}",
            page.page_index,
            page.item_index,
            page.first_dependent_position,
            expected_first_position
        )));
    }
    if page.dependent_count != page.dependent_item_indices.len() {
        return Err(library_partition_contract_error(format!(
            "work queue dependents page {} for item {} records {} dependents but stores {}",
            page.page_index,
            page.item_index,
            page.dependent_count,
            page.dependent_item_indices.len()
        )));
    }
    if page.dependent_count > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "work queue dependents page {} for item {} exceeds page size {}",
            page.page_index, page.item_index, SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE
        )));
    }
    unique_usize_set(
        &page.dependent_item_indices,
        &format!(
            "work queue dependents page {} for item {} dependents",
            page.page_index, page.item_index
        ),
    )?;
    for &dependent_item_index in &page.dependent_item_indices {
        if dependent_item_index <= page.item_index {
            return Err(library_partition_contract_error(format!(
                "work queue dependents page {} for item {} has non-later dependent item {}",
                page.page_index, page.item_index, dependent_item_index
            )));
        }
    }
    Ok(())
}
