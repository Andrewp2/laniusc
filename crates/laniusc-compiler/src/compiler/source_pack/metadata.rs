use super::*;

pub(in crate::compiler) fn prepare_metadata<I, PI, DI, P>(
    libraries: I,
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let step = prepare_metadata_chunk(
        libraries,
        store,
        target,
        Some(SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT),
    )?;
    if !step.complete {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack metadata prepare did not complete within {SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT} bounded library records; use prepare_metadata_chunk_for_target or the progress-based metadata chunk API to continue persisted preparation"
        )));
    }
    let library_partition_index_path = step.library_partition_index_path.ok_or_else(|| {
        library_partition_contract_error(
            "complete source-pack metadata prepare did not write a compact library partition index",
        )
    })?;
    Ok(FilesystemLibraryMetadataPrepareResult {
        target: step.target,
        source_file_count: step.source_file_count,
        source_byte_count: step.source_byte_count,
        source_line_count: step.source_line_count,
        library_count: step.library_count,
        library_partition_index_path,
        library_partition_count: step.library_partition_count,
        library_source_file_page_count: step.library_source_file_page_count,
    })
}

pub(in crate::compiler) fn prepare_metadata_chunk<I, PI, DI, P>(
    libraries: I,
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    max_new_libraries: Option<usize>,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if store
        .library_partition_index_path_for_target(target)
        .is_file()
    {
        let index = store.load_library_partition_index_for_target(target)?;
        return Ok(FilesystemLibraryMetadataPrepareStepResult {
            target,
            complete: true,
            source_file_count: index.source_file_count,
            source_byte_count: index.source_byte_count,
            source_line_count: index.source_line_count,
            library_count: index.partition_count,
            new_library_count: 0,
            library_partition_index_path: Some(
                store.library_partition_index_path_for_target(target),
            ),
            library_partition_count: index.partition_count,
            library_source_file_page_count: index.partition_count,
        });
    }
    let mut partition_count = 0usize;
    let mut source_file_count = 0usize;
    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    let mut library_source_file_page_count = 0usize;
    let mut new_library_count = 0usize;
    let mut complete = true;

    for library in libraries {
        let ExplicitSourceLibraryPathDependencyStream {
            library_id,
            paths,
            source_file_count: partition_source_file_count,
            dependency_library_count,
            dependency_library_ids: declared_dependency_library_ids,
        } = library;
        if partition_source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} has no source files"
            )));
        }
        if store
            .library_partition_locator_page_path_for_target(target, library_id)
            .is_file()
        {
            let locator =
                store.load_library_partition_locator_page_for_target(target, library_id)?;
            if locator.partition_index != partition_count {
                return Err(library_partition_contract_error(format!(
                    "cannot resume source-pack metadata from non-prefix library {library_id}: locator points to partition {} but next resumable partition is {partition_count}",
                    locator.partition_index
                )));
            }
            let partition =
                store.load_library_partition_for_target(target, locator.partition_index)?;
            if partition.library_id != library_id {
                return Err(library_partition_contract_error(format!(
                    "source-pack metadata locator for library {library_id} points to partition {} for library {}",
                    locator.partition_index, partition.library_id
                )));
            }
            if partition.source_file_count != partition_source_file_count {
                return Err(library_partition_contract_error(format!(
                    "source-pack metadata for library {library_id} stored {} source files but manifest declares {partition_source_file_count}",
                    partition.source_file_count
                )));
            }
            if partition.dependency_library_count != dependency_library_count {
                return Err(library_partition_contract_error(format!(
                    "source-pack metadata for library {library_id} stored {} dependencies but manifest declares {dependency_library_count}",
                    partition.dependency_library_count
                )));
            }
            verify_stored_dependency_ids(
                store,
                &partition,
                dependency_library_count,
                declared_dependency_library_ids,
            )?;
            source_byte_count = source_byte_count
                .checked_add(partition.source_byte_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "library {library_id} source byte count overflows while resuming metadata"
                    ))
                })?;
            source_line_count = source_line_count
                .checked_add(partition.source_line_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "library {library_id} source line count overflows while resuming metadata"
                    ))
                })?;
            source_file_count = source_file_count
                .checked_add(partition.source_file_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "library {library_id} global source file count overflows while resuming metadata"
                    ))
                })?;
            partition_count += 1;
            library_source_file_page_count += 1;
            continue;
        }
        if max_new_libraries.is_some_and(|limit| new_library_count >= limit) {
            complete = false;
            break;
        }
        if max_new_libraries.is_some() {
            validate_metadata_chunk_limits(
                library_id,
                partition_source_file_count,
                dependency_library_count,
            )?;
        }
        let (dependency_library_count, dependency_page_count) = store_partition_dependency_ids(
            store,
            target,
            partition_count,
            library_id,
            dependency_library_count,
            declared_dependency_library_ids,
        )?;

        let first_source_index = source_file_count;
        let partition_source_totals = store_source_file_records(
            store,
            target,
            partition_count,
            library_id,
            first_source_index,
            partition_source_file_count,
            paths,
        )?;
        let partition_source_byte_count = partition_source_totals.source_byte_count;
        let partition_source_line_count = partition_source_totals.source_line_count;
        source_byte_count = source_byte_count
            .checked_add(partition_source_byte_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source byte count overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(partition_source_line_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source line count overflows"
                ))
            })?;
        let partition = SourcePackLibraryPartition {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_index: partition_count,
            library_id,
            first_source_index,
            source_file_count: partition_source_file_count,
            source_byte_count: partition_source_byte_count,
            source_line_count: partition_source_line_count,
            dependency_library_ids: Vec::new(),
            dependency_library_count,
            dependency_page_count,
        };
        validate_library_partition(&partition, target, Some(partition.partition_index))?;
        store.store_library_partition_page(&partition)?;
        let compact_source_file_page = compact_source_file_page(&partition)?;
        store.store_library_source_file_page(&compact_source_file_page)?;
        store.store_library_partition_locator_page(&SourcePackLibraryPartitionLocatorPage {
            version: SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION,
            target,
            library_id: partition.library_id,
            partition_index: partition.partition_index,
        })?;
        source_file_count = source_file_count
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} global source file count overflows"
                ))
            })?;
        partition_count += 1;
        library_source_file_page_count += 1;
        new_library_count += 1;
    }

    if !complete {
        return Ok(FilesystemLibraryMetadataPrepareStepResult {
            target,
            complete: false,
            source_file_count,
            source_byte_count,
            source_line_count,
            library_count: partition_count,
            new_library_count,
            library_partition_index_path: None,
            library_partition_count: partition_count,
            library_source_file_page_count,
        });
    }

    let index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count,
        source_file_count,
        source_byte_count,
        source_line_count,
    };
    validate_library_partition_index(&index, target)?;
    let library_partition_index_path = store.store_library_partition_compact_index(&index)?;

    Ok(FilesystemLibraryMetadataPrepareStepResult {
        target,
        complete: true,
        source_file_count,
        source_byte_count,
        source_line_count,
        library_count: index.partition_count,
        new_library_count,
        library_partition_index_path: Some(library_partition_index_path),
        library_partition_count: index.partition_count,
        library_source_file_page_count,
    })
}

