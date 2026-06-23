use super::*;

impl FilesystemArtifactStore {
    /// Stores the compact index for build job-batch pages.
    pub fn store_build_job_batch_page_index(
        &self,
        index: &SourcePackBuildJobBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_page_index(index, index.target)?;
        let path = self.build_job_batch_index_path_for_target(index.target);
        let bytes = serialize_store_json(index, "source-pack job-batch page index")?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch page index")?;
        Ok(path)
    }

    /// Loads and validates the build job-batch page index for a target.
    pub fn load_build_job_batch_page_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildJobBatchPageIndex, CompileError> {
        let path = self.build_job_batch_index_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack job-batch page index")?;
        let index = parse_store_json::<SourcePackBuildJobBatchPageIndex>(
            &bytes,
            &path,
            "source-pack job-batch page index",
        )?;
        validate_job_batch_page_index(&index, target)?;
        Ok(index)
    }

    /// Stores the resumable cursor for job-batch preparation.
    pub(in crate::compiler) fn store_build_job_batch_prepare_progress(
        &self,
        progress: &JobBatchPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_build_job_batch_prepare_progress(
            progress,
            progress.target,
            progress.scheduled_job_count,
            progress.batch_limits,
        )?;
        let path = self.build_job_batch_prepare_progress_path_for_target(progress.target);
        let bytes = serialize_store_json(progress, "source-pack job-batch prepare progress")?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch prepare progress")?;
        Ok(path)
    }

    /// Loads and validates the job-batch preparation cursor.
    pub(in crate::compiler) fn load_build_job_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        scheduled_job_count: usize,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<JobBatchPrepareProgress, CompileError> {
        let path = self.build_job_batch_prepare_progress_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack job-batch prepare progress")?;
        let progress = parse_store_json::<JobBatchPrepareProgress>(
            &bytes,
            &path,
            "source-pack job-batch prepare progress",
        )?;
        validate_build_job_batch_prepare_progress(
            &progress,
            target,
            scheduled_job_count,
            batch_limits,
        )?;
        Ok(progress)
    }

    /// Stores one job-batch page, paging dependency lists and ranges.
    pub fn store_build_job_batch_page(
        &self,
        page: &SourcePackBuildJobBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_page_store_input(page, page.target, Some(page.batch_index))?;
        let (dependency_batch_count, dependency_page_count) =
            store_job_batch_dependency_pages(self, page.target, &page.dependency)?;
        let (dependency_range_count, dependency_range_page_count, dependency_range_batch_count) =
            store_job_batch_dependency_range_pages(self, page.target, &page.dependency)?;
        let mut stored_page = page.clone();
        stored_page.dependency.dependency_batch_indices.clear();
        stored_page.dependency.dependency_batch_count = dependency_batch_count;
        stored_page.dependency.dependency_page_count = dependency_page_count;
        stored_page.dependency.dependency_batch_ranges.clear();
        stored_page.dependency.dependency_range_count = dependency_range_count;
        stored_page.dependency.dependency_range_page_count = dependency_range_page_count;
        stored_page.dependency.dependency_range_batch_count = dependency_range_batch_count;
        validate_job_batch_page(
            &stored_page,
            stored_page.target,
            Some(stored_page.batch_index),
        )?;
        let path = self.build_job_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serialize_store_json(
            &stored_page,
            format!("source-pack job-batch page {}", page.batch_index),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch page")?;
        Ok(path)
    }

    /// Loads and validates one job-batch page.
    pub fn load_build_job_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildJobBatchPage, CompileError> {
        let path = self.build_job_batch_page_path_for_target(target, batch_index);
        let bytes = read_store_file(&path, "source-pack job-batch page")?;
        let page = parse_store_json::<SourcePackBuildJobBatchPage>(
            &bytes,
            &path,
            "source-pack job-batch page",
        )?;
        validate_job_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    /// Stores one explicit dependency-batch sidecar page.
    pub fn store_build_job_batch_dependency_page(
        &self,
        page: &SourcePackBuildJobBatchDependencyPage,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_dependency_page(page, page.target, page.batch_index, page.page_index)?;
        let path = self.build_job_batch_dependency_page_path_for_target(
            page.target,
            page.batch_index,
            page.page_index,
        );
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack job-batch dependency page {} for batch {}",
                page.page_index, page.batch_index
            ),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch dependency page")?;
        Ok(path)
    }

    /// Loads and validates one explicit dependency-batch sidecar page.
    pub fn load_build_job_batch_dependency_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> Result<SourcePackBuildJobBatchDependencyPage, CompileError> {
        let path =
            self.build_job_batch_dependency_page_path_for_target(target, batch_index, page_index);
        let bytes = read_store_file(&path, "source-pack job-batch dependency page")?;
        let page = parse_store_json::<SourcePackBuildJobBatchDependencyPage>(
            &bytes,
            &path,
            "source-pack job-batch dependency page",
        )?;
        validate_job_batch_dependency_page(&page, target, batch_index, page_index)?;
        Ok(page)
    }

    /// Stores one dependency-batch range sidecar page.
    pub fn store_build_job_batch_dependency_range_page(
        &self,
        page: &SourcePackBuildJobBatchDependencyRangePage,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_dependency_range_page(
            page,
            page.target,
            page.batch_index,
            page.page_index,
        )?;
        let path = self.build_job_batch_dependency_range_page_path_for_target(
            page.target,
            page.batch_index,
            page.page_index,
        );
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack job-batch dependency range page {} for batch {}",
                page.page_index, page.batch_index
            ),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch dependency range page")?;
        Ok(path)
    }

