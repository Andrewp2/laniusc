use super::*;

#[cfg(test)]
pub(in crate::compiler) fn source_pack_initial_work_queue_progress_from_pages(
    queue: &SourcePackWorkQueueIndex,
    work_queue_pages: &[SourcePackWorkQueuePage],
    page_size: usize,
) -> Result<
    (
        SourcePackWorkQueueProgressIndex,
        Vec<SourcePackWorkQueueProgressPage>,
    ),
    CompileError,
> {
    validate_source_pack_work_queue_index(queue, queue.target)?;
    if work_queue_pages.len() != queue.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "initial work queue progress has {} work item pages but index item count {}",
            work_queue_pages.len(),
            queue.work_item_count
        )));
    }
    let artifact_item_count =
        source_pack_work_queue_artifact_item_count_from_pages(work_queue_pages);
    if artifact_item_count != queue.artifact_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "initial work queue progress saw {artifact_item_count} artifact-backed items but index records {}",
            queue.artifact_item_count
        )));
    }
    for (item_index, page) in work_queue_pages.iter().enumerate() {
        validate_source_pack_work_queue_page(page, queue.target, Some(item_index))?;
    }

    let page_size = page_size.max(1);
    let page_count = queue.work_item_count.div_ceil(page_size);
    let mut pages = Vec::with_capacity(page_count);
    let mut artifact_item_count = 0usize;
    let mut ready_item_count = 0usize;
    let mut ready_artifact_item_count = 0usize;
    let mut first_ready_item_index = None;
    let mut first_ready_artifact_item_index = None;

    for page_index in 0..page_count {
        let first_item_index = page_index * page_size;
        let item_count = page_size.min(queue.work_item_count - first_item_index);
        let artifact_item_indices = work_queue_pages
            [first_item_index..first_item_index + item_count]
            .iter()
            .filter_map(|item| {
                source_pack_work_queue_item_kind_is_artifact_backed(item.kind)
                    .then_some(item.item_index)
            })
            .collect::<Vec<_>>();
        let ready_item_indices = work_queue_pages[first_item_index..first_item_index + item_count]
            .iter()
            .filter_map(|item| {
                (source_pack_work_queue_page_dependency_count(item) == 0).then_some(item.item_index)
            })
            .collect::<Vec<_>>();
        let ready_artifact_item_indices = work_queue_pages
            [first_item_index..first_item_index + item_count]
            .iter()
            .filter_map(|item| {
                (source_pack_work_queue_item_kind_is_artifact_backed(item.kind)
                    && source_pack_work_queue_page_dependency_count(item) == 0)
                    .then_some(item.item_index)
            })
            .collect::<Vec<_>>();
        let remaining_dependency_counts = work_queue_pages
            [first_item_index..first_item_index + item_count]
            .iter()
            .filter_map(|item| {
                let dependency_count = source_pack_work_queue_page_dependency_count(item);
                (dependency_count != 0).then_some(SourcePackWorkQueueRemainingDependencyCount {
                    item_index: item.item_index,
                    remaining_dependency_count: dependency_count,
                })
            })
            .collect::<Vec<_>>();
        let remaining_dependent_counts = work_queue_pages
            [first_item_index..first_item_index + item_count]
            .iter()
            .filter_map(|item| {
                let dependent_count = source_pack_work_queue_page_dependent_count(item);
                (dependent_count != 0).then_some(SourcePackWorkQueueRemainingDependentCount {
                    item_index: item.item_index,
                    remaining_dependent_count: dependent_count,
                })
            })
            .collect::<Vec<_>>();
        artifact_item_count += artifact_item_indices.len();
        if !ready_item_indices.is_empty() {
            ready_item_count += ready_item_indices.len();
            first_ready_item_index =
                first_ready_item_index.or_else(|| ready_item_indices.first().copied());
        }
        if !ready_artifact_item_indices.is_empty() {
            ready_artifact_item_count += ready_artifact_item_indices.len();
            first_ready_artifact_item_index = first_ready_artifact_item_index
                .or_else(|| ready_artifact_item_indices.first().copied());
        }
        let page = SourcePackWorkQueueProgressPage {
            version: SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
            target: queue.target,
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
        validate_source_pack_work_queue_progress_page(&page, queue.target, Some(page_index))?;
        pages.push(page);
    }

    let index = SourcePackWorkQueueProgressIndex {
        version: SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
        target: queue.target,
        work_item_count: queue.work_item_count,
        page_size,
        page_count,
        artifact_item_count,
        completed_item_count: 0,
        ready_item_count,
        ready_artifact_item_count,
        claimed_item_count: 0,
        first_ready_item_index,
        first_ready_artifact_item_index,
    };
    validate_source_pack_work_queue_progress_index(&index, queue.target)?;
    Ok((index, pages))
}

