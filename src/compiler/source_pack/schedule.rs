use super::*;

mod dependencies;
pub(in crate::compiler) use dependencies::*;

pub(in crate::compiler) fn prepare_schedule<I, PI, DI, P>(
    libraries: I,
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
) -> Result<PreparedLibrarySchedulePages, CompileError>
where
    I: IntoIterator<Item = ExplicitSourceLibraryPathDependencyStream<PI, DI>>,
    PI: IntoIterator<Item = P>,
    DI: IntoIterator<Item = u32>,
    P: AsRef<Path>,
{
    let mut partition_count = 0usize;
    let mut source_file_count = 0usize;
    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    let mut total_frontend_job_count = 0usize;
    let mut total_codegen_job_count = 0usize;
    let mut library_source_file_page_count = 0usize;
    let mut library_build_unit_page_count = 0usize;

    for library in libraries {
        let ExplicitSourceLibraryPathDependencyStream {
            library_id,
            source_file_count: partition_source_file_count,
            paths,
            dependency_library_count,
            dependency_library_ids: declared_dependency_library_ids,
        } = library;
        if partition_source_file_count == 0 {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} has no source files"
            )));
        }
        if store
            .library_frontend_job_locator_page_path_for_target(target, library_id)
            .is_file()
        {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} appears more than once"
            )));
        }
        let (dependency_library_count, dependency_page_count) = store_library_dependencies(
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
        let compact_build_unit_page = compact_build_unit_page(store, &partition, limits)?;
        store_frontend_unit_pages_from_source_records(&compact_build_unit_page, &partition, store)?;
        store_codegen_unit_pages_from_source_records(&compact_build_unit_page, &partition, store)?;
        let frontend_job_index = total_frontend_job_count;
        let frontend_job_count =
            library_build_unit_page_frontend_unit_count(&compact_build_unit_page);
        total_frontend_job_count = total_frontend_job_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule index frontend job range overflows at partition {}",
                    partition.partition_index
                ))
            })?;
        total_codegen_job_count = total_codegen_job_count
            .checked_add(library_build_unit_page_codegen_unit_count(
                &compact_build_unit_page,
            ))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule index codegen job range overflows at partition {}",
                    partition.partition_index
                ))
            })?;
        store.store_library_partition_page(&partition)?;
        let compact_source_file_page = compact_source_file_page(&partition)?;
        store.store_library_source_file_page(&compact_source_file_page)?;
        store.store_library_build_unit_page(&compact_build_unit_page)?;
        store.store_library_frontend_job_locator_page(
            &SourcePackLibraryFrontendJobLocatorPage {
                version: SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION,
                target,
                library_id: partition.library_id,
                partition_index: partition.partition_index,
                frontend_job_index,
                frontend_job_count,
            },
        )?;
        source_file_count = source_file_count
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "library {library_id} global source file count overflows"
                ))
            })?;
        partition_count += 1;
        library_source_file_page_count += 1;
        library_build_unit_page_count += 1;
    }

    let link_job_index = total_frontend_job_count
        .checked_add(total_codegen_job_count)
        .ok_or_else(|| {
            library_partition_contract_error("schedule index frontend/codegen job counts overflow")
        })?;
    let library_partition_index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count,
        source_file_count,
        source_byte_count,
        source_line_count,
    };
    validate_library_partition_index(&library_partition_index, target)?;
    let library_partition_index_path =
        store.store_library_partition_compact_index(&library_partition_index)?;

    let library_schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target,
        partition_count: library_partition_index.partition_count,
        frontend_job_count: total_frontend_job_count,
        codegen_job_count: total_codegen_job_count,
        link_job_index,
        job_count: link_job_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("schedule index job count overflows")
        })?,
    };
    validate_library_schedule_index(&library_schedule_index, target)?;
    let mut library_schedule_page_count = 0usize;
    let mut first_frontend_job_index = 0usize;
    let mut first_codegen_job_index =
        library_schedule_index_frontend_job_count(&library_schedule_index);
    for partition_index in 0..library_schedule_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        let build_unit_page =
            store.load_library_build_unit_page_for_target(target, partition_index)?;
        let entry = SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: build_unit_page.library_id,
            first_frontend_job_index,
            frontend_job_count: library_build_unit_page_frontend_unit_count(&build_unit_page),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: library_build_unit_page_codegen_unit_count(&build_unit_page),
        };
        let page = prepare_partition_schedule_page(
            store,
            &partition,
            &build_unit_page,
            &entry,
            &library_schedule_index,
        )?;
        store.store_library_schedule_page(&page)?;
        first_frontend_job_index = first_frontend_job_index
            .checked_add(entry.frontend_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        library_schedule_page_count += 1;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "stored schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    let library_schedule_index_path =
        store.store_library_schedule_index(&library_schedule_index)?;

    Ok(PreparedLibrarySchedulePages {
        library_partition_index,
        library_partition_index_path,
        library_source_file_page_count,
        library_build_unit_page_count,
        library_schedule_index,
        library_schedule_index_path,
        library_schedule_page_count,
    })
}

