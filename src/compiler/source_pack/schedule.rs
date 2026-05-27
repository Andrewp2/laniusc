use super::*;

pub(in crate::compiler) fn prepare_library_schedule_pages<I, PI, DI, P>(
    libraries: I,
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
) -> Result<SourcePackPreparedLibrarySchedulePages, CompileError>
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
        let (dependency_library_count, dependency_page_count) =
            store_source_pack_library_dependency_pages_from_ids(
                store,
                target,
                partition_count,
                library_id,
                dependency_library_count,
                declared_dependency_library_ids,
            )?;

        let first_source_index = source_file_count;
        let partition_source_totals =
            store_source_pack_library_source_file_record_pages_from_paths(
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
                source_pack_library_partition_contract_error(format!(
                    "library {library_id} source byte count overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(partition_source_line_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
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
        validate_source_pack_library_partition(
            &partition,
            target,
            Some(partition.partition_index),
        )?;
        let compact_build_unit_page =
            source_pack_compact_library_build_unit_page_from_stored_source_file_records(
                store, &partition, limits,
            )?;
        store_source_pack_library_frontend_unit_pages_from_stored_source_file_records(
            &compact_build_unit_page,
            &partition,
            store,
        )?;
        store_source_pack_library_codegen_unit_pages_from_stored_source_file_records(
            &compact_build_unit_page,
            &partition,
            store,
        )?;
        let frontend_job_index = total_frontend_job_count;
        let frontend_job_count =
            source_pack_library_build_unit_page_frontend_unit_count(&compact_build_unit_page);
        total_frontend_job_count = total_frontend_job_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule index frontend job range overflows at partition {}",
                    partition.partition_index
                ))
            })?;
        total_codegen_job_count = total_codegen_job_count
            .checked_add(source_pack_library_build_unit_page_codegen_unit_count(
                &compact_build_unit_page,
            ))
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule index codegen job range overflows at partition {}",
                    partition.partition_index
                ))
            })?;
        store.store_library_partition_page(&partition)?;
        let compact_source_file_page =
            source_pack_compact_library_source_file_page_from_partition(&partition)?;
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
                source_pack_library_partition_contract_error(format!(
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
            source_pack_library_partition_contract_error(
                "schedule index frontend/codegen job counts overflow",
            )
        })?;
    let library_partition_index = SourcePackLibraryPartitionIndex {
        version: SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
        target,
        partition_count,
        source_file_count,
        source_byte_count,
        source_line_count,
    };
    validate_source_pack_library_partition_index(&library_partition_index, target)?;
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
            source_pack_library_partition_contract_error("schedule index job count overflows")
        })?,
    };
    validate_source_pack_library_schedule_index(&library_schedule_index, target)?;
    let mut library_schedule_page_count = 0usize;
    let mut first_frontend_job_index = 0usize;
    let mut first_codegen_job_index =
        source_pack_library_schedule_index_frontend_job_count(&library_schedule_index);
    for partition_index in 0..library_schedule_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        let build_unit_page =
            store.load_library_build_unit_page_for_target(target, partition_index)?;
        let entry = SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: build_unit_page.library_id,
            first_frontend_job_index,
            frontend_job_count: source_pack_library_build_unit_page_frontend_unit_count(
                &build_unit_page,
            ),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: source_pack_library_build_unit_page_codegen_unit_count(
                &build_unit_page,
            ),
        };
        let page = source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies(
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
                source_pack_library_partition_contract_error(format!(
                    "schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        library_schedule_page_count += 1;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_source_pack_library_schedule_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    let library_schedule_index_path =
        store.store_library_schedule_index(&library_schedule_index)?;

    Ok(SourcePackPreparedLibrarySchedulePages {
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
pub(in crate::compiler) fn prepare_library_schedule_pages_from_metadata(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
) -> Result<SourcePackPreparedLibrarySchedulePages, CompileError> {
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    validate_source_pack_library_partition_index(&library_partition_index, target)?;
    let library_partition_index_path = store.library_partition_index_path_for_target(target);
    let mut total_frontend_job_count = 0usize;
    let mut total_codegen_job_count = 0usize;
    let mut library_build_unit_page_count = 0usize;

    for partition_index in 0..library_partition_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        validate_source_pack_library_partition(&partition, target, Some(partition_index))?;
        let source_file_page =
            store.load_library_source_file_page_for_target(target, partition_index)?;
        source_pack_validate_source_file_page_matches_partition(&partition, &source_file_page)?;
        let compact_build_unit_page =
            source_pack_compact_library_build_unit_page_from_stored_source_file_records(
                store, &partition, limits,
            )?;
        store_source_pack_library_frontend_unit_pages_from_stored_source_file_records(
            &compact_build_unit_page,
            &partition,
            store,
        )?;
        store_source_pack_library_codegen_unit_pages_from_stored_source_file_records(
            &compact_build_unit_page,
            &partition,
            store,
        )?;
        let frontend_job_index = total_frontend_job_count;
        let frontend_job_count =
            source_pack_library_build_unit_page_frontend_unit_count(&compact_build_unit_page);
        total_frontend_job_count = total_frontend_job_count
            .checked_add(frontend_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "stored metadata schedule frontend job range overflows at partition {partition_index}"
                ))
            })?;
        total_codegen_job_count = total_codegen_job_count
            .checked_add(source_pack_library_build_unit_page_codegen_unit_count(
                &compact_build_unit_page,
            ))
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
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
            source_pack_library_partition_contract_error(
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
            source_pack_library_partition_contract_error(
                "stored metadata schedule job count overflows",
            )
        })?,
    };
    validate_source_pack_library_schedule_index(&library_schedule_index, target)?;
    let mut library_schedule_page_count = 0usize;
    let mut first_frontend_job_index = 0usize;
    let mut first_codegen_job_index =
        source_pack_library_schedule_index_frontend_job_count(&library_schedule_index);
    for partition_index in 0..library_schedule_index.partition_count {
        let partition = store.load_library_partition_for_target(target, partition_index)?;
        let build_unit_page =
            store.load_library_build_unit_page_for_target(target, partition_index)?;
        let entry = SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: build_unit_page.library_id,
            first_frontend_job_index,
            frontend_job_count: source_pack_library_build_unit_page_frontend_unit_count(
                &build_unit_page,
            ),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: source_pack_library_build_unit_page_codegen_unit_count(
                &build_unit_page,
            ),
        };
        let page = source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies(
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
                source_pack_library_partition_contract_error(format!(
                    "stored metadata schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "stored metadata schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        library_schedule_page_count += 1;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored metadata schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_source_pack_library_schedule_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    let library_schedule_index_path =
        store.store_library_schedule_index(&library_schedule_index)?;

    Ok(SourcePackPreparedLibrarySchedulePages {
        library_partition_index,
        library_partition_index_path,
        library_source_file_page_count: library_schedule_index.partition_count,
        library_build_unit_page_count,
        library_schedule_index,
        library_schedule_index_path,
        library_schedule_page_count,
    })
}

pub(in crate::compiler) fn prepare_library_schedule_pages_from_metadata_chunk(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    limits: CodegenUnitLimits,
    max_new_libraries: usize,
) -> Result<SourcePackFilesystemLibrarySchedulePrepareStepResult, CompileError> {
    if max_new_libraries == 0 {
        return Err(CompileError::GpuFrontend(
            "source-pack schedule chunk max_new_libraries must be greater than zero".into(),
        ));
    }
    let limits = limits.normalized();
    let library_partition_index = store.load_library_partition_index_for_target(target)?;
    validate_source_pack_library_partition_index(&library_partition_index, target)?;
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
        SourcePackFilesystemLibrarySchedulePrepareProgress {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION,
            target,
            phase: SourcePackFilesystemLibrarySchedulePreparePhase::BuildUnitPages,
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
    validate_source_pack_library_schedule_prepare_progress(&progress, target)?;

    if progress.phase == SourcePackFilesystemLibrarySchedulePreparePhase::Complete {
        let schedule_index = store.load_library_schedule_index_for_target(target)?;
        return Ok(SourcePackFilesystemLibrarySchedulePrepareStepResult {
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

    if progress.phase == SourcePackFilesystemLibrarySchedulePreparePhase::BuildUnitPages {
        for partition_index in progress.next_partition_index..library_partition_count {
            let partition = store.load_library_partition_for_target(target, partition_index)?;
            validate_source_pack_library_partition(&partition, target, Some(partition_index))?;
            let build_unit_page_path =
                store.library_build_unit_page_path_for_target(target, partition_index);
            let build_unit_page = if build_unit_page_path.is_file() {
                store.load_library_build_unit_page_for_target(target, partition_index)?
            } else {
                if new_library_build_unit_page_count >= max_new_libraries {
                    store.store_library_schedule_prepare_progress(&progress)?;
                    return Ok(SourcePackFilesystemLibrarySchedulePrepareStepResult {
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
                source_pack_validate_source_file_page_matches_partition(
                    &partition,
                    &source_file_page,
                )?;
                let build_unit_page =
                    source_pack_compact_library_build_unit_page_from_stored_source_file_records(
                        store, &partition, limits,
                    )?;
                store_source_pack_library_frontend_unit_pages_from_stored_source_file_records(
                    &build_unit_page,
                    &partition,
                    store,
                )?;
                store_source_pack_library_codegen_unit_pages_from_stored_source_file_records(
                    &build_unit_page,
                    &partition,
                    store,
                )?;
                store.store_library_build_unit_page(&build_unit_page)?;
                new_library_build_unit_page_count += 1;
                build_unit_page
            };
            source_pack_validate_build_unit_page_matches_partition(
                &build_unit_page,
                &partition,
                limits,
            )?;
            let frontend_job_index = progress.frontend_job_count;
            let frontend_job_count =
                source_pack_library_build_unit_page_frontend_unit_count(&build_unit_page);
            progress.frontend_job_count = progress
                .frontend_job_count
                .checked_add(frontend_job_count)
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "stored metadata schedule frontend job range overflows at partition {partition_index}"
                    ))
                })?;
            progress.codegen_job_count = progress
                .codegen_job_count
                .checked_add(source_pack_library_build_unit_page_codegen_unit_count(
                    &build_unit_page,
                ))
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
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
        progress.phase = SourcePackFilesystemLibrarySchedulePreparePhase::SchedulePages;
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
            source_pack_library_partition_contract_error(
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
            source_pack_library_partition_contract_error(
                "stored metadata schedule job count overflows",
            )
        })?,
    };
    validate_source_pack_library_schedule_index(&library_schedule_index, target)?;
    let library_schedule_index_path = if store
        .library_schedule_index_path_for_target(target)
        .is_file()
    {
        let stored_index = store.load_library_schedule_index_for_target(target)?;
        if stored_index != library_schedule_index {
            return Err(source_pack_library_partition_contract_error(
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
            frontend_job_count: source_pack_library_build_unit_page_frontend_unit_count(
                &build_unit_page,
            ),
            frontend_job_index: first_frontend_job_index,
            first_codegen_job_index,
            codegen_job_count: source_pack_library_build_unit_page_codegen_unit_count(
                &build_unit_page,
            ),
        };
        if store
            .library_schedule_page_path_for_target(target, partition_index)
            .is_file()
        {
            let page = store.load_library_schedule_page_for_target(target, partition_index)?;
            source_pack_validate_schedule_page_matches_entry(&page, &entry)?;
        } else {
            if new_library_build_unit_page_count + new_library_schedule_page_count
                >= max_new_libraries
            {
                store.store_library_schedule_prepare_progress(&progress)?;
                return Ok(SourcePackFilesystemLibrarySchedulePrepareStepResult {
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
            let page =
                source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies(
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
                source_pack_library_partition_contract_error(format!(
                    "stored metadata schedule page frontend job range overflows at partition {partition_index}"
                ))
            })?;
        first_codegen_job_index = first_codegen_job_index
            .checked_add(entry.codegen_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "stored metadata schedule page codegen job range overflows at partition {partition_index}"
                ))
            })?;
        progress.library_schedule_page_count += 1;
        progress.next_partition_index = partition_index + 1;
        progress.next_frontend_job_index = first_frontend_job_index;
        progress.next_codegen_job_index = first_codegen_job_index;
    }
    if first_codegen_job_index != library_schedule_index.link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "stored metadata schedule pages ended at codegen job {first_codegen_job_index}, expected link job {}",
            library_schedule_index.link_job_index
        )));
    }
    store_source_pack_library_schedule_link_job_locator(store, &library_schedule_index)?;
    store.store_library_schedule_job_locator_index(&SourcePackLibraryScheduleJobLocatorIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
        target,
        job_count: library_schedule_index.job_count,
        locator_count: library_schedule_index.job_count,
    })?;
    progress.phase = SourcePackFilesystemLibrarySchedulePreparePhase::Complete;
    progress.next_partition_index = library_partition_count;
    progress.library_schedule_page_count = library_partition_count;
    store.store_library_schedule_prepare_progress(&progress)?;

    Ok(SourcePackFilesystemLibrarySchedulePrepareStepResult {
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

pub(in crate::compiler) fn source_pack_validate_build_unit_page_matches_partition(
    page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<(), CompileError> {
    validate_source_pack_library_build_unit_page(
        page,
        partition.target,
        Some(partition.partition_index),
    )?;
    if page.library_id != partition.library_id
        || page.first_source_index != partition.first_source_index
        || page.source_file_count != partition.source_file_count
        || page.source_byte_count != partition.source_byte_count
        || page.source_line_count != partition.source_line_count
        || page.limits != limits.normalized()
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} does not match stored metadata partition",
            partition.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_validate_schedule_page_matches_entry(
    page: &SourcePackLibrarySchedulePage,
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_page(page, page.target, Some(entry.partition_index))?;
    if page.library_id != entry.library_id
        || page.frontend_job_index != entry.frontend_job_index
        || source_pack_library_schedule_page_frontend_job_count(page)
            != source_pack_library_schedule_entry_frontend_job_count(entry)
        || page.first_codegen_job_index != entry.first_codegen_job_index
        || page.codegen_job_count != entry.codegen_job_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page {} does not match metadata-derived schedule entry",
            entry.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_library_schedule_codegen_job_locator(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
    partition_index: usize,
    codegen_job_offset: usize,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(index, index.target)?;
    if job.phase != SourcePackJobPhase::Codegen {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job {} has phase {:?}, expected codegen",
            job.job_index, job.phase
        )));
    }
    if job.job_index >= index.job_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule codegen job {} exceeds job count {}",
            job.job_index, index.job_count
        )));
    }
    let frontend_job_count = source_pack_library_schedule_index_frontend_job_count(index);
    if job.job_index < frontend_job_count || job.job_index >= index.link_job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule codegen job {} is outside codegen job range {}..{}",
            job.job_index, frontend_job_count, index.link_job_index
        )));
    }
    let Some(frontend_job_index) = job.library_job_index else {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule codegen job {} has no owning frontend job",
            job.job_index
        )));
    };
    if frontend_job_index >= frontend_job_count {
        return Err(source_pack_library_partition_contract_error(format!(
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

pub(in crate::compiler) fn store_source_pack_library_schedule_link_job_locator(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(index, index.target)?;
    let locator = SourcePackLibraryScheduleJobLocatorPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
        target: index.target,
        job_index: index.link_job_index,
        phase: SourcePackJobPhase::Link,
        partition_index: None,
        codegen_job_offset: None,
    };
    store.store_library_schedule_job_locator_page(&locator, index.job_count)?;
    let job = source_pack_link_schedule_job(index);
    store_source_pack_library_schedule_job_page(store, index, &job)?;
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_library_schedule_job_page(
    store: &SourcePackFilesystemArtifactStore,
    index: &SourcePackLibraryScheduleIndex,
    job: &SourcePackJob,
) -> Result<(), CompileError> {
    validate_source_pack_library_schedule_index(index, index.target)?;
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

pub(in crate::compiler) fn source_pack_link_schedule_job(
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

pub(in crate::compiler) struct SourcePackScheduleJobDependencyPageWriter<'a> {
    pub(in crate::compiler) store: &'a SourcePackFilesystemArtifactStore,
    pub(in crate::compiler) target: SourcePackArtifactTarget,
    pub(in crate::compiler) job_index: usize,
    pub(in crate::compiler) job_count: usize,
    pub(in crate::compiler) page_index: usize,
    pub(in crate::compiler) first_dependency_position: usize,
    pub(in crate::compiler) dependency_job_count: usize,
    pub(in crate::compiler) dependency_job_ranges: Vec<SourcePackJobIndexRange>,
    pub(in crate::compiler) current_dependency_job_indices: Vec<usize>,
}

impl<'a> SourcePackScheduleJobDependencyPageWriter<'a> {
    pub(in crate::compiler) fn new(
        store: &'a SourcePackFilesystemArtifactStore,
        target: SourcePackArtifactTarget,
        job_index: usize,
        job_count: usize,
    ) -> Self {
        Self {
            store,
            target,
            job_index,
            job_count,
            page_index: 0,
            first_dependency_position: 0,
            dependency_job_count: 0,
            dependency_job_ranges: Vec::new(),
            current_dependency_job_indices: Vec::with_capacity(
                SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE,
            ),
        }
    }

    pub(in crate::compiler) fn push(
        &mut self,
        dependency_job_index: usize,
    ) -> Result<(), CompileError> {
        if dependency_job_index >= self.job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job {}",
                self.job_index, dependency_job_index
            )));
        }
        self.current_dependency_job_indices
            .push(dependency_job_index);
        if self.current_dependency_job_indices.len()
            == SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE
        {
            self.flush()?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn flush(&mut self) -> Result<(), CompileError> {
        if self.current_dependency_job_indices.is_empty() {
            return Ok(());
        }
        let dependency_job_indices = std::mem::take(&mut self.current_dependency_job_indices);
        let dependency_page = SourcePackLibraryScheduleJobDependencyPage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION,
            target: self.target,
            job_index: self.job_index,
            page_index: self.page_index,
            first_dependency_position: self.first_dependency_position,
            dependency_count: dependency_job_indices.len(),
            dependency_job_indices,
        };
        validate_source_pack_library_schedule_job_dependency_page(
            &dependency_page,
            self.target,
            self.job_count,
            self.job_index,
            self.page_index,
        )?;
        self.store
            .store_library_schedule_job_dependency_page(&dependency_page, self.job_count)?;
        self.dependency_job_count = self
            .dependency_job_count
            .saturating_add(dependency_page.dependency_count);
        self.first_dependency_position = self
            .first_dependency_position
            .saturating_add(dependency_page.dependency_count);
        self.page_index += 1;
        Ok(())
    }

    pub(in crate::compiler) fn push_range(
        &mut self,
        first_job_index: usize,
        job_count: usize,
    ) -> Result<(), CompileError> {
        if job_count == 0 {
            return Ok(());
        }
        let end_job_index = first_job_index.checked_add(job_count).ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "schedule job page {} dependency range {}+{} overflows",
                self.job_index, first_job_index, job_count
            ))
        })?;
        if end_job_index > self.job_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} depends on non-prior job range {}..{}",
                self.job_index, first_job_index, end_job_index
            )));
        }
        if source_pack_try_push_dependency_job_range(
            &mut self.dependency_job_ranges,
            self.job_index,
            first_job_index,
            job_count,
        )? {
            return Ok(());
        }

        for dependency_job_index in first_job_index..end_job_index {
            self.push(dependency_job_index)?;
        }
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        mut self,
    ) -> Result<(usize, usize, Vec<SourcePackJobIndexRange>), CompileError> {
        self.flush()?;
        Ok((
            self.dependency_job_count,
            self.page_index,
            self.dependency_job_ranges,
        ))
    }
}

