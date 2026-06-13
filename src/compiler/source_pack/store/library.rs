use super::*;

impl FilesystemArtifactStore {
    pub fn store_library_partition_page(
        &self,
        partition: &SourcePackLibraryPartition,
    ) -> Result<PathBuf, CompileError> {
        validate_library_partition(partition, partition.target, Some(partition.partition_index))?;
        if !partition.dependency_library_ids.is_empty()
            && (partition.dependency_library_count != 0 || partition.dependency_page_count != 0)
        {
            return Err(library_partition_contract_error(format!(
                "partition {} stores both inline and paged dependencies",
                partition.partition_index
            )));
        }
        let mut stored_partition = partition.clone();
        if !partition.dependency_library_ids.is_empty() {
            let (dependency_library_count, dependency_page_count) = store_partition_dependency_ids(
                self,
                partition.target,
                partition.partition_index,
                partition.library_id,
                partition.dependency_library_ids.len(),
                partition.dependency_library_ids.iter().copied(),
            )?;
            stored_partition.dependency_library_ids.clear();
            stored_partition.dependency_library_count = dependency_library_count;
            stored_partition.dependency_page_count = dependency_page_count;
        }
        validate_library_partition(
            &stored_partition,
            stored_partition.target,
            Some(stored_partition.partition_index),
        )?;
        let path =
            self.library_partition_path_for_target(partition.target, partition.partition_index);
        let bytes = serde_json::to_vec_pretty(&stored_partition).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library partition {}: {err}",
                partition.partition_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library partition")?;
        Ok(path)
    }

