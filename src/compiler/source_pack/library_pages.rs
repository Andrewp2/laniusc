use super::*;

mod source_files;
pub(in crate::compiler) use source_files::*;

pub(in crate::compiler) struct BuildUnitSummaryAccumulator<'a> {
    pub(in crate::compiler) partition: &'a SourcePackLibraryPartition,
    pub(in crate::compiler) limits: CodegenUnitLimits,
    pub(in crate::compiler) expected_codegen_unit_index: usize,
    pub(in crate::compiler) next_source_index: usize,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) source_byte_count: usize,
    pub(in crate::compiler) source_lines: usize,
}

impl<'a> BuildUnitSummaryAccumulator<'a> {
    pub(in crate::compiler) fn new(
        partition: &'a SourcePackLibraryPartition,
        limits: CodegenUnitLimits,
    ) -> Self {
        Self {
            partition,
            limits: limits.normalized(),
            expected_codegen_unit_index: 0,
            next_source_index: partition.first_source_index,
            source_file_count: 0,
            source_byte_count: 0,
            source_lines: 0,
        }
    }

    pub(in crate::compiler) fn record_codegen_unit(
        &mut self,
        unit: &CodegenUnit,
    ) -> Result<(), CompileError> {
        validate_codegen_unit_shape(
            unit,
            self.partition.target,
            self.partition.partition_index,
            self.partition.library_id,
            self.limits,
            self.expected_codegen_unit_index,
        )?;
        if unit.first_source_index != self.next_source_index {
            return Err(library_partition_contract_error(format!(
                "partition {} codegen unit {} starts at source {}, expected {}",
                self.partition.partition_index,
                unit.unit_index,
                unit.first_source_index,
                self.next_source_index
            )));
        }
        self.next_source_index = self
            .next_source_index
            .checked_add(unit.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} codegen source range overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_file_count = self
            .source_file_count
            .checked_add(unit.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} codegen source-file count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_byte_count = self
            .source_byte_count
            .checked_add(unit.source_bytes)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} codegen source-byte count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_lines = self
            .source_lines
            .checked_add(unit.source_lines)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} codegen source-line count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.expected_codegen_unit_index = self
            .expected_codegen_unit_index
            .checked_add(1)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} codegen-unit count overflows",
                    self.partition.partition_index
                ))
            })?;
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        self,
        codegen_unit_count: usize,
    ) -> Result<BuildUnitSummary, CompileError> {
        let source_end = self
            .partition
            .first_source_index
            .checked_add(self.partition.source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    self.partition.partition_index
                ))
            })?;
        if codegen_unit_count == 0 {
            return Err(library_partition_contract_error(format!(
                "partition {} has no codegen units",
                self.partition.partition_index
            )));
        }
        if codegen_unit_count != self.expected_codegen_unit_index {
            return Err(library_partition_contract_error(format!(
                "partition {} iterated {} codegen units but recorded {}",
                self.partition.partition_index,
                codegen_unit_count,
                self.expected_codegen_unit_index
            )));
        }
        if self.next_source_index != source_end
            || self.source_file_count != self.partition.source_file_count
        {
            return Err(library_partition_contract_error(format!(
                "partition {} codegen units cover {} files ending at {}, expected {} files ending at {}",
                self.partition.partition_index,
                self.source_file_count,
                self.next_source_index,
                self.partition.source_file_count,
                source_end
            )));
        }
        if self.source_byte_count != self.partition.source_byte_count {
            return Err(library_partition_contract_error(format!(
                "partition {} codegen units sum to {} bytes but partition records {}",
                self.partition.partition_index,
                self.source_byte_count,
                self.partition.source_byte_count
            )));
        }
        if self.source_lines != self.partition.source_line_count {
            return Err(library_partition_contract_error(format!(
                "partition {} codegen units sum to {} source lines but partition records {}",
                self.partition.partition_index, self.source_lines, self.partition.source_line_count
            )));
        }
        Ok(BuildUnitSummary {
            frontend_unit: LibraryUnit {
                library_index: 0,
                library_id: self.partition.library_id,
                first_source_index: self.partition.first_source_index,
                source_file_count: self.partition.source_file_count,
                source_bytes: self.partition.source_byte_count,
                source_lines: self.source_lines,
            },
            frontend_unit_count: codegen_unit_count,
            codegen_unit_count,
        })
    }
}

