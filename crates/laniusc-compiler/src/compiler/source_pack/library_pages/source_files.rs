use super::super::*;

/// Builds the library partition plan implied by an explicit path manifest.
///
/// Source files must be grouped contiguously by library ID. Dependency records
/// are checked against the libraries that actually own files, then copied into
/// the partition records for later metadata storage.
pub(in crate::compiler) fn library_partition_plan(
    manifest: &ExplicitSourcePackPathManifest,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackLibraryPartitionPlan, CompileError> {
    if manifest.files.is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-pack library partition index has no source files".into(),
        ));
    }

    let file_library_ids = manifest
        .files
        .iter()
        .map(|file| file.library_id)
        .collect::<BTreeSet<_>>();
    let mut dependencies_by_library = BTreeMap::<u32, BTreeSet<u32>>::new();
    for dependency in &manifest.library_dependencies {
        if dependency.library_id == dependency.depends_on_library_id {
            return Err(library_partition_contract_error(format!(
                "library {} depends on itself",
                dependency.library_id
            )));
        }
        if !file_library_ids.contains(&dependency.library_id) {
            return Err(library_partition_contract_error(format!(
                "dependency references missing library {}",
                dependency.library_id
            )));
        }
        if !file_library_ids.contains(&dependency.depends_on_library_id) {
            return Err(library_partition_contract_error(format!(
                "dependency references missing library {}",
                dependency.depends_on_library_id
            )));
        }
        dependencies_by_library
            .entry(dependency.library_id)
            .or_default()
            .insert(dependency.depends_on_library_id);
    }

    let mut partitions = Vec::new();
    let mut seen_library_ids = BTreeSet::new();
    let mut first_source_index = 0usize;
    let source_byte_count = manifest
        .files
        .iter()
        .map(|file| file.byte_len)
        .sum::<usize>();
    let source_line_count = manifest
        .files
        .iter()
        .map(|file| file.line_count.unwrap_or(0))
        .sum::<usize>();

    while first_source_index < manifest.files.len() {
        let library_id = manifest.files[first_source_index].library_id;
        if !seen_library_ids.insert(library_id) {
            return Err(library_partition_contract_error(format!(
                "library {library_id} has non-contiguous source file partitions"
            )));
        }

        let mut source_file_count = 0usize;
        let mut partition_source_byte_count = 0usize;
        let mut partition_source_line_count = 0usize;
        for file in manifest.files[first_source_index..].iter() {
            if file.library_id != library_id {
                break;
            }
            source_file_count += 1;
            partition_source_byte_count += file.byte_len;
            partition_source_line_count += file.line_count.unwrap_or(0);
        }

        let dependency_library_ids = dependencies_by_library
            .get(&library_id)
            .map(|dependencies| dependencies.iter().copied().collect::<Vec<_>>())
            .unwrap_or_default();
        partitions.push(SourcePackLibraryPartition {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_index: partitions.len(),
            library_id,
            first_source_index,
            source_file_count,
            source_byte_count: partition_source_byte_count,
            source_line_count: partition_source_line_count,
            dependency_library_ids,
            dependency_library_count: 0,
            dependency_page_count: 0,
        });
        first_source_index += source_file_count;
    }

    let index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count: partitions.len(),
        source_file_count: manifest.files.len(),
        source_byte_count,
        source_line_count,
    };
    validate_library_partition_index(&index, target)?;
    let plan = SourcePackLibraryPartitionPlan { index, partitions };
    validate_library_partition_plan(&plan, target)?;
    Ok(plan)
}

/// Expands a partition plan into source-file pages for tests.
///
/// This test helper keeps the full file records inline on each page so callers
/// can validate the partition/source-file mapping without reading from the
/// filesystem store.
#[cfg(test)]
pub(in crate::compiler) fn library_source_file_pages(
    manifest: &ExplicitSourcePackPathManifest,
    plan: &SourcePackLibraryPartitionPlan,
) -> Result<Vec<SourcePackLibrarySourceFilePage>, CompileError> {
    let index = &plan.index;
    validate_library_partition_plan(plan, index.target)?;
    let mut pages = Vec::with_capacity(plan.partitions.len());

    for partition in &plan.partitions {
        let source_end = partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        if source_end > manifest.files.len() {
            return Err(library_partition_contract_error(format!(
                "partition {} source range {}..{} exceeds manifest source file count {}",
                partition.partition_index,
                partition.first_source_index,
                source_end,
                manifest.files.len()
            )));
        }

        let source_files = manifest.files[partition.first_source_index..source_end]
            .iter()
            .cloned()
            .enumerate()
            .map(|(offset, file)| SourcePackShardSourceFile {
                source_index: partition.first_source_index + offset,
                file,
            })
            .collect::<Vec<_>>();
        let page = SourcePackLibrarySourceFilePage {
            version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION,
            target: index.target,
            partition_index: partition.partition_index,
            library_id: partition.library_id,
            first_source_index: partition.first_source_index,
            source_file_count: partition.source_file_count,
            source_byte_count: partition.source_byte_count,
            source_line_count: partition.source_line_count,
            source_files,
        };
        validate_library_source_file_page(&page, index.target, Some(partition.partition_index))?;
        pages.push(page);
    }

    Ok(pages)
}