pub(in crate::compiler) fn source_pack_try_push_dependency_job_range(
    dependency_job_ranges: &mut Vec<SourcePackJobIndexRange>,
    job_index: usize,
    first_job_index: usize,
    job_count: usize,
) -> Result<bool, CompileError> {
    let end_job_index = first_job_index.checked_add(job_count).ok_or_else(|| {
        source_pack_library_partition_contract_error(format!(
            "schedule job page {job_index} dependency range {first_job_index}+{job_count} overflows"
        ))
    })?;
    if end_job_index > job_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule job page {job_index} depends on non-prior job range {first_job_index}..{end_job_index}"
        )));
    }

    let mut merged_ranges = dependency_job_ranges.clone();
    merged_ranges.push(SourcePackJobIndexRange {
        first_job_index,
        job_count,
    });
    merged_ranges.sort_by_key(|range| range.first_job_index);

    let mut compact_ranges = Vec::<SourcePackJobIndexRange>::with_capacity(merged_ranges.len());
    for range in merged_ranges {
        let Some(range_end) = range.end_job_index() else {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {job_index} dependency range starting at {} overflows",
                range.first_job_index
            )));
        };
        if let Some(last) = compact_ranges.last_mut() {
            let Some(last_end) = last.end_job_index() else {
                return Err(source_pack_library_partition_contract_error(format!(
                    "schedule job page {job_index} dependency range starting at {} overflows",
                    last.first_job_index
                )));
            };
            if range.first_job_index <= last_end {
                let compact_end = last_end.max(range_end);
                last.job_count = compact_end - last.first_job_index;
                continue;
            }
        }
        compact_ranges.push(range);
    }

    if compact_ranges.len() > SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE {
        return Ok(false);
    }
    *dependency_job_ranges = compact_ranges;
    Ok(true)
}

