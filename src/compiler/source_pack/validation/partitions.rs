use super::*;

pub(in crate::compiler) fn validate_library_partition_index(
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
        return Err(library_partition_contract_error(format!(
            "partition index target {:?} does not match requested target {:?}",
            index.target, target
        )));
    }
    if index.source_file_count == 0 {
        return Err(library_partition_contract_error(
            "partition index has no source files",
        ));
    }
    if index.partition_count == 0 {
        return Err(library_partition_contract_error(
            "partition index has no library partitions",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_metadata_prepare_progress(
    progress: &FilesystemLibraryMetadataPrepareProgress,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    if progress.version != SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION {
        return Err(CompileError::GpuFrontend(format!(
            "unsupported source-pack library metadata prepare progress version {}; expected {}",
            progress.version, SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION
        )));
    }
    if progress.target != target {
        return Err(library_partition_contract_error(format!(
            "library metadata prepare progress target {:?} does not match requested target {:?}",
            progress.target, target
        )));
    }
    if progress.library_count != progress.library_partition_count {
        return Err(library_partition_contract_error(format!(
            "library metadata prepare progress has library_count {} but partition_count {}",
            progress.library_count, progress.library_partition_count
        )));
    }
    if progress.library_source_file_page_count != progress.library_partition_count {
        return Err(library_partition_contract_error(format!(
            "library metadata prepare progress has source-file page count {} but partition_count {}",
            progress.library_source_file_page_count, progress.library_partition_count
        )));
    }
    if progress.library_partition_count == 0
        && (progress.source_file_count != 0
            || progress.source_byte_count != 0
            || progress.source_line_count != 0)
    {
        return Err(library_partition_contract_error(
            "empty library metadata prepare progress has nonzero source totals",
        ));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_partition_plan(
    plan: &SourcePackLibraryPartitionPlan,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_library_partition_records(&plan.index, &plan.partitions, target)
}

pub(in crate::compiler) fn validate_library_partition_records(
    index: &SourcePackLibraryPartitionIndex,
    partitions: &[SourcePackLibraryPartition],
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_library_partition_index(index, target)?;
    if partitions.len() != index.partition_count {
        return Err(library_partition_contract_error(format!(
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
        validate_library_partition(partition, target, Some(position))?;
        if partition.first_source_index != expected_first_source_index {
            return Err(library_partition_contract_error(format!(
                "partition {} starts at source {}, expected {}",
                partition.partition_index,
                partition.first_source_index,
                expected_first_source_index
            )));
        }
        expected_first_source_index = expected_first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        source_byte_count = source_byte_count
            .checked_add(partition.source_byte_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} byte count overflows",
                    partition.partition_index
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(partition.source_line_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} source line count overflows",
                    partition.partition_index
                ))
            })?;
        if library_index_by_id
            .insert(partition.library_id, partition.partition_index)
            .is_some()
        {
            return Err(library_partition_contract_error(format!(
                "library {} appears in more than one partition",
                partition.library_id
            )));
        }
    }

    if expected_first_source_index != index.source_file_count {
        return Err(library_partition_contract_error(format!(
            "partition source file total {} does not match index source file count {}",
            expected_first_source_index, index.source_file_count
        )));
    }
    if source_byte_count != index.source_byte_count {
        return Err(library_partition_contract_error(format!(
            "partition byte total {} does not match index source byte count {}",
            source_byte_count, index.source_byte_count
        )));
    }
    if source_line_count != index.source_line_count {
        return Err(library_partition_contract_error(format!(
            "partition source line total {} does not match index source line count {}",
            source_line_count, index.source_line_count
        )));
    }

    for partition in partitions {
        for dependency_library_id in &partition.dependency_library_ids {
            let Some(&dependency_partition_index) = library_index_by_id.get(dependency_library_id)
            else {
                return Err(library_partition_contract_error(format!(
                    "partition {} depends on missing library {}",
                    partition.partition_index, dependency_library_id
                )));
            };
            if dependency_partition_index >= partition.partition_index {
                return Err(library_partition_contract_error(format!(
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

pub(in crate::compiler) fn validate_library_partition(
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
        return Err(library_partition_contract_error(format!(
            "partition {} target {:?} does not match requested target {:?}",
            partition.partition_index, partition.target, target
        )));
    }
    if let Some(expected_partition_index) = expected_partition_index {
        if partition.partition_index != expected_partition_index {
            return Err(library_partition_contract_error(format!(
                "loaded partition {} but expected {}",
                partition.partition_index, expected_partition_index
            )));
        }
    }
    if partition.source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "partition {} has no source files",
            partition.partition_index
        )));
    }

    if !partition.dependency_library_ids.is_empty() && partition.dependency_library_count != 0 {
        return Err(library_partition_contract_error(format!(
            "partition {} records both inline and paged library dependencies",
            partition.partition_index
        )));
    }
    if partition.dependency_library_ids.len() > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "partition {} stores {} inline dependency library records, exceeding record cap {}",
            partition.partition_index,
            partition.dependency_library_ids.len(),
            SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    if partition.dependency_library_count == 0 {
        if partition.dependency_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "partition {} has dependency page count {} without dependencies",
                partition.partition_index, partition.dependency_page_count
            )));
        }
    } else {
        let expected_page_count = partition
            .dependency_library_count
            .div_ceil(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if partition.dependency_page_count != expected_page_count {
            return Err(library_partition_contract_error(format!(
                "partition {} has dependency page count {} but expected {} for {} dependencies",
                partition.partition_index,
                partition.dependency_page_count,
                expected_page_count,
                partition.dependency_library_count
            )));
        }
        if partition.dependency_library_count > partition.partition_index {
            return Err(library_partition_contract_error(format!(
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
            return Err(library_partition_contract_error(format!(
                "partition {} library {} depends on itself",
                partition.partition_index, partition.library_id
            )));
        }
        if !dependency_ids.insert(*dependency_library_id) {
            return Err(library_partition_contract_error(format!(
                "partition {} contains duplicate dependency library {}",
                partition.partition_index, dependency_library_id
            )));
        }
    }
    Ok(())
}

pub(in crate::compiler) fn validate_library_dependency_page(
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
        return Err(library_partition_contract_error(format!(
            "library dependency page {} target {:?} does not match requested target {:?}",
            page.partition_index, page.target, target
        )));
    }
    if page.partition_index != expected_partition_index {
        return Err(library_partition_contract_error(format!(
            "loaded library dependency page for partition {} but expected {}",
            page.partition_index, expected_partition_index
        )));
    }
    if page.page_index != expected_page_index {
        return Err(library_partition_contract_error(format!(
            "loaded library dependency page {} for partition {} but expected page {}",
            page.page_index, page.partition_index, expected_page_index
        )));
    }
    let expected_first_position =
        expected_page_index.saturating_mul(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
    if page.first_dependency_position != expected_first_position {
        return Err(library_partition_contract_error(format!(
            "library dependency page {} for partition {} starts at {} but expected {}",
            page.page_index,
            page.partition_index,
            page.first_dependency_position,
            expected_first_position
        )));
    }
    if page.dependency_count != page.dependency_library_ids.len() {
        return Err(library_partition_contract_error(format!(
            "library dependency page {} for partition {} records {} dependencies but stores {}",
            page.page_index,
            page.partition_index,
            page.dependency_count,
            page.dependency_library_ids.len()
        )));
    }
    if page.dependency_count > SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Err(library_partition_contract_error(format!(
            "library dependency page {} for partition {} exceeds page size {}",
            page.page_index, page.partition_index, SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE
        )));
    }
    unique_u32_set(
        &page.dependency_library_ids,
        &format!(
            "library dependency page {} for partition {} dependencies",
            page.page_index, page.partition_index
        ),
    )?;
    Ok(())
}