pub(in crate::compiler) fn validate_source_pack_library_partition_index(
    index: &SourcePackLibraryPartitionIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library partition index version {}; expected {}",
            index.version, SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "partition index has no source files",
        ));
    }
    if index.partition_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "partition index has no library partitions",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_metadata_prepare_progress(
    progress: &SourcePackFilesystemLibraryMetadataPrepareProgress,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library metadata prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "library metadata prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.library_count != progress.library_partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "library metadata prepare progress has library_count {} but partition_count {}",
            progress.library_count, progress.library_partition_count
        )));
    }
    if progress.library_source_file_page_count != progress.library_partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "library metadata prepare progress has source-file page count {} but partition_count {}",
            progress.library_source_file_page_count, progress.library_partition_count
        )));
    }
    if progress.library_partition_count == 0
        && (progress.source_file_count != 0
            || progress.source_byte_count != 0
            || progress.source_line_count != 0)
    {
        return Err(source_pack_library_partition_contract_error(
            "empty library metadata prepare progress has nonzero source totals",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_partition_plan(
    plan: &SourcePackLibraryPartitionPlan,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_library_partition_records(&plan.index, &plan.partitions, target)
}

pub(in crate::compiler) fn validate_source_pack_library_partition_records(
    index: &SourcePackLibraryPartitionIndex,
    partitions: &[SourcePackLibraryPartition],
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_library_partition_index(index, target)?;
    if partitions.len() != index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition index has {} partition records but partition_count {}",
            partitions.len(),
            index.partition_count
        )));
    }

    let mut expected_first_source_index = 0usize;
    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    let mut library_index_by_id = BTreeMap::new();
    for (position, partition) in partitions.iter().enumerate() {
        validate_source_pack_library_partition(partition, target, Some(position))?;
        if partition.first_source_index != expected_first_source_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} starts at source {}, expected {}",
                partition.partition_index,
                partition.first_source_index,
                expected_first_source_index
            )));
        }
        expected_first_source_index = expected_first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        source_byte_count = source_byte_count
            .checked_add(partition.source_byte_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} byte count overflows",
                    partition.partition_index
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(partition.source_line_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} source line count overflows",
                    partition.partition_index
                ))
            })?;
        if library_index_by_id
            .insert(partition.library_id, partition.partition_index)
            .is_some()
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "library {} appears in more than one partition",
                partition.library_id
            )));
        }
    }

    if expected_first_source_index != index.source_file_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition source file total {} does not match index source file count {}",
            expected_first_source_index, index.source_file_count
        )));
    }
    if source_byte_count != index.source_byte_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition byte total {} does not match index source byte count {}",
            source_byte_count, index.source_byte_count
        )));
    }
    if source_line_count != index.source_line_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition source line total {} does not match index source line count {}",
            source_line_count, index.source_line_count
        )));
    }

    for partition in partitions {
        for dependency_library_id in &partition.dependency_library_ids {
            let Some(&dependency_partition_index) = library_index_by_id.get(dependency_library_id)
            else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "partition {} depends on missing library {}",
                    partition.partition_index, dependency_library_id
                )));
            };
            if dependency_partition_index >= partition.partition_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "partition {} library {} depends on library {} in partition {}",
                    partition.partition_index,
                    partition.library_id,
                    dependency_library_id,
                    dependency_partition_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_partition_locator_page(
    page: &SourcePackLibraryPartitionLocatorPage,
    target: SourcePackArtifactTarget,
    expected_library_id: Option<u32>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library partition locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "library partition locator for library {} target {:?} does not match requested target {:?}",
            page.library_id, page.target, target
        )));
    }
    if let Some(expected_library_id) = expected_library_id {
        if page.library_id != expected_library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded partition locator for library {} but expected {}",
                page.library_id, expected_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_source_file_page(
    page: &SourcePackLibrarySourceFilePage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library source-file page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded source-file page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} has no source files",
            page.partition_index
        )));
    }
    page.first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "source-file page {} source range overflows",
                page.partition_index
            ))
        })?;
    if page.source_files.is_empty() {
        return Ok(());
    }
    if page.source_files.len() > SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} has {} inline source-file records but the record cap is {}",
            page.partition_index,
            page.source_files.len(),
            SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    if page.source_files.len() != page.source_file_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} has {} files but source_file_count {}",
            page.partition_index,
            page.source_files.len(),
            page.source_file_count
        )));
    }

    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    for (offset, source_file) in page.source_files.iter().enumerate() {
        let expected_source_index = page.first_source_index + offset;
        if source_file.source_index != expected_source_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "source-file page {} entry {} has source index {}, expected {}",
                page.partition_index, offset, source_file.source_index, expected_source_index
            )));
        }
        if source_file.file.library_id != page.library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "source-file page {} entry {} has library {}, expected {}",
                page.partition_index, offset, source_file.file.library_id, page.library_id
            )));
        }
        source_byte_count = source_byte_count
            .checked_add(source_file.file.byte_len)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "source-file page {} byte count overflows",
                    page.partition_index
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(source_file.file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "source-file page {} source line count overflows",
                    page.partition_index
                ))
            })?;
    }
    if source_byte_count != page.source_byte_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} byte total {} does not match source_byte_count {}",
            page.partition_index, source_byte_count, page.source_byte_count
        )));
    }
    if source_line_count != page.source_line_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} line total {} does not match source_line_count {}",
            page.partition_index, source_line_count, page.source_line_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_source_file_record_page(
    page: &SourcePackLibrarySourceFileRecordPage,
    target: SourcePackArtifactTarget,
    expected_source_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library source-file record page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file record {} target {:?} does not match requested target {:?}",
            page.source_index, page.target, target
        )));
    }
    if let Some(expected_source_index) = expected_source_index {
        if page.source_index != expected_source_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded source-file record {} but expected {}",
                page.source_index, expected_source_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file record {} has empty partition range",
            page.source_index
        )));
    }
    let source_end = page
        .first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "source-file record {} partition range overflows",
                page.source_index
            ))
        })?;
    if page.source_index < page.first_source_index || page.source_index >= source_end {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file record {} is outside partition source range {}..{}",
            page.source_index, page.first_source_index, source_end
        )));
    }
    if page.file.library_id != page.library_id {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file record {} has library {}, expected {}",
            page.source_index, page.file.library_id, page.library_id
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_build_unit_page(
    page: &SourcePackLibraryBuildUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library build-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded build-unit page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has no source files",
            page.partition_index
        )));
    }
    if page.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} stores {} inline dependency records, exceeding record cap {}",
            page.partition_index,
            page.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.frontend_units.len() > SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} stores {} inline frontend-unit records, exceeding record cap {}",
            page.partition_index,
            page.frontend_units.len(),
            SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    if page.codegen_units.len() > SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} stores {} inline codegen-unit records, exceeding record cap {}",
            page.partition_index,
            page.codegen_units.len(),
            SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP
        )));
    }
    let codegen_unit_count = source_pack_library_build_unit_page_codegen_unit_count(page);
    let frontend_unit_count = source_pack_library_build_unit_page_frontend_unit_count(page);
    if frontend_unit_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has no frontend units",
            page.partition_index
        )));
    }
    if codegen_unit_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has no codegen units",
            page.partition_index
        )));
    }
    if !page.frontend_units.is_empty() && page.frontend_units.len() != frontend_unit_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has {} inline frontend units but frontend_unit_count {}",
            page.partition_index,
            page.frontend_units.len(),
            frontend_unit_count
        )));
    }
    if !page.codegen_units.is_empty() && page.codegen_units.len() != codegen_unit_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has {} inline codegen units but codegen_unit_count {}",
            page.partition_index,
            page.codegen_units.len(),
            codegen_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} has unnormalized limits {:?}",
            page.partition_index, page.limits
        )));
    }

    let source_end = page
        .first_source_index
        .checked_add(page.source_file_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "build-unit page {} source range overflows",
                page.partition_index
            ))
        })?;
    let frontend_end = page
        .frontend_unit
        .first_source_index
        .checked_add(page.frontend_unit.source_file_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "build-unit page {} frontend source range overflows",
                page.partition_index
            ))
        })?;
    if page.frontend_unit.library_id != page.library_id
        || page.frontend_unit.first_source_index != page.first_source_index
        || page.frontend_unit.source_file_count != page.source_file_count
        || page.frontend_unit.source_bytes != page.source_byte_count
        || page.frontend_unit.source_lines != page.source_line_count
        || frontend_end != source_end
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} frontend unit does not match library partition",
            page.partition_index
        )));
    }

    if !page.frontend_units.is_empty() {
        let mut expected_source_index = page.first_source_index;
        let mut source_byte_count = 0usize;
        let mut source_line_count = 0usize;
        for (position, unit) in page.frontend_units.iter().enumerate() {
            validate_source_pack_library_frontend_unit_shape(
                unit,
                page.target,
                page.partition_index,
                page.library_id,
                page.limits,
                position,
            )?;
            if unit.first_source_index != expected_source_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "build-unit page {} frontend unit {} starts at source {}, expected {}",
                    page.partition_index,
                    unit.unit_index,
                    unit.first_source_index,
                    expected_source_index
                )));
            }
            expected_source_index = expected_source_index
                .checked_add(unit.source_file_count)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} frontend unit {} source range overflows",
                        page.partition_index, unit.unit_index
                    ))
                })?;
            source_byte_count = source_byte_count
                .checked_add(unit.source_bytes)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} frontend byte count overflows",
                        page.partition_index
                    ))
                })?;
            source_line_count = source_line_count
                .checked_add(unit.source_lines)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} frontend source-line count overflows",
                        page.partition_index
                    ))
                })?;
        }
        if expected_source_index != source_end {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} frontend source range ends at {}, expected {}",
                page.partition_index, expected_source_index, source_end
            )));
        }
        if source_byte_count != page.source_byte_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} frontend byte total {} does not match source_byte_count {}",
                page.partition_index, source_byte_count, page.source_byte_count
            )));
        }
        if source_line_count != page.source_line_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} frontend source-line total {} does not match source_line_count {}",
                page.partition_index, source_line_count, page.source_line_count
            )));
        }
    }

    if !page.codegen_units.is_empty() {
        let mut expected_source_index = page.first_source_index;
        let mut source_byte_count = 0usize;
        let mut source_line_count = 0usize;
        for (position, unit) in page.codegen_units.iter().enumerate() {
            validate_source_pack_library_codegen_unit_shape(
                unit,
                page.target,
                page.partition_index,
                page.library_id,
                page.limits,
                position,
            )?;
            if unit.first_source_index != expected_source_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "build-unit page {} codegen unit {} starts at source {}, expected {}",
                    page.partition_index,
                    unit.unit_index,
                    unit.first_source_index,
                    expected_source_index
                )));
            }
            expected_source_index = expected_source_index
                .checked_add(unit.source_file_count)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} codegen unit {} source range overflows",
                        page.partition_index, unit.unit_index
                    ))
                })?;
            source_byte_count = source_byte_count
                .checked_add(unit.source_bytes)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} codegen byte count overflows",
                        page.partition_index
                    ))
                })?;
            source_line_count = source_line_count
                .checked_add(unit.source_lines)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "build-unit page {} codegen source-line count overflows",
                        page.partition_index
                    ))
                })?;
        }
        if expected_source_index != source_end {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} codegen source range ends at {}, expected {}",
                page.partition_index, expected_source_index, source_end
            )));
        }
        if source_byte_count != page.source_byte_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} codegen byte total {} does not match source_byte_count {}",
                page.partition_index, source_byte_count, page.source_byte_count
            )));
        }
        if source_line_count != page.source_line_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} codegen source-line total {} does not match source_line_count {}",
                page.partition_index, source_line_count, page.source_line_count
            )));
        }
    }

    let mut dependency_ids = BTreeSet::new();
    for dependency_library_id in &page.dependency_library_ids {
        if *dependency_library_id == page.library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} library {} depends on itself",
                page.partition_index, page.library_id
            )));
        }
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "build-unit page {} contains duplicate dependency library {}",
                page.partition_index, dependency_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_frontend_unit_shape(
    unit: &FrontendUnit,
    _target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    limits: CodegenUnitLimits,
    expected_unit_index: usize,
) -> Result<(), CompileError> {
    if unit.unit_index != expected_unit_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit entry {expected_unit_index} has unit_index {}",
            unit.unit_index
        )));
    }
    if unit.library_id != library_id {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} has library {}, expected {}",
            unit.unit_index, unit.library_id, library_id
        )));
    }
    if unit.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} has no source files",
            unit.unit_index
        )));
    }
    if !unit.oversized_source_file
        && (unit.source_file_count > limits.max_source_files
            || unit.source_bytes > limits.max_source_bytes)
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} frontend unit {} exceeds limits {:?}",
            unit.unit_index, limits
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_frontend_unit_page(
    page: &SourcePackLibraryFrontendUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
    expected_frontend_unit_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library frontend-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "frontend-unit page {}:{} target {:?} does not match requested target {:?}",
            page.partition_index, page.frontend_unit_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded frontend-unit page partition {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if let Some(expected_frontend_unit_index) = expected_frontend_unit_index {
        if page.frontend_unit_index != expected_frontend_unit_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded frontend-unit page {} but expected {}",
                page.frontend_unit_index, expected_frontend_unit_index
            )));
        }
    }
    if page.frontend_unit_count == 0 || page.frontend_unit_index >= page.frontend_unit_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "frontend-unit page {}:{} has invalid count {}",
            page.partition_index, page.frontend_unit_index, page.frontend_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(source_pack_library_partition_contract_error(format!(
            "frontend-unit page {}:{} has unnormalized limits {:?}",
            page.partition_index, page.frontend_unit_index, page.limits
        )));
    }
    validate_source_pack_library_frontend_unit_shape(
        &page.unit,
        page.target,
        page.partition_index,
        page.library_id,
        page.limits,
        page.frontend_unit_index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_codegen_unit_shape(
    unit: &CodegenUnit,
    _target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    limits: CodegenUnitLimits,
    expected_unit_index: usize,
) -> Result<(), CompileError> {
    if unit.unit_index != expected_unit_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit entry {expected_unit_index} has unit_index {}",
            unit.unit_index
        )));
    }
    if unit.library_id != library_id {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} has library {}, expected {}",
            unit.unit_index, unit.library_id, library_id
        )));
    }
    if unit.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} has no source files",
            unit.unit_index
        )));
    }
    if !unit.oversized_source_file
        && (unit.source_file_count > limits.max_source_files
            || unit.source_bytes > limits.max_source_bytes)
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {partition_index} codegen unit {} exceeds limits {:?}",
            unit.unit_index, limits
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_codegen_unit_page(
    page: &SourcePackLibraryCodegenUnitPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
    expected_codegen_unit_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library codegen-unit page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "codegen-unit page {}:{} target {:?} does not match requested target {:?}",
            page.partition_index, page.codegen_unit_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded codegen-unit page partition {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if let Some(expected_codegen_unit_index) = expected_codegen_unit_index {
        if page.codegen_unit_index != expected_codegen_unit_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded codegen-unit page {} but expected {}",
                page.codegen_unit_index, expected_codegen_unit_index
            )));
        }
    }
    if page.codegen_unit_count == 0 || page.codegen_unit_index >= page.codegen_unit_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "codegen-unit page {}:{} has invalid count {}",
            page.partition_index, page.codegen_unit_index, page.codegen_unit_count
        )));
    }
    if page.limits != page.limits.normalized() {
        return Err(source_pack_library_partition_contract_error(format!(
            "codegen-unit page {}:{} has unnormalized limits {:?}",
            page.partition_index, page.codegen_unit_index, page.limits
        )));
    }
    validate_source_pack_library_codegen_unit_shape(
        &page.unit,
        page.target,
        page.partition_index,
        page.library_id,
        page.limits,
        page.codegen_unit_index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_index(
    index: &SourcePackLibraryScheduleIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule index version {}; expected {}",
            index.version, SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.partition_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "schedule index has no partitions",
        ));
    }
    if index.codegen_job_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "schedule index has no codegen jobs",
        ));
    }
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(index);
    if frontend_job_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "schedule index has no frontend jobs",
        ));
    }
    let expected_link_job_index = frontend_job_count
        .checked_add(index.codegen_job_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "schedule index frontend/codegen job counts overflow",
            )
        })?;
    if index.link_job_index != expected_link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index link job {}, expected {}",
            index.link_job_index, expected_link_job_index
        )));
    }
    let expected_job_count = index.link_job_index.checked_add(1).ok_or_else(|| {
        source_pack_library_partition_contract_error("schedule index job count overflows")
    })?;
    if index.job_count != expected_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index job_count {} does not match link job {}",
            index.job_count, index.link_job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_prepare_progress(
    progress: &SourcePackFilesystemLibrarySchedulePrepareProgress,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "library schedule prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.library_count != progress.library_partition_count
        || progress.library_source_file_page_count != progress.library_partition_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "library schedule prepare progress has inconsistent library counts: libraries={} partitions={} source_file_pages={}",
            progress.library_count,
            progress.library_partition_count,
            progress.library_source_file_page_count
        )));
    }
    if progress.next_partition_index > progress.library_partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "library schedule prepare progress next partition {} exceeds partition count {}",
            progress.next_partition_index, progress.library_partition_count
        )));
    }
    if progress.library_build_unit_page_count > progress.library_partition_count
        || progress.library_schedule_page_count > progress.library_partition_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "library schedule prepare progress has too many prepared pages: build_units={} schedule_pages={} partitions={}",
            progress.library_build_unit_page_count,
            progress.library_schedule_page_count,
            progress.library_partition_count
        )));
    }
    match progress.phase {
        SourcePackFilesystemLibrarySchedulePreparePhase::BuildUnitPages => {
            if progress.library_schedule_page_count != 0 {
                return Err(source_pack_library_partition_contract_error(
                    "build-unit schedule progress has prepared schedule pages",
                ));
            }
            if progress.next_partition_index != progress.library_build_unit_page_count {
                return Err(source_pack_library_partition_contract_error(format!(
                    "build-unit schedule progress next partition {} does not match build-unit page count {}",
                    progress.next_partition_index, progress.library_build_unit_page_count
                )));
            }
        }
        SourcePackFilesystemLibrarySchedulePreparePhase::SchedulePages => {
            if progress.library_build_unit_page_count != progress.library_partition_count {
                return Err(source_pack_library_partition_contract_error(
                    "schedule-page progress requires all build-unit pages",
                ));
            }
            if progress.next_partition_index != progress.library_schedule_page_count {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule-page progress next partition {} does not match schedule page count {}",
                    progress.next_partition_index, progress.library_schedule_page_count
                )));
            }
            let frontend_job_count = progress
                .frontend_job_count
                .min(progress.next_frontend_job_index);
            if frontend_job_count != progress.next_frontend_job_index {
                return Err(source_pack_library_partition_contract_error(
                    "schedule-page progress next frontend job exceeds total frontend jobs",
                ));
            }
            let first_codegen_job_index = progress.frontend_job_count;
            if progress.next_codegen_job_index < first_codegen_job_index {
                return Err(source_pack_library_partition_contract_error(
                    "schedule-page progress next codegen job precedes frontend jobs",
                ));
            }
        }
        SourcePackFilesystemLibrarySchedulePreparePhase::Complete => {
            if progress.next_partition_index != progress.library_partition_count
                || progress.library_build_unit_page_count != progress.library_partition_count
                || progress.library_schedule_page_count != progress.library_partition_count
            {
                return Err(source_pack_library_partition_contract_error(
                    "complete schedule progress does not cover every partition",
                ));
            }
        }
    }
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn validate_source_pack_library_schedule_plan(
    plan: &SourcePackLibrarySchedulePlan,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_records(&plan.index, &plan.entries, target)
}

