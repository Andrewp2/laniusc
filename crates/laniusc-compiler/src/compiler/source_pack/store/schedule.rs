use super::*;

impl FilesystemArtifactStore {
    /// Stores the compact index for all scheduled library jobs.
    pub fn store_library_schedule_index(
        &self,
        index: &SourcePackLibraryScheduleIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_library_schedule_index(index, index.target)?;
        let path = self.library_schedule_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule index: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library schedule index")?;
        Ok(path)
    }

    /// Loads and validates the library schedule index for a target.
    pub fn load_library_schedule_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackLibraryScheduleIndex, CompileError> {
        let path = self.library_schedule_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackLibraryScheduleIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule index {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_schedule_index(&index, target)?;
        Ok(index)
    }

    /// Stores the resumable cursor for library schedule preparation.
    pub fn store_library_schedule_prepare_progress(
        &self,
        progress: &FilesystemLibrarySchedulePrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_library_schedule_prepare_progress(progress, progress.target)?;
        let path = self.library_schedule_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule prepare progress: {err}"
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack library schedule prepare progress",
        )?;
        Ok(path)
    }

    /// Loads and validates the library schedule preparation cursor.
    pub fn load_library_schedule_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<FilesystemLibrarySchedulePrepareProgress, CompileError> {
        let path = self.library_schedule_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<FilesystemLibrarySchedulePrepareProgress>(&bytes)
            .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack library schedule prepare progress {}: {err}",
                path.display()
            ))
        })?;
        validate_library_schedule_prepare_progress(&progress, target)?;
        Ok(progress)
    }

    /// Stores the compact schedule page for one library partition.
    ///
    /// Inline frontend/codegen jobs are expanded into job records and locator
    /// pages before the compact partition page is written.
    pub fn store_library_schedule_page(
        &self,
        page: &SourcePackLibrarySchedulePage,
    ) -> Result<PathBuf, CompileError> {
        validate_library_schedule_page(page, page.target, Some(page.partition_index))?;
        let job_count = page.link_job_index.checked_add(1).ok_or_else(|| {
            library_partition_contract_error(format!(
                "schedule page {} link job index overflows job count",
                page.partition_index
            ))
        })?;
        self.store_library_frontend_job_locator_page(&SourcePackLibraryFrontendJobLocatorPage {
            version: SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION,
            target: page.target,
            library_id: page.library_id,
            partition_index: page.partition_index,
            frontend_job_index: page.frontend_job_index,
            frontend_job_count: library_schedule_page_frontend_job_count(page),
        })?;
        if !page.frontend_jobs.is_empty() || !page.codegen_jobs.is_empty() {
            if page.frontend_jobs.is_empty() {
                self.store_schedule_page_job_record(
                    &page.frontend_job,
                    page.target,
                    page.partition_index,
                    None,
                    job_count,
                )?;
            } else {
                for job in &page.frontend_jobs {
                    self.store_schedule_page_job_record(
                        job,
                        page.target,
                        page.partition_index,
                        None,
                        job_count,
                    )?;
                }
            }
            for (codegen_job_offset, job) in page.codegen_jobs.iter().enumerate() {
                self.store_schedule_page_job_record(
                    job,
                    page.target,
                    page.partition_index,
                    Some(codegen_job_offset),
                    job_count,
                )?;
            }
        }
        let mut stored_page = page.clone();
        stored_page.dependency_library_ids.clear();
        stored_page.frontend_job.dependency_job_indices.clear();
        stored_page.frontend_jobs.clear();
        stored_page.codegen_jobs.clear();
        validate_library_schedule_page(
            &stored_page,
            stored_page.target,
            Some(stored_page.partition_index),
        )?;
        let path = self.library_schedule_page_path_for_target(page.target, page.partition_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule page {}: {err}",
                page.partition_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library schedule page")?;
        Ok(path)
    }

    /// Stores one schedule job record plus its job-locator page.
    pub(in crate::compiler) fn store_schedule_page_job_record(
        &self,
        job: &SourcePackJob,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        codegen_job_offset: Option<usize>,
        job_count: usize,
    ) -> Result<(), CompileError> {
        let locator = SourcePackLibraryScheduleJobLocatorPage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
            target,
            job_index: job.job_index,
            phase: job.phase,
            partition_index: Some(partition_index),
            codegen_job_offset,
        };
        self.store_library_schedule_job_locator_page(&locator, job_count)?;
        let page = SourcePackLibraryScheduleJobPage {
            version: SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
            target,
            job_index: job.job_index,
            job: job.clone(),
            dependency_job_count: 0,
            dependency_page_count: 0,
            dependency_job_ranges: Vec::new(),
        };
        self.store_library_schedule_job_page(&page, job_count)?;
        Ok(())
    }

    /// Loads and validates the compact schedule page for one partition.
    pub fn load_library_schedule_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> Result<SourcePackLibrarySchedulePage, CompileError> {
        let path = self.library_schedule_page_path_for_target(target, partition_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibrarySchedulePage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule page {}: {err}",
                    path.display()
                ))
            })?;
        validate_library_schedule_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    /// Stores the locator from library id to frontend job range.
    pub fn store_library_frontend_job_locator_page(
        &self,
        page: &SourcePackLibraryFrontendJobLocatorPage,
    ) -> Result<PathBuf, CompileError> {
        validate_frontend_job_locator_page(page, page.target, Some(page.library_id))?;
        let path =
            self.library_frontend_job_locator_page_path_for_target(page.target, page.library_id);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library frontend-job locator for library {}: {err}",
                page.library_id
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library frontend-job locator")?;
        Ok(path)
    }

    /// Loads and validates the frontend-job locator for one library id.
    pub fn load_library_frontend_job_locator_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> Result<SourcePackLibraryFrontendJobLocatorPage, CompileError> {
        let path = self.library_frontend_job_locator_page_path_for_target(target, library_id);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library frontend-job locator {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackLibraryFrontendJobLocatorPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library frontend-job locator {}: {err}",
                    path.display()
                ))
            })?;
        validate_frontend_job_locator_page(&page, target, Some(library_id))?;
        Ok(page)
    }

    /// Stores the compact index for job-locator pages.
    pub fn store_library_schedule_job_locator_index(
        &self,
        index: &SourcePackLibraryScheduleJobLocatorIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_schedule_job_locator_index(index, index.target)?;
        let path = self.library_schedule_job_locator_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job-locator index: {err}"
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack library schedule job-locator index",
        )?;
        Ok(path)
    }

    /// Stores one global job-index locator page.
    pub fn store_library_schedule_job_locator_page(
        &self,
        page: &SourcePackLibraryScheduleJobLocatorPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_schedule_job_locator_page(page, page.target, job_count, Some(page.job_index))?;
        let path =
            self.library_schedule_job_locator_page_path_for_target(page.target, page.job_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job-locator page {}: {err}",
                page.job_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack library schedule job-locator page",
        )?;
        Ok(path)
    }

    /// Loads and validates one global job-index locator page.
    pub fn load_library_schedule_job_locator_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        job_count: usize,
    ) -> Result<SourcePackLibraryScheduleJobLocatorPage, CompileError> {
        let path = self.library_schedule_job_locator_page_path_for_target(target, job_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule job-locator page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackLibraryScheduleJobLocatorPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule job-locator page {}: {err}",
                    path.display()
                ))
            })?;
        validate_schedule_job_locator_page(&page, target, job_count, Some(job_index))?;
        Ok(page)
    }

    /// Stores one schedule job page, paging dependency lists when necessary.
    pub fn store_library_schedule_job_page(
        &self,
        page: &SourcePackLibraryScheduleJobPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_schedule_job_page(page, page.target, job_count, Some(page.job_index))?;
        if page.dependency_job_count != 0 || page.dependency_page_count != 0 {
            return Err(library_partition_contract_error(format!(
                "schedule job page {} is already paged; write it directly instead of re-storing dependencies",
                page.job_index
            )));
        }
        store_schedule_job_with_dependencies(self, page.target, job_count, &page.job, |writer| {
            for range in &page.dependency_job_ranges {
                writer.push_range(range.first_job_index, range.job_count)?;
            }
            for &dependency_job_index in &page.job.dependency_job_indices {
                writer.push(dependency_job_index)?;
            }
            Ok(())
        })
    }

    /// Writes an already-paged schedule job page directly.
    pub(in crate::compiler) fn write_library_schedule_job_page_file(
        &self,
        page: &SourcePackLibraryScheduleJobPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_schedule_job_page(page, page.target, job_count, Some(page.job_index))?;
        let path = self.library_schedule_job_page_path_for_target(page.target, page.job_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job page {}: {err}",
                page.job_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack library schedule job page")?;
        Ok(path)
    }

    /// Stores one dependency sidecar page for a schedule job.
    pub fn store_library_schedule_job_dependency_page(
        &self,
        page: &SourcePackLibraryScheduleJobDependencyPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_schedule_job_dependency_page(
            page,
            page.target,
            job_count,
            page.job_index,
            page.page_index,
        )?;
        let path = self.library_schedule_job_dependency_page_path_for_target(
            page.target,
            page.job_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job dependency page {} for job {}: {err}",
                page.page_index, page.job_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack library schedule job dependency page",
        )?;
        Ok(path)
    }

    /// Loads and validates one schedule-job dependency sidecar page.
    pub fn load_library_schedule_job_dependency_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
        job_count: usize,
    ) -> Result<SourcePackLibraryScheduleJobDependencyPage, CompileError> {
        let path = self
            .library_schedule_job_dependency_page_path_for_target(target, job_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule job dependency page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackLibraryScheduleJobDependencyPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule job dependency page {}: {err}",
                    path.display()
                ))
            })?;
        validate_schedule_job_dependency_page(&page, target, job_count, job_index, page_index)?;
        Ok(page)
    }

    /// Loads and validates one schedule job page.
    pub fn load_library_schedule_job_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        job_count: usize,
    ) -> Result<SourcePackLibraryScheduleJobPage, CompileError> {
        let path = self.library_schedule_job_page_path_for_target(target, job_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule job page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackLibraryScheduleJobPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule job page {}: {err}",
                    path.display()
                ))
            })?;
        validate_schedule_job_page(&page, target, job_count, Some(job_index))?;
        Ok(page)
    }
}