/// Checks that one source-file record belongs to its library partition.
///
/// The per-source record repeats partition metadata so execution shards can be
/// loaded by source index. This validator rejects records from a different
/// partition shape.
pub(in crate::compiler) fn validate_source_file_record_partition(
    partition: &SourcePackLibraryPartition,
    record: &SourcePackLibrarySourceFileRecordPage,
) -> Result<(), CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    validate_library_source_file_record_page(record, partition.target, Some(record.source_index))?;
    if record.partition_index != partition.partition_index
        || record.library_id != partition.library_id
        || record.first_source_index != partition.first_source_index
        || record.source_file_count != partition.source_file_count
    {
        return Err(library_partition_contract_error(format!(
            "source-file record {} metadata does not match partition {}",
            record.source_index, partition.partition_index
        )));
    }
    Ok(())
}

/// Checks that a compact source-file page summarizes its library partition.
///
/// Compact pages may omit inline source records, but their partition identity
/// and source totals must match the partition index page exactly.
pub(in crate::compiler) fn validate_source_file_page_partition(
    partition: &SourcePackLibraryPartition,
    page: &SourcePackLibrarySourceFilePage,
) -> Result<(), CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    validate_library_source_file_page(page, partition.target, Some(partition.partition_index))?;
    if page.partition_index != partition.partition_index
        || page.library_id != partition.library_id
        || page.first_source_index != partition.first_source_index
        || page.source_file_count != partition.source_file_count
        || page.source_byte_count != partition.source_byte_count
        || page.source_line_count != partition.source_line_count
    {
        return Err(library_partition_contract_error(format!(
            "source-file page {} metadata does not match partition {}",
            page.partition_index, partition.partition_index
        )));
    }
    Ok(())
}

/// Streams source-unit inputs from stored per-source records for a partition.
///
/// Each record is loaded by global source index and revalidated against the
/// partition before being converted into the compact codegen input shape.
pub(in crate::compiler) fn source_unit_inputs_from_records<'a>(
    store: &'a FilesystemArtifactStore,
    partition: &'a SourcePackLibraryPartition,
) -> impl Iterator<Item = Result<SourceFileUnitInput, CompileError>> + 'a {
    let source_end = partition
        .first_source_index
        .saturating_add(partition.source_file_count);
    (partition.first_source_index..source_end).map(move |source_index| {
        let record = store
            .load_library_source_file_record_page_for_target(partition.target, source_index)?;
        validate_source_file_record_partition(partition, &record)?;
        Ok(SourceFileUnitInput {
            library_id: record.file.library_id,
            source_index: record.source_index,
            byte_len: record.file.byte_len,
            line_count: record.file.line_count.unwrap_or(0),
        })
    })
}

/// Aggregate source totals produced while storing source-file records.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(in crate::compiler) struct SourceFileRecordTotals {
    /// Sum of source byte lengths for records written in the partition.
    pub(in crate::compiler) source_byte_count: usize,
    /// Sum of source line counts for records written in the partition.
    pub(in crate::compiler) source_line_count: usize,
}

/// Stores one per-source record page for every path in a library partition.
///
/// The function reads source metadata from each explicit path, writes records by
/// global source index, and returns the aggregate byte and line totals used by
/// the partition and source-file summary pages.
pub(in crate::compiler) fn store_source_file_records<I, P>(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    paths: I,
) -> Result<SourceFileRecordTotals, CompileError>
where
    I: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    if source_file_count == 0 {
        return Err(library_partition_contract_error(format!(
            "library {library_id} has no source files"
        )));
    }
    let label = format!("library {library_id}");
    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    let mut stored_source_file_count = 0usize;
    for (path_index, path) in paths.into_iter().enumerate() {
        if path_index >= source_file_count {
            return Err(library_partition_contract_error(format!(
                "library {library_id} yielded more than {source_file_count} source files"
            )));
        }
        let source_index = first_source_index.checked_add(path_index).ok_or_else(|| {
            library_partition_contract_error(format!(
                "library {library_id} source index overflows at path {path_index}"
            ))
        })?;
        let file =
            read_explicit_source_path_metadata(&label, path_index, library_id, path.as_ref())?;
        source_byte_count = source_byte_count
            .checked_add(file.byte_len)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source byte count overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source line count overflows"
                ))
            })?;
        let record = SourcePackLibrarySourceFileRecordPage {
            version: SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION,
            target,
            partition_index,
            library_id,
            first_source_index,
            source_file_count,
            source_index,
            file,
        };
        validate_library_source_file_record_page(&record, target, Some(source_index))?;
        store.store_library_source_file_record_page(&record)?;
        stored_source_file_count += 1;
    }
    if stored_source_file_count != source_file_count {
        return Err(library_partition_contract_error(format!(
            "library {library_id} stored {stored_source_file_count} source-file records but expected {source_file_count}"
        )));
    }
    Ok(SourceFileRecordTotals {
        source_byte_count,
        source_line_count,
    })
}

/// Builds a compact source-file summary page for a partition.
///
/// The returned page carries partition totals but no inline `source_files`
/// payload; individual source records remain in their per-source pages.
pub(in crate::compiler) fn compact_source_file_page(
    partition: &SourcePackLibraryPartition,
) -> Result<SourcePackLibrarySourceFilePage, CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    let page = SourcePackLibrarySourceFilePage {
        version: SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION,
        target: partition.target,
        partition_index: partition.partition_index,
        library_id: partition.library_id,
        first_source_index: partition.first_source_index,
        source_file_count: partition.source_file_count,
        source_byte_count: partition.source_byte_count,
        source_line_count: partition.source_line_count,
        source_files: Vec::new(),
    };
    validate_library_source_file_page(&page, partition.target, Some(partition.partition_index))?;
    Ok(page)
}