    pub fn store_library_dependency_page(
        &self,
        page: &SourcePackLibraryDependencyPage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_dependency_page(page, page.target, page.partition_index, page.page_index)?;
        let path = self.library_dependency_page_path_for_target(
            page.target,
            page.partition_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library dependency page {} for partition {}: {err}",
                page.page_index, page.partition_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library dependency page")?;
        Ok(path)
    }

    pub fn store_library_partition_compact_index(
        &self,
        index: &SourcePackLibraryPartitionIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_library_partition_index(index, index.target)?;
        let index_path = self.library_partition_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library partition index: {err}"
            ))
        })?;
        write_file_atomic(&index_path, &bytes, "source-pack library partition index")?;
        Ok(index_path)
    }

    pub fn load_library_partition_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackLibraryPartitionIndex, CompileError> {
        let path = self.library_partition_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library partition index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackLibraryPartitionIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library partition index {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_partition_index(&index, target)?;
        Ok(index)
    }

    pub fn store_library_metadata_prepare_progress(
        &self,
        progress: &FilesystemLibraryMetadataPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_library_metadata_prepare_progress(progress, progress.target)?;
        let path = self.library_metadata_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library metadata prepare progress: {err}"
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack library metadata prepare progress",
        )?;
        Ok(path)
    }

    pub fn load_library_metadata_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<FilesystemLibraryMetadataPrepareProgress, CompileError> {
        let path = self.library_metadata_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library metadata prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<FilesystemLibraryMetadataPrepareProgress>(&bytes)
            .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack library metadata prepare progress {}: {err}",
                path.display()
            ))
        })?;
        validate_library_metadata_prepare_progress(&progress, target)?;
        Ok(progress)
    }

    pub fn load_library_partition_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> Result<SourcePackLibraryPartition, CompileError> {
        let path = self.library_partition_path_for_target(target, partition_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library partition {}: {err}",
                path.display()
            ))
        })?;
        let partition =
            serde_json::from_slice::<SourcePackLibraryPartition>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library partition {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_partition(&partition, target, Some(partition_index))?;
        Ok(partition)
    }

    pub fn load_library_dependency_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        page_index: usize,
    ) -> Result<SourcePackLibraryDependencyPage, CompileError> {
        let path =
            self.library_dependency_page_path_for_target(target, partition_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library dependency page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibraryDependencyPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library dependency page {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_dependency_page(&page, target, partition_index, page_index)?;
        Ok(page)
    }

    pub fn store_library_partition_locator_page(
        &self,
        page: &SourcePackLibraryPartitionLocatorPage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_partition_locator_page(page, page.target, Some(page.library_id))?;
        let path =
            self.library_partition_locator_page_path_for_target(page.target, page.library_id);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library partition locator for library {}: {err}",
                page.library_id
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library partition locator")?;
        Ok(path)
    }

    pub fn load_library_partition_locator_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> Result<SourcePackLibraryPartitionLocatorPage, CompileError> {
        let path = self.library_partition_locator_page_path_for_target(target, library_id);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library partition locator {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackLibraryPartitionLocatorPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library partition locator {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_partition_locator_page(&page, target, Some(library_id))?;
        Ok(page)
    }

    pub fn store_library_source_file_page(
        &self,
        page: &SourcePackLibrarySourceFilePage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_source_file_page(page, page.target, Some(page.partition_index))?;
        for source_file in &page.source_files {
            self.store_library_source_file_record_page(&SourcePackLibrarySourceFileRecordPage {
                version: SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION,
                target: page.target,
                partition_index: page.partition_index,
                library_id: page.library_id,
                first_source_index: page.first_source_index,
                source_file_count: page.source_file_count,
                source_index: source_file.source_index,
                file: source_file.file.clone(),
            })?;
        }
        let mut stored_page = page.clone();
        stored_page.source_files.clear();
        validate_library_source_file_page(
            &stored_page,
            stored_page.target,
            Some(stored_page.partition_index),
        )?;
        let path = self.library_source_file_page_path_for_target(page.target, page.partition_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library source-file page {}: {err}",
                page.partition_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library source-file page")?;
        Ok(path)
    }

    pub fn load_library_source_file_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> Result<SourcePackLibrarySourceFilePage, CompileError> {
        let path = self.library_source_file_page_path_for_target(target, partition_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library source-file page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibrarySourceFilePage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library source-file page {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_source_file_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    pub fn store_library_source_file_record_page(
        &self,
        page: &SourcePackLibrarySourceFileRecordPage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_source_file_record_page(page, page.target, Some(page.source_index))?;
        let path =
            self.library_source_file_record_page_path_for_target(page.target, page.source_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library source-file record {}: {err}",
                page.source_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library source-file record")?;
        Ok(path)
    }

    pub fn load_library_source_file_record_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> Result<SourcePackLibrarySourceFileRecordPage, CompileError> {
        let path = self.library_source_file_record_page_path_for_target(target, source_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library source-file record {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackLibrarySourceFileRecordPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library source-file record {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_source_file_record_page(&page, target, Some(source_index))?;
        Ok(page)
    }

    pub fn store_library_build_unit_page(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_build_unit_page(page, page.target, Some(page.partition_index))?;
        let frontend_unit_count = if page.frontend_units.is_empty() {
            library_build_unit_page_frontend_unit_count(page)
        } else {
            self.store_library_frontend_unit_pages_from_units(page)?
        };
        let codegen_unit_count = if page.codegen_units.is_empty() {
            library_build_unit_page_codegen_unit_count(page)
        } else {
            self.store_library_codegen_unit_pages_from_units(page)?
        };
        let mut stored_page = page.clone();
        stored_page.frontend_unit_count = frontend_unit_count;
        stored_page.codegen_unit_count = codegen_unit_count;
        stored_page.dependency_library_ids.clear();
        stored_page.frontend_units.clear();
        stored_page.codegen_units.clear();
        validate_library_build_unit_page(
            &stored_page,
            stored_page.target,
            Some(stored_page.partition_index),
        )?;
        let path = self.library_build_unit_page_path_for_target(page.target, page.partition_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library build-unit page {}: {err}",
                page.partition_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library build-unit page")?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_library_frontend_unit_pages_from_units(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<usize, CompileError> {
        for unit in &page.frontend_units {
            let unit_page = library_frontend_unit_page(page, unit.clone())?;
            self.store_library_frontend_unit_page(&unit_page)?;
        }
        Ok(page.frontend_units.len())
    }

    pub(in crate::compiler) fn store_library_codegen_unit_pages_from_units(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<usize, CompileError> {
        for unit in &page.codegen_units {
            let unit_page = library_codegen_unit_page(page, unit.clone())?;
            self.store_library_codegen_unit_page(&unit_page)?;
        }
        Ok(page.codegen_units.len())
    }

    pub fn load_library_build_unit_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> Result<SourcePackLibraryBuildUnitPage, CompileError> {
        let path = self.library_build_unit_page_path_for_target(target, partition_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library build-unit page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibraryBuildUnitPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library build-unit page {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_build_unit_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    pub fn store_library_frontend_unit_page(
        &self,
        page: &SourcePackLibraryFrontendUnitPage,
    ) -> Result<PathBuf, CompileError> {
        validate_frontend_unit_page(
            page,
            page.target,
            Some(page.partition_index),
            Some(page.frontend_unit_index),
        )?;
        let path = self.library_frontend_unit_page_path_for_target(
            page.target,
            page.partition_index,
            page.frontend_unit_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library frontend-unit page {}:{}: {err}",
                page.partition_index, page.frontend_unit_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library frontend-unit page")?;
        Ok(path)
    }

    pub fn load_library_frontend_unit_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        frontend_unit_index: usize,
    ) -> Result<SourcePackLibraryFrontendUnitPage, CompileError> {
        let path = self.library_frontend_unit_page_path_for_target(
            target,
            partition_index,
            frontend_unit_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library frontend-unit page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibraryFrontendUnitPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library frontend-unit page {}: {err}",
                    path.display()
                ))
            })?;
        validate_frontend_unit_page(
            &page,
            target,
            Some(partition_index),
            Some(frontend_unit_index),
        )?;
        Ok(page)
    }

    pub fn store_library_codegen_unit_page(
        &self,
        page: &SourcePackLibraryCodegenUnitPage,
    ) -> Result<PathBuf, CompileError> {
        validate_codegen_unit_page(
            page,
            page.target,
            Some(page.partition_index),
            Some(page.codegen_unit_index),
        )?;
        let path = self.library_codegen_unit_page_path_for_target(
            page.target,
            page.partition_index,
            page.codegen_unit_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library codegen-unit page {}:{}: {err}",
                page.partition_index, page.codegen_unit_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library codegen-unit page")?;
        Ok(path)
    }

    pub fn load_library_codegen_unit_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        codegen_unit_index: usize,
    ) -> Result<SourcePackLibraryCodegenUnitPage, CompileError> {
        let path = self.library_codegen_unit_page_path_for_target(
            target,
            partition_index,
            codegen_unit_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library codegen-unit page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibraryCodegenUnitPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library codegen-unit page {}: {err}",
                    path.display()
                ))
            })?;
        validate_codegen_unit_page(
            &page,
            target,
            Some(partition_index),
            Some(codegen_unit_index),
        )?;
        Ok(page)
    }
}