pub(in crate::compiler) fn store_schedule_job_page_with_dependencies<F>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    job_count: usize,
    job: &SourcePackJob,
    mut write_dependencies: F,
) -> Result<PathBuf, CompileError>
where
    F: FnMut(&mut SourcePackScheduleJobDependencyPageWriter<'_>) -> Result<(), CompileError>,
{
    let mut writer =
        SourcePackScheduleJobDependencyPageWriter::new(store, target, job.job_index, job_count);
    write_dependencies(&mut writer)?;
    let (dependency_job_count, dependency_page_count, dependency_job_ranges) = writer.finish()?;
    let mut stored_job = job.clone();
    stored_job.dependency_job_indices.clear();
    let page = SourcePackLibraryScheduleJobPage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
        target,
        job_index: job.job_index,
        job: stored_job,
        dependency_job_count,
        dependency_page_count,
        dependency_job_ranges,
    };
    store.write_library_schedule_job_page_file(&page, job_count)
}

pub(in crate::compiler) fn source_pack_write_library_dependency_frontend_job_ranges(
    writer: &mut SourcePackScheduleJobDependencyPageWriter<'_>,
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
) -> Result<(), CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    if !partition.dependency_library_ids.is_empty() {
        for &dependency_library_id in &partition.dependency_library_ids {
            source_pack_write_library_dependency_frontend_job_range(
                writer,
                store,
                partition,
                dependency_library_id,
            )?;
        }
        return Ok(());
    }

    let mut loaded_dependency_count = 0usize;
    for page_index in 0..partition.dependency_page_count {
        let dependency_page = store.load_library_dependency_page_for_target(
            partition.target,
            partition.partition_index,
            page_index,
        )?;
        if dependency_page.first_dependency_position != loaded_dependency_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} dependency page {} starts at {} but loaded {} dependencies",
                partition.partition_index,
                page_index,
                dependency_page.first_dependency_position,
                loaded_dependency_count
            )));
        }
        let remaining_dependency_count = partition
            .dependency_library_count
            .checked_sub(loaded_dependency_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} loaded too many dependencies before page {}",
                    partition.partition_index, page_index
                ))
            })?;
        let expected_page_dependency_count =
            remaining_dependency_count.min(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} dependency page {} has {} dependencies but expected {}",
                partition.partition_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        for dependency_library_id in dependency_page.dependency_library_ids {
            source_pack_write_library_dependency_frontend_job_range(
                writer,
                store,
                partition,
                dependency_library_id,
            )?;
            loaded_dependency_count += 1;
        }
    }
    if loaded_dependency_count != partition.dependency_library_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} loaded {} library dependencies but expected {}",
            partition.partition_index, loaded_dependency_count, partition.dependency_library_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_write_library_dependency_frontend_job_range(
    writer: &mut SourcePackScheduleJobDependencyPageWriter<'_>,
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    dependency_library_id: u32,
) -> Result<(), CompileError> {
    if dependency_library_id == partition.library_id {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} library {} depends on itself",
            partition.partition_index, partition.library_id
        )));
    }
    let locator = store.load_library_frontend_job_locator_page_for_target(
        partition.target,
        dependency_library_id,
    )?;
    if locator.partition_index >= partition.partition_index {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} library {} depends on library {} in partition {}",
            partition.partition_index,
            partition.library_id,
            dependency_library_id,
            locator.partition_index
        )));
    }
    writer.push_range(
        locator.frontend_job_index,
        source_pack_library_frontend_job_locator_count(&locator),
    )
}