#[cfg(test)]
pub(in crate::compiler) fn prepare_schedule_from_metadata(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
) -> Result<PreparedLibrarySchedulePages, CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    validate_library_partition_index(&library_partition_index, target)?;
    let library_partition_index_path = store.library_partition_index_path_for_target(target);
    let mut total_frontend_job_count = 0usize;
    let mut total_codegen_job_count = 0usize;
    let mut library_build_unit_page_count = 0usize;

    for partition_index in 0..library_partition_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        validate_library_partition(&partition, target, Some(partition_index))?;
        let source_file_page =
            store.load_library_source_file_page_for_target(target, partition_index)?;
        validate_source_file_page_partition(&partition, &source_file_page)?;
        let compact_build_unit_page = compact_build_unit_page(store, &partition, limits)?;
        store_frontend_unit_pages_from_source_records(&compact_build_unit_page, &partition, store)?;
        store_codegen_unit_pages_from_source_records(&compact_build_unit_page, &partition, store)?;
        let frontend_job_index = total_frontend_job_count;
        let frontend_job_count =
            library_build_unit_page_frontend_unit_count(&compact_build_unit_page);
        total_frontend_job_count = total_frontend_job_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule frontend job range overflows at partition {partition_index}"
                ))
            })?;
        total_codegen_job_count = total_codegen_job_count
            .checked_add(library_build_unit_page_codegen_unit_count(
                &compact_build_unit_page,
            ))
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule codegen job range overflows at partition {partition_index}"
                ))
            })?;
        store.store_library_build_unit_page(&compact_build_unit_page)?;
        store.store_library_frontend_job_locator_page(
            &SourcePackLibraryFrontendJobLocatorPage {
                version: SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION,
                target,
                library_id: partition.library_id,
                partition_index: partition.partition_index,
                frontend_job_index,
                frontend_job_count,
            },
        )?;
        library_build_unit_page_count += 1;
    }

    let link_job_index = total_frontend_job_count
        .checked_add(total_codegen_job_count)
        .ok_or_else(|| {
            library_partition_contract_error(
                "stored metadata schedule frontend/codegen job counts overflow",
            )
        })?;
    let library_schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target,
        partition_count: library_partition_index.partition_count,
        frontend_job_count: total_frontend_job_count,
        codegen_job_count: total_codegen_job_count,
        link_job_index,
        job_count: link_job_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("stored metadata schedule job count overflows")
        })?,
    };
    validate_library_schedule_index(&library_schedule_index, target)?;
    let mut library_schedule_page_count = 0usize;
    let mut first_frontend_job_index = 0usize;
    let mut first_codegen_job_index =
        library_schedule_index_frontend_job_count(&library_schedule_index);
    for partition_index in 0..library_schedule_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        let build_unit_page =
            store.load_library_build_unit_page_for_target(target, partition_index)?;
        let entry = SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: build_unit_page.library_id,
            first_frontend_job_index,
            frontend_job_count: library_build_unit_page_frontend_unit_count(&build_unit_page),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: library_build_unit_page_codegen_unit_count(&build_unit_page),
        };
        let page = prepare_partition_schedule_page(
            store,
            &partition,
            &build_unit_page,
            &entry,
            &library_schedule_index,
        )?;
        store.store_library_schedule_page(&page)?;
        first_frontend_job_index = first_frontend_job_index
            .checked_add(entry.frontend_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        library_schedule_page_count += 1;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "stored metadata schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    let library_schedule_index_path =
        store.store_library_schedule_index(&library_schedule_index)?;

    Ok(PreparedLibrarySchedulePages {
        library_partition_index,
        library_partition_index_path,
        library_source_file_page_count: library_schedule_index.partition_count,
        library_build_unit_page_count,
        library_schedule_index,
        library_schedule_index_path,
        library_schedule_page_count,
    })
}

