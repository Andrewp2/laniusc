use super::*;

impl FilesystemArtifactStore {
    /// Stores the resumable artifact-ref preparation checkpoint.
    ///
    /// The checkpoint is validated against the schedule and partition indices
    /// before it is written so stale progress cannot be resumed silently.
    pub(in crate::compiler) fn store_build_artifact_ref_prepare_progress(
        &self,
        progress: &ArtifactRefPrepareProgress,
        schedule_index: &SourcePackLibraryScheduleIndex,
        library_partition_index: &SourcePackLibraryPartitionIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_build_artifact_ref_prepare_progress(
            progress,
            schedule_index,
            library_partition_index,
        )?;
        let path = self.build_artifact_ref_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack artifact-ref prepare progress: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack artifact-ref prepare progress")?;
        Ok(path)
    }

    /// Loads and validates artifact-ref preparation progress for a target.
    ///
    /// Validation ties the checkpoint back to the current schedule and library
    /// partition indices before callers continue writing artifact refs.
    pub(in crate::compiler) fn load_build_artifact_ref_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        schedule_index: &SourcePackLibraryScheduleIndex,
        library_partition_index: &SourcePackLibraryPartitionIndex,
    ) -> Result<ArtifactRefPrepareProgress, CompileError> {
        let path = self.build_artifact_ref_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack artifact-ref prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress =
            serde_json::from_slice::<ArtifactRefPrepareProgress>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack artifact-ref prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_artifact_ref_prepare_progress(
            &progress,
            schedule_index,
            library_partition_index,
        )?;
        Ok(progress)
    }

    /// Stores the top-level artifact-ref index.
    ///
    /// The index summarizes how many artifacts exist and how they split across
    /// interface, object, and linked-output kinds.
    pub fn store_build_artifact_ref_index(
        &self,
        index: &SourcePackBuildArtifactRefIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_artifact_ref_index(index, index.target)?;
        let path = self.build_artifact_ref_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack artifact-ref index: {err}"))
        })?;
        write_file_atomic(&path, &bytes, "source-pack artifact-ref index")?;
        Ok(path)
    }

    /// Loads the top-level artifact-ref index for a target.
    pub fn load_build_artifact_ref_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactRefIndex, CompileError> {
        let path = self.build_artifact_ref_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack artifact-ref index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackBuildArtifactRefIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack artifact-ref index {}: {err}",
                    path.display()
                ))
            })?;
        validate_artifact_ref_index(&index, target)?;
        Ok(index)
    }

    /// Stores one artifact-ref page by artifact index.
    ///
    /// Artifact-ref pages are the durable mapping from artifact index to key,
    /// kind, producing job, and source provenance.
    pub fn store_build_artifact_ref_page(
        &self,
        page: &SourcePackBuildArtifactRefPage,
        artifact_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_artifact_ref_page(page, page.target, artifact_count, Some(page.artifact_index))?;
        let path = self.build_artifact_ref_page_path_for_target(page.target, page.artifact_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack artifact-ref page {}: {err}",
                page.artifact_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack artifact-ref page")?;
        Ok(path)
    }

    /// Loads and validates one artifact-ref page by artifact index.
    pub fn load_build_artifact_ref_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
        artifact_count: usize,
    ) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
        let path = self.build_artifact_ref_page_path_for_target(target, artifact_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack artifact-ref page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackBuildArtifactRefPage>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack artifact-ref page {}: {err}",
                    path.display()
                ))
            })?;
        validate_artifact_ref_page(&page, target, artifact_count, Some(artifact_index))?;
        Ok(page)
    }

    /// Stores a paged chunk of library-interface inputs for a job artifact manifest.
    ///
    /// These sidecar pages are used when a job has too many interface inputs to
    /// keep inline in its manifest row.
    pub fn store_job_artifact_input_interface_page(
        &self,
        page: &SourcePackJobArtifactInputInterfacePage,
    ) -> Result<PathBuf, CompileError> {
        validate_job_artifact_input_interface_page(
            page,
            page.target,
            page.job_index,
            page.page_index,
        )?;
        let path = self.job_artifact_input_interface_page_path_for_target(
            page.target,
            page.job_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack job artifact input interface page {}:{}: {err}",
                page.job_index, page.page_index
            ))
        })?;
        write_file_atomic(
            &path,
            &bytes,
            "source-pack job artifact input interface page",
        )?;
        Ok(path)
    }

    /// Loads a paged chunk of library-interface inputs for a job artifact manifest.
    pub fn load_job_artifact_input_interface_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> Result<SourcePackJobArtifactInputInterfacePage, CompileError> {
        let path =
            self.job_artifact_input_interface_page_path_for_target(target, job_index, page_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job artifact input interface page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackJobArtifactInputInterfacePage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job artifact input interface page {}: {err}",
                    path.display()
                ))
            })?;
        validate_job_artifact_input_interface_page(&page, target, job_index, page_index)?;
        Ok(page)
    }
}
