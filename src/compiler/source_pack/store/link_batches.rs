use super::*;

impl FilesystemArtifactStore {
    pub fn store_build_link_batch_page_index(
        &self,
        index: &SourcePackBuildLinkBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_link_batch_page_index(index, index.target)?;
        let path = self.build_link_batch_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-batch page index: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack link-batch page index")?;
        Ok(path)
    }

    pub fn load_build_link_batch_page_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildLinkBatchPageIndex, CompileError> {
        let path = self.build_link_batch_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link-batch page index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackBuildLinkBatchPageIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link-batch page index {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_batch_page_index(&index, target)?;
        Ok(index)
    }

    pub(in crate::compiler) fn store_build_link_batch_prepare_progress(
        &self,
        progress: &LinkBatchPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-batch prepare progress: {err}"
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack link-batch prepare progress")?;
        Ok(path)
    }

    pub(in crate::compiler) fn load_build_link_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_ref_index: &SourcePackBuildArtifactRefIndex,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<LinkBatchPrepareProgress, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link-batch prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress =
            serde_json::from_slice::<LinkBatchPrepareProgress>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link-batch prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_build_link_batch_prepare_progress(
            &progress,
            target,
            artifact_ref_index,
            batch_limits,
        )?;
        Ok(progress)
    }

    pub fn store_build_link_interface_batch_page(
        &self,
        page: &SourcePackBuildLinkInterfaceBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_interface_batch_page(page, page.target, Some(page.batch_index))?;
        let path =
            self.build_link_interface_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-interface batch page {}: {err}",
                page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack link-interface batch page")?;
        Ok(path)
    }

    pub fn load_build_link_interface_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildLinkInterfaceBatchPage, CompileError> {
        let path = self.build_link_interface_batch_page_path_for_target(target, batch_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link-interface batch page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildLinkInterfaceBatchPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link-interface batch page {}: {err}",
                    path.display()
                ))
            })?;
        validate_link_interface_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    pub fn store_build_link_object_batch_page(
        &self,
        page: &SourcePackBuildLinkObjectBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_object_batch_page(page, page.target, Some(page.batch_index))?;
        let path = self.build_link_object_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-object batch page {}: {err}",
                page.batch_index
            ))
        })?;
        write_file_atomic(&path, &bytes, "source-pack link-object batch page")?;
        Ok(path)
    }

    pub fn load_build_link_object_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildLinkObjectBatchPage, CompileError> {
        let path = self.build_link_object_batch_page_path_for_target(target, batch_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link-object batch page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackBuildLinkObjectBatchPage>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link-object batch page {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_link_object_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }
}