pub(in crate::compiler) struct BuildUnitSummary {
    pub(in crate::compiler) frontend_unit: LibraryUnit,
    pub(in crate::compiler) frontend_unit_count: usize,
    pub(in crate::compiler) codegen_unit_count: usize,
}

pub(in crate::compiler) fn summarize_build_units(
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<BuildUnitSummary, CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    let mut summary_builder = BuildUnitSummaryAccumulator::new(partition, limits);
    let codegen_unit_count = CodegenUnitPlan::try_for_each_from_fallible_files(
        source_unit_inputs_from_records(store, partition),
        limits,
        |unit| summary_builder.record_codegen_unit(&unit),
    )?;
    let frontend_unit_count = FrontendUnitPlan::try_for_each_from_fallible_files(
        source_unit_inputs_from_records(store, partition),
        limits,
        |_| Ok::<(), CompileError>(()),
    )?;
    let mut summary = summary_builder.finish(codegen_unit_count)?;
    summary.frontend_unit_count = frontend_unit_count;
    Ok(summary)
}

pub(in crate::compiler) fn compact_build_unit_page(
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<SourcePackLibraryBuildUnitPage, CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    let summary = summarize_build_units(store, partition, limits)?;
    let page = SourcePackLibraryBuildUnitPage {
        version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
        target: partition.target,
        partition_index: partition.partition_index,
        library_id: partition.library_id,
        dependency_library_ids: partition.dependency_library_ids.clone(),
        first_source_index: partition.first_source_index,
        source_file_count: partition.source_file_count,
        source_byte_count: partition.source_byte_count,
        source_line_count: partition.source_line_count,
        limits: limits.normalized(),
        frontend_unit: summary.frontend_unit,
        frontend_unit_count: summary.frontend_unit_count,
        codegen_unit_count: summary.codegen_unit_count,
        frontend_units: Vec::new(),
        codegen_units: Vec::new(),
    };
    validate_library_build_unit_page(&page, partition.target, Some(partition.partition_index))?;
    Ok(page)
}

pub(in crate::compiler) fn library_build_unit_page_codegen_unit_count(
    page: &SourcePackLibraryBuildUnitPage,
) -> usize {
    page.codegen_unit_count.max(page.codegen_units.len())
}

pub(in crate::compiler) fn library_build_unit_page_frontend_unit_count(
    page: &SourcePackLibraryBuildUnitPage,
) -> usize {
    page.frontend_unit_count
        .max(page.frontend_units.len())
        .max(usize::from(page.frontend_unit.source_file_count != 0))
}

pub(in crate::compiler) fn library_schedule_index_frontend_job_count(
    index: &SourcePackLibraryScheduleIndex,
) -> usize {
    index.frontend_job_count.max(index.partition_count)
}

pub(in crate::compiler) fn library_schedule_entry_frontend_job_count(
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> usize {
    entry.frontend_job_count.max(1)
}

pub(in crate::compiler) fn library_schedule_entry_first_frontend_job_index(
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> usize {
    entry.first_frontend_job_index.max(entry.frontend_job_index)
}

pub(in crate::compiler) fn library_frontend_job_locator_count(
    page: &SourcePackLibraryFrontendJobLocatorPage,
) -> usize {
    page.frontend_job_count.max(1)
}

pub(in crate::compiler) fn library_schedule_page_frontend_job_count(
    page: &SourcePackLibrarySchedulePage,
) -> usize {
    page.frontend_job_count
        .max(page.frontend_jobs.len())
        .max(usize::from(page.frontend_job.source_file_count != 0))
}

pub(in crate::compiler) fn library_schedule_page_first_frontend_unit_index(
    page: &SourcePackLibrarySchedulePage,
) -> usize {
    page.first_frontend_unit_index
        .max(page.frontend_job.phase_unit_index)
}

pub(in crate::compiler) fn library_schedule_page_frontend_job_end(
    page: &SourcePackLibrarySchedulePage,
) -> Result<usize, CompileError> {
    page.frontend_job_index
        .checked_add(library_schedule_page_frontend_job_count(page))
        .ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} frontend job range overflows",
                page.partition_index
            ))
        })
}