#[cfg(test)]
pub(in crate::compiler) fn validate_source_pack_library_schedule_records(
    index: &SourcePackLibraryScheduleIndex,
    entries: &[SourcePackLibraryScheduleIndexEntry],
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(index, target)?;
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(index);
    let expected_link_job_index = frontend_job_count
        .checked_add(index.codegen_job_count)
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(
                "schedule index frontend/codegen job counts overflow",
            )
        })?;
    if entries.len() != index.partition_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index has {} entries but partition_count {}",
            entries.len(),
            index.partition_count
        )));
    }

    let mut expected_first_frontend_job_index = 0usize;
    let mut expected_first_codegen_job_index = frontend_job_count;
    let mut library_ids = BTreeSet::new();
    for (position, entry) in entries.iter().enumerate() {
        if entry.partition_index != position {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index entry {position} has partition_index {}",
                entry.partition_index
            )));
        }
        let entry_first_frontend_job_index =
            source_pack_library_schedule_entry_first_frontend_job_index(entry);
        if entry.frontend_job_index != entry_first_frontend_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index entry {position} frontend_job_index {} does not match first_frontend_job_index {}",
                entry.frontend_job_index, entry_first_frontend_job_index
            )));
        }
        if entry_first_frontend_job_index != expected_first_frontend_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index entry {position} first frontend job {}, expected {}",
                entry_first_frontend_job_index, expected_first_frontend_job_index
            )));
        }
        let entry_frontend_job_count = source_pack_library_schedule_entry_frontend_job_count(entry);
        expected_first_frontend_job_index = expected_first_frontend_job_index
            .checked_add(entry_frontend_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule index entry {position} frontend job range overflows"
                ))
            })?;
        if entry.codegen_job_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index entry {position} has no codegen jobs"
            )));
        }
        if entry.first_codegen_job_index != expected_first_codegen_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index entry {position} first codegen job {}, expected {}",
                entry.first_codegen_job_index, expected_first_codegen_job_index
            )));
        }
        if !library_ids.insert(entry.library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index library {} appears more than once",
                entry.library_id
            )));
        }
        expected_first_codegen_job_index = expected_first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule index entry {position} codegen job range overflows"
                ))
            })?;
    }

    if expected_first_frontend_job_index != frontend_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index frontend job count {} does not match entry total {}",
            frontend_job_count, expected_first_frontend_job_index
        )));
    }
    let codegen_job_count = expected_first_codegen_job_index - frontend_job_count;
    if codegen_job_count != index.codegen_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index codegen job count {} does not match entry total {}",
            index.codegen_job_count, codegen_job_count
        )));
    }
    if expected_link_job_index != expected_first_codegen_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule index entry codegen job total {} does not match scalar link job {}",
            expected_first_codegen_job_index, expected_link_job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_job_inline_dependency_count(
    job: &SourcePackJob,
    context: &str,
) -> Result<(), CompileError> {
    if job.dependency_job_indices.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "{context} stores {} inline dependency records, exceeding record cap {}",
            job.dependency_job_indices.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_page(
    page: &SourcePackLibrarySchedulePage,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if page.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded schedule page {} but expected {}",
                page.partition_index, expected_partition_index
            )));
        }
    }
    if page.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} stores {} inline dependency library records, exceeding record cap {}",
            page.partition_index,
            page.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.frontend_jobs.len() > SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} stores {} inline frontend-job records, exceeding record cap {}",
            page.partition_index,
            page.frontend_jobs.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    if page.codegen_jobs.len() > SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} stores {} inline codegen-job records, exceeding record cap {}",
            page.partition_index,
            page.codegen_jobs.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP
        )));
    }
    validate_source_pack_job_shape(
        &page.frontend_job,
        &format!("schedule page {} first frontend job", page.partition_index),
        |message| source_pack_library_partition_contract_error(message),
    )?;
    validate_source_pack_library_schedule_job_inline_dependency_count(
        &page.frontend_job,
        &format!(
            "schedule page {} first frontend dependencies",
            page.partition_index
        ),
    )?;
    if page.codegen_jobs.len() != page.codegen_job_count {
        if !page.codegen_jobs.is_empty() {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} has {} codegen jobs but codegen_job_count {}",
                page.partition_index,
                page.codegen_jobs.len(),
                page.codegen_job_count
            )));
        }
    }
    if page.codegen_job_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} has no codegen jobs",
            page.partition_index
        )));
    }
    let frontend_job_count = source_pack_library_schedule_page_frontend_job_count(page);
    if frontend_job_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} has no frontend jobs",
            page.partition_index
        )));
    }
    if !page.frontend_jobs.is_empty() && page.frontend_jobs.len() != frontend_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} has {} inline frontend jobs but frontend_job_count {}",
            page.partition_index,
            page.frontend_jobs.len(),
            frontend_job_count
        )));
    }

    if page.frontend_job.job_index != page.frontend_job_index
        || page.frontend_job.phase != SourcePackJobPhase::LibraryFrontend
        || page.frontend_job.phase_unit_index
            != source_pack_library_schedule_page_first_frontend_unit_index(page)
        || page.frontend_job.library_job_index.is_some()
        || page.frontend_job.library_id != page.library_id
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} frontend job does not match page metadata",
            page.partition_index
        )));
    }

    let mut dependency_ids = BTreeSet::new();
    for dependency_library_id in &page.dependency_library_ids {
        if *dependency_library_id == page.library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} library {} depends on itself",
                page.partition_index, page.library_id
            )));
        }
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} contains duplicate dependency library {}",
                page.partition_index, dependency_library_id
            )));
        }
    }
    source_pack_manifest_unique_usize_set(
        &page.frontend_job.dependency_job_indices,
        &format!(
            "schedule page {} first frontend dependencies",
            page.partition_index
        ),
    )?;

    for (offset, job) in page.frontend_jobs.iter().enumerate() {
        let expected_job_index = page.frontend_job_index + offset;
        validate_source_pack_job_shape(
            job,
            &format!(
                "schedule page {} frontend job {}",
                page.partition_index, job.job_index
            ),
            |message| source_pack_library_partition_contract_error(message),
        )?;
        validate_source_pack_library_schedule_job_inline_dependency_count(
            job,
            &format!(
                "schedule page {} frontend job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if job.job_index != expected_job_index
            || job.phase != SourcePackJobPhase::LibraryFrontend
            || job.phase_unit_index
                != source_pack_library_schedule_page_first_frontend_unit_index(page) + offset
            || job.library_job_index.is_some()
            || job.library_id != page.library_id
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} frontend job entry {} does not match page metadata",
                page.partition_index, offset
            )));
        }
        source_pack_manifest_unique_usize_set(
            &job.dependency_job_indices,
            &format!(
                "schedule page {} frontend job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
    }

    for (offset, job) in page.codegen_jobs.iter().enumerate() {
        let expected_job_index = page.first_codegen_job_index + offset;
        validate_source_pack_job_shape(
            job,
            &format!(
                "schedule page {} codegen job {}",
                page.partition_index, job.job_index
            ),
            |message| source_pack_library_partition_contract_error(message),
        )?;
        validate_source_pack_library_schedule_job_inline_dependency_count(
            job,
            &format!(
                "schedule page {} codegen job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if job.job_index != expected_job_index
            || job.phase != SourcePackJobPhase::Codegen
            || job.phase_unit_index != page.first_codegen_unit_index + offset
            || !job.library_job_index.is_some_and(|frontend_job_index| {
                source_pack_library_schedule_page_contains_frontend_job(page, frontend_job_index)
                    .unwrap_or(false)
            })
            || job.library_id != page.library_id
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} codegen job entry {} does not match page metadata",
                page.partition_index, offset
            )));
        }
        source_pack_manifest_unique_usize_set(
            &job.dependency_job_indices,
            &format!(
                "schedule page {} codegen job {} dependencies",
                page.partition_index, job.job_index
            ),
        )?;
        if !job
            .dependency_job_indices
            .contains(&job.library_job_index.expect("checked above"))
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} codegen job {} does not depend on owning frontend job {:?}",
                page.partition_index, job.job_index, job.library_job_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_job_locator_index(
    index: &SourcePackLibraryScheduleJobLocatorIndex,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if index.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job-locator index version {}; expected {}",
            index.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION
        )));
    }
    if index.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job-locator index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.job_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "schedule job-locator index has no jobs",
        ));
    }
    if index.locator_count != index.job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job-locator index has {} locators but {} jobs",
            index.locator_count, index.job_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_frontend_job_locator_page(
    page: &SourcePackLibraryFrontendJobLocatorPage,
    target: SourcePackArtifactTarget,
    expected_library_id: Option<u32>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library frontend-job locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "library frontend-job locator for library {} target {:?} does not match requested target {:?}",
            page.library_id, page.target, target
        )));
    }
    if let Some(expected_library_id) = expected_library_id {
        if page.library_id != expected_library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded frontend-job locator for library {} but expected {}",
                page.library_id, expected_library_id
            )));
        }
    }
    if source_pack_library_frontend_job_locator_count(page) == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "library frontend-job locator for library {} has no frontend jobs",
            page.library_id
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_job_locator_page(
    page: &SourcePackLibraryScheduleJobLocatorPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job-locator page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job-locator page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded schedule job-locator page {} but expected {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job-locator page {} exceeds job count {}",
            page.job_index, job_count
        )));
    }
    match page.phase {
        SourcePackJobPhase::LibraryFrontend => {
            if page.partition_index.is_none() || page.codegen_job_offset.is_some() {
                return Err(source_pack_library_partition_contract_error(format!(
                    "frontend job-locator page {} has partition {:?} and codegen offset {:?}",
                    page.job_index, page.partition_index, page.codegen_job_offset
                )));
            }
        }
        SourcePackJobPhase::Codegen => {
            if page.partition_index.is_none() || page.codegen_job_offset.is_none() {
                return Err(source_pack_library_partition_contract_error(format!(
                    "codegen job-locator page {} is missing partition or codegen offset",
                    page.job_index
                )));
            }
        }
        SourcePackJobPhase::Link => {
            if page.partition_index.is_some() || page.codegen_job_offset.is_some() {
                return Err(source_pack_library_partition_contract_error(format!(
                    "link job-locator page {} has partition {:?} and codegen offset {:?}",
                    page.job_index, page.partition_index, page.codegen_job_offset
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_schedule_job_page_explicit_dependency_count(
    page: &SourcePackLibraryScheduleJobPage,
) -> usize {
    page.dependency_job_count
        .max(page.job.dependency_job_indices.len())
}

pub(in crate::compiler) fn source_pack_job_index_range_dependency_count(
    ranges: &[SourcePackJobIndexRange],
) -> usize {
    ranges.iter().map(|range| range.job_count).sum()
}

pub(in crate::compiler) fn source_pack_validate_job_dependency_ranges<F>(
    dependency_job_ranges: &[SourcePackJobIndexRange],
    explicit_dependencies: &BTreeSet<usize>,
    context: &str,
    max_dependency_job_index_exclusive: usize,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut ranges = Vec::<(usize, usize)>::new();
    for (range_position, range) in dependency_job_ranges.iter().enumerate() {
        if range.job_count == 0 {
            return Err(make_error(format!(
                "{context} dependency job range {range_position} is empty"
            )));
        }
        let Some(end_job_index) = range.end_job_index() else {
            return Err(make_error(format!(
                "{context} dependency job range {range_position} overflows usize"
            )));
        };
        if end_job_index > max_dependency_job_index_exclusive {
            return Err(make_error(format!(
                "{context} dependency job range {}..{} exceeds dependency bound {}",
                range.first_job_index, end_job_index, max_dependency_job_index_exclusive
            )));
        }
        if let Some(duplicate) = explicit_dependencies
            .iter()
            .copied()
            .find(|&dependency_job_index| range.contains(dependency_job_index))
        {
            return Err(make_error(format!(
                "{context} dependency job range {}..{} duplicates explicit dependency {}",
                range.first_job_index, end_job_index, duplicate
            )));
        }
        if let Some(&(overlap_start, overlap_end)) = ranges
            .iter()
            .find(|&&(start, end)| range.first_job_index < end && start < end_job_index)
        {
            return Err(make_error(format!(
                "{context} dependency job range {}..{} overlaps range {}..{}",
                range.first_job_index, end_job_index, overlap_start, overlap_end
            )));
        }
        ranges.push((range.first_job_index, end_job_index));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_validate_job_dependent_ranges<F>(
    dependent_job_ranges: &[SourcePackJobIndexRange],
    explicit_dependents: &BTreeSet<usize>,
    context: &str,
    min_dependent_job_index_exclusive: usize,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    let mut ranges = Vec::<(usize, usize)>::new();
    for (range_position, range) in dependent_job_ranges.iter().enumerate() {
        if range.job_count == 0 {
            return Err(make_error(format!(
                "{context} dependent job range {range_position} is empty"
            )));
        }
        let Some(end_job_index) = range.end_job_index() else {
            return Err(make_error(format!(
                "{context} dependent job range {range_position} overflows usize"
            )));
        };
        if range.first_job_index <= min_dependent_job_index_exclusive {
            return Err(make_error(format!(
                "{context} dependent job range {}..{} is not after item {}",
                range.first_job_index, end_job_index, min_dependent_job_index_exclusive
            )));
        }
        if let Some(duplicate) = explicit_dependents
            .iter()
            .copied()
            .find(|&dependent_job_index| range.contains(dependent_job_index))
        {
            return Err(make_error(format!(
                "{context} dependent job range {}..{} duplicates explicit dependent {}",
                range.first_job_index, end_job_index, duplicate
            )));
        }
        if let Some(&(overlap_start, overlap_end)) = ranges
            .iter()
            .find(|&&(start, end)| range.first_job_index < end && start < end_job_index)
        {
            return Err(make_error(format!(
                "{context} dependent job range {}..{} overlaps range {}..{}",
                range.first_job_index, end_job_index, overlap_start, overlap_end
            )));
        }
        ranges.push((range.first_job_index, end_job_index));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_job_shape<F>(
    job: &SourcePackJob,
    context: &str,
    make_error: F,
) -> Result<(), CompileError>
where
    F: Fn(String) -> CompileError,
{
    job.first_source_index
        .checked_add(job.source_file_count)
        .ok_or_else(|| {
            make_error(format!(
                "{context} job {} source range overflows",
                job.job_index
            ))
        })?;
    match job.phase {
        SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
            if job.source_file_count == 0 {
                return Err(make_error(format!(
                    "{context} job {} has no source files",
                    job.job_index
                )));
            }
            if job.oversized_source_file && job.source_file_count != 1 {
                return Err(make_error(format!(
                    "{context} job {} marks an oversized source file but spans {} files",
                    job.job_index, job.source_file_count
                )));
            }
            if job.phase == SourcePackJobPhase::LibraryFrontend && job.library_job_index.is_some() {
                return Err(make_error(format!(
                    "{context} frontend job {} cannot reference owning library job {:?}",
                    job.job_index, job.library_job_index
                )));
            }
        }
        SourcePackJobPhase::Link => {
            if job.source_file_count != 0
                || job.source_bytes != 0
                || job.source_lines != 0
                || job.oversized_source_file
                || job.library_job_index.is_some()
                || !job.dependency_job_indices.is_empty()
            {
                return Err(make_error(format!(
                    "{context} link job {} has non-link job payload",
                    job.job_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_job_page(
    page: &SourcePackLibraryScheduleJobPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: Option<usize>,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page target {:?} does not match requested target {:?}",
            page.target, target
        )));
    }
    if let Some(expected_job_index) = expected_job_index {
        if page.job_index != expected_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded schedule job page {} but requested job {}",
                page.job_index, expected_job_index
            )));
        }
    }
    if page.job_index >= job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} exceeds job_count {}",
            page.job_index, job_count
        )));
    }
    if page.job.job_index != page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} contains job {}",
            page.job_index, page.job.job_index
        )));
    }
    validate_source_pack_job_shape(
        &page.job,
        &format!("schedule job page {}", page.job_index),
        |message| source_pack_library_partition_contract_error(message),
    )?;
    let explicit_dependency_job_count =
        source_pack_schedule_job_page_explicit_dependency_count(page);
    if !page.job.dependency_job_indices.is_empty() && page.dependency_job_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} records both inline and paged dependencies",
            page.job_index
        )));
    }
    if page.job.dependency_job_indices.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} stores {} inline dependency records, exceeding record cap {}",
            page.job_index,
            page.job.dependency_job_indices.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.dependency_job_ranges.len()
        > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} stores {} inline dependency range records, exceeding record cap {}",
            page.job_index,
            page.dependency_job_ranges.len(),
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if page.dependency_job_count == 0 {
        if page.dependency_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} has dependency page count {} without dependencies",
                page.job_index, page.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency_job_count
            .div_ceil(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if page.dependency_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} has dependency page count {} but expected {} for {} dependencies",
                page.job_index,
                page.dependency_page_count,
                expected_page_count,
                page.dependency_job_count
            )));
        }
    }
    let explicit_dependencies = source_pack_manifest_unique_usize_set(
        &page.job.dependency_job_indices,
        &format!("schedule job page {} dependencies", page.job_index),
    )?;
    source_pack_validate_job_dependency_ranges(
        &page.dependency_job_ranges,
        &explicit_dependencies,
        &format!("schedule job page {}", page.job_index),
        page.job_index,
        |message| source_pack_library_partition_contract_error(message),
    )?;
    for &dependency_job_index in &page.job.dependency_job_indices {
        if dependency_job_index >= page.job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job {}",
                page.job_index, dependency_job_index
            )));
        }
    }
    let dependency_job_count = explicit_dependency_job_count.saturating_add(
        page.dependency_job_ranges
            .iter()
            .map(|range| range.job_count)
            .sum::<usize>(),
    );
    if dependency_job_count > page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {} dependency count {} exceeds prior job count {}",
            page.job_index, dependency_job_count, page.job_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_schedule_job_dependency_page(
    page: &SourcePackLibraryScheduleJobDependencyPage,
    target: SourcePackArtifactTarget,
    job_count: usize,
    expected_job_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library schedule job dependency page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job dependency page {} target {:?} does not match requested target {:?}",
            page.job_index, page.target, target
        )));
    }
    if page.job_index != expected_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded schedule job dependency page for job {} but expected {}",
            page.job_index, expected_job_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded schedule job dependency page {} for job {} but expected page {}",
            page.page_index, page.job_index, expected_page_index
        )));
    }
    let expected_first_position = expected_page_index
        .saturating_mul(SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} starts at {} but expected {}",
            page.page_index,
            page.job_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_job_indices.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} records {} dependencies but stores {}",
            page.page_index,
            page.job_index,
            page.dependency_count,
            page.dependency_job_indices.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job dependency page {} for job {} exceeds page size {}",
            page.page_index,
            page.job_index,
            SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.dependency_job_indices,
        &format!(
            "schedule job dependency page {} for job {} dependencies",
            page.page_index, page.job_index
        ),
    )?;
    for &dependency_job_index in &page.dependency_job_indices {
        if dependency_job_index >= page.job_index || dependency_job_index >= job_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job dependency page {} for job {} has invalid dependency job {}",
                page.page_index, page.job_index, dependency_job_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_plan_index(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.limits != index.limits.normalized() {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan has unnormalized limits {:?}",
            index.limits
        )));
    }
    if index.input_partition_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan has no input partitions",
        ));
    }
    if index.link_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link plan has no groups",
        ));
    }
    if index.final_link_group_index >= index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan final group {} exceeds group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    if index.final_link_job_index != index.first_link_job_index + index.final_link_group_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link plan final job {} does not match first job {} plus group {}",
            index.final_link_job_index, index.first_link_job_index, index.final_link_group_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_group_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link group {} target {:?} does not match requested target {:?}",
            group.group_index, group.target, target
        )));
    }
    if let Some(expected_group_index) = expected_group_index {
        if group.group_index != expected_group_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded hierarchical link group {} but expected {}",
                group.group_index, expected_group_index
            )));
        }
    }
    if group.input_partition_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline partition records, exceeding record cap {}",
            group.group_index,
            group.input_partition_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_frontend_job_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline frontend-job records, exceeding record cap {}",
            group.group_index,
            group.input_frontend_job_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_codegen_job_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline codegen-job records, exceeding record cap {}",
            group.group_index,
            group.input_codegen_job_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    if group.input_link_group_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link group {} stores {} inline input-group records, exceeding record cap {}",
            group.group_index,
            group.input_link_group_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &group.input_partition_indices,
        &format!("hierarchical link group {} partitions", group.group_index),
    )?;
    source_pack_manifest_unique_usize_set(
        &group.input_frontend_job_indices,
        &format!(
            "hierarchical link group {} frontend jobs",
            group.group_index
        ),
    )?;
    source_pack_manifest_unique_usize_set(
        &group.input_codegen_job_indices,
        &format!("hierarchical link group {} codegen jobs", group.group_index),
    )?;
    source_pack_manifest_unique_usize_set(
        &group.input_link_group_indices,
        &format!("hierarchical link group {} input groups", group.group_index),
    )?;
    let input_partition_count = source_pack_hierarchical_link_group_input_partition_count(group);
    let input_frontend_job_count =
        source_pack_hierarchical_link_group_input_frontend_job_count(group);
    if group.input_partition_count != 0
        && !group.input_partition_indices.is_empty()
        && group.input_partition_count != group.input_partition_indices.len()
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
                    "hierarchical link reduce group {} has invalid page shape",
                    group.group_index
                )));
            }
            for &input_group_index in &group.input_link_group_indices {
                if input_group_index >= group.group_index {
                    return Err(source_pack_library_partition_contract_error(format!(
                        "hierarchical link reduce group {} depends on non-prior group {}",
                        group.group_index, input_group_index
                    )));
                }
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_index(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.link_group_count == 0 {
        return Err(source_pack_library_partition_contract_error(
            "hierarchical link execution has no groups",
        ));
    }
    if index.final_link_group_index >= index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution final group {} exceeds group count {}",
            index.final_link_group_index, index.link_group_count
        )));
    }
    if index.final_link_job_index != index.first_link_job_index + index.final_link_group_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution final job {} does not match first job {} plus group {}",
            index.final_link_job_index, index.first_link_job_index, index.final_link_group_index
        )));
    }
    validate_source_pack_manifest_artifact_key(
        target,
        &index.final_output_key,
        "hierarchical link execution final output",
    )?;
    Ok(())
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub(in crate::compiler) enum SourcePackHierarchicalLinkExecutionPageValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_page(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_hierarchical_link_execution_page_with_mode(
        page,
        target,
        expected_group_index,
        SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_page_store_input(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_hierarchical_link_execution_page_with_mode(
        page,
        target,
        expected_group_index,
        SourcePackHierarchicalLinkExecutionPageValidationMode::StoreInput,
    )
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_page_with_mode(
    page: &SourcePackHierarchicalLinkExecutionPage,
    target: SourcePackArtifactTarget,
    expected_group_index: Option<usize>,
    mode: SourcePackHierarchicalLinkExecutionPageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack hierarchical link execution page version {}; expected {}",
            page.version, SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution page {} target {:?} does not match requested target {:?}",
            page.group_index, page.target, target
        )));
    }
    if let Some(expected_group_index) = expected_group_index {
        if page.group_index != expected_group_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded hierarchical link execution page {} but expected {}",
                page.group_index, expected_group_index
            )));
        }
    }
    validate_source_pack_manifest_artifact_key(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline interface range records, exceeding record cap {}",
            page.group_index,
            page.input_interface_ranges.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_interfaces.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        && mode == SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline interface records, exceeding record cap {}",
            page.group_index,
            page.input_interfaces.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_objects.len() > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
        && mode == SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline object records, exceeding record cap {}",
            page.group_index,
            page.input_objects.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_group_indices.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        && mode == SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline partial-link group records, exceeding record cap {}",
            page.group_index,
            page.input_group_indices.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        )));
    }
    if page.input_group_output_keys.len()
        > SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        && mode == SourcePackHierarchicalLinkExecutionPageValidationMode::Persisted
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} stores {} inline partial-link key records, exceeding record cap {}",
            page.group_index,
            page.input_group_output_keys.len(),
            SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution group {} input groups",
            page.group_index
        ),
    )?;
    validate_source_pack_hierarchical_link_execution_artifact_refs(
        &page.input_interfaces,
        SourcePackArtifactKind::LibraryInterface,
        target,
        page.job_index,
        &format!(
            "hierarchical link execution group {} interface inputs",
            page.group_index
        ),
    )?;
    validate_source_pack_hierarchical_link_execution_artifact_refs(
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
    source_pack_validate_job_dependency_ranges(
        &page.input_interface_ranges,
        &explicit_interface_dependency_jobs,
        &format!(
            "hierarchical link execution group {} interface inputs",
            page.group_index
        ),
        page.job_index,
        |message| source_pack_library_partition_contract_error(message),
    )?;
    let ranged_input_interface_count =
        source_pack_job_index_range_dependency_count(&page.input_interface_ranges);
    let inline_input_interface_count = page.input_interfaces.len();
    let input_interface_count = source_pack_hierarchical_link_execution_input_interface_count(page);
    let input_object_count = source_pack_hierarchical_link_execution_input_object_count(page);
    let input_group_count = source_pack_hierarchical_link_execution_input_group_count(page);
    if page.input_interface_page_count != 0 && !page.input_interfaces.is_empty() {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged interface inputs",
            page.group_index
        )));
    }
    if page.input_interface_count != 0 {
        if page.input_interface_count < ranged_input_interface_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} records interface input count {} below ranged input count {}",
                page.group_index, page.input_interface_count, ranged_input_interface_count
            )));
        }
        if !page.input_interfaces.is_empty() {
            let expected_input_interface_count =
                inline_input_interface_count.saturating_add(ranged_input_interface_count);
            if page.input_interface_count != expected_input_interface_count {
                return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} records interface input count {} but has no explicit interface pages and {} ranged refs",
                page.group_index, page.input_interface_count, ranged_input_interface_count
            )));
        }
    }
    if input_interface_count == 0 {
        if page.input_interface_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} has interface page count {} without interface inputs",
                page.group_index, page.input_interface_page_count
            )));
        }
    } else if page.input_interface_page_count != 0 {
        if page.input_interface_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} stores paged interface inputs without recording their total count",
                page.group_index
            )));
        }
        let explicit_input_interface_count = page
            .input_interface_count
            .checked_sub(ranged_input_interface_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "hierarchical link execution group {} records interface input count {} below ranged input count {}",
                    page.group_index, page.input_interface_count, ranged_input_interface_count
                ))
            })?;
        let expected_page_count = explicit_input_interface_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE);
        if page.input_interface_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} records object input count {} but stores {} object refs",
            page.group_index,
            page.input_object_count,
            page.input_objects.len()
        )));
    }
    if page.input_object_page_count != 0 && !page.input_objects.is_empty() {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged object inputs",
            page.group_index
        )));
    }
    if page.input_object_count == 0 {
        if page.input_object_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} has object page count {} without object inputs",
                page.group_index, page.input_object_page_count
            )));
        }
    } else if page.input_objects.is_empty() {
        let expected_page_count = page
            .input_object_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE);
        if page.input_object_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} records group input count {} but stores {} input groups",
            page.group_index,
            page.input_group_count,
            page.input_group_indices.len()
        )));
    }
    if page.input_group_page_count != 0
        && (!page.input_group_indices.is_empty() || !page.input_group_output_keys.is_empty())
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} mixes inline and paged partial-link inputs",
            page.group_index
        )));
    }
    if page.input_group_count == 0 {
        if page.input_group_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} has partial-link page count {} without group inputs",
                page.group_index, page.input_group_page_count
            )));
        }
    } else if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
        let expected_page_count = page
            .input_group_count
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
        if page.input_group_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution group {} has partial-link page count {} but expected {} for {} inputs",
                page.group_index,
                page.input_group_page_count,
                expected_page_count,
                page.input_group_count
            )));
        }
    }

    if page.input_group_indices.len() != page.input_group_output_keys.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution group {} has {} input groups but {} input output keys",
            page.group_index,
            page.input_group_indices.len(),
            page.input_group_output_keys.len()
        )));
    }
    let mut input_group_output_keys = BTreeSet::new();
    for key in &page.input_group_output_keys {
        validate_source_pack_manifest_artifact_key(
            target,
            key,
            &format!(
                "hierarchical link execution group {} input-group output",
                page.group_index
            ),
        )?;
        if !input_group_output_keys.insert(key.clone()) {
            return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
                    "hierarchical link execution reduce group {} has invalid page shape",
                    page.group_index
                )));
            }
            for &input_group_index in &page.input_group_indices {
                if input_group_index >= page.group_index {
                    return Err(source_pack_library_partition_contract_error(format!(
                        "hierarchical link execution reduce group {} depends on non-prior group {}",
                        page.group_index, input_group_index
                    )));
                }
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_artifact_refs(
    artifacts: &[SourcePackArtifactRef],
    expected_kind: SourcePackArtifactKind,
    target: SourcePackArtifactTarget,
    consumer_job_index: usize,
    label: &str,
) -> Result<(), CompileError> {
    source_pack_artifact_ref_index_set(artifacts, label)?;
    for artifact in artifacts {
        if artifact.kind != expected_kind {
            return Err(source_pack_library_partition_contract_error(format!(
                "{label} artifact {} has kind {:?}, expected {:?}",
                artifact.artifact_index, artifact.kind, expected_kind
            )));
        }
        if artifact.producing_job_index >= consumer_job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "{label} artifact {} producer job {} is not before consumer link job {}",
                artifact.artifact_index, artifact.producing_job_index, consumer_job_index
            )));
        }
        validate_source_pack_manifest_artifact_key(
            target,
            &artifact.key,
            &format!("{label} artifact {}", artifact.artifact_index),
        )?;
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_interface_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded hierarchical link execution interface page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE);
    if page.first_input_position != expected_first_input_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} starts at {} but expected {}",
            page.group_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_interfaces.len() {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution interface page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    validate_source_pack_hierarchical_link_execution_artifact_refs(
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

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_object_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded hierarchical link execution object page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE);
    if page.first_input_position != expected_first_input_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} starts at {} but expected {}",
            page.group_index,
            page.page_index,
            page.first_input_position,
            expected_first_input_position
        )));
    }
    if page.input_count != page.input_objects.len() {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution object page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    validate_source_pack_hierarchical_link_execution_artifact_refs(
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

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_partial_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} target {:?} does not match requested target {:?}",
            page.group_index, page.page_index, page.target, target
        )));
    }
    if page.group_index != expected_group_index || page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded hierarchical link execution partial page {}:{} but expected {}:{}",
            page.group_index, page.page_index, expected_group_index, expected_page_index
        )));
    }
    let expected_first_input_position = expected_page_index
        .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
    if page.first_input_position != expected_first_input_position {
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution partial page {}:{} has invalid input count {}",
            page.group_index, page.page_index, page.input_count
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.input_group_indices,
        &format!(
            "hierarchical link execution partial page {}:{} input groups",
            page.group_index, page.page_index
        ),
    )?;
    let mut input_group_output_keys = BTreeSet::new();
    for &input_group_index in &page.input_group_indices {
        if input_group_index >= page.group_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution partial page {}:{} depends on non-prior group {}",
                page.group_index, page.page_index, input_group_index
            )));
        }
    }
    for key in &page.input_group_output_keys {
        validate_source_pack_manifest_artifact_key(
            target,
            key,
            &format!(
                "hierarchical link execution partial page {}:{} input-group output",
                page.group_index, page.page_index
            ),
        )?;
        if !input_group_output_keys.insert(key.clone()) {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution partial page {}:{} repeats input-group output key {:?}",
                page.group_index, page.page_index, key
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_hierarchical_link_execution_pages(
    index: &SourcePackHierarchicalLinkExecutionIndex,
    pages: &[SourcePackHierarchicalLinkExecutionPage],
) -> Result<(), CompileError> {
    validate_source_pack_hierarchical_link_execution_index(index, index.target)?;
    if pages.len() != index.link_group_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "hierarchical link execution store has {} pages but index records {}",
            pages.len(),
            index.link_group_count
        )));
    }
    for (position, page) in pages.iter().enumerate() {
        validate_source_pack_hierarchical_link_execution_page(page, index.target, Some(position))?;
        let expected_final = page.group_index == index.final_link_group_index;
        if page.final_output != expected_final {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution page {} final_output {} does not match final group {}",
                page.group_index, page.final_output, index.final_link_group_index
            )));
        }
        if page.final_output && page.output_key != index.final_output_key {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link execution page {} final output {:?} does not match index {:?}",
                page.group_index, page.output_key, index.final_output_key
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_work_queue_index(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.work_item_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue item count {} is invalid",
            index.work_item_count
        )));
    }
    if index.artifact_item_count > index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue artifact item count {} exceeds item count {}",
            index.artifact_item_count, index.work_item_count
        )));
    }
    if index.final_item_index >= index.work_item_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue final item {} exceeds item count {}",
            index.final_item_index, index.work_item_count
        )));
    }
    if index.final_job_index != index.final_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue final job {} does not match final item {}",
            index.final_job_index, index.final_item_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_work_queue_page(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_page_with_mode(
        page,
        target,
        expected_item_index,
        SourcePackWorkQueuePageValidationMode::Persisted,
    )
}