pub(in crate::compiler) fn store_source_pack_library_dependency_pages(
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
) -> Result<(usize, usize), CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    if partition.dependency_library_ids.is_empty() {
        return Ok((
            partition.dependency_library_count,
            partition.dependency_page_count,
        ));
    }
    let mut dependency_library_count = 0usize;
    let mut dependency_page_count = 0usize;
    for (page_index, dependency_chunk) in partition
        .dependency_library_ids
        .chunks(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE)
        .enumerate()
    {
        let dependency_page = SourcePackLibraryDependencyPage {
            version: SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION,
            target: partition.target,
            partition_index: partition.partition_index,
            page_index,
            first_dependency_position: page_index
                .saturating_mul(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE),
            dependency_count: dependency_chunk.len(),
            dependency_library_ids: dependency_chunk.to_vec(),
        };
        validate_source_pack_library_dependency_page(
            &dependency_page,
            partition.target,
            partition.partition_index,
            page_index,
        )?;
        store.store_library_dependency_page(&dependency_page)?;
        dependency_library_count =
            dependency_library_count.saturating_add(dependency_page.dependency_count);
        dependency_page_count += 1;
    }
    Ok((dependency_library_count, dependency_page_count))
}

pub(in crate::compiler) fn store_source_pack_library_dependency_pages_from_ids<I>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    expected_dependency_library_count: usize,
    dependency_library_ids: I,
) -> Result<(usize, usize), CompileError>
where
    I: IntoIterator<Item = u32>,
{
    let mut dependency_library_count = 0usize;
    let mut dependency_page_count = 0usize;
    let mut first_dependency_position = 0usize;
    let mut dependency_page_ids =
        Vec::with_capacity(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
    let mut previous_dependency_library_id = None;

    for dependency_library_id in dependency_library_ids {
        if dependency_library_count >= expected_dependency_library_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {partition_index} received more than {expected_dependency_library_count} dependency libraries"
            )));
        }
        if dependency_library_id == library_id {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} depends on itself"
            )));
        }
        if previous_dependency_library_id.is_some_and(|previous_dependency_library_id| {
            dependency_library_id <= previous_dependency_library_id
        }) {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} dependency ids must be strictly sorted and unique"
            )));
        }
        let partition_locator_path =
            store.library_partition_locator_page_path_for_target(target, dependency_library_id);
        let frontend_job_locator_path =
            store.library_frontend_job_locator_page_path_for_target(target, dependency_library_id);
        let dependency_partition_index = if partition_locator_path.is_file() {
            store
                .load_library_partition_locator_page_for_target(target, dependency_library_id)?
                .partition_index
        } else if frontend_job_locator_path.is_file() {
            store
                .load_library_frontend_job_locator_page_for_target(target, dependency_library_id)?
                .partition_index
        } else {
            return Err(CompileError::GpuFrontend(format!(
                "explicit source pack library {library_id} depends on missing or later library {dependency_library_id}"
            )));
        };
        if dependency_partition_index >= partition_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {partition_index} library {library_id} depends on library {dependency_library_id} in partition {}",
                dependency_partition_index
            )));
        }
        previous_dependency_library_id = Some(dependency_library_id);
        dependency_page_ids.push(dependency_library_id);
        dependency_library_count += 1;
        if dependency_page_ids.len() == SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE {
            store_source_pack_library_dependency_page_from_ids(
                store,
                target,
                partition_index,
                dependency_page_count,
                first_dependency_position,
                std::mem::take(&mut dependency_page_ids),
            )?;
            dependency_page_count += 1;
            first_dependency_position = dependency_library_count;
            dependency_page_ids =
                Vec::with_capacity(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        }
    }

    if dependency_library_count != expected_dependency_library_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {partition_index} received {dependency_library_count} dependency libraries but expected {expected_dependency_library_count}"
        )));
    }
    if !dependency_page_ids.is_empty() {
        store_source_pack_library_dependency_page_from_ids(
            store,
            target,
            partition_index,
            dependency_page_count,
            first_dependency_position,
            dependency_page_ids,
        )?;
        dependency_page_count += 1;
    }

    Ok((dependency_library_count, dependency_page_count))
}

pub(in crate::compiler) fn store_source_pack_library_dependency_page_from_ids(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    page_index: usize,
    first_dependency_position: usize,
    dependency_library_ids: Vec<u32>,
) -> Result<(), CompileError> {
    let dependency_page = SourcePackLibraryDependencyPage {
        version: SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION,
        target,
        partition_index,
        page_index,
        first_dependency_position,
        dependency_count: dependency_library_ids.len(),
        dependency_library_ids,
    };
    validate_source_pack_library_dependency_page(
        &dependency_page,
        target,
        partition_index,
        page_index,
    )?;
    store.store_library_dependency_page(&dependency_page)?;
    Ok(())
}
