use super::*;

impl FilesystemArtifactStore {
    pub fn store_build_job_batch_page_index(
        &self,
        index: &SourcePackBuildJobBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_job_batch_page_index(index, index.target)?;
        let path = self.build_job_batch_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack job-batch page index: {err}"))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch page index")?;
        Ok(path)
    }

    pub fn load_build_job_batch_page_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildJobBatchPageIndex, CompileError> {
        let path = self.build_job_batch_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch page index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackBuildJobBatchPageIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch page index {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_page_index(&index, target)?;
        Ok(index)
    }

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
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch prepare progress: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch prepare progress")?;
        Ok(path)
    }

    pub(in crate::compiler) fn load_build_job_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        scheduled_job_count: usize,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<JobBatchPrepareProgress, CompileError> {
        let path = self.build_job_batch_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress =
            serde_json::from_slice::<JobBatchPrepareProgress>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_job_batch_prepare_progress(
            &progress,
            target,
            scheduled_job_count,
            batch_limits,
        )?;
        Ok(progress)
    }

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
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch page {}: {err}",
                page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch page")?;
        Ok(path)
    }

    pub fn load_build_job_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildJobBatchPage, CompileError> {
        let path = self.build_job_batch_page_path_for_target(target, batch_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackBuildJobBatchPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

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
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch dependency page {} for batch {}: {err}",
                page.page_index, page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch dependency page")?;
        Ok(path)
    }

    pub fn load_build_job_batch_dependency_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> Result<SourcePackBuildJobBatchDependencyPage, CompileError> {
        let path =
            self.build_job_batch_dependency_page_path_for_target(target, batch_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch dependency page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildJobBatchDependencyPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch dependency page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_dependency_page(&page, target, batch_index, page_index)?;
        Ok(page)
    }

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
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch dependency range page {} for batch {}: {err}",
                page.page_index, page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch dependency range page")?;
        Ok(path)
    }

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
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch dependency range page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildJobBatchDependencyRangePage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch dependency range page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_dependency_range_page(&page, target, batch_index, page_index)?;
        Ok(page)
    }

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
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch dependents page {}: {err}",
                page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch dependents page")?;
        Ok(path)
    }

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

    pub fn load_build_job_batch_dependents_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        batch_count: usize,
    ) -> Result<SourcePackBuildJobBatchDependentsPage, CompileError> {
        let path = self.build_job_batch_dependents_page_path_for_target(target, batch_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                let first_dependent_page_path = self
                    .build_job_batch_dependent_batch_page_path_for_target(target, batch_index, 0);
                if first_dependent_page_path.is_file() {
                    return Err(CompileError::GpuFrontend(format!(
                        "read source-pack job-batch dependents page {}: missing count page but dependent-batch pages exist",
                        path.display()
                    )));
                }
                return empty_build_job_batch_dependents_page(target, batch_index, batch_count);
            }
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack job-batch dependents page {}: {err}",
                    path.display()
                )));
            }
        };
        let page = serde_json::from_slice::<SourcePackBuildJobBatchDependentsPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch dependents page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_dependents_page(&page, target, batch_count, Some(batch_index))?;
        Ok(page)
    }

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
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch dependent-batch page {} for batch {}: {err}",
                page.page_index, page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch dependent-batch page")?;
        Ok(path)
    }

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
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch dependent-batch page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildJobBatchDependentBatchPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch dependent-batch page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_dependent_batch_page(
            &page,
            target,
            batch_count,
            batch_index,
            page_index,
        )?;
        Ok(page)
    }

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
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job-batch job-locator page {}: {err}",
                page.job_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack job-batch job-locator page")?;
        Ok(path)
    }

    pub fn load_build_job_batch_job_locator_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        scheduled_job_count: usize,
    ) -> Result<SourcePackBuildJobBatchJobLocatorPage, CompileError> {
        let path = self.build_job_batch_job_locator_page_path_for_target(target, job_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch job-locator page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildJobBatchJobLocatorPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch job-locator page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_batch_locator_page(&page, target, scheduled_job_count, Some(job_index))?;
        Ok(page)
    }
}
