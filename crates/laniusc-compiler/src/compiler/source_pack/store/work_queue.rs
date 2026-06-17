use super::*;

impl FilesystemArtifactStore {
    pub fn load_work_queue_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackWorkQueueIndex, CompileError> {
        let path = self.work_queue_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackWorkQueueIndex>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack work queue index {}: {err}",
                path.display()
            ))
        })?;
        validate_work_queue_index(&index, target)?;
        Ok(index)
    }

    pub fn store_work_queue_page(
        &self,
        page: &SourcePackWorkQueuePage,
    ) -> Result<PathBuf, CompileError> {
        validate_work_queue_page_store_input(page, page.target, Some(page.item_index))?;
        let (dependency_item_count, dependency_page_count) =
            if page.dependency_item_indices.is_empty() {
                (page.dependency_item_count, page.dependency_page_count)
            } else {
                self.store_work_queue_dependency_pages_from_indices(
                    page.target,
                    page.item_index,
                    &page.dependency_item_indices,
                )?
            };
        let (dependent_item_count, dependent_page_count) = if page.dependent_item_indices.is_empty()
        {
            (page.dependent_item_count, page.dependent_page_count)
        } else {
            self.store_work_queue_dependent_pages_from_indices(
                page.target,
                page.item_index,
                &page.dependent_item_indices,
            )?
        };
        let partition_count = page.partition_count.max(page.partition_indices.len());
        let input_frontend_job_count = page
            .input_frontend_job_count
            .max(page.input_frontend_job_indices.len());
        let mut stored_page = page.clone();
        stored_page.dependency_item_indices.clear();
        stored_page.dependency_item_count = dependency_item_count;
        stored_page.dependency_page_count = dependency_page_count;
        stored_page.dependent_item_indices.clear();
        stored_page.dependent_item_count = dependent_item_count;
        stored_page.dependent_page_count = dependent_page_count;
        stored_page.input_frontend_job_count = input_frontend_job_count;
        stored_page.input_frontend_job_indices.clear();
        if matches!(stored_page.kind, SourcePackWorkQueueItemKind::LinkReduce) {
            stored_page.partition_count = partition_count;
            stored_page.partition_indices.clear();
        }
        validate_work_queue_page(&stored_page, page.target, Some(page.item_index))?;
        self.validate_work_queue_page_sidecars(&stored_page)?;
        let path = self.work_queue_page_path_for_target(page.target, page.item_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue page {}: {err}",
                page.item_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack work queue page")?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_work_queue_dependency_pages_from_indices(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        dependency_item_indices: &[usize],
    ) -> Result<(usize, usize), CompileError> {
        let mut seen = BTreeSet::new();
        let mut dependency_item_count = 0usize;
        let mut page_index = 0usize;
        let mut current_dependency_item_indices =
            Vec::with_capacity(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
        let flush = |page_index: &mut usize,
                     dependency_item_count: &mut usize,
                     current_dependency_item_indices: &mut Vec<usize>|
         -> Result<(), CompileError> {
            if current_dependency_item_indices.is_empty() {
                return Ok(());
            }
            let dependency_item_indices = std::mem::take(current_dependency_item_indices);
            let page = SourcePackWorkQueueDependenciesPage {
                version: SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
                target,
                item_index,
                page_index: *page_index,
                first_dependency_position: (*page_index)
                    .saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE),
                dependency_count: dependency_item_indices.len(),
                dependency_item_indices,
            };
            self.store_work_queue_dependencies_page(&page)?;
            *dependency_item_count = dependency_item_count.saturating_add(page.dependency_count);
            *page_index += 1;
            Ok(())
        };
        for &dependency_item_index in dependency_item_indices {
            if !seen.insert(dependency_item_index) {
                return Err(library_partition_contract_error(format!(
                    "work queue page {item_index} contains duplicate dependency item {dependency_item_index}"
                )));
            }
            current_dependency_item_indices.push(dependency_item_index);
            if current_dependency_item_indices.len()
                == SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE
            {
                flush(
                    &mut page_index,
                    &mut dependency_item_count,
                    &mut current_dependency_item_indices,
                )?;
            }
        }
        flush(
            &mut page_index,
            &mut dependency_item_count,
            &mut current_dependency_item_indices,
        )?;
        Ok((dependency_item_count, page_index))
    }

    pub(in crate::compiler) fn store_work_queue_dependent_pages_from_indices(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        dependent_item_indices: &[usize],
    ) -> Result<(usize, usize), CompileError> {
        let mut seen = BTreeSet::new();
        let mut dependent_item_count = 0usize;
        let mut page_index = 0usize;
        let mut current_dependent_item_indices =
            Vec::with_capacity(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
        let flush = |page_index: &mut usize,
                     dependent_item_count: &mut usize,
                     current_dependent_item_indices: &mut Vec<usize>|
         -> Result<(), CompileError> {
            if current_dependent_item_indices.is_empty() {
                return Ok(());
            }
            let dependent_item_indices = std::mem::take(current_dependent_item_indices);
            let page = SourcePackWorkQueueDependentsPage {
                version: SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
                target,
                item_index,
                page_index: *page_index,
                first_dependent_position: (*page_index)
                    .saturating_mul(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE),
                dependent_count: dependent_item_indices.len(),
                dependent_item_indices,
            };
            self.store_work_queue_dependents_page(&page)?;
            *dependent_item_count = dependent_item_count.saturating_add(page.dependent_count);
            *page_index += 1;
            Ok(())
        };
        for &dependent_item_index in dependent_item_indices {
            if !seen.insert(dependent_item_index) {
                return Err(library_partition_contract_error(format!(
                    "work queue page {item_index} contains duplicate dependent item {dependent_item_index}"
                )));
            }
            current_dependent_item_indices.push(dependent_item_index);
            if current_dependent_item_indices.len()
                == SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE
            {
                flush(
                    &mut page_index,
                    &mut dependent_item_count,
                    &mut current_dependent_item_indices,
                )?;
            }
        }
        flush(
            &mut page_index,
            &mut dependent_item_count,
            &mut current_dependent_item_indices,
        )?;
        Ok((dependent_item_count, page_index))
    }

    pub fn load_work_queue_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
    ) -> Result<SourcePackWorkQueuePage, CompileError> {
        let path = self.work_queue_page_path_for_target(target, item_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackWorkQueuePage>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack work queue page {}: {err}",
                path.display()
            ))
        })?;
        validate_work_queue_page(&page, target, Some(item_index))?;
        self.validate_work_queue_page_sidecars(&page)?;
        Ok(page)
    }

    fn validate_work_queue_page_sidecars(
        &self,
        page: &SourcePackWorkQueuePage,
    ) -> Result<(), CompileError> {
        self.validate_work_queue_dependency_sidecars(page)?;
        self.validate_work_queue_dependent_sidecars(page)?;
        Ok(())
    }

    fn validate_work_queue_dependency_sidecars(
        &self,
        page: &SourcePackWorkQueuePage,
    ) -> Result<(), CompileError> {
        let mut required_link_dependencies = required_link_dependency_items(page)?;

        for &dependency_item_index in &page.dependency_item_indices {
            required_link_dependencies.remove(&dependency_item_index);
        }
        for range in &page.dependency_item_ranges {
            let Some(indices) = range.iter() else {
                return Err(library_partition_contract_error(format!(
                    "work queue page {} dependency range starting at {} overflows usize",
                    page.item_index, range.first_job_index
                )));
            };
            for dependency_item_index in indices {
                required_link_dependencies.remove(&dependency_item_index);
            }
        }

        let mut streamed_dependency_count = 0usize;
        for page_index in 0..page.dependency_page_count {
            let dependency_page = self.load_work_queue_dependencies_page_for_target(
                page.target,
                page.item_index,
                page_index,
            )?;
            if dependency_page.first_dependency_position != streamed_dependency_count {
                return Err(library_partition_contract_error(format!(
                    "work queue dependencies page {} for item {} starts at {} but streamed {} dependencies",
                    page_index,
                    page.item_index,
                    dependency_page.first_dependency_position,
                    streamed_dependency_count
                )));
            }
            let remaining_dependency_count = page
                .dependency_item_count
                .checked_sub(streamed_dependency_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "work queue page {} streamed too many dependencies before page {}",
                        page.item_index, page_index
                    ))
                })?;
            let expected_page_dependency_count = remaining_dependency_count
                .min(SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE);
            if dependency_page.dependency_count != expected_page_dependency_count {
                return Err(library_partition_contract_error(format!(
                    "work queue dependencies page {} for item {} has {} dependencies but expected {}",
                    page_index,
                    page.item_index,
                    dependency_page.dependency_count,
                    expected_page_dependency_count
                )));
            }
            for dependency_item_index in dependency_page.dependency_item_indices {
                required_link_dependencies.remove(&dependency_item_index);
            }
            streamed_dependency_count = streamed_dependency_count
                .checked_add(dependency_page.dependency_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "work queue page {} dependency stream count overflows",
                        page.item_index
                    ))
                })?;
        }
        if streamed_dependency_count != page.dependency_item_count {
            return Err(library_partition_contract_error(format!(
                "work queue page {} streamed {} dependencies but expected {}",
                page.item_index, streamed_dependency_count, page.dependency_item_count
            )));
        }
        if !required_link_dependencies.is_empty() {
            let label = match page.kind {
                SourcePackWorkQueueItemKind::LinkLeaf => "codegen inputs",
                SourcePackWorkQueueItemKind::LinkReduce => "link-group input items",
                _ => "link inputs",
            };
            return Err(library_partition_contract_error(format!(
                "work queue {:?} page {} {label} {:?} are not listed as dependencies",
                page.kind, page.item_index, required_link_dependencies
            )));
        }
        Ok(())
    }

    fn validate_work_queue_dependent_sidecars(
        &self,
        page: &SourcePackWorkQueuePage,
    ) -> Result<(), CompileError> {
        let mut streamed_dependent_count = 0usize;
        for page_index in 0..page.dependent_page_count {
            let dependent_page = self.load_work_queue_dependents_page_for_target(
                page.target,
                page.item_index,
                page_index,
            )?;
            if dependent_page.first_dependent_position != streamed_dependent_count {
                return Err(library_partition_contract_error(format!(
                    "work queue dependents page {} for item {} starts at {} but streamed {} dependents",
                    page_index,
                    page.item_index,
                    dependent_page.first_dependent_position,
                    streamed_dependent_count
                )));
            }
            let remaining_dependent_count = page
                .dependent_item_count
                .checked_sub(streamed_dependent_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "work queue page {} streamed too many dependents before page {}",
                        page.item_index, page_index
                    ))
                })?;
            let expected_page_dependent_count =
                remaining_dependent_count.min(SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE);
            if dependent_page.dependent_count != expected_page_dependent_count {
                return Err(library_partition_contract_error(format!(
                    "work queue dependents page {} for item {} has {} dependents but expected {}",
                    page_index,
                    page.item_index,
                    dependent_page.dependent_count,
                    expected_page_dependent_count
                )));
            }
            streamed_dependent_count = streamed_dependent_count
                .checked_add(dependent_page.dependent_count)
                .ok_or_else(|| {
                    library_partition_contract_error(format!(
                        "work queue page {} dependent stream count overflows",
                        page.item_index
                    ))
                })?;
        }
        if streamed_dependent_count != page.dependent_item_count {
            return Err(library_partition_contract_error(format!(
                "work queue page {} streamed {} dependents but expected {}",
                page.item_index, streamed_dependent_count, page.dependent_item_count
            )));
        }
        Ok(())
    }

    pub fn store_work_queue_dependencies_page(
        &self,
        page: &SourcePackWorkQueueDependenciesPage,
    ) -> Result<PathBuf, CompileError> {
        validate_work_queue_dependencies_page(page, page.target, page.item_index, page.page_index)?;
        let path = self.work_queue_dependencies_page_path_for_target(
            page.target,
            page.item_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue dependencies page {} for item {}: {err}",
                page.page_index, page.item_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack work queue dependencies page")?;
        Ok(path)
    }

    pub fn load_work_queue_dependencies_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> Result<SourcePackWorkQueueDependenciesPage, CompileError> {
        let path =
            self.work_queue_dependencies_page_path_for_target(target, item_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue dependencies page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackWorkQueueDependenciesPage>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue dependencies page {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_work_queue_dependencies_page(&page, target, item_index, page_index)?;
        Ok(page)
    }

    pub fn store_work_queue_dependents_page(
        &self,
        page: &SourcePackWorkQueueDependentsPage,
    ) -> Result<PathBuf, CompileError> {
        validate_work_queue_dependents_page(page, page.target, page.item_index, page.page_index)?;
        let path = self.work_queue_dependents_page_path_for_target(
            page.target,
            page.item_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue dependents page {} for item {}: {err}",
                page.page_index, page.item_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack work queue dependents page")?;
        Ok(path)
    }

    pub fn load_work_queue_dependents_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> Result<SourcePackWorkQueueDependentsPage, CompileError> {
        let path = self.work_queue_dependents_page_path_for_target(target, item_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue dependents page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackWorkQueueDependentsPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue dependents page {}: {err}",
                    path.display()
                ))
            })?;
        validate_work_queue_dependents_page(&page, target, item_index, page_index)?;
        Ok(page)
    }

    pub fn store_work_queue_progress_index(
        &self,
        index: &SourcePackWorkQueueProgressIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_progress_index(index, index.target)?;
        let path = self.work_queue_progress_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress index: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack work queue progress index")?;
        Ok(path)
    }

    pub fn load_work_queue_progress_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackWorkQueueProgressIndex, CompileError> {
        let path = self.work_queue_progress_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue progress index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackWorkQueueProgressIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress index {}: {err}",
                    path.display()
                ))
            })?;
        validate_progress_index(&index, target)?;
        Ok(index)
    }

    pub fn store_work_queue_progress_page(
        &self,
        page: &SourcePackWorkQueueProgressPage,
    ) -> Result<PathBuf, CompileError> {
        validate_progress_page(page, page.target, Some(page.page_index))?;
        let path = self.work_queue_progress_page_path_for_target(page.target, page.page_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress page {}: {err}",
                page.page_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack work queue progress page")?;
        self.store_work_queue_progress_page_summary_for_target(
            page.target,
            &progress_page_summary(page),
        )?;
        Ok(path)
    }

    pub fn store_work_queue_progress_page_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        summary: &SourcePackWorkQueueProgressPageSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_progress_page_summary(summary)?;
        let path =
            self.work_queue_progress_page_summary_path_for_target(target, summary.page_index);
        let bytes = serde_json::to_vec_pretty(summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress page summary {}: {err}",
                summary.page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack work queue progress page summary",
        )?;
        Ok(path)
    }

    pub fn try_load_work_queue_progress_page_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> Result<Option<SourcePackWorkQueueProgressPageSummary>, CompileError> {
        let path = self.work_queue_progress_page_summary_path_for_target(target, page_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack work queue progress page summary {}: {err}",
                    path.display()
                )));
            }
        };
        let summary = serde_json::from_slice::<SourcePackWorkQueueProgressPageSummary>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress page summary {}: {err}",
                    path.display()
                ))
            })?;
        validate_progress_page_summary(&summary)?;
        Ok(Some(summary))
    }

    pub fn store_work_queue_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page: &SourcePackWorkQueueProgressDirectoryPage,
    ) -> Result<PathBuf, CompileError> {
        if page.target != target {
            return Err(library_partition_contract_error(format!(
                "work queue progress directory page {} target {:?} does not match requested target {:?}",
                page.directory_page_index, page.target, target
            )));
        }
        let path = self
            .work_queue_progress_directory_page_path_for_target(target, page.directory_page_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress directory page {}: {err}",
                page.directory_page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack work queue progress directory page",
        )?;
        Ok(path)
    }

    pub fn try_load_work_queue_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> Result<Option<SourcePackWorkQueueProgressDirectoryPage>, CompileError> {
        let path =
            self.work_queue_progress_directory_page_path_for_target(target, directory_page_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack work queue progress directory page {}: {err}",
                    path.display()
                )));
            }
        };
        let page = serde_json::from_slice::<SourcePackWorkQueueProgressDirectoryPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress directory page {}: {err}",
                    path.display()
                ))
            })?;
        Ok(Some(page))
    }

    pub fn store_work_queue_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page: &SourcePackWorkQueueProgressDirectoryIndexPage,
        index: &SourcePackWorkQueueProgressIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_progress_directory_index_page(page, target, index)?;
        let path = self.work_queue_progress_directory_index_page_path_for_target(
            target,
            page.directory_index_page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress directory-index page {}: {err}",
                page.directory_index_page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack work queue progress directory-index page",
        )?;
        Ok(path)
    }

    pub fn try_load_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> Result<Option<SourcePackWorkQueueProgressDirectoryIndexPage>, CompileError> {
        let path = self.work_queue_progress_directory_index_page_path_for_target(
            target,
            directory_index_page_index,
        );
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack work queue progress directory-index page {}: {err}",
                    path.display()
                )));
            }
        };
        let page = serde_json::from_slice::<SourcePackWorkQueueProgressDirectoryIndexPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress directory-index page {}: {err}",
                    path.display()
                ))
            })?;
        Ok(Some(page))
    }

    pub fn load_work_queue_progress_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> Result<SourcePackWorkQueueProgressPage, CompileError> {
        let path = self.work_queue_progress_page_path_for_target(target, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack work queue progress page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackWorkQueueProgressPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack work queue progress page {}: {err}",
                    path.display()
                ))
            })?;
        validate_progress_page(&page, target, Some(page_index))?;
        Ok(page)
    }
}