    /// Loads and validates one dependency-batch range sidecar page.
    pub fn load_build_job_batch_dependency_range_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> Result<SourcePackBuildJobBatchDependencyRangePage, CompileError> {
        let path = self.build_job_batch_dependency_range_page_path_for_target(
            target,
            batch_index,
            page_index,
        );
        let bytes = read_store_file(&path, "source-pack job-batch dependency range page")?;
        let page = parse_store_json::<SourcePackBuildJobBatchDependencyRangePage>(
            &bytes,
            &path,
            "source-pack job-batch dependency range page",
        )?;
        validate_job_batch_dependency_range_page(&page, target, batch_index, page_index)?;
        Ok(page)
    }

    /// Stores the dependent-batch summary page for one job batch.
    ///
    /// Inline dependent lists are split into fixed-size dependent-batch pages
    /// before the compact count page is written.
    pub fn store_build_job_batch_dependents_page(
        &self,
        page: &SourcePackBuildJobBatchDependentsPage,
        batch_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_dependents_page_store_input(
            page,
            page.target,
            batch_count,
            Some(page.batch_index),
        )?;
        let (dependent_batch_count, dependent_page_count) =
            if page.dependents.dependent_batch_indices.is_empty() {
                (page.dependent_batch_count, page.dependent_page_count)
            } else {
                self.store_build_job_batch_dependent_pages_from_indices(
                    page.target,
                    page.batch_index,
                    batch_count,
                    &page.dependents.dependent_batch_indices,
                )?
            };
        let mut stored_page = page.clone();
        stored_page.dependents.dependent_batch_indices.clear();
        stored_page.dependent_batch_count = dependent_batch_count;
        stored_page.dependent_page_count = dependent_page_count;
        validate_job_batch_dependents_page(
            &stored_page,
            stored_page.target,
            batch_count,
            Some(stored_page.batch_index),
        )?;
        let path =
            self.build_job_batch_dependents_page_path_for_target(page.target, page.batch_index);
        let bytes = serialize_store_json(
            &stored_page,
            format!("source-pack job-batch dependents page {}", page.batch_index),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch dependents page")?;
        Ok(path)
    }

    /// Splits dependent batch indices into fixed-size sidecar pages.
    pub(in crate::compiler) fn store_build_job_batch_dependent_pages_from_indices(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        batch_count: usize,
        dependent_batch_indices: &[usize],
    ) -> Result<(usize, usize), CompileError> {
        let mut seen = BTreeSet::new();
        for (page_index, chunk) in dependent_batch_indices
            .chunks(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            for &dependent_batch_index in chunk {
                if !seen.insert(dependent_batch_index) {
                    return Err(artifact_shard_contract_error(format!(
                        "job-batch dependents page {batch_index} contains duplicate dependent batch {dependent_batch_index}"
                    )));
                }
            }
            let page = SourcePackBuildJobBatchDependentBatchPage {
                version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION,
                target,
                batch_count,
                batch_index,
                page_index,
                first_dependent_position: page_index
                    .saturating_mul(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE),
                dependent_count: chunk.len(),
                dependent_batch_indices: chunk.to_vec(),
            };
            self.store_build_job_batch_dependent_batch_page(&page, batch_count)?;
        }
        Ok((
            dependent_batch_indices.len(),
            dependent_batch_indices
                .len()
                .div_ceil(SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE),
        ))
    }

    /// Loads and validates the dependent-batch summary page for one job batch.
    pub fn load_build_job_batch_dependents_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        batch_count: usize,
    ) -> Result<SourcePackBuildJobBatchDependentsPage, CompileError> {
        let path = self.build_job_batch_dependents_page_path_for_target(target, batch_index);
        let Some(bytes) = try_read_store_file(&path, "source-pack job-batch dependents page")?
        else {
            let first_dependent_page_path =
                self.build_job_batch_dependent_batch_page_path_for_target(target, batch_index, 0);
            if first_dependent_page_path.is_file() {
                return Err(source_pack_store_metadata_error(format!(
                    "read source-pack job-batch dependents page {}: missing count page but dependent-batch pages exist",
                    path.display()
                )));
            }
            return empty_build_job_batch_dependents_page(target, batch_index, batch_count);
        };
        let page = parse_store_json::<SourcePackBuildJobBatchDependentsPage>(
            &bytes,
            &path,
            "source-pack job-batch dependents page",
        )?;
        validate_job_batch_dependents_page(&page, target, batch_count, Some(batch_index))?;
        Ok(page)
    }

