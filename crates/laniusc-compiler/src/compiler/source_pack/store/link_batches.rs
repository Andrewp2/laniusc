use super::*;

impl FilesystemArtifactStore {
    /// Stores the top-level link-batch page index.
    ///
    /// The index records how many interface and object link-batch pages were
    /// produced for a target.
    pub fn store_build_link_batch_page_index(
        &self,
        index: &SourcePackBuildLinkBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_link_batch_page_index(index, index.target)?;
        let path = self.build_link_batch_index_path_for_target(index.target);
        let bytes = serialize_store_json(index, "source-pack link-batch page index")?;
        write_store_file_atomic(&path, &bytes, "source-pack link-batch page index")?;
        Ok(path)
    }

    /// Loads and validates the link-batch page index for a target.
    pub fn load_build_link_batch_page_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildLinkBatchPageIndex, CompileError> {
        let path = self.build_link_batch_index_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack link-batch page index")?;
        let index = parse_store_json::<SourcePackBuildLinkBatchPageIndex>(
            &bytes,
            &path,
            "source-pack link-batch page index",
        )?;
        validate_link_batch_page_index(&index, target)?;
        Ok(index)
    }

    /// Stores the resumable link-batch preparation checkpoint.
    pub(in crate::compiler) fn store_build_link_batch_prepare_progress(
        &self,
        progress: &LinkBatchPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(progress.target);
        let bytes = serialize_store_json(progress, "source-pack link-batch prepare progress")?;
        write_store_file_atomic(&path, &bytes, "source-pack link-batch prepare progress")?;
        Ok(path)
    }

    /// Loads and validates link-batch preparation progress for a target.
    ///
    /// The progress record is checked against the current artifact-ref index and
    /// batch limits before preparation resumes.
    pub(in crate::compiler) fn load_build_link_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_ref_index: &SourcePackBuildArtifactRefIndex,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<LinkBatchPrepareProgress, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(target);
        let bytes = read_store_file(&path, "source-pack link-batch prepare progress")?;
        let progress = parse_store_json::<LinkBatchPrepareProgress>(
            &bytes,
            &path,
            "source-pack link-batch prepare progress",
        )?;
        validate_build_link_batch_prepare_progress(
            &progress,
            target,
            artifact_ref_index,
            batch_limits,
        )?;
        Ok(progress)
    }

    /// Stores one link-interface batch page.
    ///
    /// Interface batches list library-interface artifacts that should be streamed
    /// into the final link job together.
    pub fn store_build_link_interface_batch_page(
        &self,
        page: &SourcePackBuildLinkInterfaceBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_interface_batch_page(page, page.target, Some(page.batch_index))?;
        let path =
            self.build_link_interface_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serialize_store_json(
            page,
            format!("source-pack link-interface batch page {}", page.batch_index),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack link-interface batch page")?;
        Ok(path)
    }

    /// Loads and validates one link-interface batch page by batch index.
    pub fn load_build_link_interface_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildLinkInterfaceBatchPage, CompileError> {
        let path = self.build_link_interface_batch_page_path_for_target(target, batch_index);
        let bytes = read_store_file(&path, "source-pack link-interface batch page")?;
        let page = parse_store_json::<SourcePackBuildLinkInterfaceBatchPage>(
            &bytes,
            &path,
            "source-pack link-interface batch page",
        )?;
        validate_link_interface_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    /// Stores one link-object batch page.
    ///
    /// Object batches list codegen-object artifacts that should be streamed into
    /// the final link job together.
    pub fn store_build_link_object_batch_page(
        &self,
        page: &SourcePackBuildLinkObjectBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_link_object_batch_page(page, page.target, Some(page.batch_index))?;
        let path = self.build_link_object_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serialize_store_json(
            page,
            format!("source-pack link-object batch page {}", page.batch_index),
        )?;
        write_store_file_atomic(&path, &bytes, "source-pack link-object batch page")?;
        Ok(path)
    }

    /// Loads and validates one link-object batch page by batch index.
    pub fn load_build_link_object_batch_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildLinkObjectBatchPage, CompileError> {
        let path = self.build_link_object_batch_page_path_for_target(target, batch_index);
        let bytes = read_store_file(&path, "source-pack link-object batch page")?;
        let page = parse_store_json::<SourcePackBuildLinkObjectBatchPage>(
            &bytes,
            &path,
            "source-pack link-object batch page",
        )?;
        validate_link_object_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }
}