pub(in crate::compiler) fn library_schedule_page_contains_frontend_job(
    page: &SourcePackLibrarySchedulePage,
    job_index: usize,
) -> Result<bool, CompileError> {
    Ok(job_index >= page.frontend_job_index
        && job_index < library_schedule_page_frontend_job_end(page)?)
}

pub(in crate::compiler) fn library_frontend_unit_page(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    unit: FrontendUnit,
) -> Result<SourcePackLibraryFrontendUnitPage, CompileError> {
    validate_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    let frontend_unit_count = library_build_unit_page_frontend_unit_count(build_unit_page);
    let page = SourcePackLibraryFrontendUnitPage {
        version: SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION,
        target: build_unit_page.target,
        partition_index: build_unit_page.partition_index,
        library_id: build_unit_page.library_id,
        limits: build_unit_page.limits,
        frontend_unit_index: unit.unit_index,
        frontend_unit_count,
        unit,
    };
    validate_frontend_unit_page(
        &page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
        Some(page.frontend_unit_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn library_codegen_unit_page(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    unit: CodegenUnit,
) -> Result<SourcePackLibraryCodegenUnitPage, CompileError> {
    validate_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    let codegen_unit_count = library_build_unit_page_codegen_unit_count(build_unit_page);
    let page = SourcePackLibraryCodegenUnitPage {
        version: SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION,
        target: build_unit_page.target,
        partition_index: build_unit_page.partition_index,
        library_id: build_unit_page.library_id,
        limits: build_unit_page.limits,
        codegen_unit_index: unit.unit_index,
        codegen_unit_count,
        unit,
    };
    validate_codegen_unit_page(
        &page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
        Some(page.codegen_unit_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn store_frontend_unit_pages_from_source_records(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    store: &FilesystemArtifactStore,
) -> Result<(), CompileError> {
    validate_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    validate_library_partition(
        partition,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    if build_unit_page.library_id != partition.library_id
        || build_unit_page.first_source_index != partition.first_source_index
        || build_unit_page.source_file_count != partition.source_file_count
        || build_unit_page.source_byte_count != partition.source_byte_count
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} does not match partition metadata",
            build_unit_page.partition_index
        )));
    }
    let expected_frontend_unit_count = library_build_unit_page_frontend_unit_count(build_unit_page);
    let mut emitted_frontend_unit_count = 0usize;
    let iterated_frontend_unit_count = FrontendUnitPlan::try_for_each_from_fallible_files(
        source_unit_inputs_from_records(store, partition),
        build_unit_page.limits,
        |unit| {
            let page = library_frontend_unit_page(build_unit_page, unit)?;
            store.store_library_frontend_unit_page(&page)?;
            emitted_frontend_unit_count += 1;
            Ok::<(), CompileError>(())
        },
    )?;
    if iterated_frontend_unit_count != expected_frontend_unit_count
        || emitted_frontend_unit_count != expected_frontend_unit_count
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} emitted {} frontend-unit pages from {} iterated stored records but expected {}",
            build_unit_page.partition_index,
            emitted_frontend_unit_count,
            iterated_frontend_unit_count,
            expected_frontend_unit_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_codegen_unit_pages_from_source_records(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    store: &FilesystemArtifactStore,
) -> Result<(), CompileError> {
    validate_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    validate_library_partition(
        partition,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    if build_unit_page.library_id != partition.library_id
        || build_unit_page.first_source_index != partition.first_source_index
        || build_unit_page.source_file_count != partition.source_file_count
        || build_unit_page.source_byte_count != partition.source_byte_count
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} does not match partition metadata",
            build_unit_page.partition_index
        )));
    }
    let expected_codegen_unit_count = library_build_unit_page_codegen_unit_count(build_unit_page);
    let mut emitted_codegen_unit_count = 0usize;
    let iterated_codegen_unit_count = CodegenUnitPlan::try_for_each_from_fallible_files(
        source_unit_inputs_from_records(store, partition),
        build_unit_page.limits,
        |unit| {
            let page = library_codegen_unit_page(build_unit_page, unit)?;
            store.store_library_codegen_unit_page(&page)?;
            emitted_codegen_unit_count += 1;
            Ok::<(), CompileError>(())
        },
    )?;
    if iterated_codegen_unit_count != expected_codegen_unit_count
        || emitted_codegen_unit_count != expected_codegen_unit_count
    {
        return Err(library_partition_contract_error(format!(
            "build-unit page {} emitted {} codegen-unit pages from {} iterated stored records but expected {}",
            build_unit_page.partition_index,
            emitted_codegen_unit_count,
            iterated_codegen_unit_count,
            expected_codegen_unit_count
        )));
    }
    Ok(())
}