pub(in crate::compiler) fn validate_source_pack_work_queue_page_store_input(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
) -> Result<(), CompileError> {
    validate_source_pack_work_queue_page_with_mode(
        page,
        target,
        expected_item_index,
        SourcePackWorkQueuePageValidationMode::StoreInput,
    )
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub(in crate::compiler) enum SourcePackWorkQueuePageValidationMode {
    Persisted,
    StoreInput,
}

pub(in crate::compiler) fn validate_source_pack_work_queue_inline_record_count(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} stores {} inline {} records, exceeding record cap {}",
            page.item_index, count, label, cap
        )));
    }
    Ok(true)
}

pub(in crate::compiler) fn validate_source_pack_work_queue_page_with_mode(
    page: &SourcePackWorkQueuePage,
    target: SourcePackArtifactTarget,
    expected_item_index: Option<usize>,
    mode: SourcePackWorkQueuePageValidationMode,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_WORK_QUEUE_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack work queue page version {}; expected {}",
            page.version, SOURCE_PACK_WORK_QUEUE_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if let Some(expected_item_index) = expected_item_index {
        if page.item_index != expected_item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded work queue page {} but expected {}",
                page.item_index, expected_item_index
            )));
        }
    }
    if page.item_index != page.job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} job index {} does not match item index",
            page.item_index, page.job_index
        )));
    }
    let scan_dependency_item_indices = validate_source_pack_work_queue_inline_record_count(
        page,
        "dependency",
        page.dependency_item_indices.len(),
        SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
        mode == SourcePackWorkQueuePageValidationMode::StoreInput,
    )?;
    let scan_dependent_item_indices = validate_source_pack_work_queue_inline_record_count(
        page,
        "dependent",
        page.dependent_item_indices.len(),
        SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
        mode == SourcePackWorkQueuePageValidationMode::StoreInput,
    )?;
    let scan_partition_indices = validate_source_pack_work_queue_inline_record_count(
        page,
        "partition",
        page.partition_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        mode == SourcePackWorkQueuePageValidationMode::StoreInput
            && matches!(page.kind, SourcePackWorkQueueItemKind::LinkReduce),
    )?;
    let scan_input_frontend_job_indices = validate_source_pack_work_queue_inline_record_count(
        page,
        "frontend input",
        page.input_frontend_job_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        mode == SourcePackWorkQueuePageValidationMode::StoreInput,
    )?;
    validate_source_pack_work_queue_inline_record_count(
        page,
        "codegen input",
        page.input_codegen_job_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        false,
    )?;
    validate_source_pack_work_queue_inline_record_count(
        page,
        "link-group input",
        page.input_link_group_indices.len(),
        SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
        false,
    )?;
    if scan_dependency_item_indices {
        let explicit_dependencies = source_pack_manifest_unique_usize_set(
            &page.dependency_item_indices,
            &format!("work queue page {} dependencies", page.item_index),
        )?;
        for &dependency_item_index in &page.dependency_item_indices {
            if dependency_item_index >= page.item_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue page {} depends on non-prior item {}",
                    page.item_index, dependency_item_index
                )));
            }
        }
        source_pack_validate_job_dependency_ranges(
            &page.dependency_item_ranges,
            &explicit_dependencies,
            &format!("work queue page {}", page.item_index),
            page.item_index,
            |message| source_pack_library_partition_contract_error(message),
        )?;
    }
    if page.dependency_item_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} stores {} inline dependency range records, exceeding record cap {}",
            page.item_index,
            page.dependency_item_ranges.len(),
            SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        )));
    }
    if !page.dependency_item_indices.is_empty() && page.dependency_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} records both inline and paged dependencies",
            page.item_index
        )));
    }
    if page.dependency_item_count == 0 {
        if page.dependency_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} has dependency page count {} without dependencies",
                page.item_index, page.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependency_item_count
            .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
        if page.dependency_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} has dependency page count {} but expected {} for {} dependencies",
                page.item_index,
                page.dependency_page_count,
                expected_page_count,
                page.dependency_item_count
            )));
        }
    }
    if scan_dependent_item_indices {
        let explicit_dependents = source_pack_manifest_unique_usize_set(
            &page.dependent_item_indices,
            &format!("work queue page {} dependents", page.item_index),
        )?;
        for &dependent_item_index in &page.dependent_item_indices {
            if dependent_item_index <= page.item_index {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue page {} has non-later dependent item {}",
                    page.item_index, dependent_item_index
                )));
            }
        }
        source_pack_validate_job_dependent_ranges(
            &page.dependent_item_ranges,
            &explicit_dependents,
            &format!("work queue page {}", page.item_index),
            page.item_index,
            |message| source_pack_library_partition_contract_error(message),
        )?;
    }
    if page.dependent_item_ranges.len() > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} stores {} inline dependent range records, exceeding record cap {}",
            page.item_index,
            page.dependent_item_ranges.len(),
            SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE
        )));
    }
    if !page.dependent_item_indices.is_empty() && page.dependent_item_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue page {} records both inline and paged dependents",
            page.item_index
        )));
    }
    if page.dependent_item_count == 0 {
        if page.dependent_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} has dependent page count {} without dependents",
                page.item_index, page.dependent_page_count
            )));
        }
    } else {
        let expected_page_count = page
            .dependent_item_count
            .div_ceil(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
        if page.dependent_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue page {} kind {:?} cannot map directly to artifact batch {}",
                page.item_index, page.kind, artifact_batch_index
            )));
        }
    }
    if scan_partition_indices {
        source_pack_manifest_unique_usize_set(
            &page.partition_indices,
            &format!("work queue page {} partitions", page.item_index),
        )?;
    }
    if scan_input_frontend_job_indices {
        source_pack_manifest_unique_usize_set(
            &page.input_frontend_job_indices,
            &format!("work queue page {} frontend inputs", page.item_index),
        )?;
    }
    source_pack_manifest_unique_usize_set(
        &page.input_codegen_job_indices,
        &format!("work queue page {} codegen inputs", page.item_index),
    )?;
    source_pack_manifest_unique_usize_set(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
        return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue link reduce page {} has invalid shape",
                    page.item_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_work_queue_dependencies_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependencies page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if page.item_index != expected_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded work queue dependencies page for item {} but expected {}",
            page.item_index, expected_item_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded work queue dependencies page {} for item {} but expected page {}",
            page.page_index, page.item_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} starts at {} but expected {}",
            page.page_index,
            page.item_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_item_indices.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} records {} dependencies but stores {}",
            page.page_index,
            page.item_index,
            page.dependency_count,
            page.dependency_item_indices.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependencies page {} for item {} exceeds page size {}",
            page.page_index, page.item_index, SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.dependency_item_indices,
        &format!(
            "work queue dependencies page {} for item {} dependencies",
            page.page_index, page.item_index
        ),
    )?;
    for &dependency_item_index in &page.dependency_item_indices {
        if dependency_item_index >= page.item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue dependencies page {} for item {} has non-prior dependency item {}",
                page.page_index, page.item_index, dependency_item_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_work_queue_dependents_page(
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
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependents page {} target {:?} does not match requested target {:?}",
            page.item_index, page.target, target
        )));
    }
    if page.item_index != expected_item_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded work queue dependents page for item {} but expected {}",
            page.item_index, expected_item_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded work queue dependents page {} for item {} but expected page {}",
            page.page_index, page.item_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
    if page.first_dependent_position != expected_first_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependents page {} for item {} starts at {} but expected {}",
            page.page_index,
            page.item_index,
            page.first_dependent_position,
            expected_first_position
        )));
    }
    if page.dependent_count != page.dependent_item_indices.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependents page {} for item {} records {} dependents but stores {}",
            page.page_index,
            page.item_index,
            page.dependent_count,
            page.dependent_item_indices.len()
        )));
    }
    if page.dependent_count > SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "work queue dependents page {} for item {} exceeds page size {}",
            page.page_index, page.item_index, SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_usize_set(
        &page.dependent_item_indices,
        &format!(
            "work queue dependents page {} for item {} dependents",
            page.page_index, page.item_index
        ),
    )?;
    for &dependent_item_index in &page.dependent_item_indices {
        if dependent_item_index <= page.item_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue dependents page {} for item {} has non-later dependent item {}",
                page.page_index, page.item_index, dependent_item_index
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_filesystem_work_queue_final_linked_output_for_progress(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    progress: &SourcePackFilesystemWorkQueueProgressSnapshot,
) -> Result<(Option<String>, Option<PathBuf>), CompileError> {
    if !progress.complete {
        return Ok((None, None));
    }
    let link_index = store.load_hierarchical_link_execution_index_for_target(target)?;
    let linked_output_key = link_index.final_output_key;
    let linked_output_path = store.path_for_key(&linked_output_key)?;
    if !linked_output_path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack complete work queue has no linked output artifact {linked_output_key:?} at {}",
            linked_output_path.display()
        )));
    }
    Ok((Some(linked_output_key), Some(linked_output_path)))
}