fn required_link_dependency_items(
    page: &SourcePackWorkQueuePage,
) -> Result<BTreeSet<usize>, CompileError> {
    match page.kind {
        SourcePackWorkQueueItemKind::LinkLeaf => Ok(page
            .input_codegen_job_indices
            .iter()
            .copied()
            .collect::<BTreeSet<_>>()),
        SourcePackWorkQueueItemKind::LinkReduce => {
            let link_group_index = page.link_group_index.ok_or_else(|| {
                library_partition_contract_error(format!(
                    "work queue link reduce page {} has no link group index",
                    page.item_index
                ))
            })?;
            let first_link_item_index = page.item_index.checked_sub(link_group_index).ok_or_else(
                || {
                    library_partition_contract_error(format!(
                        "work queue link reduce page {} link group {} cannot derive first link item",
                        page.item_index, link_group_index
                    ))
                },
            )?;
            let mut required = BTreeSet::new();
            for &input_group_index in &page.input_link_group_indices {
                let input_item_index = first_link_item_index
                    .checked_add(input_group_index)
                    .ok_or_else(|| {
                        library_partition_contract_error(format!(
                            "work queue link reduce page {} input link group {} overflows item index",
                            page.item_index, input_group_index
                        ))
                    })?;
                required.insert(input_item_index);
            }
            Ok(required)
        }
        _ => Ok(BTreeSet::new()),
    }
}
