use super::*;

impl ExecutionShardLoader for FilesystemArtifactStore {
    fn load_execution_shard(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
        self.load_build_artifact_execution_shard_for_target(target, shard_index)
    }

    fn load_source_file_for_index(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> Result<ExplicitSourcePathFile, CompileError> {
        let library_partition_index = self.load_library_partition_index_for_target(target)?;
        let mut partition_cache = BTreeMap::<usize, SourcePackLibraryPartition>::new();
        let mut source_file_page_cache = BTreeMap::<usize, SourcePackLibrarySourceFilePage>::new();
        stored_source_file_for_index(
            self,
            target,
            &library_partition_index,
            source_index,
            &mut partition_cache,
            &mut source_file_page_cache,
        )
    }

    fn load_job_artifact_input_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> Result<SourcePackJobArtifactInputInterfacePage, CompileError> {
        self.load_job_artifact_input_interface_page_for_target(target, job_index, page_index)
    }

    fn load_build_artifact_ref_index(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactRefIndex, CompileError> {
        self.load_build_artifact_ref_index_for_target(target)
    }

    fn load_build_artifact_ref_page(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
        artifact_count: usize,
    ) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
        self.load_build_artifact_ref_page_for_target(target, artifact_index, artifact_count)
    }

    fn load_hierarchical_link_execution_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionInterfacePage, CompileError> {
        self.load_hierarchical_link_execution_interface_page_for_target(
            target,
            group_index,
            page_index,
        )
    }

    fn load_hierarchical_link_execution_object_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionObjectPage, CompileError> {
        self.load_hierarchical_link_execution_object_page_for_target(
            target,
            group_index,
            page_index,
        )
    }

    fn load_hierarchical_link_execution_partial_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPartialPage, CompileError> {
        self.load_hierarchical_link_execution_partial_page_for_target(
            target,
            group_index,
            page_index,
        )
    }

    fn load_source_files_for_range(
        &self,
        target: SourcePackArtifactTarget,
        first_source_index: usize,
        source_file_count: usize,
    ) -> Result<Vec<ExplicitSourcePathFile>, CompileError> {
        let source_end = first_source_index
            .checked_add(source_file_count)
            .ok_or_else(|| {
                library_partition_contract_error(format!(
                    "source-pack source range {first_source_index}+{source_file_count} overflows"
                ))
            })?;
        let library_partition_index = self.load_library_partition_index_for_target(target)?;
        let mut partition_cache = BTreeMap::<usize, SourcePackLibraryPartition>::new();
        let mut source_file_page_cache = BTreeMap::<usize, SourcePackLibrarySourceFilePage>::new();
        let mut files = Vec::with_capacity(source_file_count);
        for source_index in first_source_index..source_end {
            files.push(stored_source_file_for_index(
                self,
                target,
                &library_partition_index,
                source_index,
                &mut partition_cache,
                &mut source_file_page_cache,
            )?);
        }
        validate_explicit_source_path_files_metadata("source-pack job", &files)?;
        Ok(files)
    }
}

impl ExecutionShardLoader for ArtifactPathStore {
    fn load_execution_shard(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
        self.inner.load_execution_shard(target, shard_index)
    }

    fn load_source_file_for_index(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> Result<ExplicitSourcePathFile, CompileError> {
        self.inner.load_source_file_for_index(target, source_index)
    }

    fn load_job_artifact_input_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> Result<SourcePackJobArtifactInputInterfacePage, CompileError> {
        self.inner
            .load_job_artifact_input_interface_page(target, job_index, page_index)
    }

    fn load_build_artifact_ref_index(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactRefIndex, CompileError> {
        self.inner.load_build_artifact_ref_index(target)
    }

    fn load_build_artifact_ref_page(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
        artifact_count: usize,
    ) -> Result<SourcePackBuildArtifactRefPage, CompileError> {
        self.inner
            .load_build_artifact_ref_page(target, artifact_index, artifact_count)
    }

    fn load_hierarchical_link_execution_interface_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionInterfacePage, CompileError> {
        self.inner
            .load_hierarchical_link_execution_interface_page(target, group_index, page_index)
    }

    fn load_hierarchical_link_execution_object_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionObjectPage, CompileError> {
        self.inner
            .load_hierarchical_link_execution_object_page(target, group_index, page_index)
    }

    fn load_hierarchical_link_execution_partial_page(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPartialPage, CompileError> {
        self.inner
            .load_hierarchical_link_execution_partial_page(target, group_index, page_index)
    }
}