pub(in crate::compiler) fn validate_source_pack_library_partition(
    partition: &SourcePackLibraryPartition,
    target: SourcePackArtifactTarget,
    expected_partition_index: Option<usize>,
) -> Result<(), CompileError> {
    if partition.version != SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library partition version {}; expected {}",
            partition.version, SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION
        )));
    }
    if partition.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} target {:?} does not match requested target {:?}",
            partition.partition_index, partition.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if partition.partition_index != expected_partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "loaded partition {} but expected {}",
                partition.partition_index, expected_partition_index
            )));
        }
    }
    if partition.source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} has no source files",
            partition.partition_index
        )));
    }

    if !partition.dependency_library_ids.is_empty() && partition.dependency_library_count != 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} records both inline and paged library dependencies",
            partition.partition_index
        )));
    }
    if partition.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} stores {} inline dependency library records, exceeding record cap {}",
            partition.partition_index,
            partition.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if partition.dependency_library_count == 0 {
        if partition.dependency_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} has dependency page count {} without dependencies",
                partition.partition_index, partition.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = partition
            .dependency_library_count
            .div_ceil(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if partition.dependency_page_count != expected_page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} has dependency page count {} but expected {} for {} dependencies",
                partition.partition_index,
                partition.dependency_page_count,
                expected_page_count,
                partition.dependency_library_count
            )));
        }
        if partition.dependency_library_count > partition.partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} dependency count {} exceeds prior partition count {}",
                partition.partition_index,
                partition.dependency_library_count,
                partition.partition_index
            )));
        }
    }

    let mut dependency_ids = BTreeSet::new();
    for dependency_library_id in &partition.dependency_library_ids {
        if *dependency_library_id == partition.library_id {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} library {} depends on itself",
                partition.partition_index, partition.library_id
            )));
        }
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} contains duplicate dependency library {}",
                partition.partition_index, dependency_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_library_dependency_page(
    page: &SourcePackLibraryDependencyPage,
    target: SourcePackArtifactTarget,
    expected_partition_index: usize,
    expected_page_index: usize,
) -> Result<(), CompileError> {
    if page.version != SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library dependency page version {}; expected {}",
            page.version, SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION
        )));
    }
    if page.target != target {
        return Err(source_pack_library_partition_contract_error(format!(
            "library dependency page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if page.partition_index != expected_partition_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded library dependency page for partition {} but expected {}",
            page.partition_index, expected_partition_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "loaded library dependency page {} for partition {} but expected page {}",
            page.page_index, page.partition_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(source_pack_library_partition_contract_error(format!(
            "library dependency page {} for partition {} starts at {} but expected {}",
            page.page_index,
            page.partition_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_library_ids.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "library dependency page {} for partition {} records {} dependencies but stores {}",
            page.page_index,
            page.partition_index,
            page.dependency_count,
            page.dependency_library_ids.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(source_pack_library_partition_contract_error(format!(
            "library dependency page {} for partition {} exceeds page size {}",
            page.page_index, page.partition_index, SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    source_pack_manifest_unique_u32_set(
        &page.dependency_library_ids,
        &format!(
            "library dependency page {} for partition {} dependencies",
            page.page_index, page.partition_index
        ),
    )?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_build_now_unix_nanos() -> Result<u128, CompileError> {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .map_err(|err| CompileError::GpuFrontend(format!("system clock is before epoch: {err}")))
}

pub(in crate::compiler) fn source_pack_progress_summary_min_lease(
    existing: Option<u128>,
    candidate: Option<u128>,
) -> Option<u128> {
    match (existing, candidate) {
        (Some(existing), Some(candidate)) => Some(existing.min(candidate)),
        (Some(existing), None) => Some(existing),
        (None, Some(candidate)) => Some(candidate),
        (None, None) => None,
    }
}

pub(in crate::compiler) fn source_pack_build_link_input_shard_index(
    plan: &SourcePackBuildArtifactShardPlan,
) -> Result<SourcePackBuildLinkInputShardIndex, CompileError> {
    validate_source_pack_build_artifact_shard_plan(plan)?;
    let mut link_interface_shard_range = None;
    let mut link_object_shard_range = None;
    for shard in &plan.shards {
        match shard.kind {
            SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
                source_pack_extend_link_input_shard_range(
                    &mut link_interface_shard_range,
                    shard.shard_index,
                    "interface",
                )?;
            }
            SourcePackBuildArtifactShardKind::LinkObjectBatches => {
                source_pack_extend_link_input_shard_range(
                    &mut link_object_shard_range,
                    shard.shard_index,
                    "object",
                )?;
            }
            SourcePackBuildArtifactShardKind::JobBatches => {}
        }
    }
    let link_input_index = SourcePackBuildLinkInputShardIndex {
        version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
        target: plan.index.target,
        link_interface_shard_range,
        link_object_shard_range,
    };
    validate_source_pack_build_link_input_shard_index(&link_input_index, plan.index.target)?;
    Ok(link_input_index)
}

pub(in crate::compiler) fn source_pack_update_ready_frontier_after_batch_completion_bounded(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    completed_batch_index: usize,
    now_unix_nanos: Option<u128>,
) -> Result<(), CompileError> {
    let summary = store.load_build_progress_summary_for_target(target)?;
    source_pack_for_each_job_batch_dependent_index(
        store,
        target,
        completed_batch_index,
        summary.job_batch_count,
        |dependent_batch_index| {
            let locator =
                store.load_build_batch_shard_locator_for_target(target, dependent_batch_index)?;
            let dependent_execution_shard = store
                .load_build_artifact_execution_shard_for_target(target, locator.shard_index)?;
            if dependent_execution_shard.shard.kind != SourcePackBuildArtifactShardKind::JobBatches
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "reverse dependency points to non-job shard {:?}",
                    dependent_execution_shard.shard.kind
                )));
            }
            let mut progress =
                store.load_build_progress_shard_for_target(target, locator.shard_index)?;
            let mut progress_changed = progress.prune_inactive_batch_claims(now_unix_nanos)?;
            if !dependent_execution_shard
                .shard
                .batch_indices
                .contains(&dependent_batch_index)
            {
                return Err(source_pack_artifact_shard_contract_error(format!(
                    "dependent batch {dependent_batch_index} is not in execution shard {}",
                    locator.shard_index
                )));
            }
            if progress.is_batch_completed(dependent_batch_index) {
                if progress_changed {
                    store.store_build_progress_shard(&progress)?;
                }
                return Ok(());
            }
            let dependency = source_pack_execution_shard_batch_dependency(
                &dependent_execution_shard,
                dependent_batch_index,
            )?;
            let mut dependencies_complete = true;
            source_pack_for_each_stored_job_batch_dependency_index(
                store,
                target,
                dependency,
                |dependency_batch_index| {
                    if !source_pack_progress_batch_is_completed_from_locator(
                        store,
                        target,
                        dependency_batch_index,
                    )? {
                        dependencies_complete = false;
                    }
                    Ok(())
                },
            )?;
            if dependencies_complete {
                let was_ready = progress.is_batch_ready(dependent_batch_index);
                progress.record_batch_ready(dependent_batch_index)?;
                progress_changed = progress_changed || !was_ready;
            } else if progress.remove_ready_batch(dependent_batch_index)? {
                progress_changed = true;
            }
            if progress_changed {
                store.store_build_progress_shard(&progress)?;
            }
            Ok(())
        },
    )?;
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_build_state_progress_shards(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    state: &SourcePackBuildState,
) -> Result<(), CompileError> {
    validate_source_pack_build_state_version(state)?;
    let summary = store.load_build_progress_summary_for_target(target)?;
    if state.completed_batch_count != summary.completed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "compact source-pack build state records {} completed batches, but persisted progress summary records {}",
            state.completed_batch_count, summary.completed_batch_count
        )));
    }
    if state.claimed_batch_count != summary.claimed_batch_count {
        return Err(CompileError::GpuFrontend(format!(
            "compact source-pack build state records {} claimed batches, but persisted progress summary records {}",
            state.claimed_batch_count, summary.claimed_batch_count
        )));
    }
    if let Some(linked_output_key) = &state.linked_output_key {
        if summary
            .linked_output_key
            .as_ref()
            .is_some_and(|existing| existing != linked_output_key)
        {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress summary already recorded linked output {:?}, cannot replace with {:?}",
                summary.linked_output_key.as_deref(),
                linked_output_key
            )));
        }
        if summary.linked_output_key.is_none() {
            return Err(CompileError::GpuFrontend(
                "compact source-pack build state cannot introduce a linked output key; write the producing progress shard instead".into(),
            ));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_completed_batch_artifacts_from_execution_shard(
    store: &SourcePackFilesystemArtifactStore,
    execution_shard: &SourcePackBuildArtifactExecutionShard,
    batch_index: usize,
) -> Result<(), CompileError> {
    let batch = source_pack_execution_shard_job_batch(execution_shard, batch_index)?;
    for &job_index in &batch.job_indices {
        let job_manifest = source_pack_execution_shard_job_artifact(execution_shard, job_index)?;
        for artifact in &job_manifest.outputs {
            if !store.artifact_exists(artifact)? {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack build state marks batch {} complete but output artifact {:?} from job {} is missing",
                    batch.batch_index, artifact.key, job_manifest.job_index
                )));
            }
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_ready_batch_dependency_artifacts_from_execution_shards(
    store: &SourcePackFilesystemArtifactStore,
    job_batch_count: usize,
    target: SourcePackArtifactTarget,
    ready_batch_indices: &[usize],
) -> Result<(), CompileError> {
    for &ready_batch_index in ready_batch_indices {
        if ready_batch_index >= job_batch_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "ready batch {ready_batch_index} exceeds job batch count {job_batch_count}"
            )));
        }
        let ready_execution_shard =
            source_pack_execution_shard_for_batch_locator(store, target, ready_batch_index)?;
        validate_source_pack_build_artifact_execution_shard(&ready_execution_shard, target)?;
        let dependency = source_pack_execution_shard_batch_dependency(
            &ready_execution_shard,
            ready_batch_index,
        )?;
        source_pack_for_each_stored_job_batch_dependency_index(
            store,
            target,
            dependency,
            |dependency_batch_index| {
                validate_source_pack_ready_batch_dependency_artifact_from_execution_shards(
                    store,
                    job_batch_count,
                    target,
                    ready_batch_index,
                    dependency_batch_index,
                )?;
                Ok(())
            },
        )?;
    }
    Ok(())
}

