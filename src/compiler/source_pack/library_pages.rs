use super::*;

pub(in crate::compiler) fn source_pack_library_partition_index(
    manifest: &ExplicitSourcePackPathManifest,
    target: SourcePackArtifactTarget,
) -> Result<SourcePackLibraryPartitionIndex, CompileError> {
    Ok(source_pack_library_partition_plan(manifest, target)?.index)
}

pub(in crate::compiler) fn source_pack_library_partition_plan(
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
            return Err(source_pack_library_partition_contract_error(format!(
                "library {} depends on itself",
                dependency.library_id
            )));
        }
        if !file_library_ids.contains(&dependency.library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "dependency references missing library {}",
                dependency.library_id
            )));
        }
        if !file_library_ids.contains(&dependency.depends_on_library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
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
    validate_source_pack_library_partition_index(&index, target)?;
    let plan = SourcePackLibraryPartitionPlan { index, partitions };
    validate_source_pack_library_partition_plan(&plan, target)?;
    Ok(plan)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_source_file_pages(
    manifest: &ExplicitSourcePackPathManifest,
    plan: &SourcePackLibraryPartitionPlan,
) -> Result<Vec<SourcePackLibrarySourceFilePage>, CompileError> {
    let index = &plan.index;
    validate_source_pack_library_partition_plan(plan, index.target)?;
    let mut pages = Vec::with_capacity(plan.partitions.len());

    for partition in &plan.partitions {
        let source_end = partition
            .first_source_index
            .checked_add(partition.source_file_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    partition.partition_index
                ))
            })?;
        if source_end > manifest.files.len() {
            return Err(source_pack_library_partition_contract_error(format!(
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
        validate_source_pack_library_source_file_page(
            &page,
            index.target,
            Some(partition.partition_index),
        )?;
        pages.push(page);
    }

    Ok(pages)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_build_unit_page(
    partition: &SourcePackLibraryPartition,
    source_file_page: &SourcePackLibrarySourceFilePage,
    limits: CodegenUnitLimits,
) -> Result<SourcePackLibraryBuildUnitPage, CompileError> {
    validate_source_pack_library_partition(
        partition,
        source_file_page.target,
        Some(source_file_page.partition_index),
    )?;
    validate_source_pack_library_source_file_page(
        source_file_page,
        source_file_page.target,
        Some(partition.partition_index),
    )?;
    if partition.library_id != source_file_page.library_id
        || partition.first_source_index != source_file_page.first_source_index
        || partition.source_file_count != source_file_page.source_file_count
        || partition.source_byte_count != source_file_page.source_byte_count
        || partition.source_line_count != source_file_page.source_line_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} library/source-file page metadata mismatch",
            partition.partition_index
        )));
    }
    if source_file_page.source_files.is_empty() {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} build-unit planning requires inline source-file records",
            partition.partition_index
        )));
    }

    let SourcePackJobPlan {
        libraries,
        frontend_units,
        codegen_units,
        ..
    } = SourcePackJobPlan::from_file_stream_with_dependencies(
        source_file_page
            .source_files
            .iter()
            .map(|source_file| SourceFileUnitInput {
                library_id: source_file.file.library_id,
                source_index: source_file.source_index,
                byte_len: source_file.file.byte_len,
                line_count: source_file.file.line_count.unwrap_or(0),
            }),
        &[],
        limits,
    );
    let mut libraries = libraries.libraries;
    if libraries.len() != 1 {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} planned {} frontend library units",
            partition.partition_index,
            libraries.len()
        )));
    }
    let frontend_units = frontend_units.units;
    let frontend_unit_count = frontend_units.len();
    let codegen_units = codegen_units.units;
    let codegen_unit_count = codegen_units.len();
    let page = SourcePackLibraryBuildUnitPage {
        version: SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
        target: source_file_page.target,
        partition_index: partition.partition_index,
        library_id: partition.library_id,
        dependency_library_ids: partition.dependency_library_ids.clone(),
        first_source_index: partition.first_source_index,
        source_file_count: partition.source_file_count,
        source_byte_count: partition.source_byte_count,
        source_line_count: partition.source_line_count,
        limits: limits.normalized(),
        frontend_unit: libraries.remove(0),
        frontend_unit_count,
        codegen_unit_count,
        frontend_units,
        codegen_units,
    };
    validate_source_pack_library_build_unit_page(
        &page,
        source_file_page.target,
        Some(partition.partition_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_source_file_unit_input_from_record(
    record: &SourcePackLibrarySourceFileRecordPage,
) -> SourceFileUnitInput {
    SourceFileUnitInput {
        library_id: record.file.library_id,
        source_index: record.source_index,
        byte_len: record.file.byte_len,
        line_count: record.file.line_count.unwrap_or(0),
    }
}

pub(in crate::compiler) fn source_pack_validate_source_file_record_matches_partition(
    partition: &SourcePackLibraryPartition,
    record: &SourcePackLibrarySourceFileRecordPage,
) -> Result<(), CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    validate_source_pack_library_source_file_record_page(
        record,
        partition.target,
        Some(record.source_index),
    )?;
    if record.partition_index != partition.partition_index
        || record.library_id != partition.library_id
        || record.first_source_index != partition.first_source_index
        || record.source_file_count != partition.source_file_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file record {} metadata does not match partition {}",
            record.source_index, partition.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_validate_source_file_page_matches_partition(
    partition: &SourcePackLibraryPartition,
    page: &SourcePackLibrarySourceFilePage,
) -> Result<(), CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    validate_source_pack_library_source_file_page(
        page,
        partition.target,
        Some(partition.partition_index),
    )?;
    if page.partition_index != partition.partition_index
        || page.library_id != partition.library_id
        || page.first_source_index != partition.first_source_index
        || page.source_file_count != partition.source_file_count
        || page.source_byte_count != partition.source_byte_count
        || page.source_line_count != partition.source_line_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "source-file page {} metadata does not match partition {}",
            page.partition_index, partition.partition_index
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn source_pack_library_source_file_unit_inputs_from_stored_records<'a>(
    store: &'a SourcePackFilesystemArtifactStore,
    partition: &'a SourcePackLibraryPartition,
) -> impl Iterator<Item = Result<SourceFileUnitInput, CompileError>> + 'a {
    let source_end = partition
        .first_source_index
        .saturating_add(partition.source_file_count);
    (partition.first_source_index..source_end).map(move |source_index| {
        let record = store
            .load_library_source_file_record_page_for_target(partition.target, source_index)?;
        source_pack_validate_source_file_record_matches_partition(partition, &record)?;
        Ok(source_pack_source_file_unit_input_from_record(&record))
    })
}

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub(in crate::compiler) struct SourcePackStoredSourceFileRecordTotals {
    pub(in crate::compiler) source_byte_count: usize,
    pub(in crate::compiler) source_line_count: usize,
}