pub(in crate::compiler) fn prepare_schedule_chunk_from_metadata(
    store: &FilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
    max_new_libraries: usize,
) -> Result<FilesystemLibrarySchedulePrepareStepResult, CompileError> {
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack schedule chunk max_new_libraries must be greater than zero".into(),
        ));
    }
    let limits = limits.normalized();
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    validate_library_partition_index(&library_partition_index, target)?;
    let library_partition_count = library_partition_index.partition_count;
    let source_file_count = library_partition_index.source_file_count;
    let source_byte_count = library_partition_index.source_byte_count;
    let source_line_count = library_partition_index.source_line_count;

    let mut progress = if store
        .library_schedule_prepare_progress_path_for_target(target)
        .is_file()
    {
        store.load_library_schedule_prepare_progress_for_target(target)?
    } else {
        FilesystemLibrarySchedulePrepareProgress {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION,
            target,
            phase: FilesystemLibrarySchedulePreparePhase::BuildUnitPages,
            next_partition_index: 0,
            source_file_count,
            source_byte_count,
            source_line_count,
            library_count: library_partition_count,
            library_partition_count,
            library_source_file_page_count: library_partition_count,
            library_build_unit_page_count: 0,
            library_schedule_page_count: 0,
            frontend_job_count: 0,
            codegen_job_count: 0,
            next_frontend_job_index: 0,
            next_codegen_job_index: 0,
        }
    };
    validate_library_schedule_prepare_progress(&progress, target)?;

    if progress.phase == FilesystemLibrarySchedulePreparePhase::Complete {
        let schedule_index = store.load_library_schedule_index_for_target(target)?;
        return Ok(FilesystemLibrarySchedulePrepareStepResult {
            target,
            complete: true,
            source_file_count,
            source_byte_count,
            source_line_count,
            library_count: library_partition_count,
            library_partition_count,
            library_source_file_page_count: library_partition_count,
            library_build_unit_page_count: library_partition_count,
            new_library_build_unit_page_count: 0,
            library_schedule_index_path: Some(store.library_schedule_index_path_for_target(target)),
            library_schedule_page_count: library_partition_count,
            new_library_schedule_page_count: 0,
            frontend_job_count: schedule_index.frontend_job_count,
            codegen_job_count: schedule_index.codegen_job_count,
            scheduled_job_count: schedule_index.job_count,
        });
    }

    let mut new_library_build_unit_page_count = 0usize;
    let mut new_library_schedule_page_count = 0usize;

    if progress.phase == FilesystemLibrarySchedulePreparePhase::BuildUnitPages {
        for partition_index in progress.next_partition_index..library_partition_count {
            let partition = store.load_library_partition_for_target(target, partition_index)?;
            validate_library_partition(&partition, target, Some(partition_index))?;
            let build_unit_page_path =
                store.library_build_unit_page_path_for_target(target, partition_index);
            let build_unit_page = if build_unit_page_path.is_file() {
                store.load_library_build_unit_page_for_target(target, partition_index)?
            } else {
                if new_library_build_unit_page_count >= max_new_libraries {
                    store.store_library_schedule_prepare_progress(&progress)?;
                    return Ok(FilesystemLibrarySchedulePrepareStepResult {
                        target,
                        complete: false,
                        source_file_count,
                        source_byte_count,
                        source_line_count,
                        library_count: library_partition_count,
                        library_partition_count,
                        library_source_file_page_count: library_partition_count,
                        library_build_unit_page_count: progress.library_build_unit_page_count,
                        new_library_build_unit_page_count,
                        library_schedule_index_path: None,
                        library_schedule_page_count: 0,
                        new_library_schedule_page_count,
                        frontend_job_count: progress.frontend_job_count,
                        codegen_job_count: progress.codegen_job_count,
                        scheduled_job_count: 0,
                    });
                }
                let source_file_page =
                    store.load_library_source_file_page_for_target(target, partition_index)?;
                validate_source_file_page_partition(&partition, &source_file_page)?;
                let build_unit_page = compact_build_unit_page(store, &partition, limits)?;
                store_frontend_unit_pages_from_source_records(&build_unit_page, &partition, store)?;
                store_codegen_unit_pages_from_source_records(&build_unit_page, &partition, store)?;
                store.store_library_build_unit_page(&build_unit_page)?;
                new_library_build_unit_page_count += 1;
                build_unit_page
            };
            validate_build_unit_partition(&build_unit_page, &partition, limits)?;
            let frontend_job_index = progress.frontend_job_count;
            let frontend_job_count = library_build_unit_page_frontend_unit_count(&build_unit_page);
            progress.frontend_job_count = progress
                .frontend_job_count
                .checked_add(frontend_job_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "stored metadata schedule frontend job range overflows at partition {partition_index}"
                    ))
                })?;
            progress.codegen_job_count = progress
                .codegen_job_count
                .checked_add(library_build_unit_page_codegen_unit_count(
                    &build_unit_page,
                ))
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "stored metadata schedule codegen job range overflows at partition {partition_index}"
                    ))
                })?;
            store.store_library_frontend_job_locator_page(
                &SourcePackLibraryFrontendJobLocatorPage {
                    version: SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION,
                    target,
                    library_id: partition.library_id,
                    partition_index: partition.partition_index,
                    frontend_job_index,
                    frontend_job_count,
                },
            )?;
            progress.library_build_unit_page_count += 1;
            progress.next_partition_index = partition_index + 1;
        }
        progress.phase = FilesystemLibrarySchedulePreparePhase::SchedulePages;
        progress.next_partition_index = 0;
        progress.library_schedule_page_count = 0;
        progress.next_frontend_job_index = 0;
        progress.next_codegen_job_index = progress.frontend_job_count;
        store.store_library_schedule_prepare_progress(&progress)?;
    }

    let link_job_index = progress
        .frontend_job_count
        .checked_add(progress.codegen_job_count)
        .ok_or_else(|| {
            library_partition_contract_error(
                "stored metadata schedule frontend/codegen job counts overflow",
            )
        })?;
    let library_schedule_index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target,
        partition_count: library_partition_index.partition_count,
        frontend_job_count: progress.frontend_job_count,
        codegen_job_count: progress.codegen_job_count,
        link_job_index,
        job_count: link_job_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error("stored metadata schedule job count overflows")
        })?,
    };
    validate_library_schedule_index(&library_schedule_index, target)?;
    let library_schedule_index_path = if store
        .library_schedule_index_path_for_target(target)
        .is_file()
    {
        let stored_index = store.load_library_schedule_index_for_target(target)?;
        if stored_index != library_schedule_index {
            return Err(library_partition_contract_error(
                "stored source-pack library schedule index does not match metadata-derived build-unit pages",
            ));
        }
        store.library_schedule_index_path_for_target(target)
    } else {
        store.store_library_schedule_index(&library_schedule_index)?
    };

    let mut first_frontend_job_index = progress.next_frontend_job_index;
    let mut first_codegen_job_index = progress.next_codegen_job_index;
    for partition_index in progress.next_partition_index..library_schedule_index.partition_count {
        let build_unit_page =
            store.load_library_build_unit_page_for_target(target, partition_index)?;
        let entry = SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: build_unit_page.library_id,
            first_frontend_job_index,
            frontend_job_count: library_build_unit_page_frontend_unit_count(&build_unit_page),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: library_build_unit_page_codegen_unit_count(&build_unit_page),
        };
        if store
            .library_schedule_page_path_for_target(target, partition_index)
            .is_file()
        {
            let page = store.load_library_schedule_page_for_target(target, partition_index)?;
            validate_schedule_entry_page(&page, &entry)?;
        } else {
            if new_library_build_unit_page_count + new_library_schedule_page_count
                >= max_new_libraries
            {
                store.store_library_schedule_prepare_progress(&progress)?;
                return Ok(FilesystemLibrarySchedulePrepareStepResult {
                    target,
                    complete: false,
                    source_file_count,
                    source_byte_count,
                    source_line_count,
                    library_count: library_partition_count,
                    library_partition_count,
                    library_source_file_page_count: library_partition_count,
                    library_build_unit_page_count: progress.library_build_unit_page_count,
                    new_library_build_unit_page_count,
                    library_schedule_index_path: Some(library_schedule_index_path),
                    library_schedule_page_count: progress.library_schedule_page_count,
                    new_library_schedule_page_count,
                    frontend_job_count: library_schedule_index.frontend_job_count,
                    codegen_job_count: library_schedule_index.codegen_job_count,
                    scheduled_job_count: library_schedule_index.job_count,
                });
            }
            let partition = store.load_library_partition_for_target(target, partition_index)?;
            let page = prepare_partition_schedule_page(
                store,
                &partition,
                &build_unit_page,
                &entry,
                &library_schedule_index,
            )?;
            store.store_library_schedule_page(&page)?;
            new_library_schedule_page_count += 1;
        }
        first_frontend_job_index = first_frontend_job_index
            .checked_add(entry.frontend_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "stored metadata schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        progress.library_schedule_page_count += 1;
        progress.next_partition_index = partition_index + 1;
        progress.next_frontend_job_index = first_frontend_job_index;
        progress.next_codegen_job_index = first_codegen_job_index;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "stored metadata schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    progress.phase = FilesystemLibrarySchedulePreparePhase::Complete;
    progress.next_partition_index = library_partition_count;
    progress.library_schedule_page_count = library_partition_count;
    store.store_library_schedule_prepare_progress(&progress)?;

    Ok(FilesystemLibrarySchedulePrepareStepResult {
        target,
        complete: true,
        source_file_count,
        source_byte_count,
        source_line_count,
        library_count: library_partition_count,
        library_partition_count,
        library_source_file_page_count: library_partition_count,
        library_build_unit_page_count: progress.library_build_unit_page_count,
        new_library_build_unit_page_count,
        library_schedule_index_path: Some(library_schedule_index_path),
        library_schedule_page_count: progress.library_schedule_page_count,
        new_library_schedule_page_count,
        frontend_job_count: library_schedule_index.frontend_job_count,
        codegen_job_count: library_schedule_index.codegen_job_count,
        scheduled_job_count: library_schedule_index.job_count,
    })
}