pub(in crate::compiler) fn validate_source_pack_ready_batch_dependency_artifact_from_execution_shards(
    store: &SourcePackFilesystemArtifactStore,
    job_batch_count: usize,
    target: SourcePackArtifactTarget,
    ready_batch_index: usize,
    dependency_batch_index: usize,
) -> Result<(), CompileError> {
    if dependency_batch_index >= job_batch_count {
        return Err(source_pack_artifact_shard_contract_error(format!(
            "ready batch {ready_batch_index} dependency {dependency_batch_index} exceeds job batch count {job_batch_count}"
        )));
    }
    if !source_pack_progress_batch_is_completed_from_locator(store, target, dependency_batch_index)?
    {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack ready batch {ready_batch_index} dependency {dependency_batch_index} is not complete"
        )));
    }
    let dependency_execution_shard =
        source_pack_execution_shard_for_batch_locator(store, target, dependency_batch_index)?;
    validate_source_pack_build_artifact_execution_shard(&dependency_execution_shard, target)?;
    validate_source_pack_completed_batch_artifacts_from_execution_shard(
        store,
        &dependency_execution_shard,
        dependency_batch_index,
    )?;
    Ok(())
}

pub(in crate::compiler) fn source_pack_build_artifact_execution_shard(
    manifest: &SourcePackPathBuildManifest,
    shard: &SourcePackBuildArtifactShard,
) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
    validate_source_pack_path_build_manifest_versions(manifest)?;
    validate_source_pack_build_artifact_shard(shard, manifest.artifacts.target)?;

    let mut source_file_indices = BTreeSet::new();
    let mut jobs = Vec::new();
    let mut job_artifacts = Vec::new();
    for &job_index in &shard.job_indices {
        let job = source_pack_schedule_job(&manifest.artifacts.job_schedule, job_index)?.clone();
        for source_index in
            job.first_source_index..job.first_source_index.saturating_add(job.source_file_count)
        {
            source_file_indices.insert(source_index);
        }
        let job_manifest =
            source_pack_job_artifact_manifest(&manifest.artifacts.job_artifacts, job_index)?
                .clone();
        jobs.push(job);
        job_artifacts.push(job_manifest);
    }

    let mut job_batches = Vec::new();
    let mut batch_dependencies = Vec::new();
    let mut batch_dependents = Vec::new();
    let mut link_interface_batches = Vec::new();
    let mut link_object_batches = Vec::new();
    match shard.kind {
        SourcePackBuildArtifactShardKind::JobBatches => {
            for &batch_index in &shard.batch_indices {
                job_batches.push(
                    source_pack_artifact_manifest_batch(&manifest.artifacts, batch_index)?.clone(),
                );
                batch_dependencies.push(
                    source_pack_job_batch_dependency(
                        &manifest.artifacts.batch_dependencies,
                        batch_index,
                    )?
                    .clone(),
                );
                batch_dependents.push(SourcePackJobBatchDependents {
                    batch_index,
                    dependent_batch_indices: Vec::new(),
                });
            }
        }
        SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
            for &batch_index in &shard.batch_indices {
                link_interface_batches.push(
                    source_pack_link_interface_batch(
                        &manifest.artifacts.link_interface_batches,
                        batch_index,
                    )?
                    .clone(),
                );
            }
        }
        SourcePackBuildArtifactShardKind::LinkObjectBatches => {
            for &batch_index in &shard.batch_indices {
                link_object_batches.push(
                    source_pack_link_object_batch(
                        &manifest.artifacts.link_object_batches,
                        batch_index,
                    )?
                    .clone(),
                );
            }
        }
    }

    let source_files = source_file_indices
        .into_iter()
        .map(|source_index| {
            let file = manifest
                .source_files
                .get(source_index)
                .cloned()
                .ok_or_else(|| {
                    source_pack_artifact_shard_contract_error(format!(
                        "execution shard {} references missing source file {}",
                        shard.shard_index, source_index
                    ))
                })?;
            Ok(SourcePackShardSourceFile { source_index, file })
        })
        .collect::<Result<Vec<_>, CompileError>>()?;

    let artifact_indices = shard
        .input_artifact_indices
        .iter()
        .chain(shard.output_artifact_indices.iter())
        .copied()
        .collect::<BTreeSet<_>>()
        .into_iter()
        .collect::<Vec<_>>();
    let mut artifact_refs =
        artifact_refs_for_indices(&manifest.artifacts.artifacts, &artifact_indices)?;
    let mut seen_artifact_refs = artifact_refs
        .iter()
        .map(|artifact| artifact.artifact_index)
        .collect::<BTreeSet<_>>();
    for range in &shard.input_artifact_ranges {
        let Some(indices) = range.iter() else {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "execution shard {} input artifact range starting at {} overflows",
                shard.shard_index, range.first_artifact_index
            )));
        };
        for artifact_index in indices {
            if !seen_artifact_refs.insert(artifact_index) {
                continue;
            }
            artifact_refs.push(source_pack_artifact_ref_for_index(
                &manifest.artifacts.artifacts,
                artifact_index,
            )?);
        }
    }

    Ok(SourcePackBuildArtifactExecutionShard {
        version: SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
        target: manifest.artifacts.target,
        shard: shard.clone(),
        source_files,
        job_batches,
        batch_dependencies,
        batch_dependents,
        jobs,
        job_artifacts,
        artifact_refs,
        link_interface_batches,
        link_object_batches,
    })
}