pub(in crate::compiler) fn store_source_pack_library_source_file_record_pages_from_paths<I, P>(
    store: &SourcePackFilesystemArtifactStore,
    target: SourcePackArtifactTarget,
    partition_index: usize,
    library_id: u32,
    first_source_index: usize,
    source_file_count: usize,
    paths: I,
) -> Result<SourcePackStoredSourceFileRecordTotals, CompileError>
where
    I: IntoIterator<Item = P>,
    P: AsRef<Path>,
{
    if source_file_count == 0 {
        return Err(source_pack_library_partition_contract_error(format!(
            "library {library_id} has no source files"
        )));
    }
    let label = format!("library {library_id}");
    let mut source_byte_count = 0usize;
    let mut source_line_count = 0usize;
    let mut stored_source_file_count = 0usize;
    for (path_index, path) in paths.into_iter().enumerate() {
        if path_index >= source_file_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "library {library_id} yielded more than {source_file_count} source files"
            )));
        }
        let source_index = first_source_index.checked_add(path_index).ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "library {library_id} source index overflows at path {path_index}"
            ))
        })?;
        let file =
            read_explicit_source_path_metadata(&label, path_index, library_id, path.as_ref())?;
        source_byte_count = source_byte_count
            .checked_add(file.byte_len)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "library {library_id} source byte count overflows"
                ))
            })?;
        source_line_count = source_line_count
            .checked_add(file.line_count.unwrap_or(0))
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
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
        validate_source_pack_library_source_file_record_page(&record, target, Some(source_index))?;
        store.store_library_source_file_record_page(&record)?;
        stored_source_file_count += 1;
    }
    if stored_source_file_count != source_file_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "library {library_id} stored {stored_source_file_count} source-file records but expected {source_file_count}"
        )));
    }
    Ok(SourcePackStoredSourceFileRecordTotals {
        source_byte_count,
        source_line_count,
    })
}