#[cfg(test)]
pub(in crate::compiler) fn load_library_dependency_ids(
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
) -> Result<Vec<u32>, CompileError> {
    validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
    if !partition.dependency_library_ids.is_empty() {
        return Ok(partition.dependency_library_ids.clone());
    }
    let mut dependencies = Vec::with_capacity(partition.dependency_library_count);
    for page_index in 0..partition.dependency_page_count {
        let dependency_page = store.load_library_dependency_page_for_target(
            partition.target,
            partition.partition_index,
            page_index,
        )?;
        if dependency_page.first_dependency_position != dependencies.len() {
            return Err(library_partition_contract_error(format!(
                "partition {} dependency page {} starts at {} but loaded {} dependencies",
                partition.partition_index,
                page_index,
                dependency_page.first_dependency_position,
                dependencies.len()
            )));
        }
        let remaining_dependency_count = partition
            .dependency_library_count
            .checked_sub(dependencies.len())
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "partition {} loaded too many dependencies before page {}",
                    partition.partition_index, page_index
                ))
            })?;
        let expected_page_dependency_count =
            remaining_dependency_count.min(SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE);
        if dependency_page.dependency_count != expected_page_dependency_count {
            return Err(library_partition_contract_error(format!(
                "partition {} dependency page {} has {} dependencies but expected {}",
                partition.partition_index,
                page_index,
                dependency_page.dependency_count,
                expected_page_dependency_count
            )));
        }
        dependencies.extend(dependency_page.dependency_library_ids);
    }
    if dependencies.len() != partition.dependency_library_count {
        return Err(library_partition_contract_error(format!(
            "partition {} loaded {} library dependencies but expected {}",
            partition.partition_index,
            dependencies.len(),
            partition.dependency_library_count
        )));
    }
    unique_u32_set(
        &dependencies,
        &format!(
            "partition {} paged library dependencies",
            partition.partition_index
        ),
    )?;
    for &dependency_library_id in &dependencies {
        if dependency_library_id == partition.library_id {
            return Err(library_partition_contract_error(format!(
                "partition {} library {} depends on itself",
                partition.partition_index, partition.library_id
            )));
        }
        let dependency_partition_index = match store
            .load_library_partition_locator_page_for_target(partition.target, dependency_library_id)
        {
            Ok(locator) => locator.partition_index,
            Err(_) => {
                store
                    .load_library_frontend_job_locator_page_for_target(
                        partition.target,
                        dependency_library_id,
                    )?
                    .partition_index
            }
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
    Ok(dependencies)
}

pub(in crate::compiler) fn prepare_partition_schedule_page(
    store: &FilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    entry: &SourcePackLibraryScheduleIndexEntry,
    index: &SourcePackLibraryScheduleIndex,
) -> Result<SourcePackLibrarySchedulePage, CompileError> {
    validate_library_partition(partition, index.target, Some(entry.partition_index))?;
    validate_library_build_unit_page(build_unit_page, index.target, Some(entry.partition_index))?;
    if build_unit_page.library_id != entry.library_id
        || library_build_unit_page_codegen_unit_count(build_unit_page) != entry.codegen_job_count
        || library_build_unit_page_frontend_unit_count(build_unit_page)
            != library_schedule_entry_frontend_job_count(entry)
    {
        return Err(library_partition_contract_error(format!(
            "schedule entry {} does not match build-unit page metadata",
            entry.partition_index
        )));
    }

    let first_frontend_unit_index = library_schedule_entry_first_frontend_job_index(entry);
    let frontend_job_count = library_schedule_entry_frontend_job_count(entry);
    let first_frontend_unit_page =
        store.load_library_frontend_unit_page_for_target(index.target, entry.partition_index, 0)?;
    let first_frontend_job = frontend_job_from_unit(
        build_unit_page.library_id,
        &first_frontend_unit_page.unit,
        entry.frontend_job_index,
        first_frontend_unit_index,
    );
    let mut page = SourcePackLibrarySchedulePage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
        target: index.target,
        partition_index: entry.partition_index,
        library_id: build_unit_page.library_id,
        dependency_library_ids: build_unit_page.dependency_library_ids.clone(),
        frontend_job_index: entry.frontend_job_index,
        first_frontend_unit_index,
        frontend_job_count,
        first_codegen_unit_index: entry.first_codegen_job_index
            - library_schedule_index_frontend_job_count(index),
        first_codegen_job_index: entry.first_codegen_job_index,
        codegen_job_count: entry.codegen_job_count,
        link_job_index: index.link_job_index,
        frontend_job: first_frontend_job.clone(),
        frontend_jobs: Vec::new(),
        codegen_jobs: Vec::new(),
    };

    for frontend_unit_offset in 0..frontend_job_count {
        let unit_page = store.load_library_frontend_unit_page_for_target(
            index.target,
            entry.partition_index,
            frontend_unit_offset,
        )?;
        let job_index = entry
            .frontend_job_index
            .checked_add(frontend_unit_offset)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule page {} frontend job offset {} overflows",
                    entry.partition_index, frontend_unit_offset
                ))
            })?;
        let phase_unit_index = first_frontend_unit_index
            .checked_add(frontend_unit_offset)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "schedule page {} frontend phase-unit offset {} overflows",
                    entry.partition_index, frontend_unit_offset
                ))
            })?;
        let mut job = frontend_job_from_unit(
            build_unit_page.library_id,
            &unit_page.unit,
            job_index,
            phase_unit_index,
        );
        job.dependency_job_indices.clear();
        let frontend_locator = SourcePackLibraryScheduleJobLocatorPage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
            target: index.target,
            job_index,
            phase: SourcePackJobPhase::LibraryFrontend,
            partition_index: Some(entry.partition_index),
            codegen_job_offset: None,
        };
        store.store_library_schedule_job_locator_page(&frontend_locator, index.job_count)?;
        store_schedule_job_with_dependencies(
            store,
            index.target,
            index.job_count,
            &job,
            |writer| write_dependency_frontend_job_ranges(writer, store, partition),
        )?;
    }

    let first_codegen_unit_index =
        entry.first_codegen_job_index - library_schedule_index_frontend_job_count(index);
    for codegen_unit_offset in 0..entry.codegen_job_count {
        let unit_page = store.load_library_codegen_unit_page_for_target(
            index.target,
            entry.partition_index,
            codegen_unit_offset,
        )?;
        if codegen_unit_offset >= frontend_job_count {
            return Err(library_partition_contract_error(format!(
                "schedule page {} codegen unit {} has no matching frontend unit among {}",
                entry.partition_index, codegen_unit_offset, frontend_job_count
            )));
        }
        let owning_frontend_job_index = entry
            .frontend_job_index
            .checked_add(codegen_unit_offset)
            .ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} owning frontend job offset {} overflows",
                entry.partition_index, codegen_unit_offset
            ))
        })?;
        let mut job = codegen_job_from_unit(
            &page,
            &unit_page.unit,
            entry.first_codegen_job_index + codegen_unit_offset,
            first_codegen_unit_index + codegen_unit_offset,
            owning_frontend_job_index,
        );
        job.dependency_job_indices.clear();
        store_codegen_job_locator(
            store,
            index,
            entry.partition_index,
            codegen_unit_offset,
            &job,
        )?;
        store_schedule_job_with_dependencies(
            store,
            index.target,
            index.job_count,
            &job,
            |writer| {
                writer.push(owning_frontend_job_index)?;
                if codegen_unit_offset > 0 {
                    writer.push_range(entry.frontend_job_index, codegen_unit_offset)?;
                }
                let remaining_frontend_job_count = frontend_job_count
                    .checked_sub(codegen_unit_offset.saturating_add(1))
                    .ok_or_else(|| {
                        library_partition_contract_error(format!(
                            "schedule page {} codegen unit {} exceeds frontend job count {}",
                            entry.partition_index, codegen_unit_offset, frontend_job_count
                        ))
                    })?;
                if remaining_frontend_job_count > 0 {
                    let first_following_frontend_job_index =
                        owning_frontend_job_index.checked_add(1).ok_or_else(|| {
                            library_partition_contract_error(format!(
                                "schedule page {} following frontend dependency overflows",
                                entry.partition_index
                            ))
                        })?;
                    writer.push_range(
                        first_following_frontend_job_index,
                        remaining_frontend_job_count,
                    )?;
                }
                write_dependency_frontend_job_ranges(writer, store, partition)
            },
        )?;
    }
    page.frontend_job.dependency_job_indices.clear();
    page.frontend_jobs = Vec::new();
    page.codegen_jobs = Vec::new();
    validate_library_schedule_page_for_index(&page, index)?;
    Ok(page)
}

