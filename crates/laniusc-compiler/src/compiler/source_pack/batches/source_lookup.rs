use super::*;

pub(in crate::compiler) fn stored_source_file_for_index(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    library_partition_index: &SourcePackLibraryPartitionIndex,
    source_index: usize,
    partition_cache: &mut BTreeMap<usize, SourcePackLibraryPartition>,
    page_cache: &mut BTreeMap<usize, SourcePackLibrarySourceFilePage>,
) -> Result<ExplicitSourcePathFile, CompileError> {
    let partition = library_partition_for_source_index_from_stored_pages(
        store,
        library_partition_index,
        target,
        source_index,
        partition_cache,
    )?;
    if !page_cache.contains_key(&partition.partition_index) {
        let page =
            store.load_library_source_file_page_for_target(target, partition.partition_index)?;
        validate_library_source_file_page(&page, target, Some(partition.partition_index))?;
        page_cache.insert(partition.partition_index, page);
    }
    let page = page_cache.get(&partition.partition_index).ok_or_else(|| {
        artifact_shard_contract_error(format!(
            "source file page {} was not cached",
            partition.partition_index
        ))
    })?;
    if page.source_files.is_empty() {
        let record = store.load_library_source_file_record_page_for_target(target, source_index)?;
        validate_library_source_file_record_page(&record, target, Some(source_index))?;
        if record.partition_index != partition.partition_index
            || record.library_id != partition.library_id
            || record.first_source_index != partition.first_source_index
            || record.source_file_count != partition.source_file_count
        {
            return Err(artifact_shard_contract_error(format!(
                "source-file record {} does not match partition {} metadata",
                source_index, partition.partition_index
            )));
        }
        return Ok(record.file);
    }
    page.source_files
        .iter()
        .find(|source_file| source_file.source_index == source_index)
        .map(|source_file| source_file.file.clone())
        .ok_or_else(|| {
            artifact_shard_contract_error(format!(
                "source file page {} does not contain source file {}",
                partition.partition_index, source_index
            ))
        })
}

pub(in crate::compiler) fn library_partition_for_source_index_from_stored_pages(
    store: &FilesystemArtifactStore,
    index: &SourcePackLibraryPartitionIndex,
    target: SourcePackArtifactTarget,
    source_index: usize,
    partition_cache: &mut BTreeMap<usize, SourcePackLibraryPartition>,
) -> Result<SourcePackLibraryPartition, CompileError> {
    validate_library_partition_index(index, target)?;
    if source_index >= index.source_file_count {
        return Err(artifact_shard_contract_error(format!(
            "source index {} exceeds partition index source file count {}",
            source_index, index.source_file_count
        )));
    }
    if let Some(partition) = partition_cache.values().find(|partition| {
        partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .is_some_and(|source_end| {
                partition.first_source_index <= source_index && source_index < source_end
            })
    }) {
        return Ok(partition.clone());
    }

    let mut low = 0usize;
    let mut high = index.partition_count;
    while low < high {
        let partition_index = low + (high - low) / 2;
        let partition = if let Some(partition) = partition_cache.get(&partition_index) {
            partition.clone()
        } else {
            let partition = store.load_library_partition_for_target(target, partition_index)?;
            partition_cache.insert(partition_index, partition.clone());
            partition
        };
        let source_end = partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        if source_index < partition.first_source_index {
            high = partition_index;
        } else if source_index >= source_end {
            low = partition_index + 1;
        } else {
            return Ok(partition);
        }
    }

    Err(artifact_shard_contract_error(format!(
        "source index {} is not covered by any persisted library partition",
        source_index
    )))
}