pub(in crate::compiler) fn source_pack_compact_library_source_file_page_from_partition(
    partition: &SourcePackLibraryPartition,
) -> Result<SourcePackLibrarySourceFilePage, CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
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
    validate_source_pack_library_source_file_page(
        &page,
        partition.target,
        Some(partition.partition_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) struct SourcePackStoredBuildUnitSummaryBuilder<'a> {
    pub(in crate::compiler) partition: &'a SourcePackLibraryPartition,
    pub(in crate::compiler) limits: CodegenUnitLimits,
    pub(in crate::compiler) expected_codegen_unit_index: usize,
    pub(in crate::compiler) next_source_index: usize,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) source_byte_count: usize,
    pub(in crate::compiler) source_lines: usize,
}

impl<'a> SourcePackStoredBuildUnitSummaryBuilder<'a> {
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
        validate_source_pack_library_codegen_unit_shape(
            unit,
            self.partition.target,
            self.partition.partition_index,
            self.partition.library_id,
            self.limits,
            self.expected_codegen_unit_index,
        )?;
        if unit.first_source_index != self.next_source_index {
            return Err(source_pack_library_partition_contract_error(format!(
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
                source_pack_library_partition_contract_error(format!(
                    "partition {} codegen source range overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_file_count = self
            .source_file_count
            .checked_add(unit.source_file_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} codegen source-file count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_byte_count = self
            .source_byte_count
            .checked_add(unit.source_bytes)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} codegen source-byte count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.source_lines = self
            .source_lines
            .checked_add(unit.source_lines)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} codegen source-line count overflows",
                    self.partition.partition_index
                ))
            })?;
        self.expected_codegen_unit_index = self
            .expected_codegen_unit_index
            .checked_add(1)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} codegen-unit count overflows",
                    self.partition.partition_index
                ))
            })?;
        Ok(())
    }

    pub(in crate::compiler) fn finish(
        self,
        codegen_unit_count: usize,
    ) -> Result<SourcePackStoredBuildUnitSummary, CompileError> {
        let source_end = self
            .partition
            .first_source_index
            .checked_add(self.partition.source_file_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "partition {} source range overflows",
                    self.partition.partition_index
                ))
            })?;
        if codegen_unit_count == 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} has no codegen units",
                self.partition.partition_index
            )));
        }
        if codegen_unit_count != self.expected_codegen_unit_index {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} iterated {} codegen units but recorded {}",
                self.partition.partition_index,
                codegen_unit_count,
                self.expected_codegen_unit_index
            )));
        }
        if self.next_source_index != source_end
            || self.source_file_count != self.partition.source_file_count
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} codegen units cover {} files ending at {}, expected {} files ending at {}",
                self.partition.partition_index,
                self.source_file_count,
                self.next_source_index,
                self.partition.source_file_count,
                source_end
            )));
        }
        if self.source_byte_count != self.partition.source_byte_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} codegen units sum to {} bytes but partition records {}",
                self.partition.partition_index,
                self.source_byte_count,
                self.partition.source_byte_count
            )));
        }
        if self.source_lines != self.partition.source_line_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "partition {} codegen units sum to {} source lines but partition records {}",
                self.partition.partition_index, self.source_lines, self.partition.source_line_count
            )));
        }
        Ok(SourcePackStoredBuildUnitSummary {
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

pub(in crate::compiler) struct SourcePackStoredBuildUnitSummary {
    pub(in crate::compiler) frontend_unit: LibraryUnit,
    pub(in crate::compiler) frontend_unit_count: usize,
    pub(in crate::compiler) codegen_unit_count: usize,
}

pub(in crate::compiler) fn source_pack_summarize_library_build_units_from_stored_source_file_records(
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<SourcePackStoredBuildUnitSummary, CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    let mut summary_builder = SourcePackStoredBuildUnitSummaryBuilder::new(partition, limits);
    let codegen_unit_count = CodegenUnitPlan::try_for_each_from_fallible_files(
        source_pack_library_source_file_unit_inputs_from_stored_records(store, partition),
        limits,
        |unit| summary_builder.record_codegen_unit(&unit),
    )?;
    let frontend_unit_count = FrontendUnitPlan::try_for_each_from_fallible_files(
        source_pack_library_source_file_unit_inputs_from_stored_records(store, partition),
        limits,
        |_| Ok::<(), CompileError>(()),
    )?;
    let mut summary = summary_builder.finish(codegen_unit_count)?;
    summary.frontend_unit_count = frontend_unit_count;
    Ok(summary)
}

pub(in crate::compiler) fn source_pack_compact_library_build_unit_page_from_stored_source_file_records(
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    limits: CodegenUnitLimits,
) -> Result<SourcePackLibraryBuildUnitPage, CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
    let summary = source_pack_summarize_library_build_units_from_stored_source_file_records(
        store, partition, limits,
    )?;
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
    validate_source_pack_library_build_unit_page(
        &page,
        partition.target,
        Some(partition.partition_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_library_build_unit_page_codegen_unit_count(
    page: &SourcePackLibraryBuildUnitPage,
) -> usize {
    page.codegen_unit_count.max(page.codegen_units.len())
}

pub(in crate::compiler) fn source_pack_library_build_unit_page_frontend_unit_count(
    page: &SourcePackLibraryBuildUnitPage,
) -> usize {
    page.frontend_unit_count
        .max(page.frontend_units.len())
        .max(usize::from(page.frontend_unit.source_file_count != 0))
}

pub(in crate::compiler) fn source_pack_library_schedule_index_frontend_job_count(
    index: &SourcePackLibraryScheduleIndex,
) -> usize {
    index.frontend_job_count.max(index.partition_count)
}

pub(in crate::compiler) fn source_pack_library_schedule_entry_frontend_job_count(
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> usize {
    entry.frontend_job_count.max(1)
}

pub(in crate::compiler) fn source_pack_library_schedule_entry_first_frontend_job_index(
    entry: &SourcePackLibraryScheduleIndexEntry,
) -> usize {
    entry.first_frontend_job_index.max(entry.frontend_job_index)
}

pub(in crate::compiler) fn source_pack_library_frontend_job_locator_count(
    page: &SourcePackLibraryFrontendJobLocatorPage,
) -> usize {
    page.frontend_job_count.max(1)
}

pub(in crate::compiler) fn source_pack_library_schedule_page_frontend_job_count(
    page: &SourcePackLibrarySchedulePage,
) -> usize {
    page.frontend_job_count
        .max(page.frontend_jobs.len())
        .max(usize::from(page.frontend_job.source_file_count != 0))
}

pub(in crate::compiler) fn source_pack_library_schedule_page_first_frontend_unit_index(
    page: &SourcePackLibrarySchedulePage,
) -> usize {
    page.first_frontend_unit_index
        .max(page.frontend_job.phase_unit_index)
}

pub(in crate::compiler) fn source_pack_library_schedule_page_frontend_job_end(
    page: &SourcePackLibrarySchedulePage,
) -> Result<usize, CompileError> {
    page.frontend_job_index
        .checked_add(source_pack_library_schedule_page_frontend_job_count(page))
        .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "schedule page {} frontend job range overflows",
                page.partition_index
            ))
        })
}

pub(in crate::compiler) fn source_pack_library_schedule_page_contains_frontend_job(
    page: &SourcePackLibrarySchedulePage,
    job_index: usize,
) -> Result<bool, CompileError> {
    Ok(job_index >= page.frontend_job_index
        && job_index < source_pack_library_schedule_page_frontend_job_end(page)?)
}

pub(in crate::compiler) fn source_pack_library_frontend_unit_page(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    unit: FrontendUnit,
) -> Result<SourcePackLibraryFrontendUnitPage, CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    let frontend_unit_count =
        source_pack_library_build_unit_page_frontend_unit_count(build_unit_page);
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
    validate_source_pack_library_frontend_unit_page(
        &page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
        Some(page.frontend_unit_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_library_codegen_unit_page(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    unit: CodegenUnit,
) -> Result<SourcePackLibraryCodegenUnitPage, CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    let codegen_unit_count =
        source_pack_library_build_unit_page_codegen_unit_count(build_unit_page);
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
    validate_source_pack_library_codegen_unit_page(
        &page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
        Some(page.codegen_unit_index),
    )?;
    Ok(page)
}

pub(in crate::compiler) fn store_source_pack_library_frontend_unit_pages_from_stored_source_file_records(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    store: &SourcePackFilesystemArtifactStore,
) -> Result<(), CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    validate_source_pack_library_partition(
        partition,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    if build_unit_page.library_id != partition.library_id
        || build_unit_page.first_source_index != partition.first_source_index
        || build_unit_page.source_file_count != partition.source_file_count
        || build_unit_page.source_byte_count != partition.source_byte_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} does not match partition metadata",
            build_unit_page.partition_index
        )));
    }
    let expected_frontend_unit_count =
        source_pack_library_build_unit_page_frontend_unit_count(build_unit_page);
    let mut emitted_frontend_unit_count = 0usize;
    let iterated_frontend_unit_count = FrontendUnitPlan::try_for_each_from_fallible_files(
        source_pack_library_source_file_unit_inputs_from_stored_records(store, partition),
        build_unit_page.limits,
        |unit| {
            let page = source_pack_library_frontend_unit_page(build_unit_page, unit)?;
            store.store_library_frontend_unit_page(&page)?;
            emitted_frontend_unit_count += 1;
            Ok::<(), CompileError>(())
        },
    )?;
    if iterated_frontend_unit_count != expected_frontend_unit_count
        || emitted_frontend_unit_count != expected_frontend_unit_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} emitted {} frontend-unit pages from {} iterated stored records but expected {}",
            build_unit_page.partition_index,
            emitted_frontend_unit_count,
            iterated_frontend_unit_count,
            expected_frontend_unit_count
        )));
    }
    Ok(())
}