pub(in crate::compiler) fn empty_metadata_prepare_progress(
    target: SourcePackArtifactTarget,
) -> FilesystemLibraryMetadataPrepareProgress {
    FilesystemLibraryMetadataPrepareProgress {
        version: SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION,
        target,
        source_file_count: 0,
        source_byte_count: 0,
        source_line_count: 0,
        library_count: 0,
        library_partition_count: 0,
        library_source_file_page_count: 0,
    }
}

pub(in crate::compiler) fn load_metadata_prepare_progress_or_default(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
) -> Result<FilesystemLibraryMetadataPrepareProgress, CompileError> {
    if store
        .library_metadata_prepare_progress_path_for_target(target)
        .is_file()
    {
        store.load_library_metadata_prepare_progress_for_target(target)
    } else {
        Ok(empty_metadata_prepare_progress(target))
    }
}

pub(in crate::compiler) fn validate_metadata_chunk_limits(
    library_id: u32,
    source_file_count: usize,
    _dependency_library_count: usize,
) -> Result<(), CompileError> {
    if source_file_count > SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack metadata chunk library {library_id} declares {source_file_count} source files, exceeding chunk source-file cap {SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT}; split the library into bounded library records"
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn resume_metadata_chunk<I, PI, DI, P>(
    libraries: I,
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    max_new_libraries: usize,
    manifest_complete_after_input: bool,
) -> Result<FilesystemLibraryMetadataPrepareStepResult, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    if store
        .library_partition_index_path_for_target(target)
        .is_file()
    {
        let index = store.load_library_partition_index_for_target(target)?;
        return Ok(FilesystemLibraryMetadataPrepareStepResult {
            target,
            complete: true,
            source_file_count: index.source_file_count,
            source_byte_count: index.source_byte_count,
            source_line_count: index.source_line_count,
            library_count: index.partition_count,
            new_library_count: 0,
            library_partition_index_path: Some(
                store.library_partition_index_path_for_target(target),
            ),
            library_partition_count: index.partition_count,
            library_source_file_page_count: index.partition_count,
        });
    }

    let progress = load_metadata_prepare_progress_or_default(store, target)?;
    let mut partition_count = progress.library_partition_count;
    let mut source_file_count = progress.source_file_count;
    let mut source_byte_count = progress.source_byte_count;
    let mut source_line_count = progress.source_line_count;
    let mut library_source_file_page_count = progress.library_source_file_page_count;
    let mut new_library_count = 0usize;
    let mut complete = manifest_complete_after_input;

    for library in libraries {
        if new_library_count >= max_new_libraries {
            complete = false;
            break;
        }
        let ExplicitSourceLibraryPathDependencyStream {
            library_id,
            paths,
            source_file_count: partition_source_file_count,
            dependency_library_count,
            dependency_library_ids: declared_dependency_library_ids,
        } = library;
        if partition_source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} has no source files"
            )));
        }
        if store
            .library_partition_locator_page_path_for_target(target, library_id)
            .is_file()
        {
            return Err(library_partition_contract_error(format!(
                "resumable source-pack metadata stream started at already persisted library {library_id}; expected next partition {partition_count}"
            )));
        }
        validate_metadata_chunk_limits(
            library_id,
            partition_source_file_count,
            dependency_library_count,
        )?;

        let (dependency_library_count, dependency_page_count) = store_partition_dependency_ids(
            store,
            target,
            partition_count,
            library_id,
            dependency_library_count,
            declared_dependency_library_ids,
        )?;

        let first_source_index = source_file_count;
        let partition_source_totals = store_source_file_records(
            store,
            target,
            partition_count,
            library_id,
            first_source_index,
            partition_source_file_count,
            paths,
        )?;
        let partition_source_byte_count = partition_source_totals.source_byte_count;
        let partition_source_line_count = partition_source_totals.source_line_count;
        source_byte_count = source_byte_count
            .checked_add(partition_source_byte_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source byte count overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(partition_source_line_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} source line count overflows"
                ))
            })?;
        let partition = SourcePackLibraryPartition {
            version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
            target,
            partition_index: partition_count,
            library_id,
            first_source_index,
            source_file_count: partition_source_file_count,
            source_byte_count: partition_source_byte_count,
            source_line_count: partition_source_line_count,
            dependency_library_ids: Vec::new(),
            dependency_library_count,
            dependency_page_count,
        };
        validate_library_partition(&partition, target, Some(partition.partition_index))?;
        store.store_library_partition_page(&partition)?;
        let compact_source_file_page = compact_source_file_page(&partition)?;
        store.store_library_source_file_page(&compact_source_file_page)?;
        store.store_library_partition_locator_page(&SourcePackLibraryPartitionLocatorPage {
            version: SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION,
            target,
            library_id: partition.library_id,
            partition_index: partition.partition_index,
        })?;
        source_file_count = source_file_count
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} global source file count overflows"
                ))
            })?;
        partition_count += 1;
        library_source_file_page_count += 1;
        new_library_count += 1;
    }

    if !complete {
        let progress = FilesystemLibraryMetadataPrepareProgress {
            version: SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION,
            target,
            source_file_count,
            source_byte_count,
            source_line_count,
            library_count: partition_count,
            library_partition_count: partition_count,
            library_source_file_page_count,
        };
        store.store_library_metadata_prepare_progress(&progress)?;
        return Ok(FilesystemLibraryMetadataPrepareStepResult {
            target,
            complete: false,
            source_file_count,
            source_byte_count,
            source_line_count,
            library_count: partition_count,
            new_library_count,
            library_partition_index_path: None,
            library_partition_count: partition_count,
            library_source_file_page_count,
        });
    }

    let index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count,
        source_file_count,
        source_byte_count,
        source_line_count,
    };
    validate_library_partition_index(&index, target)?;
    let library_partition_index_path = store.store_library_partition_compact_index(&index)?;

    Ok(FilesystemLibraryMetadataPrepareStepResult {
        target,
        complete: true,
        source_file_count,
        source_byte_count,
        source_line_count,
        library_count: index.partition_count,
        new_library_count,
        library_partition_index_path: Some(library_partition_index_path),
        library_partition_count: index.partition_count,
        library_source_file_page_count,
    })
}