    /// Stores one dependent-batch sidecar page.
    pub fn store_build_job_batch_dependent_batch_page(
        &self,
        page: &SourcePackBuildJobBatchDependentBatchPage,
        batch_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_dependent_batch_page(
            page,
            page.target,
            batch_count,
            page.batch_index,
            page.page_index,
        )?;
        let path = self.build_job_batch_dependent_batch_page_path_for_target(
            page.target,
            page.batch_index,
            page.page_index,
        );
        let bytes = serialize_store_json(
            page,
            format!(
                "source-pack job-batch dependent-batch page {} for batch {}",
                page.page_index, page.batch_index
            ),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch dependent-batch page")?;
        Ok(path)
    }

    /// Loads and validates one dependent-batch sidecar page.
    pub fn load_build_job_batch_dependent_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
        batch_count: usize,
    ) -> Result<SourcePackBuildJobBatchDependentBatchPage, CompileError> {
        let path = self.build_job_batch_dependent_batch_page_path_for_target(
            target,
            batch_index,
            page_index,
        );
        let bytes = read_store_file(&path, "source-pack job-batch dependent-batch page")?;
        let page = parse_store_json::<SourcePackBuildJobBatchDependentBatchPage>(
            &bytes,
            &path,
            "source-pack job-batch dependent-batch page",
        )?;
        validate_job_batch_dependent_batch_page(
            &page,
            target,
            batch_count,
            batch_index,
            page_index,
        )?;
        Ok(page)
    }

    /// Stores the locator mapping one scheduled job to its job batch.
    pub fn store_build_job_batch_job_locator_page(
        &self,
        page: &SourcePackBuildJobBatchJobLocatorPage,
        scheduled_job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_locator_page(
            page,
            page.target,
            scheduled_job_count,
            Some(page.job_index),
        )?;
        let path =
            self.build_job_batch_job_locator_page_path_for_target(page.target, page.job_index);
        let bytes = serialize_store_json(
            page,
            format!("source-pack job-batch job-locator page {}", page.job_index),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack job-batch job-locator page")?;
        Ok(path)
    }

    /// Loads and validates the job-batch locator for one scheduled job.
    pub fn load_build_job_batch_job_locator_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        scheduled_job_count: usize,
    ) -> Result<SourcePackBuildJobBatchJobLocatorPage, CompileError> {
        let path = self.build_job_batch_job_locator_page_path_for_target(target, job_index);
        let bytes = read_store_file(&path, "source-pack job-batch job-locator page")?;
        let page = parse_store_json::<SourcePackBuildJobBatchJobLocatorPage>(
            &bytes,
            &path,
            "source-pack job-batch job-locator page",
        )?;
        validate_job_batch_locator_page(&page, target, scheduled_job_count, Some(job_index))?;
        Ok(page)
    }
}