pub(in crate::compiler) fn store_source_pack_library_codegen_unit_pages_from_stored_source_file_records(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    partition: &SourcePackLibraryPartition,
    store: &SourcePackFilesystemArtifactStore,
) -> Result<(), CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    validate_source_pack_library_partition(
        partition,
        build_unit_page.target,
        Some(build_unit_page.partition_index),
    )?;
    if build_unit_page.library_id != partition.library_id
        || build_unit_page.first_source_index != partition.first_source_index
        || build_unit_page.source_file_count != partition.source_file_count
        || build_unit_page.source_byte_count != partition.source_byte_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "build-unit page {} does not match partition metadata",
            build_unit_page.partition_index
        )));
    }
    let expected_codegen_unit_count =
        source_pack_library_build_unit_page_codegen_unit_count(build_unit_page);
    let mut emitted_codegen_unit_count = 0usize;
    let iterated_codegen_unit_count = CodegenUnitPlan::try_for_each_from_fallible_files(
        source_pack_library_source_file_unit_inputs_from_stored_records(store, partition),
        build_unit_page.limits,
        |unit| {
            let page = source_pack_library_codegen_unit_page(build_unit_page, unit)?;
            store.store_library_codegen_unit_page(&page)?;
            emitted_codegen_unit_count += 1;
            Ok::<(), CompileError>(())
        },
    )?;
    if iterated_codegen_unit_count != expected_codegen_unit_count
        || emitted_codegen_unit_count != expected_codegen_unit_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
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
pub(in crate::compiler) fn source_pack_library_schedule_plan(
    build_unit_pages: &[SourcePackLibraryBuildUnitPage],
) -> Result<SourcePackLibrarySchedulePlan, CompileError> {
    if build_unit_pages.is_empty() {
        return Err(source_pack_library_partition_contract_error(
            "schedule index has no library build-unit pages",
        ));
    }
    let target = build_unit_pages[0].target;
    let partition_count = build_unit_pages.len();
    let mut first_codegen_job_index = partition_count;
    let mut entries = Vec::with_capacity(partition_count);
    let mut library_ids = BTreeSet::new();

    for (partition_index, page) in build_unit_pages.iter().enumerate() {
        validate_source_pack_library_build_unit_page(page, target, Some(partition_index))?;
        if !library_ids.insert(page.library_id) {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule index library {} appears in more than one build-unit page",
                page.library_id
            )));
        }
        let codegen_job_count = source_pack_library_build_unit_page_codegen_unit_count(page);
        entries.push(SourcePackLibraryScheduleIndexEntry {
            partition_index,
            library_id: page.library_id,
            first_frontend_job_index: partition_index,
            frontend_job_count: 1,
            frontend_job_index: partition_index,
            first_codegen_job_index,
            codegen_job_count,
        });
        first_codegen_job_index = first_codegen_job_index
            .checked_add(codegen_job_count)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule index codegen job range overflows at partition {partition_index}"
                ))
            })?;
    }

    let link_job_index = first_codegen_job_index;
    let index = SourcePackLibraryScheduleIndex {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
        target,
        partition_count,
        frontend_job_count: partition_count,
        codegen_job_count: link_job_index - partition_count,
        link_job_index,
        job_count: link_job_index + 1,
    };
    validate_source_pack_library_schedule_index(&index, target)?;
    let plan = SourcePackLibrarySchedulePlan { index, entries };
    validate_source_pack_library_schedule_plan(&plan, target)?;
    Ok(plan)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_schedule_pages(
    build_unit_pages: &[SourcePackLibraryBuildUnitPage],
    plan: &SourcePackLibrarySchedulePlan,
) -> Result<Vec<SourcePackLibrarySchedulePage>, CompileError> {
    let index = &plan.index;
    validate_source_pack_library_schedule_plan(plan, index.target)?;
    if build_unit_pages.len() != plan.entries.len() {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule page build-unit page count {} does not match schedule index entry count {}",
            build_unit_pages.len(),
            plan.entries.len()
        )));
    }
    let frontend_job_index_by_library_id = plan
        .entries
        .iter()
        .map(|entry| (entry.library_id, entry.frontend_job_index))
        .collect::<BTreeMap<_, _>>();
    let mut pages = Vec::with_capacity(build_unit_pages.len());

    for (build_unit_page, entry) in build_unit_pages.iter().zip(plan.entries.iter()) {
        pages.push(source_pack_library_schedule_page(
            build_unit_page,
            entry,
            index,
            &frontend_job_index_by_library_id,
        )?);
    }
    Ok(pages)
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_load_library_dependency_ids(
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
) -> Result<Vec<u32>, CompileError> {
    validate_source_pack_library_partition(
        partition,
        partition.target,
        Some(partition.partition_index),
    )?;
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
            return Err(source_pack_library_partition_contract_error(format!(
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
        dependencies.extend(dependency_page.dependency_library_ids);
    }
    if dependencies.len() != partition.dependency_library_count {
        return Err(source_pack_library_partition_contract_error(format!(
            "partition {} loaded {} library dependencies but expected {}",
            partition.partition_index,
            dependencies.len(),
            partition.dependency_library_count
        )));
    }
    source_pack_manifest_unique_u32_set(
        &dependencies,
        &format!(
            "partition {} paged library dependencies",
            partition.partition_index
        ),
    )?;
    for &dependency_library_id in &dependencies {
        if dependency_library_id == partition.library_id {
            return Err(source_pack_library_partition_contract_error(format!(
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
            return Err(source_pack_library_partition_contract_error(format!(
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

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_schedule_page(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    entry: &SourcePackLibraryScheduleIndexEntry,
    index: &SourcePackLibraryScheduleIndex,
    frontend_job_index_by_library_id: &BTreeMap<u32, usize>,
) -> Result<SourcePackLibrarySchedulePage, CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        index.target,
        Some(entry.partition_index),
    )?;
    if build_unit_page.library_id != entry.library_id
        || source_pack_library_build_unit_page_codegen_unit_count(build_unit_page)
            != entry.codegen_job_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule entry {} does not match build-unit page metadata",
            entry.partition_index
        )));
    }

    let dependency_job_indices = build_unit_page
        .dependency_library_ids
        .iter()
        .map(|dependency_library_id| {
            frontend_job_index_by_library_id
                .get(dependency_library_id)
                .copied()
                .ok_or_else(|| {
                    source_pack_library_partition_contract_error(format!(
                        "schedule page {} depends on missing library {}",
                        entry.partition_index, dependency_library_id
                    ))
                })
        })
        .collect::<Result<Vec<_>, _>>()?;
    source_pack_library_schedule_page_with_dependency_jobs(
        build_unit_page,
        entry,
        index,
        dependency_job_indices,
    )
}

#[cfg(test)]
pub(in crate::compiler) fn source_pack_library_schedule_page_with_dependency_jobs(
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    entry: &SourcePackLibraryScheduleIndexEntry,
    index: &SourcePackLibraryScheduleIndex,
    dependency_job_indices: Vec<usize>,
) -> Result<SourcePackLibrarySchedulePage, CompileError> {
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        index.target,
        Some(entry.partition_index),
    )?;
    if build_unit_page.library_id != entry.library_id
        || source_pack_library_build_unit_page_codegen_unit_count(build_unit_page)
            != entry.codegen_job_count
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule entry {} does not match build-unit page metadata",
            entry.partition_index
        )));
    }
    let first_frontend_unit_index =
        source_pack_library_schedule_entry_first_frontend_job_index(entry);
    let frontend_job = SourcePackJob {
        job_index: entry.frontend_job_index,
        phase: SourcePackJobPhase::LibraryFrontend,
        phase_unit_index: first_frontend_unit_index,
        library_job_index: None,
        library_id: build_unit_page.library_id,
        first_source_index: build_unit_page.frontend_unit.first_source_index,
        source_file_count: build_unit_page.frontend_unit.source_file_count,
        source_bytes: build_unit_page.frontend_unit.source_bytes,
        source_lines: build_unit_page.frontend_unit.source_lines,
        oversized_source_file: false,
        dependency_job_indices: dependency_job_indices.clone(),
    };
    let first_codegen_unit_index = entry.first_codegen_job_index
        - source_pack_library_schedule_index_frontend_job_count(index);
    let codegen_jobs = build_unit_page
        .codegen_units
        .iter()
        .enumerate()
        .map(|(offset, unit)| {
            let mut dependency_job_indices = Vec::with_capacity(dependency_job_indices.len() + 1);
            dependency_job_indices.push(entry.frontend_job_index);
            dependency_job_indices.extend_from_slice(&frontend_job.dependency_job_indices);
            SourcePackJob {
                job_index: entry.first_codegen_job_index + offset,
                phase: SourcePackJobPhase::Codegen,
                phase_unit_index: first_codegen_unit_index + offset,
                library_job_index: Some(entry.frontend_job_index),
                library_id: unit.library_id,
                first_source_index: unit.first_source_index,
                source_file_count: unit.source_file_count,
                source_bytes: unit.source_bytes,
                source_lines: unit.source_lines,
                oversized_source_file: unit.oversized_source_file,
                dependency_job_indices,
            }
        })
        .collect::<Vec<_>>();
    let page = SourcePackLibrarySchedulePage {
        version: SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
        target: index.target,
        partition_index: entry.partition_index,
        library_id: build_unit_page.library_id,
        dependency_library_ids: build_unit_page.dependency_library_ids.clone(),
        frontend_job_index: entry.frontend_job_index,
        first_frontend_unit_index,
        frontend_job_count: 1,
        first_codegen_unit_index,
        first_codegen_job_index: entry.first_codegen_job_index,
        codegen_job_count: entry.codegen_job_count,
        link_job_index: index.link_job_index,
        frontend_job,
        frontend_jobs: Vec::new(),
        codegen_jobs,
    };
    validate_source_pack_library_schedule_page(&page, index.target, Some(entry.partition_index))?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_library_schedule_page_with_stored_codegen_units_from_partition_dependencies(
    store: &SourcePackFilesystemArtifactStore,
    partition: &SourcePackLibraryPartition,
    build_unit_page: &SourcePackLibraryBuildUnitPage,
    entry: &SourcePackLibraryScheduleIndexEntry,
    index: &SourcePackLibraryScheduleIndex,
) -> Result<SourcePackLibrarySchedulePage, CompileError> {
    validate_source_pack_library_partition(partition, index.target, Some(entry.partition_index))?;
    validate_source_pack_library_build_unit_page(
        build_unit_page,
        index.target,
        Some(entry.partition_index),
    )?;
    if build_unit_page.library_id != entry.library_id
        || source_pack_library_build_unit_page_codegen_unit_count(build_unit_page)
            != entry.codegen_job_count
        || source_pack_library_build_unit_page_frontend_unit_count(build_unit_page)
            != source_pack_library_schedule_entry_frontend_job_count(entry)
    {
        return Err(source_pack_library_partition_contract_error(format!(
            "schedule entry {} does not match build-unit page metadata",
            entry.partition_index
        )));
    }

    let first_frontend_unit_index =
        source_pack_library_schedule_entry_first_frontend_job_index(entry);
    let frontend_job_count = source_pack_library_schedule_entry_frontend_job_count(entry);
    let first_frontend_unit_page =
        store.load_library_frontend_unit_page_for_target(index.target, entry.partition_index, 0)?;
    let first_frontend_job = source_pack_frontend_job_from_unit(
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
            - source_pack_library_schedule_index_frontend_job_count(index),
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
                source_pack_library_partition_contract_error(format!(
                    "schedule page {} frontend job offset {} overflows",
                    entry.partition_index, frontend_unit_offset
                ))
            })?;
        let phase_unit_index = first_frontend_unit_index
            .checked_add(frontend_unit_offset)
            .ok_or_else(|| {
                source_pack_library_partition_contract_error(format!(
                    "schedule page {} frontend phase-unit offset {} overflows",
                    entry.partition_index, frontend_unit_offset
                ))
            })?;
        let mut job = source_pack_frontend_job_from_unit(
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
        store_schedule_job_page_with_dependencies(
            store,
            index.target,
            index.job_count,
            &job,
            |writer| {
                source_pack_write_library_dependency_frontend_job_ranges(writer, store, partition)
            },
        )?;
    }

    let first_codegen_unit_index = entry.first_codegen_job_index
        - source_pack_library_schedule_index_frontend_job_count(index);
    for codegen_unit_offset in 0..entry.codegen_job_count {
        let unit_page = store.load_library_codegen_unit_page_for_target(
            index.target,
            entry.partition_index,
            codegen_unit_offset,
        )?;
        if codegen_unit_offset >= frontend_job_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule page {} codegen unit {} has no matching frontend unit among {}",
                entry.partition_index, codegen_unit_offset, frontend_job_count
            )));
        }
        let owning_frontend_job_index = entry
            .frontend_job_index
            .checked_add(codegen_unit_offset)
            .ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
                "schedule page {} owning frontend job offset {} overflows",
                entry.partition_index, codegen_unit_offset
            ))
        })?;
        let mut job = source_pack_codegen_job_from_unit(
            &page,
            &unit_page.unit,
            entry.first_codegen_job_index + codegen_unit_offset,
            first_codegen_unit_index + codegen_unit_offset,
            owning_frontend_job_index,
        );
        job.dependency_job_indices.clear();
        store_source_pack_library_schedule_codegen_job_locator(
            store,
            index,
            entry.partition_index,
            codegen_unit_offset,
            &job,
        )?;
        store_schedule_job_page_with_dependencies(
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
                        source_pack_library_partition_contract_error(format!(
                            "schedule page {} codegen unit {} exceeds frontend job count {}",
                            entry.partition_index, codegen_unit_offset, frontend_job_count
                        ))
                    })?;
                if remaining_frontend_job_count > 0 {
                    let first_following_frontend_job_index =
                        owning_frontend_job_index.checked_add(1).ok_or_else(|| {
                            source_pack_library_partition_contract_error(format!(
                                "schedule page {} following frontend dependency overflows",
                                entry.partition_index
                            ))
                        })?;
                    writer.push_range(
                        first_following_frontend_job_index,
                        remaining_frontend_job_count,
                    )?;
                }
                source_pack_write_library_dependency_frontend_job_ranges(writer, store, partition)
            },
        )?;
    }
    page.frontend_job.dependency_job_indices.clear();
    page.frontend_jobs = Vec::new();
    page.codegen_jobs = Vec::new();
    validate_source_pack_library_schedule_page(&page, index.target, Some(entry.partition_index))?;
    Ok(page)
}

pub(in crate::compiler) fn source_pack_frontend_job_from_unit(
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

pub(in crate::compiler) fn source_pack_codegen_job_from_unit(
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