pub(in crate::compiler) fn verify_stored_dependency_ids<I>(
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    expected_dependency_library_count: usize,
    dependency_library_ids: I,
) -> Result<(), CompileError>
where
    I: IntoIterator<Item = u32>,
{
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;

    let stored_dependency_count = if partition.dependency_library_ids.is_empty() {
        partition.dependency_library_count
    } else {
        partition.dependency_library_ids.len()
    };
    if stored_dependency_count != expected_dependency_library_count {
        return Err(library_partition_contract_error(format!(
            "source-pack metadata for library {} stored {} dependencies but manifest declares {expected_dependency_library_count}",
            partition.library_id, stored_dependency_count
        )));
    }

    let mut expected_dependency_library_ids = dependency_library_ids.into_iter();
    let mut previous_expected_dependency_library_id = None;
    let mut dependency_position = 0usize;

    for &stored_dependency_library_id in &partition.dependency_library_ids {
        verify_next_stored_dependency_id(
            partition,
            &mut expected_dependency_library_ids,
            &mut previous_expected_dependency_library_id,
            dependency_position,
            stored_dependency_library_id,
        )?;
        dependency_position += 1;
    }

    for page_index in 0..partition.dependency_page_count {
        let dependency_page = store.load_library_dependency_page_for_target(
            partition.target,
            partition.partition_index,
            page_index,
        )?;
        if dependency_page.first_dependency_position != dependency_position {
            return Err(library_partition_contract_error(format!(
                "partition {} dependency page {} starts at {} but loaded {} dependencies",
                partition.partition_index,
                page_index,
                dependency_page.first_dependency_position,
                dependency_position
            )));
        }
        for stored_dependency_library_id in dependency_page.dependency_library_ids {
            verify_next_stored_dependency_id(
                partition,
                &mut expected_dependency_library_ids,
                &mut previous_expected_dependency_library_id,
                dependency_position,
                stored_dependency_library_id,
            )?;
            dependency_position += 1;
        }
    }

    if let Some(extra_dependency_library_id) = expected_dependency_library_ids.next() {
        return Err(library_partition_contract_error(format!(
            "source-pack metadata for library {} manifest declares extra dependency {} after {} stored dependencies",
            partition.library_id, extra_dependency_library_id, dependency_position
        )));
    }
    if dependency_position != expected_dependency_library_count {
        return Err(library_partition_contract_error(format!(
            "source-pack metadata for library {} loaded {} dependencies but manifest declares {expected_dependency_library_count}",
            partition.library_id, dependency_position
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn verify_next_stored_dependency_id<I>(
    partition: &SourcePackLibraryPartition,
    expected_dependency_library_ids: &mut I,
    previous_expected_dependency_library_id: &mut Option<u32>,
    dependency_position: usize,
    stored_dependency_library_id: u32,
) -> Result<(), CompileError>
where
    I: Iterator<Item = u32>,
{
    let expected_dependency_library_id = expected_dependency_library_ids.next().ok_or_else(|| {
        library_partition_contract_error(format!(
            "source-pack metadata for library {} stores dependency {} at position {} but manifest ended early",
            partition.library_id, stored_dependency_library_id, dependency_position
        ))
    })?;
    if expected_dependency_library_id == partition.library_id {
        return Err(CompileError::GpuFrontend(format!(
            "explicit source pack library {} depends on itself",
            partition.library_id
        )));
    }
    if previous_expected_dependency_library_id
        .as_ref()
        .is_some_and(|previous_dependency_library_id| {
            expected_dependency_library_id <= *previous_dependency_library_id
        })
    {
        return Err(CompileError::GpuFrontend(format!(
            "explicit source pack library {} dependency ids must be strictly sorted and unique",
            partition.library_id
        )));
    }
    if stored_dependency_library_id != expected_dependency_library_id {
        return Err(library_partition_contract_error(format!(
            "source-pack metadata for library {} stored dependency {} at position {} but manifest declares {}",
            partition.library_id,
            stored_dependency_library_id,
            dependency_position,
            expected_dependency_library_id
        )));
    }
    *previous_expected_dependency_library_id = Some(expected_dependency_library_id);
    Ok(())
}
