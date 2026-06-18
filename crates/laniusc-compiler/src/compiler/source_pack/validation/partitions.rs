use super::*;

/// Validates the compact library partition index for a target.
///
/// The index must describe at least one source file and one partition, and its
/// source-byte summary must prove real source metadata was scanned.
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
    validate_source_byte_summary(
        "partition index",
        index.source_file_count,
        index.source_byte_count,
    )?;
    if index.partition_count == 0 {
        return Err(library_partition_contract_error(
            "partition index has no library partitions",
        ));
    }
    if index.partition_count > index.source_file_count {
        return Err(library_partition_contract_error(format!(
            "partition index has {} library partitions for {} source files; each partition must carry at least one source file before scheduling or linking",
            index.partition_count, index.source_file_count
        )));
    }
    Ok(())
}

/// Validates the resumable library-metadata preparation checkpoint.
///
/// The checkpoint's library, partition, and source-file page counts must stay in
/// lockstep because each prepared library produces exactly one partition page
/// and one compact source-file page.
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

/// Validates an in-memory library partition plan.
pub(in crate::compiler) fn validate_library_partition_plan(
    plan: &SourcePackLibraryPartitionPlan,
    target: SourcePackArtifactTarget,
) -> Result<(), CompileError> {
    validate_library_partition_records(&plan.index, &plan.partitions, target)
}

/// Validates the partition records against their compact index.
///
/// Partitions must be dense by index, cover the source-file range without gaps,
/// sum to the index totals, and depend only on libraries in earlier partitions.
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

fn validate_library_dependency_ids_strictly_ascending(
    dependency_library_ids: &[u32],
    context: &str,
) -> Result<(), CompileError> {
    let mut previous_dependency_library_id = None;
    for &dependency_library_id in dependency_library_ids {
        if let Some(previous_dependency_library_id) = previous_dependency_library_id
            && dependency_library_id <= previous_dependency_library_id
        {
            return Err(library_partition_contract_error(format!(
                "{context} dependency library ids must be strictly ascending; id {dependency_library_id} follows {previous_dependency_library_id}"
            )));
        }
        previous_dependency_library_id = Some(dependency_library_id);
    }
    Ok(())
}

/// Validates one library partition page.
///
/// A partition must carry source files, non-empty source-byte evidence, and
/// either inline or paged dependency IDs, but not both.
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
    validate_source_byte_summary(
        &format!("partition {}", partition.partition_index),
        partition.source_file_count,
        partition.source_byte_count,
    )?;

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
    validate_library_dependency_ids_strictly_ascending(
        &partition.dependency_library_ids,
        &format!("partition {}", partition.partition_index),
    )?;
    Ok(())
}

fn validate_source_byte_summary(
    context: &str,
    source_file_count: usize,
    source_byte_count: usize,
) -> Result<(), CompileError> {
    if source_byte_count == 0 {
        return Err(library_partition_contract_error(format!(
            "{context} has empty source-byte summary for {source_file_count} source files; source-pack replay must carry concrete source-byte evidence before scheduling or linking"
        )));
    }
    if source_byte_count < source_file_count {
        return Err(library_partition_contract_error(format!(
            "{context} source-byte summary {source_byte_count} is smaller than source-file count {source_file_count}; source-pack replay must not treat empty source metadata as linkable package input"
        )));
    }
    Ok(())
}

/// Validates one sidecar page of library dependency IDs.
///
/// Dependency pages must be dense by page position and contain sorted, unique
/// dependency library IDs within the configured page size.
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
    let expected_first_position = checked_first_record_position(
        &format!(
            "library dependency page {expected_page_index} for partition {expected_partition_index}"
        ),
        expected_page_index,
        SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE,
    )?;
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
    validate_library_dependency_ids_strictly_ascending(
        &page.dependency_library_ids,
        &format!(
            "library dependency page {} for partition {}",
            page.page_index, page.partition_index
        ),
    )?;
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn library_dependency_pages_reject_overflowed_first_record_positions() {
        let target = SourcePackArtifactTarget::Generic;
        let page_index = usize::MAX;
        let dependency_page = SourcePackLibraryDependencyPage {
            version: SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION,
            target,
            partition_index: 1,
            page_index,
            first_dependency_position: usize::MAX,
            dependency_count: 1,
            dependency_library_ids: vec![0],
        };

        let err = validate_library_dependency_page(&dependency_page, target, 1, page_index)
            .expect_err("overflowed dependency page positions must be rejected");
        assert!(
            matches!(err, CompileError::GpuFrontend(_)),
            "unexpected dependency page validation error: {err}"
        );
    }

    #[test]
    fn library_partitions_reject_empty_source_byte_summaries() {
        let target = SourcePackArtifactTarget::Generic;
        let valid_index = SourcePackLibraryPartitionIndex {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_count: 1,
            source_file_count: 2,
            source_byte_count: 8,
            source_line_count: 0,
        };
        validate_library_partition_index(&valid_index, target)
            .expect("nonempty source-byte summary should validate");

        let empty_index = SourcePackLibraryPartitionIndex {
            source_byte_count: 0,
            ..valid_index.clone()
        };
        let err = validate_library_partition_index(&empty_index, target)
            .expect_err("partition indexes must carry source-byte evidence");
        let message = err.to_string();
        assert!(
            message.contains("partition index")
                && message.contains("empty source-byte summary")
                && message.contains("source-byte evidence"),
            "unexpected partition index source-byte error: {message}"
        );

        let short_index = SourcePackLibraryPartitionIndex {
            source_byte_count: 1,
            ..valid_index
        };
        let err = validate_library_partition_index(&short_index, target)
            .expect_err("partition indexes must not report fewer bytes than files");
        let message = err.to_string();
        assert!(
            message.contains("source-byte summary 1") && message.contains("source-file count 2"),
            "unexpected partition byte/file count error: {message}"
        );

        let valid_partition = SourcePackLibraryPartition {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_index: 0,
            library_id: 1,
            first_source_index: 0,
            source_file_count: 1,
            source_byte_count: 4,
            source_line_count: 0,
            dependency_library_ids: Vec::new(),
            dependency_library_count: 0,
            dependency_page_count: 0,
        };
        validate_library_partition(&valid_partition, target, Some(0))
            .expect("nonempty partition source-byte summary should validate");

        let empty_partition = SourcePackLibraryPartition {
            source_byte_count: 0,
            ..valid_partition
        };
        let err = validate_library_partition(&empty_partition, target, Some(0))
            .expect_err("library partitions must carry source-byte evidence");
        let message = err.to_string();
        assert!(
            message.contains("partition 0")
                && message.contains("empty source-byte summary")
                && message.contains("scheduling or linking"),
            "unexpected partition source-byte error: {message}"
        );
    }
}