pub(in crate::compiler) fn validate_build_unit_partition(
    page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<(), CompileError> {
    validate_library_build_unit_page(page, partition.target, Some(partition.partition_index))?;
    if page.library_id != partition.library_id
        || page.first_source_index != partition.first_source_index
        || page.source_file_count != partition.source_file_count
        || page.source_byte_count != partition.source_byte_count
        || page.source_line_count != partition.source_line_count
        || page.limits != limits.normalized()
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} does not match stored metadata partition",
            partition.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn validate_schedule_entry_page(
    page: &SourcePackLibrarySchedulePage,
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> Result<(), CompileError> {
    validate_library_schedule_page(page, page.target, Some(entry.partition_index))?;
    if page.library_id != entry.library_id
        || page.frontend_job_index != entry.frontend_job_index
        || library_schedule_page_frontend_job_count(page)
            != library_schedule_entry_frontend_job_count(entry)
        || page.first_codegen_job_index != entry.first_codegen_job_index
        || page.codegen_job_count != entry.codegen_job_count
    {
        return Err(library_partition_contract_error(format!(
            "schedule page {} does not match metadata-derived schedule entry",
            entry.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_codegen_job_locator(
    store: &FilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
    partition_index: usize,
    codegen_job_offset: usize,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    validate_library_schedule_index(index, index.target)?;
    if job.phase != SourcePackJobPhase::Codegen {
        return Err(library_partition_contract_error(format!(
            "schedule job {} has phase {:?}, expected codegen",
            job.job_index, job.phase
        )));
    }
    if job.job_index >= index.job_count {
        return Err(library_partition_contract_error(format!(
            "schedule codegen job {} exceeds job count {}",
            job.job_index, index.job_count
        )));
    }
    let frontend_job_count = library_schedule_index_frontend_job_count(index);
    if job.job_index < frontend_job_count || job.job_index >= index.link_job_index {
        return Err(library_partition_contract_error(format!(
            "schedule codegen job {} is outside codegen job range {}..{}",
            job.job_index, frontend_job_count, index.link_job_index
        )));
    }
    let Some(frontend_job_index) = job.library_job_index else {
        return Err(library_partition_contract_error(format!(
            "schedule codegen job {} has no owning frontend job",
            job.job_index
        )));
    };
    if frontend_job_index >= frontend_job_count {
        return Err(library_partition_contract_error(format!(
            "schedule codegen job {} owner {} is outside frontend job range 0..{}",
            job.job_index, frontend_job_index, frontend_job_count
        )));
    }
    let locator = SourcePackLibraryScheduleJobLocatorPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
        target: index.target,
        job_index: job.job_index,
        phase: SourcePackJobPhase::Codegen,
        partition_index: Some(partition_index),
        codegen_job_offset: Some(codegen_job_offset),
    };
    store.store_library_schedule_job_locator_page(&locator, index.job_count)?;
    Ok(())
}

pub(in crate::compiler) fn store_link_job_locator(
    store: &FilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
) -> Result<(), CompileError> {
    validate_library_schedule_index(index, index.target)?;
    let locator = SourcePackLibraryScheduleJobLocatorPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
        target: index.target,
        job_index: index.link_job_index,
        phase: SourcePackJobPhase::Link,
        partition_index: None,
        codegen_job_offset: None,
    };
    store.store_library_schedule_job_locator_page(&locator, index.job_count)?;
    let job = link_schedule_job(index);
    store_schedule_job_page(store, index, &job)?;
    Ok(())
}

pub(in crate::compiler) fn store_schedule_job_page(
    store: &FilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    validate_library_schedule_index(index, index.target)?;
    let page = SourcePackLibraryScheduleJobPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
        target: index.target,
        job_index: job.job_index,
        job: job.clone(),
        dependency_job_count: 0,
        dependency_page_count: 0,
        dependency_job_ranges: Vec::new(),
    };
    store.store_library_schedule_job_page(&page, index.job_count)?;
    Ok(())
}

pub(in crate::compiler) fn link_schedule_job(
    index: &SourcePackLibraryScheduleIndex,
) -> SourcePackJob {
    SourcePackJob {
        job_index: index.link_job_index,
        phase: SourcePackJobPhase::Link,
        phase_unit_index: 0,
        library_job_index: None,
        library_id: u32::MAX,
        first_source_index: 0,
        source_file_count: 0,
        source_bytes: 0,
        source_lines: 0,
        oversized_source_file: false,
        dependency_job_indices: Vec::new(),
    }
}