pub(in crate::compiler) fn frontend_job_from_unit(
    library_id: u32,
    unit: &FrontendUnit,
    job_index: usize,
    phase_unit_index: usize,
) -> SourcePackJob {
    SourcePackJob {
        job_index,
        phase: SourcePackJobPhase::LibraryFrontend,
        phase_unit_index,
        library_job_index: None,
        library_id,
        first_source_index: unit.first_source_index,
        source_file_count: unit.source_file_count,
        source_bytes: unit.source_bytes,
        source_lines: unit.source_lines,
        oversized_source_file: unit.oversized_source_file,
        dependency_job_indices: Vec::new(),
    }
}

pub(in crate::compiler) fn codegen_job_from_unit(
    page: &SourcePackLibrarySchedulePage,
    unit: &CodegenUnit,
    job_index: usize,
    phase_unit_index: usize,
    frontend_job_index: usize,
) -> SourcePackJob {
    let mut dependency_job_indices =
        Vec::with_capacity(page.frontend_job.dependency_job_indices.len() + 1);
    dependency_job_indices.push(frontend_job_index);
    dependency_job_indices.extend_from_slice(&page.frontend_job.dependency_job_indices);
    SourcePackJob {
        job_index,
        phase: SourcePackJobPhase::Codegen,
        phase_unit_index,
        library_job_index: Some(frontend_job_index),
        library_id: unit.library_id,
        first_source_index: unit.first_source_index,
        source_file_count: unit.source_file_count,
        source_bytes: unit.source_bytes,
        source_lines: unit.source_lines,
        oversized_source_file: unit.oversized_source_file,
        dependency_job_indices,
    }
}
