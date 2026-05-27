use super::*;

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactStore {
    pub(in crate::compiler) root: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactPath {
    pub key: String,
    pub path: PathBuf,
}

#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackFilesystemArtifactPathStore {
    pub(in crate::compiler) inner: SourcePackFilesystemArtifactStore,
}

#[derive(Debug)]
pub(in crate::compiler) struct SourcePackFilesystemBuildStateLock {
    pub(in crate::compiler) path: PathBuf,
}

impl Drop for SourcePackFilesystemBuildStateLock {
    fn drop(&mut self) {
        let _ = fs::remove_file(&self.path);
    }
}

impl SourcePackFilesystemArtifactStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }

    pub fn root(&self) -> &Path {
        &self.root
    }

    pub fn path_for_key(&self, key: &str) -> Result<PathBuf, CompileError> {
        source_pack_filesystem_artifact_path(&self.root, key)
    }

    pub fn build_manifest_path(&self) -> PathBuf {
        self.build_manifest_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_manifest_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_MANIFEST_FILE,
            target,
        )
    }

    pub fn artifact_manifest_path(&self) -> PathBuf {
        self.artifact_manifest_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_manifest_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_MANIFEST_FILE,
            target,
        )
    }

    pub fn library_partition_index_path(&self) -> PathBuf {
        self.library_partition_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn library_partition_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_INDEX_FILE,
            target,
        )
    }

    pub fn library_metadata_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn library_partition_path(&self, partition_index: usize) -> PathBuf {
        self.library_partition_path_for_target(SourcePackArtifactTarget::Generic, partition_index)
    }

    pub fn library_partition_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_FILE_STEM}-{partition_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_partition_locator_page_path(&self, library_id: u32) -> PathBuf {
        self.library_partition_locator_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            library_id,
        )
    }

    pub fn library_partition_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_LOCATOR_PAGE_FILE_STEM}-{library_id:010}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_dependency_page_path(
        &self,
        partition_index: usize,
        page_index: usize,
    ) -> PathBuf {
        self.library_dependency_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
            page_index,
        )
    }

    pub fn library_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_DEPENDENCY_PAGE_FILE_STEM}-{partition_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_source_file_page_path(&self, partition_index: usize) -> PathBuf {
        self.library_source_file_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
        )
    }

    pub fn library_source_file_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SOURCE_FILE_PAGE_FILE_STEM}-{partition_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_source_file_record_page_path(&self, source_index: usize) -> PathBuf {
        self.library_source_file_record_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            source_index,
        )
    }

    pub fn library_source_file_record_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SOURCE_FILE_RECORD_PAGE_FILE_STEM}-{source_index:010}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_build_unit_page_path(&self, partition_index: usize) -> PathBuf {
        self.library_build_unit_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
        )
    }

    pub fn library_build_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_BUILD_UNIT_PAGE_FILE_STEM}-{partition_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_frontend_unit_page_path(
        &self,
        partition_index: usize,
        frontend_unit_index: usize,
    ) -> PathBuf {
        self.library_frontend_unit_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
            frontend_unit_index,
        )
    }

    pub fn library_frontend_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        frontend_unit_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_FRONTEND_UNIT_PAGE_FILE_STEM}-{partition_index:08}-{frontend_unit_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_codegen_unit_page_path(
        &self,
        partition_index: usize,
        codegen_unit_index: usize,
    ) -> PathBuf {
        self.library_codegen_unit_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
            codegen_unit_index,
        )
    }

    pub fn library_codegen_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        codegen_unit_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_CODEGEN_UNIT_PAGE_FILE_STEM}-{partition_index:08}-{codegen_unit_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_index_path(&self) -> PathBuf {
        self.library_schedule_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn library_schedule_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_INDEX_FILE,
            target,
        )
    }

    pub fn library_schedule_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn library_schedule_page_path(&self, partition_index: usize) -> PathBuf {
        self.library_schedule_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            partition_index,
        )
    }

    pub fn library_schedule_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_PAGE_FILE_STEM}-{partition_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_frontend_job_locator_page_path(&self, library_id: u32) -> PathBuf {
        self.library_frontend_job_locator_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            library_id,
        )
    }

    pub fn library_frontend_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_FILE_STEM}-{library_id:010}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_locator_index_path(&self) -> PathBuf {
        self.library_schedule_job_locator_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn library_schedule_job_locator_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_FILE,
            target,
        )
    }

    pub fn library_schedule_job_locator_page_path(&self, job_index: usize) -> PathBuf {
        self.library_schedule_job_locator_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            job_index,
        )
    }

    pub fn library_schedule_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_FILE_STEM}-{job_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_page_path(&self, job_index: usize) -> PathBuf {
        self.library_schedule_job_page_path_for_target(SourcePackArtifactTarget::Generic, job_index)
    }

    pub fn library_schedule_job_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_PAGE_FILE_STEM}-{job_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_dependency_page_path(
        &self,
        job_index: usize,
        page_index: usize,
    ) -> PathBuf {
        self.library_schedule_job_dependency_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            job_index,
            page_index,
        )
    }

    pub fn library_schedule_job_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_FILE_STEM}-{job_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_plan_index_path(&self) -> PathBuf {
        self.hierarchical_link_plan_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn hierarchical_link_plan_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_PLAN_INDEX_FILE,
            target,
        )
    }

    pub fn hierarchical_link_plan_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn hierarchical_link_group_page_path(&self, group_index: usize) -> PathBuf {
        self.hierarchical_link_group_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            group_index,
        )
    }

    pub fn hierarchical_link_group_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_GROUP_PAGE_FILE_STEM}-{group_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_index_path(&self) -> PathBuf {
        self.hierarchical_link_execution_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn hierarchical_link_execution_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_INDEX_FILE,
            target,
        )
    }

    pub fn hierarchical_link_execution_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn hierarchical_link_execution_page_path(&self, group_index: usize) -> PathBuf {
        self.hierarchical_link_execution_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            group_index,
        )
    }

    pub fn hierarchical_link_execution_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PAGE_FILE_STEM}-{group_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_interface_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_object_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_partial_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_index_path(&self) -> PathBuf {
        self.build_job_batch_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_job_batch_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_INDEX_FILE,
            target,
        )
    }

    pub fn build_job_batch_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_job_batch_dependents_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_job_batch_page_path(&self, batch_index: usize) -> PathBuf {
        self.build_job_batch_page_path_for_target(SourcePackArtifactTarget::Generic, batch_index)
    }

    pub fn build_job_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_job_locator_page_path(&self, job_index: usize) -> PathBuf {
        self.build_job_batch_job_locator_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            job_index,
        )
    }

    pub fn build_job_batch_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_FILE_STEM}-{job_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependency_page_path(
        &self,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        self.build_job_batch_dependency_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            batch_index,
            page_index,
        )
    }

    pub fn build_job_batch_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENCY_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependency_range_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependents_page_path(&self, batch_index: usize) -> PathBuf {
        self.build_job_batch_dependents_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            batch_index,
        )
    }

    pub fn build_job_batch_dependents_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENTS_PAGE_FILE_STEM}-{batch_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependent_batch_page_path(
        &self,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        self.build_job_batch_dependent_batch_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            batch_index,
            page_index,
        )
    }

    pub fn build_job_batch_dependent_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_artifact_ref_index_path(&self) -> PathBuf {
        self.build_artifact_ref_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_artifact_ref_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_INDEX_FILE,
            target,
        )
    }

    pub fn build_artifact_ref_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_artifact_ref_page_path(&self, artifact_index: usize) -> PathBuf {
        self.build_artifact_ref_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            artifact_index,
        )
    }

    pub fn build_artifact_ref_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_PAGE_FILE_STEM}-{artifact_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn job_artifact_input_interface_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_FILE_STEM}-{job_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_link_batch_index_path(&self) -> PathBuf {
        self.build_link_batch_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_link_batch_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_LINK_BATCH_INDEX_FILE,
            target,
        )
    }

    pub fn build_link_batch_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_LINK_BATCH_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_link_interface_batch_page_path(&self, batch_index: usize) -> PathBuf {
        self.build_link_interface_batch_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            batch_index,
        )
    }

    pub fn build_link_interface_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_LINK_INTERFACE_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_link_object_batch_page_path(&self, batch_index: usize) -> PathBuf {
        self.build_link_object_batch_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            batch_index,
        )
    }

    pub fn build_link_object_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_LINK_OBJECT_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_index_path(&self) -> PathBuf {
        self.work_queue_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn work_queue_index_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_WORK_QUEUE_INDEX_FILE,
            target,
        )
    }

    pub fn work_queue_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn work_queue_page_path(&self, item_index: usize) -> PathBuf {
        self.work_queue_page_path_for_target(SourcePackArtifactTarget::Generic, item_index)
    }

    pub fn work_queue_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PAGE_FILE_STEM}-{item_index:08}.json");
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_dependencies_page_path(
        &self,
        item_index: usize,
        page_index: usize,
    ) -> PathBuf {
        self.work_queue_dependencies_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            item_index,
            page_index,
        )
    }

    pub fn work_queue_dependencies_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_DEPENDENCIES_PAGE_FILE_STEM}-{item_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_dependents_page_path(&self, item_index: usize, page_index: usize) -> PathBuf {
        self.work_queue_dependents_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            item_index,
            page_index,
        )
    }

    pub fn work_queue_dependents_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_DEPENDENTS_PAGE_FILE_STEM}-{item_index:08}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_index_path(&self) -> PathBuf {
        self.work_queue_progress_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn work_queue_progress_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_INDEX_FILE,
            target,
        )
    }

    pub fn work_queue_progress_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn work_queue_progress_page_path(&self, page_index: usize) -> PathBuf {
        self.work_queue_progress_page_path_for_target(SourcePackArtifactTarget::Generic, page_index)
    }

    pub fn work_queue_progress_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PAGE_FILE_STEM}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_page_summary_path(&self, page_index: usize) -> PathBuf {
        self.work_queue_progress_page_summary_path_for_target(
            SourcePackArtifactTarget::Generic,
            page_index,
        )
    }

    pub fn work_queue_progress_page_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PAGE_SUMMARY_FILE_STEM}-{page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_directory_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_FILE_STEM}-{directory_page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_directory_index_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM}-{directory_index_page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn artifact_shard_index_path(&self) -> PathBuf {
        self.artifact_shard_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn artifact_shard_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_INDEX_FILE,
            target,
        )
    }

    pub fn artifact_shard_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn link_input_shard_index_path(&self) -> PathBuf {
        self.link_input_shard_index_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn link_input_shard_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_LINK_INPUT_SHARD_INDEX_FILE,
            target,
        )
    }

    pub fn artifact_shard_path(&self, shard_index: usize) -> PathBuf {
        self.artifact_shard_path_for_target(SourcePackArtifactTarget::Generic, shard_index)
    }

    pub fn artifact_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_FILE_STEM}-{shard_index:08}.json");
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn artifact_execution_shard_path(&self, shard_index: usize) -> PathBuf {
        self.artifact_execution_shard_path_for_target(
            SourcePackArtifactTarget::Generic,
            shard_index,
        )
    }

    pub fn artifact_execution_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_ARTIFACT_EXECUTION_SHARD_FILE_STEM}-{shard_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn batch_shard_locator_path(&self, batch_index: usize) -> PathBuf {
        self.batch_shard_locator_path_for_target(SourcePackArtifactTarget::Generic, batch_index)
    }

    pub fn batch_shard_locator_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{SOURCE_PACK_FILESYSTEM_BATCH_SHARD_LOCATOR_FILE_STEM}-{batch_index:08}.json");
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_shard_path(&self, shard_index: usize) -> PathBuf {
        self.build_progress_shard_path_for_target(SourcePackArtifactTarget::Generic, shard_index)
    }

    pub fn build_progress_shard_summary_path(&self, shard_index: usize) -> PathBuf {
        self.build_progress_shard_summary_path_for_target(
            SourcePackArtifactTarget::Generic,
            shard_index,
        )
    }

    pub fn build_progress_directory_page_path(&self, directory_page_index: usize) -> PathBuf {
        self.build_progress_directory_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            directory_page_index,
        )
    }

    pub fn build_progress_directory_index_page_path(
        &self,
        directory_index_page_index: usize,
    ) -> PathBuf {
        self.build_progress_directory_index_page_path_for_target(
            SourcePackArtifactTarget::Generic,
            directory_index_page_index,
        )
    }

    pub fn build_progress_summary_path(&self) -> PathBuf {
        self.build_progress_summary_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_progress_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SUMMARY_FILE,
            target,
        )
    }

    pub fn build_progress_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SHARD_FILE_STEM}-{shard_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_shard_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SHARD_SUMMARY_FILE_STEM}-{shard_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_directory_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_DIRECTORY_PAGE_FILE_STEM}-{directory_page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_directory_index_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM}-{directory_index_page_index:08}.json"
        );
        source_pack_filesystem_target_path(&self.root, &file_name, target)
    }

    pub fn build_state_path(&self) -> PathBuf {
        self.build_state_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_state_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        source_pack_filesystem_target_path(
            &self.root,
            SOURCE_PACK_FILESYSTEM_BUILD_STATE_FILE,
            target,
        )
    }

    pub fn build_state_lock_path(&self) -> PathBuf {
        self.build_state_lock_path_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn build_state_lock_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        let state_path = self.build_state_path_for_target(target);
        let mut lock_file_name = state_path
            .file_name()
            .expect("source-pack build state path has a file name")
            .to_os_string();
        lock_file_name.push(".lock");
        state_path.with_file_name(lock_file_name)
    }

    pub(in crate::compiler) fn try_lock_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackFilesystemBuildStateLock, CompileError> {
        let path = self.build_state_lock_path_for_target(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack build state lock directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        match fs::OpenOptions::new()
            .write(true)
            .create_new(true)
            .open(&path)
        {
            Ok(_) => Ok(SourcePackFilesystemBuildStateLock { path }),
            Err(err) if err.kind() == std::io::ErrorKind::AlreadyExists => {
                Err(CompileError::GpuFrontend(format!(
                    "source-pack build state lock is already held at {}",
                    path.display()
                )))
            }
            Err(err) => Err(CompileError::GpuFrontend(format!(
                "create source-pack build state lock {}: {err}",
                path.display()
            ))),
        }
    }

    pub fn legacy_build_manifest_path(&self) -> PathBuf {
        self.root.join(SOURCE_PACK_FILESYSTEM_BUILD_MANIFEST_FILE)
    }

    pub fn legacy_artifact_manifest_path(&self) -> PathBuf {
        self.root
            .join(SOURCE_PACK_FILESYSTEM_ARTIFACT_MANIFEST_FILE)
    }

    pub fn legacy_build_state_path(&self) -> PathBuf {
        self.root.join(SOURCE_PACK_FILESYSTEM_BUILD_STATE_FILE)
    }

    pub fn path_for_artifact(
        &self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<PathBuf, CompileError> {
        self.path_for_key(&artifact.key)
    }

    pub fn artifact_exists(&self, artifact: &SourcePackArtifactRef) -> Result<bool, CompileError> {
        Ok(self.path_for_artifact(artifact)?.is_file())
    }

    pub fn load_linked_output(&self, key: &str) -> Result<Vec<u8>, CompileError> {
        read_source_pack_filesystem_artifact(&self.root, key, "linked output")
    }

    pub fn store_library_partition_index(
        &self,
        index: &SourcePackLibraryPartitionIndex,
        partitions: &[SourcePackLibraryPartition],
    ) -> Result<SourcePackFilesystemLibraryPartitionStoreResult, CompileError> {
        validate_source_pack_library_partition_records(index, partitions, index.target)?;
        let mut library_partition_count = 0usize;

        for partition in partitions {
            self.store_library_partition_page(partition)?;
            self.store_library_partition_locator_page(&SourcePackLibraryPartitionLocatorPage {
                version: SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION,
                target: partition.target,
                library_id: partition.library_id,
                partition_index: partition.partition_index,
            })?;
            library_partition_count += 1;
        }

        let index_path = self.store_library_partition_compact_index(index)?;

        Ok(SourcePackFilesystemLibraryPartitionStoreResult {
            library_partition_index_path: index_path,
            library_partition_count,
        })
    }

    pub fn store_library_partition_page(
        &self,
        partition: &SourcePackLibraryPartition,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_partition(
            partition,
            partition.target,
            Some(partition.partition_index),
        )?;
        let (dependency_library_count, dependency_page_count) =
            store_source_pack_library_dependency_pages(self, partition)?;
        let mut stored_partition = partition.clone();
        stored_partition.dependency_library_ids.clear();
        stored_partition.dependency_library_count = dependency_library_count;
        stored_partition.dependency_page_count = dependency_page_count;
        validate_source_pack_library_partition(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library partition",
        )?;
        Ok(path)
    }

    pub fn store_library_dependency_page(
        &self,
        page: &SourcePackLibraryDependencyPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_dependency_page(
            page,
            page.target,
            page.partition_index,
            page.page_index,
        )?;
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library dependency page",
        )?;
        Ok(path)
    }

    pub fn store_library_partition_compact_index(
        &self,
        index: &SourcePackLibraryPartitionIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_partition_index(index, index.target)?;
        let index_path = self.library_partition_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library partition index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &index_path,
            &bytes,
            "source-pack library partition index",
        )?;
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
        validate_source_pack_library_partition_index(&index, target)?;
        Ok(index)
    }

    pub fn store_library_metadata_prepare_progress(
        &self,
        progress: &SourcePackFilesystemLibraryMetadataPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_metadata_prepare_progress(progress, progress.target)?;
        let path = self.library_metadata_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library metadata prepare progress: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library metadata prepare progress",
        )?;
        Ok(path)
    }

    pub fn load_library_metadata_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackFilesystemLibraryMetadataPrepareProgress, CompileError> {
        let path = self.library_metadata_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library metadata prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress =
            serde_json::from_slice::<SourcePackFilesystemLibraryMetadataPrepareProgress>(&bytes)
                .map_err(|err| {
                    CompileError::GpuFrontend(format!(
                        "parse source-pack library metadata prepare progress {}: {err}",
                        path.display()
                    ))
                })?;
        validate_source_pack_library_metadata_prepare_progress(&progress, target)?;
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
        validate_source_pack_library_partition(&partition, target, Some(partition_index))?;
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
        validate_source_pack_library_dependency_page(&page, target, partition_index, page_index)?;
        Ok(page)
    }

    pub fn store_library_partition_locator_page(
        &self,
        page: &SourcePackLibraryPartitionLocatorPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_partition_locator_page(
            page,
            page.target,
            Some(page.library_id),
        )?;
        let path =
            self.library_partition_locator_page_path_for_target(page.target, page.library_id);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library partition locator for library {}: {err}",
                page.library_id
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library partition locator",
        )?;
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
        validate_source_pack_library_partition_locator_page(&page, target, Some(library_id))?;
        Ok(page)
    }

    pub fn store_library_source_file_pages(
        &self,
        pages: &[SourcePackLibrarySourceFilePage],
    ) -> Result<SourcePackFilesystemLibrarySourceFilePageStoreResult, CompileError> {
        let mut library_source_file_page_count = 0usize;
        for page in pages {
            self.store_library_source_file_page(page)?;
            library_source_file_page_count += 1;
        }
        Ok(SourcePackFilesystemLibrarySourceFilePageStoreResult {
            library_source_file_page_count,
        })
    }

    pub fn store_library_source_file_page(
        &self,
        page: &SourcePackLibrarySourceFilePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_source_file_page(
            page,
            page.target,
            Some(page.partition_index),
        )?;
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
        validate_source_pack_library_source_file_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library source-file page",
        )?;
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
        validate_source_pack_library_source_file_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    pub fn store_library_source_file_record_page(
        &self,
        page: &SourcePackLibrarySourceFileRecordPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_source_file_record_page(
            page,
            page.target,
            Some(page.source_index),
        )?;
        let path =
            self.library_source_file_record_page_path_for_target(page.target, page.source_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library source-file record {}: {err}",
                page.source_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library source-file record",
        )?;
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
        validate_source_pack_library_source_file_record_page(&page, target, Some(source_index))?;
        Ok(page)
    }

    pub fn store_library_build_unit_pages(
        &self,
        pages: &[SourcePackLibraryBuildUnitPage],
    ) -> Result<SourcePackFilesystemLibraryBuildUnitPageStoreResult, CompileError> {
        let mut library_build_unit_page_count = 0usize;
        for page in pages {
            self.store_library_build_unit_page(page)?;
            library_build_unit_page_count += 1;
        }
        Ok(SourcePackFilesystemLibraryBuildUnitPageStoreResult {
            library_build_unit_page_count,
        })
    }

    pub fn store_library_build_unit_page(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_build_unit_page(
            page,
            page.target,
            Some(page.partition_index),
        )?;
        let frontend_unit_count = if page.frontend_units.is_empty() {
            source_pack_library_build_unit_page_frontend_unit_count(page)
        } else {
            self.store_library_frontend_unit_pages_from_units(page)?
        };
        let codegen_unit_count = if page.codegen_units.is_empty() {
            source_pack_library_build_unit_page_codegen_unit_count(page)
        } else {
            self.store_library_codegen_unit_pages_from_units(page)?
        };
        let mut stored_page = page.clone();
        stored_page.frontend_unit_count = frontend_unit_count;
        stored_page.codegen_unit_count = codegen_unit_count;
        stored_page.dependency_library_ids.clear();
        stored_page.frontend_units.clear();
        stored_page.codegen_units.clear();
        validate_source_pack_library_build_unit_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library build-unit page",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_library_frontend_unit_pages_from_units(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<usize, CompileError> {
        for unit in &page.frontend_units {
            let unit_page = source_pack_library_frontend_unit_page(page, unit.clone())?;
            self.store_library_frontend_unit_page(&unit_page)?;
        }
        Ok(page.frontend_units.len())
    }

    pub(in crate::compiler) fn store_library_codegen_unit_pages_from_units(
        &self,
        page: &SourcePackLibraryBuildUnitPage,
    ) -> Result<usize, CompileError> {
        for unit in &page.codegen_units {
            let unit_page = source_pack_library_codegen_unit_page(page, unit.clone())?;
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
        validate_source_pack_library_build_unit_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    pub fn store_library_frontend_unit_page(
        &self,
        page: &SourcePackLibraryFrontendUnitPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_frontend_unit_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library frontend-unit page",
        )?;
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
        validate_source_pack_library_frontend_unit_page(
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
        validate_source_pack_library_codegen_unit_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library codegen-unit page",
        )?;
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
        validate_source_pack_library_codegen_unit_page(
            &page,
            target,
            Some(partition_index),
            Some(codegen_unit_index),
        )?;
        Ok(page)
    }

    pub fn store_library_schedule_index(
        &self,
        index: &SourcePackLibraryScheduleIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_index(index, index.target)?;
        let path = self.library_schedule_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule index",
        )?;
        Ok(path)
    }

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
        validate_source_pack_library_schedule_index(&index, target)?;
        Ok(index)
    }

    pub fn store_library_schedule_prepare_progress(
        &self,
        progress: &SourcePackFilesystemLibrarySchedulePrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_prepare_progress(progress, progress.target)?;
        let path = self.library_schedule_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule prepare progress: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule prepare progress",
        )?;
        Ok(path)
    }

    pub fn load_library_schedule_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackFilesystemLibrarySchedulePrepareProgress, CompileError> {
        let path = self.library_schedule_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress =
            serde_json::from_slice::<SourcePackFilesystemLibrarySchedulePrepareProgress>(&bytes)
                .map_err(|err| {
                    CompileError::GpuFrontend(format!(
                        "parse source-pack library schedule prepare progress {}: {err}",
                        path.display()
                    ))
                })?;
        validate_source_pack_library_schedule_prepare_progress(&progress, target)?;
        Ok(progress)
    }

    pub fn store_library_schedule_pages(
        &self,
        pages: &[SourcePackLibrarySchedulePage],
    ) -> Result<SourcePackFilesystemLibrarySchedulePageStoreResult, CompileError> {
        let mut library_schedule_page_count = 0usize;
        for page in pages {
            self.store_library_schedule_page(page)?;
            library_schedule_page_count += 1;
        }
        Ok(SourcePackFilesystemLibrarySchedulePageStoreResult {
            library_schedule_page_count,
        })
    }

    pub fn store_library_schedule_page(
        &self,
        page: &SourcePackLibrarySchedulePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_page(page, page.target, Some(page.partition_index))?;
        let job_count = page.link_job_index.checked_add(1).ok_or_else(|| {
            source_pack_library_partition_contract_error(format!(
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
            frontend_job_count: source_pack_library_schedule_page_frontend_job_count(page),
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
        validate_source_pack_library_schedule_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule page",
        )?;
        Ok(path)
    }

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
        validate_source_pack_library_schedule_page(&page, target, Some(partition_index))?;
        Ok(page)
    }

    pub fn store_library_frontend_job_locator_page(
        &self,
        page: &SourcePackLibraryFrontendJobLocatorPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_frontend_job_locator_page(
            page,
            page.target,
            Some(page.library_id),
        )?;
        let path =
            self.library_frontend_job_locator_page_path_for_target(page.target, page.library_id);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library frontend-job locator for library {}: {err}",
                page.library_id
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library frontend-job locator",
        )?;
        Ok(path)
    }

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
        validate_source_pack_library_frontend_job_locator_page(&page, target, Some(library_id))?;
        Ok(page)
    }

    pub fn store_library_schedule_job_locator_index(
        &self,
        index: &SourcePackLibraryScheduleJobLocatorIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_job_locator_index(index, index.target)?;
        let path = self.library_schedule_job_locator_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job-locator index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule job-locator index",
        )?;
        Ok(path)
    }

    pub fn load_library_schedule_job_locator_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackLibraryScheduleJobLocatorIndex, CompileError> {
        let path = self.library_schedule_job_locator_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack library schedule job-locator index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackLibraryScheduleJobLocatorIndex>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack library schedule job-locator index {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_library_schedule_job_locator_index(&index, target)?;
        Ok(index)
    }

    pub fn store_library_schedule_job_locator_page(
        &self,
        page: &SourcePackLibraryScheduleJobLocatorPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_job_locator_page(
            page,
            page.target,
            job_count,
            Some(page.job_index),
        )?;
        let path =
            self.library_schedule_job_locator_page_path_for_target(page.target, page.job_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job-locator page {}: {err}",
                page.job_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule job-locator page",
        )?;
        Ok(path)
    }

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
        validate_source_pack_library_schedule_job_locator_page(
            &page,
            target,
            job_count,
            Some(job_index),
        )?;
        Ok(page)
    }

    pub fn store_library_schedule_job_page(
        &self,
        page: &SourcePackLibraryScheduleJobPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_job_page(
            page,
            page.target,
            job_count,
            Some(page.job_index),
        )?;
        if page.dependency_job_count != 0 || page.dependency_page_count != 0 {
            return Err(source_pack_library_partition_contract_error(format!(
                "schedule job page {} is already paged; write it directly instead of re-storing dependencies",
                page.job_index
            )));
        }
        store_schedule_job_page_with_dependencies(
            self,
            page.target,
            job_count,
            &page.job,
            |writer| {
                for range in &page.dependency_job_ranges {
                    writer.push_range(range.first_job_index, range.job_count)?;
                }
                for &dependency_job_index in &page.job.dependency_job_indices {
                    writer.push(dependency_job_index)?;
                }
                Ok(())
            },
        )
    }

    pub(in crate::compiler) fn write_library_schedule_job_page_file(
        &self,
        page: &SourcePackLibraryScheduleJobPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_job_page(
            page,
            page.target,
            job_count,
            Some(page.job_index),
        )?;
        let path = self.library_schedule_job_page_path_for_target(page.target, page.job_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack library schedule job page {}: {err}",
                page.job_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule job page",
        )?;
        Ok(path)
    }

    pub fn store_library_schedule_job_dependency_page(
        &self,
        page: &SourcePackLibraryScheduleJobDependencyPage,
        job_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_library_schedule_job_dependency_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack library schedule job dependency page",
        )?;
        Ok(path)
    }

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
        validate_source_pack_library_schedule_job_dependency_page(
            &page, target, job_count, job_index, page_index,
        )?;
        Ok(page)
    }

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
        validate_source_pack_library_schedule_job_page(&page, target, job_count, Some(job_index))?;
        Ok(page)
    }

    pub fn store_hierarchical_link_plan(
        &self,
        index: &SourcePackHierarchicalLinkPlanIndex,
        groups: &[SourcePackHierarchicalLinkGroupPage],
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_plan_index(index, index.target)?;
        if groups.len() != index.link_group_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "hierarchical link plan store has {} group pages but index group count {}",
                groups.len(),
                index.link_group_count
            )));
        }
        for group in groups {
            self.store_hierarchical_link_group_page(group)?;
        }
        let path = self.hierarchical_link_plan_index_path_for_target(index.target);
        validate_source_pack_hierarchical_link_plan_index(index, index.target)?;
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link plan index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link plan index",
        )?;
        Ok(path)
    }

    pub fn load_hierarchical_link_plan_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkPlanIndex, CompileError> {
        let path = self.hierarchical_link_plan_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link plan index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackHierarchicalLinkPlanIndex>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link plan index {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_source_pack_hierarchical_link_plan_index(&index, target)?;
        Ok(index)
    }

    pub fn store_hierarchical_link_group_page(
        &self,
        group: &SourcePackHierarchicalLinkGroupPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_group_page(
            group,
            group.target,
            Some(group.group_index),
        )?;
        let mut stored_group = group.clone();
        stored_group.input_frontend_job_count =
            source_pack_hierarchical_link_group_input_frontend_job_count(group);
        stored_group.input_frontend_job_indices.clear();
        if stored_group.kind == SourcePackHierarchicalLinkGroupKind::Reduce {
            stored_group.input_partition_count =
                source_pack_hierarchical_link_group_input_partition_count(group);
            stored_group.input_partition_indices.clear();
        }
        validate_source_pack_hierarchical_link_group_page(
            &stored_group,
            group.target,
            Some(group.group_index),
        )?;
        let path =
            self.hierarchical_link_group_page_path_for_target(group.target, group.group_index);
        let bytes = serde_json::to_vec_pretty(&stored_group).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link group page {}: {err}",
                group.group_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link group page",
        )?;
        Ok(path)
    }

    pub fn load_hierarchical_link_group_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkGroupPage, CompileError> {
        let path = self.hierarchical_link_group_page_path_for_target(target, group_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link group page {}: {err}",
                path.display()
            ))
        })?;
        let group = serde_json::from_slice::<SourcePackHierarchicalLinkGroupPage>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link group page {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_source_pack_hierarchical_link_group_page(&group, target, Some(group_index))?;
        Ok(group)
    }

    pub fn store_hierarchical_link_execution(
        &self,
        index: &SourcePackHierarchicalLinkExecutionIndex,
        pages: &[SourcePackHierarchicalLinkExecutionPage],
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_execution_pages(index, pages)?;
        for page in pages {
            self.store_hierarchical_link_execution_page(page)?;
        }
        let path = self.hierarchical_link_execution_index_path_for_target(index.target);
        validate_source_pack_hierarchical_link_execution_index(index, index.target)?;
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link execution index",
        )?;
        Ok(path)
    }

    pub fn load_hierarchical_link_execution_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackHierarchicalLinkExecutionIndex, CompileError> {
        let path = self.hierarchical_link_execution_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionIndex>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution index {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_hierarchical_link_execution_index(&index, target)?;
        Ok(index)
    }

    pub fn store_hierarchical_link_execution_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_execution_page_store_input(
            page,
            page.target,
            Some(page.group_index),
        )?;
        let explicit_input_interface_page_count = if page.input_interfaces.is_empty() {
            page.input_interface_page_count
        } else {
            self.store_hierarchical_link_execution_interface_pages_from_refs(
                page.target,
                page.group_index,
                page.job_index,
                &page.input_interfaces,
            )?
        };
        let input_interface_count = page.input_interfaces.len().saturating_add(
            source_pack_job_index_range_dependency_count(&page.input_interface_ranges),
        );
        let input_interface_count = if page.input_interfaces.is_empty() {
            page.input_interface_count
        } else {
            input_interface_count
        };
        let input_object_page_count = if page.input_objects.is_empty() {
            page.input_object_page_count
        } else {
            self.store_hierarchical_link_execution_object_pages_from_refs(
                page.target,
                page.group_index,
                page.job_index,
                &page.input_objects,
            )?
        };
        let input_object_count = if page.input_objects.is_empty() {
            page.input_object_count
        } else {
            page.input_objects.len()
        };
        let input_group_page_count =
            if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
                page.input_group_page_count
            } else {
                self.store_hierarchical_link_execution_partial_pages_from_inputs(
                    page.target,
                    page.group_index,
                    page.job_index,
                    &page.input_group_indices,
                    &page.input_group_output_keys,
                )?
            };
        let input_group_count =
            if page.input_group_indices.is_empty() && page.input_group_output_keys.is_empty() {
                page.input_group_count
            } else {
                page.input_group_indices.len()
            };
        let mut stored_page = page.clone();
        stored_page.input_interface_count = input_interface_count;
        stored_page.input_interface_page_count = explicit_input_interface_page_count;
        stored_page.input_interfaces.clear();
        stored_page.input_object_count = input_object_count;
        stored_page.input_object_page_count = input_object_page_count;
        stored_page.input_objects.clear();
        stored_page.input_group_count = input_group_count;
        stored_page.input_group_page_count = input_group_page_count;
        stored_page.input_group_indices.clear();
        stored_page.input_group_output_keys.clear();
        validate_source_pack_hierarchical_link_execution_page(
            &stored_page,
            page.target,
            Some(page.group_index),
        )?;
        let path =
            self.hierarchical_link_execution_page_path_for_target(page.target, page.group_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution page {}: {err}",
                page.group_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link execution page",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_hierarchical_link_execution_interface_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_interfaces: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_interfaces) in input_interfaces
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackHierarchicalLinkExecutionInterfacePage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position: page_index.saturating_mul(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
                ),
                input_count: input_interfaces.len(),
                input_interfaces: input_interfaces.to_vec(),
            };
            self.store_hierarchical_link_execution_interface_page(&page)?;
        }
        Ok(input_interfaces
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn store_hierarchical_link_execution_object_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_objects: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_objects) in input_objects
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackHierarchicalLinkExecutionObjectPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position: page_index.saturating_mul(
                    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
                ),
                input_count: input_objects.len(),
                input_objects: input_objects.to_vec(),
            };
            self.store_hierarchical_link_execution_object_page(&page)?;
        }
        Ok(input_objects
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn store_hierarchical_link_execution_partial_pages_from_inputs(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        job_index: usize,
        input_group_indices: &[usize],
        input_group_output_keys: &[String],
    ) -> Result<usize, CompileError> {
        for (page_index, input_group_indices) in input_group_indices
            .chunks(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let first_input_position = page_index
                .saturating_mul(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE);
            let input_group_output_keys = input_group_output_keys[first_input_position
                ..first_input_position.saturating_add(input_group_indices.len())]
                .to_vec();
            let page = SourcePackHierarchicalLinkExecutionPartialPage {
                version: SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
                target,
                group_index,
                job_index,
                page_index,
                first_input_position,
                input_count: input_group_indices.len(),
                input_group_indices: input_group_indices.to_vec(),
                input_group_output_keys,
            };
            self.store_hierarchical_link_execution_partial_page(&page)?;
        }
        Ok(input_group_indices
            .len()
            .div_ceil(SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE))
    }

    pub fn store_hierarchical_link_execution_interface_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionInterfacePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_execution_interface_page(
            page,
            page.target,
            page.group_index,
            page.page_index,
        )?;
        let path = self.hierarchical_link_execution_interface_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution interface page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link execution interface page",
        )?;
        Ok(path)
    }

    pub fn store_hierarchical_link_execution_object_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionObjectPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_execution_object_page(
            page,
            page.target,
            page.group_index,
            page.page_index,
        )?;
        let path = self.hierarchical_link_execution_object_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution object page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link execution object page",
        )?;
        Ok(path)
    }

    pub fn store_hierarchical_link_execution_partial_page(
        &self,
        page: &SourcePackHierarchicalLinkExecutionPartialPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_hierarchical_link_execution_partial_page(
            page,
            page.target,
            page.group_index,
            page.page_index,
        )?;
        let path = self.hierarchical_link_execution_partial_page_path_for_target(
            page.target,
            page.group_index,
            page.page_index,
        );
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack hierarchical link execution partial page {}:{}: {err}",
                page.group_index, page.page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack hierarchical link execution partial page",
        )?;
        Ok(path)
    }

    pub fn load_hierarchical_link_execution_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPage, CompileError> {
        let path = self.hierarchical_link_execution_page_path_for_target(target, group_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution page {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_hierarchical_link_execution_page(&page, target, Some(group_index))?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_interface_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionInterfacePage, CompileError> {
        let path = self.hierarchical_link_execution_interface_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution interface page {}: {err}",
                path.display()
            ))
        })?;
        let page =
            serde_json::from_slice::<SourcePackHierarchicalLinkExecutionInterfacePage>(&bytes)
                .map_err(|err| {
                    CompileError::GpuFrontend(format!(
                        "parse source-pack hierarchical link execution interface page {}: {err}",
                        path.display()
                    ))
                })?;
        validate_source_pack_hierarchical_link_execution_interface_page(
            &page,
            target,
            group_index,
            page_index,
        )?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_object_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionObjectPage, CompileError> {
        let path = self.hierarchical_link_execution_object_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution object page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionObjectPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution object page {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_hierarchical_link_execution_object_page(
            &page,
            target,
            group_index,
            page_index,
        )?;
        Ok(page)
    }

    pub fn load_hierarchical_link_execution_partial_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> Result<SourcePackHierarchicalLinkExecutionPartialPage, CompileError> {
        let path = self.hierarchical_link_execution_partial_page_path_for_target(
            target,
            group_index,
            page_index,
        );
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack hierarchical link execution partial page {}: {err}",
                path.display()
            ))
        })?;
        let page = serde_json::from_slice::<SourcePackHierarchicalLinkExecutionPartialPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack hierarchical link execution partial page {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_hierarchical_link_execution_partial_page(
            &page,
            target,
            group_index,
            page_index,
        )?;
        Ok(page)
    }

    pub fn store_build_job_batch_page_index(
        &self,
        index: &SourcePackBuildJobBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_page_index(index, index.target)?;
        let path = self.build_job_batch_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack job-batch page index: {err}"))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch page index",
        )?;
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
        validate_source_pack_build_job_batch_page_index(&index, target)?;
        Ok(index)
    }

    pub(in crate::compiler) fn store_build_job_batch_prepare_progress(
        &self,
        progress: &SourcePackBuildJobBatchPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_prepare_progress(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch prepare progress",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn load_build_job_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        scheduled_job_count: usize,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildJobBatchPrepareProgress, CompileError> {
        let path = self.build_job_batch_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack job-batch prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<SourcePackBuildJobBatchPrepareProgress>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack job-batch prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_job_batch_prepare_progress(
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
        validate_source_pack_build_job_batch_page_store_input(
            page,
            page.target,
            Some(page.batch_index),
        )?;
        let (dependency_batch_count, dependency_page_count) =
            store_source_pack_build_job_batch_dependency_pages(
                self,
                page.target,
                &page.dependency,
            )?;
        let (dependency_range_count, dependency_range_page_count, dependency_range_batch_count) =
            store_source_pack_build_job_batch_dependency_range_pages(
                self,
                page.target,
                &page.dependency,
            )?;
        let mut stored_page = page.clone();
        stored_page.dependency.dependency_batch_indices.clear();
        stored_page.dependency.dependency_batch_count = dependency_batch_count;
        stored_page.dependency.dependency_page_count = dependency_page_count;
        stored_page.dependency.dependency_batch_ranges.clear();
        stored_page.dependency.dependency_range_count = dependency_range_count;
        stored_page.dependency.dependency_range_page_count = dependency_range_page_count;
        stored_page.dependency.dependency_range_batch_count = dependency_range_batch_count;
        validate_source_pack_build_job_batch_page(
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
        write_source_pack_filesystem_file_atomically(&path, &bytes, "source-pack job-batch page")?;
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
        validate_source_pack_build_job_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    pub fn store_build_job_batch_dependency_page(
        &self,
        page: &SourcePackBuildJobBatchDependencyPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_dependency_page(
            page,
            page.target,
            page.batch_index,
            page.page_index,
        )?;
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch dependency page",
        )?;
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
        validate_source_pack_build_job_batch_dependency_page(
            &page,
            target,
            batch_index,
            page_index,
        )?;
        Ok(page)
    }

    pub fn store_build_job_batch_dependency_range_page(
        &self,
        page: &SourcePackBuildJobBatchDependencyRangePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_dependency_range_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch dependency range page",
        )?;
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
        validate_source_pack_build_job_batch_dependency_range_page(
            &page,
            target,
            batch_index,
            page_index,
        )?;
        Ok(page)
    }

    pub fn store_build_job_batch_dependents_page(
        &self,
        page: &SourcePackBuildJobBatchDependentsPage,
        batch_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_dependents_page_store_input(
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
        validate_source_pack_build_job_batch_dependents_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch dependents page",
        )?;
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
                    return Err(source_pack_artifact_shard_contract_error(format!(
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
                return source_pack_empty_build_job_batch_dependents_page(
                    target,
                    batch_index,
                    batch_count,
                );
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
        validate_source_pack_build_job_batch_dependents_page(
            &page,
            target,
            batch_count,
            Some(batch_index),
        )?;
        Ok(page)
    }

    pub fn load_build_job_batch_dependents_page_with_embedded_count_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildJobBatchDependentsPage, CompileError> {
        let path = self.build_job_batch_dependents_page_path_for_target(target, batch_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                let index = self.load_build_job_batch_page_index_for_target(target)?;
                return self.load_build_job_batch_dependents_page_for_target(
                    target,
                    batch_index,
                    index.batch_count,
                );
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
        let batch_count = page.batch_count;
        if batch_count == 0 {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "job-batch dependents page {} does not record a batch count",
                page.batch_index
            )));
        }
        validate_source_pack_build_job_batch_dependents_page(
            &page,
            target,
            batch_count,
            Some(batch_index),
        )?;
        Ok(page)
    }

    pub fn store_build_job_batch_dependent_batch_page(
        &self,
        page: &SourcePackBuildJobBatchDependentBatchPage,
        batch_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_job_batch_dependent_batch_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch dependent-batch page",
        )?;
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
        validate_source_pack_build_job_batch_dependent_batch_page(
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
        validate_source_pack_build_job_batch_job_locator_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job-batch job-locator page",
        )?;
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
        validate_source_pack_build_job_batch_job_locator_page(
            &page,
            target,
            scheduled_job_count,
            Some(job_index),
        )?;
        Ok(page)
    }

    pub(in crate::compiler) fn store_build_artifact_ref_prepare_progress(
        &self,
        progress: &SourcePackBuildArtifactRefPrepareProgress,
        schedule_index: &SourcePackLibraryScheduleIndex,
        library_partition_index: &SourcePackLibraryPartitionIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_artifact_ref_prepare_progress(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack artifact-ref prepare progress",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn load_build_artifact_ref_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        schedule_index: &SourcePackLibraryScheduleIndex,
        library_partition_index: &SourcePackLibraryPartitionIndex,
    ) -> Result<SourcePackBuildArtifactRefPrepareProgress, CompileError> {
        let path = self.build_artifact_ref_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack artifact-ref prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<SourcePackBuildArtifactRefPrepareProgress>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack artifact-ref prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_artifact_ref_prepare_progress(
            &progress,
            schedule_index,
            library_partition_index,
        )?;
        Ok(progress)
    }

    pub fn store_build_artifact_ref_index(
        &self,
        index: &SourcePackBuildArtifactRefIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_artifact_ref_index(index, index.target)?;
        let path = self.build_artifact_ref_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack artifact-ref index: {err}"))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack artifact-ref index",
        )?;
        Ok(path)
    }

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
        validate_source_pack_build_artifact_ref_index(&index, target)?;
        Ok(index)
    }

    pub fn store_build_artifact_ref_page(
        &self,
        page: &SourcePackBuildArtifactRefPage,
        artifact_count: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_artifact_ref_page(
            page,
            page.target,
            artifact_count,
            Some(page.artifact_index),
        )?;
        let path = self.build_artifact_ref_page_path_for_target(page.target, page.artifact_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack artifact-ref page {}: {err}",
                page.artifact_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack artifact-ref page",
        )?;
        Ok(path)
    }

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
        validate_source_pack_build_artifact_ref_page(
            &page,
            target,
            artifact_count,
            Some(artifact_index),
        )?;
        Ok(page)
    }

    pub fn store_job_artifact_input_interface_page(
        &self,
        page: &SourcePackJobArtifactInputInterfacePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_job_artifact_input_interface_page(
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack job artifact input interface page",
        )?;
        Ok(path)
    }

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
        validate_source_pack_job_artifact_input_interface_page(
            &page, target, job_index, page_index,
        )?;
        Ok(page)
    }

    pub fn store_build_link_batch_page_index(
        &self,
        index: &SourcePackBuildLinkBatchPageIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_link_batch_page_index(index, index.target)?;
        let path = self.build_link_batch_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-batch page index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack link-batch page index",
        )?;
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
        validate_source_pack_build_link_batch_page_index(&index, target)?;
        Ok(index)
    }

    pub(in crate::compiler) fn store_build_link_batch_prepare_progress(
        &self,
        progress: &SourcePackBuildLinkBatchPrepareProgress,
    ) -> Result<PathBuf, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(progress.target);
        let bytes = serde_json::to_vec_pretty(progress).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-batch prepare progress: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack link-batch prepare progress",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn load_build_link_batch_prepare_progress_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_ref_index: &SourcePackBuildArtifactRefIndex,
        batch_limits: SourcePackJobBatchLimits,
    ) -> Result<SourcePackBuildLinkBatchPrepareProgress, CompileError> {
        let path = self.build_link_batch_prepare_progress_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link-batch prepare progress {}: {err}",
                path.display()
            ))
        })?;
        let progress = serde_json::from_slice::<SourcePackBuildLinkBatchPrepareProgress>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link-batch prepare progress {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_link_batch_prepare_progress(
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
        validate_source_pack_build_link_interface_batch_page(
            page,
            page.target,
            Some(page.batch_index),
        )?;
        let path =
            self.build_link_interface_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-interface batch page {}: {err}",
                page.batch_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack link-interface batch page",
        )?;
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
        validate_source_pack_build_link_interface_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    pub fn store_build_link_object_batch_page(
        &self,
        page: &SourcePackBuildLinkObjectBatchPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_link_object_batch_page(
            page,
            page.target,
            Some(page.batch_index),
        )?;
        let path = self.build_link_object_batch_page_path_for_target(page.target, page.batch_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack link-object batch page {}: {err}",
                page.batch_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack link-object batch page",
        )?;
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
        validate_source_pack_build_link_object_batch_page(&page, target, Some(batch_index))?;
        Ok(page)
    }

    pub fn store_work_queue(
        &self,
        index: &SourcePackWorkQueueIndex,
        pages: &[SourcePackWorkQueuePage],
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_index(index, index.target)?;
        if pages.len() != index.work_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue store has {} pages but index item count {}",
                pages.len(),
                index.work_item_count
            )));
        }
        let artifact_item_count = source_pack_work_queue_artifact_item_count_from_pages(pages);
        if artifact_item_count != index.artifact_item_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue store has {artifact_item_count} artifact-backed items but index records {}",
                index.artifact_item_count
            )));
        }
        for (item_index, page) in pages.iter().enumerate() {
            validate_source_pack_work_queue_page(page, index.target, Some(item_index))?;
            self.store_work_queue_page(page)?;
        }
        let path = self.work_queue_index_path_for_target(index.target);
        validate_source_pack_work_queue_index(index, index.target)?;
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack work queue index: {err}"))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue index",
        )?;
        Ok(path)
    }

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
        validate_source_pack_work_queue_index(&index, target)?;
        Ok(index)
    }

    pub fn store_work_queue_page(
        &self,
        page: &SourcePackWorkQueuePage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_page_store_input(page, page.target, Some(page.item_index))?;
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
        validate_source_pack_work_queue_page(&stored_page, page.target, Some(page.item_index))?;
        let path = self.work_queue_page_path_for_target(page.target, page.item_index);
        let bytes = serde_json::to_vec_pretty(&stored_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue page {}: {err}",
                page.item_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(&path, &bytes, "source-pack work queue page")?;
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
                return Err(source_pack_library_partition_contract_error(format!(
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
                return Err(source_pack_library_partition_contract_error(format!(
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
        validate_source_pack_work_queue_page(&page, target, Some(item_index))?;
        Ok(page)
    }

    pub fn store_work_queue_dependencies_page(
        &self,
        page: &SourcePackWorkQueueDependenciesPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_dependencies_page(
            page,
            page.target,
            page.item_index,
            page.page_index,
        )?;
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue dependencies page",
        )?;
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
        validate_source_pack_work_queue_dependencies_page(&page, target, item_index, page_index)?;
        Ok(page)
    }

    pub fn store_work_queue_dependents_page(
        &self,
        page: &SourcePackWorkQueueDependentsPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_dependents_page(
            page,
            page.target,
            page.item_index,
            page.page_index,
        )?;
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue dependents page",
        )?;
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
        validate_source_pack_work_queue_dependents_page(&page, target, item_index, page_index)?;
        Ok(page)
    }

    pub fn store_work_queue_progress(
        &self,
        index: &SourcePackWorkQueueProgressIndex,
        pages: &[SourcePackWorkQueueProgressPage],
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_progress_index(index, index.target)?;
        if pages.len() != index.page_count {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress store has {} pages but index page count {}",
                pages.len(),
                index.page_count
            )));
        }
        let mut artifact_item_count = 0usize;
        let mut completed_item_count = 0usize;
        let mut ready_item_count = 0usize;
        let mut ready_artifact_item_count = 0usize;
        let mut claimed_item_count = 0usize;
        let mut first_ready_item_index = None;
        let mut first_ready_artifact_item_index = None;
        for (position, page) in pages.iter().enumerate() {
            if page.page_index != position {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue progress store page slot {position} has page index {}",
                    page.page_index
                )));
            }
            if page.target != index.target {
                return Err(source_pack_library_partition_contract_error(format!(
                    "work queue progress store page {} target {:?} does not match index target {:?}",
                    page.page_index, page.target, index.target
                )));
            }
            let summary = source_pack_work_queue_progress_page_summary(page);
            source_pack_work_queue_progress_validate_page_summary_shape(index, &summary)?;
            artifact_item_count = artifact_item_count.saturating_add(summary.artifact_item_count);
            completed_item_count =
                completed_item_count.saturating_add(summary.completed_item_count);
            ready_item_count = ready_item_count.saturating_add(summary.ready_item_count);
            ready_artifact_item_count =
                ready_artifact_item_count.saturating_add(summary.ready_artifact_item_count);
            claimed_item_count = claimed_item_count.saturating_add(summary.claimed_item_count);
            first_ready_item_index = first_ready_item_index.or(summary.first_ready_item_index);
            first_ready_artifact_item_index =
                first_ready_artifact_item_index.or(summary.first_ready_artifact_item_index);
            self.store_work_queue_progress_page(page)?;
        }
        if artifact_item_count != index.artifact_item_count
            || completed_item_count != index.completed_item_count
            || ready_item_count != index.ready_item_count
            || ready_artifact_item_count != index.ready_artifact_item_count
            || claimed_item_count != index.claimed_item_count
            || first_ready_item_index != index.first_ready_item_index
            || first_ready_artifact_item_index != index.first_ready_artifact_item_index
        {
            return Err(source_pack_library_partition_contract_error(format!(
                "work queue progress store page summaries artifact/completed/ready/ready-artifact/claimed {artifact_item_count}/{completed_item_count}/{ready_item_count}/{ready_artifact_item_count}/{claimed_item_count} first-ready {:?}/{:?} do not match compact index {}/{}/{}/{}/{} {:?}/{:?}",
                first_ready_item_index,
                first_ready_artifact_item_index,
                index.artifact_item_count,
                index.completed_item_count,
                index.ready_item_count,
                index.ready_artifact_item_count,
                index.claimed_item_count,
                index.first_ready_item_index,
                index.first_ready_artifact_item_index
            )));
        }
        for directory_page_index in 0..index
            .page_count
            .div_ceil(SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE)
        {
            let directory_page = source_pack_work_queue_progress_directory_page_from_summaries(
                self,
                index.target,
                index,
                &[],
                directory_page_index,
            )?;
            self.store_work_queue_progress_directory_page_for_target(
                index.target,
                &directory_page,
            )?;
        }
        self.store_work_queue_progress_directory_index_pages_for_index(index)?;
        self.store_work_queue_progress_index(index)
    }

    #[cfg(test)]
    pub(in crate::compiler) fn store_work_queue_progress_directory_pages_for_index(
        &self,
        index: &SourcePackWorkQueueProgressIndex,
    ) -> Result<(), CompileError> {
        validate_source_pack_work_queue_progress_index(index, index.target)?;
        let directory_page_count = source_pack_work_queue_progress_directory_page_count(index)?;
        for directory_page_index in 0..directory_page_count {
            let directory_page = source_pack_work_queue_progress_directory_page_from_summaries(
                self,
                index.target,
                index,
                &[],
                directory_page_index,
            )?;
            self.store_work_queue_progress_directory_page_for_target(
                index.target,
                &directory_page,
            )?;
        }
        self.store_work_queue_progress_directory_index_pages_for_index(index)
    }

    pub(in crate::compiler) fn store_work_queue_progress_directory_index_pages_for_index(
        &self,
        index: &SourcePackWorkQueueProgressIndex,
    ) -> Result<(), CompileError> {
        validate_source_pack_work_queue_progress_index(index, index.target)?;
        let directory_index_page_count =
            source_pack_work_queue_progress_directory_index_page_count(index)?;
        for directory_index_page_index in 0..directory_index_page_count {
            let directory_index_page =
                source_pack_work_queue_progress_directory_index_page_from_directory_pages(
                    self,
                    index.target,
                    index,
                    &[],
                    directory_index_page_index,
                )?;
            self.store_work_queue_progress_directory_index_page_for_target(
                index.target,
                &directory_index_page,
                index,
            )?;
        }
        Ok(())
    }

    pub fn store_work_queue_progress_index(
        &self,
        index: &SourcePackWorkQueueProgressIndex,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_progress_index(index, index.target)?;
        let path = self.work_queue_progress_index_path_for_target(index.target);
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue progress index",
        )?;
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
        validate_source_pack_work_queue_progress_index(&index, target)?;
        Ok(index)
    }

    pub fn store_work_queue_progress_page(
        &self,
        page: &SourcePackWorkQueueProgressPage,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_progress_page(page, page.target, Some(page.page_index))?;
        let path = self.work_queue_progress_page_path_for_target(page.target, page.page_index);
        let bytes = serde_json::to_vec_pretty(page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress page {}: {err}",
                page.page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue progress page",
        )?;
        self.store_work_queue_progress_page_summary_for_target(
            page.target,
            &source_pack_work_queue_progress_page_summary(page),
        )?;
        Ok(path)
    }

    pub fn store_work_queue_progress_page_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        summary: &SourcePackWorkQueueProgressPageSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_work_queue_progress_page_summary(summary)?;
        let path =
            self.work_queue_progress_page_summary_path_for_target(target, summary.page_index);
        let bytes = serde_json::to_vec_pretty(summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack work queue progress page summary {}: {err}",
                summary.page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
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
        validate_source_pack_work_queue_progress_page_summary(&summary)?;
        Ok(Some(summary))
    }

    pub fn store_work_queue_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page: &SourcePackWorkQueueProgressDirectoryPage,
    ) -> Result<PathBuf, CompileError> {
        if page.target != target {
            return Err(source_pack_library_partition_contract_error(format!(
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
        write_source_pack_filesystem_file_atomically(
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
        validate_source_pack_work_queue_progress_directory_index_page(page, target, index)?;
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
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack work queue progress directory-index page",
        )?;
        Ok(path)
    }

    pub fn try_load_work_queue_progress_directory_index_page_for_target(
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
        validate_source_pack_work_queue_progress_page(&page, target, Some(page_index))?;
        Ok(page)
    }

    pub fn store_build_artifact_manifest(
        &self,
        manifest: &SourcePackBuildArtifactManifest,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_artifact_manifest(manifest)?;
        let path = self.artifact_manifest_path_for_target(manifest.target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack build artifact manifest directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let compact_manifest = source_pack_compact_build_artifact_manifest(manifest)?;
        let bytes = serde_json::to_vec_pretty(&compact_manifest).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build artifact manifest: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build artifact manifest",
        )?;
        Ok(path)
    }

    pub fn load_build_artifact_manifest(
        &self,
    ) -> Result<SourcePackBuildArtifactManifest, CompileError> {
        self.load_build_artifact_manifest_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn load_build_artifact_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactManifest, CompileError> {
        let path = self.artifact_manifest_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact manifest {}: {err}",
                path.display()
            ))
        })?;
        let manifest =
            serde_json::from_slice::<SourcePackBuildArtifactManifest>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact manifest {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_artifact_manifest(&manifest)?;
        Ok(manifest)
    }

    pub fn store_build_artifact_shard_plan(
        &self,
        plan: &SourcePackBuildArtifactShardPlan,
    ) -> Result<SourcePackFilesystemArtifactShardStoreResult, CompileError> {
        validate_source_pack_build_artifact_shard_plan(plan)?;
        let index = &plan.index;
        let index_path = self.artifact_shard_index_path_for_target(index.target);
        let link_input_index = source_pack_build_link_input_shard_index(plan)?;
        let link_input_index_path = self.link_input_shard_index_path_for_target(index.target);
        let link_input_index_bytes =
            serde_json::to_vec_pretty(&link_input_index).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "serialize source-pack link input shard index: {err}"
                ))
            })?;
        let mut artifact_shard_count = 0usize;
        let mut batch_shard_locator_count = 0usize;
        for shard in &plan.shards {
            let path = self.artifact_shard_path_for_target(index.target, shard.shard_index);
            let bytes = serde_json::to_vec_pretty(shard).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "serialize source-pack build artifact shard {}: {err}",
                    shard.shard_index
                ))
            })?;
            write_source_pack_filesystem_file_atomically(
                &path,
                &bytes,
                "source-pack build artifact shard",
            )?;
            artifact_shard_count += 1;

            if shard.kind == SourcePackBuildArtifactShardKind::JobBatches {
                for &batch_index in &shard.batch_indices {
                    let locator = SourcePackBuildBatchShardLocator {
                        version: SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION,
                        target: index.target,
                        batch_index,
                        shard_index: shard.shard_index,
                    };
                    let locator_path =
                        self.batch_shard_locator_path_for_target(index.target, batch_index);
                    let bytes = serde_json::to_vec_pretty(&locator).map_err(|err| {
                        CompileError::GpuFrontend(format!(
                            "serialize source-pack batch shard locator {batch_index}: {err}"
                        ))
                    })?;
                    write_source_pack_filesystem_file_atomically(
                        &locator_path,
                        &bytes,
                        "source-pack batch shard locator",
                    )?;
                    batch_shard_locator_count += 1;
                }
            }
        }
        validate_source_pack_build_artifact_shard_index(index)?;
        let bytes = serde_json::to_vec_pretty(index).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build artifact shard index: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &link_input_index_path,
            &link_input_index_bytes,
            "source-pack link input shard index",
        )?;
        write_source_pack_filesystem_file_atomically(
            &index_path,
            &bytes,
            "source-pack build artifact shard index",
        )?;

        Ok(SourcePackFilesystemArtifactShardStoreResult {
            artifact_shard_index_path: index_path,
            link_input_shard_index_path: link_input_index_path,
            artifact_shard_count,
            artifact_execution_shard_count: 0,
            batch_shard_locator_count,
        })
    }

    pub fn store_build_artifact_execution_shards(
        &self,
        manifest: &SourcePackPathBuildManifest,
        plan: &SourcePackBuildArtifactShardPlan,
    ) -> Result<SourcePackFilesystemArtifactExecutionShardStoreResult, CompileError> {
        validate_source_pack_path_build_manifest_versions(manifest)?;
        validate_source_pack_build_artifact_shard_plan(plan)?;
        store_source_pack_job_batch_dependents_pages_from_manifest_dependencies(
            self,
            manifest.artifacts.target,
            &manifest.artifacts.batch_dependencies.batches,
            manifest.artifacts.job_batch_count,
        )?;
        let mut artifact_execution_shard_count = 0usize;
        for shard in &plan.shards {
            let execution_shard = source_pack_build_artifact_execution_shard(manifest, shard)?;
            self.store_build_artifact_execution_shard_with_batch_count(
                &execution_shard,
                Some(manifest.artifacts.job_batch_count),
            )?;
            artifact_execution_shard_count += 1;
        }
        Ok(SourcePackFilesystemArtifactExecutionShardStoreResult {
            artifact_execution_shard_count,
        })
    }

    pub fn store_build_artifact_execution_shard_records(
        &self,
        execution_shards: &[SourcePackBuildArtifactExecutionShard],
    ) -> Result<SourcePackFilesystemArtifactExecutionShardStoreResult, CompileError> {
        let mut artifact_execution_shard_count = 0usize;
        for execution_shard in execution_shards {
            self.store_build_artifact_execution_shard_with_batch_count(execution_shard, None)?;
            artifact_execution_shard_count += 1;
        }
        Ok(SourcePackFilesystemArtifactExecutionShardStoreResult {
            artifact_execution_shard_count,
        })
    }

    pub fn store_build_artifact_execution_shard_record(
        &self,
        execution_shard: &SourcePackBuildArtifactExecutionShard,
    ) -> Result<PathBuf, CompileError> {
        self.store_build_artifact_execution_shard_with_batch_count(execution_shard, None)
    }

    pub(in crate::compiler) fn store_build_artifact_execution_shard_with_batch_count(
        &self,
        execution_shard: &SourcePackBuildArtifactExecutionShard,
        batch_count: Option<usize>,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_artifact_execution_shard_store_input(
            execution_shard,
            execution_shard.target,
        )?;
        let mut stored_execution_shard = execution_shard.clone();
        for dependency in &mut stored_execution_shard.batch_dependencies {
            let (dependency_batch_count, dependency_page_count) =
                store_source_pack_build_job_batch_dependency_pages(
                    self,
                    stored_execution_shard.target,
                    dependency,
                )?;
            let (dependency_range_count, dependency_range_page_count, dependency_range_batch_count) =
                store_source_pack_build_job_batch_dependency_range_pages(
                    self,
                    stored_execution_shard.target,
                    dependency,
                )?;
            dependency.dependency_batch_indices.clear();
            dependency.dependency_batch_count = dependency_batch_count;
            dependency.dependency_page_count = dependency_page_count;
            dependency.dependency_batch_ranges.clear();
            dependency.dependency_range_count = dependency_range_count;
            dependency.dependency_range_page_count = dependency_range_page_count;
            dependency.dependency_range_batch_count = dependency_range_batch_count;
        }
        let mut dependent_batch_count = batch_count;
        for dependents in &mut stored_execution_shard.batch_dependents {
            if !dependents.dependent_batch_indices.is_empty() {
                if dependent_batch_count.is_none() {
                    dependent_batch_count = Some(
                        Self::source_pack_execution_shard_inferred_batch_count(execution_shard)?,
                    );
                }
                let dependent_batch_count =
                    dependent_batch_count.expect("execution-shard dependent batch count");
                let page = SourcePackBuildJobBatchDependentsPage {
                    version: SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
                    target: stored_execution_shard.target,
                    batch_count: dependent_batch_count,
                    batch_index: dependents.batch_index,
                    dependents: dependents.clone(),
                    dependent_batch_count: 0,
                    dependent_page_count: 0,
                };
                self.store_build_job_batch_dependents_page(&page, dependent_batch_count)?;
                dependents.dependent_batch_indices.clear();
            }
        }
        for job_manifest in &mut stored_execution_shard.job_artifacts {
            match job_manifest.phase {
                SourcePackJobPhase::LibraryFrontend | SourcePackJobPhase::Codegen => {
                    let explicit_input_interface_count = job_manifest.input_interfaces.len();
                    if !job_manifest.input_interfaces.is_empty() {
                        let input_interface_page_count = self
                            .store_job_artifact_input_interface_pages_from_refs(
                                stored_execution_shard.target,
                                job_manifest.job_index,
                                &job_manifest.input_interfaces,
                            )?;
                        job_manifest.input_interface_page_count = input_interface_page_count;
                        job_manifest.input_interfaces.clear();
                    }
                    let retained_input_interface_count = explicit_input_interface_count
                        .saturating_add(source_pack_job_index_range_dependency_count(
                            &job_manifest.input_interface_ranges,
                        ))
                        .saturating_add(source_pack_artifact_index_range_count(
                            &job_manifest.input_interface_artifact_ranges,
                        ));
                    job_manifest.input_interface_count = job_manifest
                        .input_interface_count
                        .max(retained_input_interface_count);
                }
                SourcePackJobPhase::Link => {
                    job_manifest.input_interface_count = 0;
                    job_manifest.input_interface_page_count = 0;
                    job_manifest.input_interface_ranges.clear();
                    job_manifest.input_interfaces.clear();
                    job_manifest.input_objects.clear();
                }
            }
        }
        source_pack_prune_persisted_execution_shard_artifact_refs(&mut stored_execution_shard)?;
        validate_source_pack_build_artifact_execution_shard(
            &stored_execution_shard,
            stored_execution_shard.target,
        )?;
        let path = self.artifact_execution_shard_path_for_target(
            stored_execution_shard.target,
            stored_execution_shard.shard.shard_index,
        );
        let bytes = serde_json::to_vec_pretty(&stored_execution_shard).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build artifact execution shard {}: {err}",
                stored_execution_shard.shard.shard_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build artifact execution shard",
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_job_artifact_input_interface_pages_from_refs(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        input_interfaces: &[SourcePackArtifactRef],
    ) -> Result<usize, CompileError> {
        for (page_index, input_interfaces) in input_interfaces
            .chunks(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE)
            .enumerate()
        {
            let page = SourcePackJobArtifactInputInterfacePage {
                version: SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION,
                target,
                job_index,
                page_index,
                first_input_position: page_index
                    .saturating_mul(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE),
                input_count: input_interfaces.len(),
                input_interfaces: input_interfaces.to_vec(),
            };
            self.store_job_artifact_input_interface_page(&page)?;
        }
        Ok(input_interfaces
            .len()
            .div_ceil(SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE))
    }

    pub(in crate::compiler) fn source_pack_execution_shard_inferred_batch_count(
        execution_shard: &SourcePackBuildArtifactExecutionShard,
    ) -> Result<usize, CompileError> {
        let mut batch_count = 0usize;
        for batch_index in execution_shard
            .shard
            .batch_indices
            .iter()
            .copied()
            .chain(
                execution_shard
                    .batch_dependencies
                    .iter()
                    .map(|dependency| dependency.batch_index),
            )
            .chain(
                execution_shard
                    .batch_dependencies
                    .iter()
                    .flat_map(|dependency| dependency.dependency_batch_indices.iter().copied()),
            )
            .chain(
                execution_shard
                    .batch_dependents
                    .iter()
                    .map(|dependents| dependents.batch_index),
            )
            .chain(
                execution_shard
                    .batch_dependents
                    .iter()
                    .flat_map(|dependents| dependents.dependent_batch_indices.iter().copied()),
            )
        {
            batch_count = batch_count.max(batch_index.checked_add(1).ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} batch index overflows inferred batch count",
                    execution_shard.shard.shard_index
                ))
            })?);
        }
        for range in execution_shard
            .batch_dependencies
            .iter()
            .flat_map(|dependency| dependency.dependency_batch_ranges.iter())
        {
            batch_count = batch_count.max(range.end_batch_index().ok_or_else(|| {
                source_pack_artifact_shard_contract_error(format!(
                    "execution shard {} dependency range overflows inferred batch count",
                    execution_shard.shard.shard_index
                ))
            })?);
        }
        Ok(batch_count)
    }

    pub fn load_build_artifact_shard_index(
        &self,
    ) -> Result<SourcePackBuildArtifactShardIndex, CompileError> {
        self.load_build_artifact_shard_index_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn load_build_artifact_shard_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildArtifactShardIndex, CompileError> {
        let path = self.artifact_shard_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact shard index {}: {err}",
                path.display()
            ))
        })?;
        let index =
            serde_json::from_slice::<SourcePackBuildArtifactShardIndex>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact shard index {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_artifact_shard_index(&index)?;
        if index.target != target {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded shard index target {:?} does not match requested target {:?}",
                index.target, target
            )));
        }
        Ok(index)
    }

    pub fn load_link_input_shard_index_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildLinkInputShardIndex, CompileError> {
        let path = self.link_input_shard_index_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack link input shard index {}: {err}",
                path.display()
            ))
        })?;
        let index = serde_json::from_slice::<SourcePackBuildLinkInputShardIndex>(&bytes).map_err(
            |err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack link input shard index {}: {err}",
                    path.display()
                ))
            },
        )?;
        validate_source_pack_build_link_input_shard_index(&index, target)?;
        Ok(index)
    }

    pub fn load_build_artifact_shard(
        &self,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactShard, CompileError> {
        self.load_build_artifact_shard_for_target(SourcePackArtifactTarget::Generic, shard_index)
    }

    pub fn load_build_artifact_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactShard, CompileError> {
        let path = self.artifact_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact shard {}: {err}",
                path.display()
            ))
        })?;
        let shard =
            serde_json::from_slice::<SourcePackBuildArtifactShard>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build artifact shard {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_artifact_shard(&shard, target)?;
        if shard.shard_index != shard_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded shard {} from {} but requested shard {}",
                shard.shard_index,
                path.display(),
                shard_index
            )));
        }
        Ok(shard)
    }

    pub fn load_build_artifact_execution_shard(
        &self,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
        self.load_build_artifact_execution_shard_for_target(
            SourcePackArtifactTarget::Generic,
            shard_index,
        )
    }

    pub fn load_build_artifact_execution_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildArtifactExecutionShard, CompileError> {
        let path = self.artifact_execution_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build artifact execution shard {}: {err}",
                path.display()
            ))
        })?;
        let execution_shard = serde_json::from_slice::<SourcePackBuildArtifactExecutionShard>(
            &bytes,
        )
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build artifact execution shard {}: {err}",
                path.display()
            ))
        })?;
        validate_source_pack_build_artifact_execution_shard(&execution_shard, target)?;
        if execution_shard.shard.shard_index != shard_index {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "loaded execution shard {} from {} but requested shard {}",
                execution_shard.shard.shard_index,
                path.display(),
                shard_index
            )));
        }
        Ok(execution_shard)
    }

    pub fn load_build_batch_shard_locator_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> Result<SourcePackBuildBatchShardLocator, CompileError> {
        let path = self.batch_shard_locator_path_for_target(target, batch_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack batch shard locator {}: {err}",
                path.display()
            ))
        })?;
        let locator =
            serde_json::from_slice::<SourcePackBuildBatchShardLocator>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack batch shard locator {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_batch_shard_locator(&locator, target, batch_index)?;
        Ok(locator)
    }

    pub fn store_path_build_manifest(
        &self,
        manifest: &SourcePackPathBuildManifest,
    ) -> Result<PathBuf, CompileError> {
        self.store_path_build_manifest_with_shard_limits(
            manifest,
            SourcePackBuildShardLimits::default(),
        )
    }

    pub fn store_path_build_manifest_with_shard_limits(
        &self,
        manifest: &SourcePackPathBuildManifest,
        shard_limits: SourcePackBuildShardLimits,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_path_build_manifest_versions(manifest)?;
        store_source_pack_job_batch_dependents_pages_from_manifest_dependencies(
            self,
            manifest.artifacts.target,
            &manifest.artifacts.batch_dependencies.batches,
            manifest.artifacts.job_batch_count,
        )?;
        let mut link_interface_shard_range = None;
        let mut link_object_shard_range = None;
        let shard_index = manifest.artifacts.try_for_each_build_artifact_shard(
            shard_limits,
            |shard| -> Result<(), CompileError> {
                store_source_pack_build_artifact_shard_page(self, shard)?;
                store_source_pack_build_batch_shard_locators(self, shard)?;
                let execution_shard = source_pack_build_artifact_execution_shard(manifest, shard)?;
                self.store_build_artifact_execution_shard_with_batch_count(
                    &execution_shard,
                    Some(manifest.artifacts.job_batch_count),
                )?;
                match shard.kind {
                    SourcePackBuildArtifactShardKind::LinkInterfaceBatches => {
                        source_pack_extend_link_input_shard_range(
                            &mut link_interface_shard_range,
                            shard.shard_index,
                            "interface",
                        )?;
                    }
                    SourcePackBuildArtifactShardKind::LinkObjectBatches => {
                        source_pack_extend_link_input_shard_range(
                            &mut link_object_shard_range,
                            shard.shard_index,
                            "object",
                        )?;
                    }
                    SourcePackBuildArtifactShardKind::JobBatches => {}
                }
                Ok(())
            },
        )?;
        let link_input_index = SourcePackBuildLinkInputShardIndex {
            version: SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
            target: manifest.artifacts.target,
            link_interface_shard_range,
            link_object_shard_range,
        };
        validate_source_pack_build_link_input_shard_index(
            &link_input_index,
            manifest.artifacts.target,
        )?;
        store_source_pack_build_artifact_shard_compact_indexes(
            self,
            &shard_index,
            &link_input_index,
        )?;
        self.store_initial_build_progress_shards(&shard_index)?;
        self.store_compact_path_build_manifest(manifest)
    }

    pub fn store_compact_path_build_manifest(
        &self,
        manifest: &SourcePackPathBuildManifest,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_path_build_manifest_versions(manifest)?;
        let path = self.build_manifest_path_for_target(manifest.artifacts.target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack path build manifest directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let compact_manifest = SourcePackPathBuildManifest {
            source_files: Vec::new(),
            library_dependencies: Vec::new(),
            artifacts: source_pack_compact_build_artifact_manifest(&manifest.artifacts)?,
            ..manifest.clone()
        };
        validate_source_pack_path_build_manifest_versions(&compact_manifest)?;
        let bytes = serde_json::to_vec_pretty(&compact_manifest).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack path build manifest: {err}"))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack path build manifest",
        )?;
        Ok(path)
    }

    pub fn load_path_build_manifest(&self) -> Result<SourcePackPathBuildManifest, CompileError> {
        self.load_path_build_manifest_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn load_path_build_manifest_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackPathBuildManifest, CompileError> {
        let path = self.build_manifest_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack path build manifest {}: {err}",
                path.display()
            ))
        })?;
        let manifest =
            serde_json::from_slice::<SourcePackPathBuildManifest>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack path build manifest {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_path_build_manifest_versions(&manifest)?;
        Ok(manifest)
    }

    pub fn store_build_progress_shard(
        &self,
        shard: &SourcePackBuildProgressShard,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_shard(shard)?;
        let old_shard_path =
            self.build_progress_shard_path_for_target(shard.target, shard.shard_index);
        let old_shard = if old_shard_path.is_file() {
            Some(self.load_build_progress_shard_for_target(shard.target, shard.shard_index)?)
        } else {
            None
        };
        let path = self.write_build_progress_shard_file(shard)?;
        let summary =
            self.update_build_progress_summary_after_shard_store(old_shard.as_ref(), shard)?;
        self.store_build_progress_directory_page_for_shard(&summary, shard.shard_index)?;
        Ok(path)
    }

    pub(in crate::compiler) fn write_build_progress_shard_file(
        &self,
        shard: &SourcePackBuildProgressShard,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_shard(shard)?;
        let path = self.build_progress_shard_path_for_target(shard.target, shard.shard_index);
        let bytes = serde_json::to_vec_pretty(shard).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress shard {}: {err}",
                shard.shard_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build progress shard",
        )?;
        self.store_build_progress_shard_summary_for_target(
            shard.target,
            &source_pack_build_progress_shard_summary(shard)?,
        )?;
        Ok(path)
    }

    pub fn store_build_progress_shard_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        summary: &SourcePackBuildProgressShardSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_shard_summary(summary)?;
        if summary.target != target {
            return Err(CompileError::GpuFrontend(format!(
                "source-pack progress shard summary target {:?} does not match requested target {:?}",
                summary.target, target
            )));
        }
        let path = self.build_progress_shard_summary_path_for_target(target, summary.shard_index);
        let bytes = serde_json::to_vec_pretty(summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress shard summary {}: {err}",
                summary.shard_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build progress shard summary",
        )?;
        Ok(path)
    }

    pub fn store_build_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page: &SourcePackBuildProgressDirectoryPage,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_directory_page(directory_page, target, summary)?;
        let path = self.build_progress_directory_page_path_for_target(
            target,
            directory_page.directory_page_index,
        );
        let bytes = serde_json::to_vec_pretty(directory_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress directory page {}: {err}",
                directory_page.directory_page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build progress directory page",
        )?;
        Ok(path)
    }

    pub fn try_load_build_progress_directory_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> Result<Option<SourcePackBuildProgressDirectoryPage>, CompileError> {
        let path = self.build_progress_directory_page_path_for_target(target, directory_page_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress directory page {}: {err}",
                    path.display()
                )));
            }
        };
        let directory_page = serde_json::from_slice::<SourcePackBuildProgressDirectoryPage>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress directory page {}: {err}",
                    path.display()
                ))
            })?;
        if directory_page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION {
            return Err(CompileError::GpuFrontend(format!(
                "unsupported source-pack build progress directory page version {}; expected {}",
                directory_page.version, SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION
            )));
        }
        if directory_page.target != target
            || directory_page.directory_page_index != directory_page_index
        {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack build progress directory page target {:?} index {} from {} but requested target {:?} index {}",
                directory_page.target,
                directory_page.directory_page_index,
                path.display(),
                target,
                directory_page_index
            )));
        }
        Ok(Some(directory_page))
    }

    pub fn store_build_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page: &SourcePackBuildProgressDirectoryIndexPage,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_directory_index_page(
            directory_index_page,
            target,
            summary,
        )?;
        let path = self.build_progress_directory_index_page_path_for_target(
            target,
            directory_index_page.directory_index_page_index,
        );
        let bytes = serde_json::to_vec_pretty(directory_index_page).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress directory-index page {}: {err}",
                directory_index_page.directory_index_page_index
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build progress directory-index page",
        )?;
        Ok(path)
    }

    pub fn try_load_build_progress_directory_index_page_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> Result<Option<SourcePackBuildProgressDirectoryIndexPage>, CompileError> {
        let path = self.build_progress_directory_index_page_path_for_target(
            target,
            directory_index_page_index,
        );
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress directory-index page {}: {err}",
                    path.display()
                )));
            }
        };
        let directory_index_page = serde_json::from_slice::<
            SourcePackBuildProgressDirectoryIndexPage,
        >(&bytes)
        .map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build progress directory-index page {}: {err}",
                path.display()
            ))
        })?;
        if directory_index_page.version != SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION {
            return Err(CompileError::GpuFrontend(format!(
                "unsupported source-pack build progress directory-index page version {}; expected {}",
                directory_index_page.version,
                SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION
            )));
        }
        if directory_index_page.target != target
            || directory_index_page.directory_index_page_index != directory_index_page_index
        {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack build progress directory-index page target {:?} index {} from {} but requested target {:?} index {}",
                directory_index_page.target,
                directory_index_page.directory_index_page_index,
                path.display(),
                target,
                directory_index_page_index
            )));
        }
        Ok(Some(directory_index_page))
    }

    pub(in crate::compiler) fn store_build_progress_directory_page_for_shard(
        &self,
        summary: &SourcePackBuildProgressSummary,
        shard_index: usize,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_summary(summary)?;
        if shard_index >= summary.job_batch_shard_count {
            return Err(source_pack_artifact_shard_contract_error(format!(
                "source-pack build progress directory cannot refresh shard {shard_index}; summary has {} shards",
                summary.job_batch_shard_count
            )));
        }
        let directory_page_index =
            source_pack_build_progress_directory_page_index_for_shard(shard_index);
        let directory_page = source_pack_build_progress_directory_page_from_summaries(
            self,
            summary.target,
            summary,
            directory_page_index,
        )?;
        let path = self.store_build_progress_directory_page_for_target(
            summary.target,
            &directory_page,
            summary,
        )?;
        let directory_index_page_index =
            source_pack_build_progress_directory_index_page_index_for_directory_page(
                directory_page_index,
            );
        let directory_index_page =
            source_pack_build_progress_directory_index_page_from_directory_pages(
                self,
                summary.target,
                summary,
                Some(&directory_page),
                directory_index_page_index,
            )?;
        self.store_build_progress_directory_index_page_for_target(
            summary.target,
            &directory_index_page,
            summary,
        )?;
        Ok(path)
    }

    pub(in crate::compiler) fn store_build_progress_directory_pages_for_summary(
        &self,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<(), CompileError> {
        let directory_page_count = source_pack_build_progress_directory_page_count(summary)?;
        for directory_page_index in 0..directory_page_count {
            let directory_page = source_pack_build_progress_directory_page_from_summaries(
                self,
                summary.target,
                summary,
                directory_page_index,
            )?;
            self.store_build_progress_directory_page_for_target(
                summary.target,
                &directory_page,
                summary,
            )?;
        }
        let directory_index_page_count =
            source_pack_build_progress_directory_index_page_count(summary)?;
        for directory_index_page_index in 0..directory_index_page_count {
            let directory_index_page =
                source_pack_build_progress_directory_index_page_from_directory_pages(
                    self,
                    summary.target,
                    summary,
                    None,
                    directory_index_page_index,
                )?;
            self.store_build_progress_directory_index_page_for_target(
                summary.target,
                &directory_index_page,
                summary,
            )?;
        }
        Ok(())
    }

    pub fn store_build_progress_summary(
        &self,
        summary: &SourcePackBuildProgressSummary,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_progress_summary(summary)?;
        let path = self.build_progress_summary_path_for_target(summary.target);
        let compact_summary = summary.clone();
        validate_source_pack_build_progress_summary(&compact_summary)?;
        let bytes = serde_json::to_vec_pretty(&compact_summary).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "serialize source-pack build progress summary: {err}"
            ))
        })?;
        write_source_pack_filesystem_file_atomically(
            &path,
            &bytes,
            "source-pack build progress summary",
        )?;
        Ok(path)
    }

    pub fn load_build_progress_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildProgressSummary, CompileError> {
        let path = self.build_progress_summary_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build progress summary {}: {err}",
                path.display()
            ))
        })?;
        let summary =
            serde_json::from_slice::<SourcePackBuildProgressSummary>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress summary {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_progress_summary(&summary)?;
        if summary.target != target {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress summary target {:?} from {} but requested target {:?}",
                summary.target,
                path.display(),
                target
            )));
        }
        Ok(summary)
    }

    pub fn try_load_build_progress_shard_summary_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<Option<SourcePackBuildProgressShardSummary>, CompileError> {
        let path = self.build_progress_shard_summary_path_for_target(target, shard_index);
        let bytes = match fs::read(&path) {
            Ok(bytes) => bytes,
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => return Ok(None),
            Err(err) => {
                return Err(CompileError::GpuFrontend(format!(
                    "read source-pack build progress shard summary {}: {err}",
                    path.display()
                )));
            }
        };
        let summary = serde_json::from_slice::<SourcePackBuildProgressShardSummary>(&bytes)
            .map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress shard summary {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_progress_shard_summary(&summary)?;
        if summary.target != target || summary.shard_index != shard_index {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress shard summary target {:?} index {} from {} but requested target {:?} index {}",
                summary.target,
                summary.shard_index,
                path.display(),
                target,
                shard_index
            )));
        }
        Ok(Some(summary))
    }

    pub(in crate::compiler) fn update_build_progress_summary_after_shard_store(
        &self,
        old_shard: Option<&SourcePackBuildProgressShard>,
        new_shard: &SourcePackBuildProgressShard,
    ) -> Result<SourcePackBuildProgressSummary, CompileError> {
        validate_source_pack_build_progress_shard(new_shard)?;
        if let Some(old_shard) = old_shard {
            validate_source_pack_build_progress_shard(old_shard)?;
            if old_shard.target != new_shard.target
                || old_shard.shard_index != new_shard.shard_index
                || old_shard.batch_indices != new_shard.batch_indices
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack progress shard update changed identity from target {:?} index {} batches {:?} to target {:?} index {} batches {:?}",
                    old_shard.target,
                    old_shard.shard_index,
                    old_shard.batch_indices,
                    new_shard.target,
                    new_shard.shard_index,
                    new_shard.batch_indices
                )));
            }
        }
        let old_shard_summary = old_shard
            .map(source_pack_build_progress_shard_summary)
            .transpose()?;
        let new_shard_summary = source_pack_build_progress_shard_summary(new_shard)?;

        let old_completed_count = old_shard
            .map(|shard| shard.completed_batch_indices.len())
            .unwrap_or(0);
        let new_completed_count = new_shard.completed_batch_indices.len();
        let old_ready_count = old_shard
            .map(|shard| shard.ready_batch_indices.len())
            .unwrap_or(0);
        let new_ready_count = new_shard.ready_batch_indices.len();
        let old_claimed_count = old_shard
            .map(|shard| shard.claimed_batches.len())
            .unwrap_or(0);
        let new_claimed_count = new_shard.claimed_batches.len();
        let old_ready_claimed_count = old_shard_summary
            .as_ref()
            .map(|summary| summary.ready_claimed_batch_count)
            .unwrap_or(0);
        let new_ready_claimed_count = new_shard_summary.ready_claimed_batch_count;
        let old_earliest_claim_lease = old_shard_summary
            .as_ref()
            .and_then(|summary| summary.earliest_claim_lease_expires_unix_nanos);
        let new_earliest_claim_lease = new_shard_summary.earliest_claim_lease_expires_unix_nanos;
        let old_first_ready =
            old_shard.and_then(|shard| shard.ready_batch_indices.iter().copied().min());
        let new_first_ready = new_shard.ready_batch_indices.iter().copied().min();
        let old_job_batch_count = old_shard
            .map(|shard| shard.batch_indices.len())
            .unwrap_or(0);
        let new_job_batch_count = new_shard.batch_indices.len();
        let summary_path = self.build_progress_summary_path_for_target(new_shard.target);
        let mut summary = if summary_path.is_file() {
            self.load_build_progress_summary_for_target(new_shard.target)?
        } else {
            SourcePackBuildProgressSummary::new(new_shard.target, 0)
        };
        summary.job_batch_count = summary
            .job_batch_count
            .saturating_add(new_job_batch_count)
            .checked_sub(old_job_batch_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.job_batch_shard_count = summary
            .job_batch_shard_count
            .max(new_shard.shard_index.saturating_add(1));
        summary.completed_batch_count = summary
            .completed_batch_count
            .saturating_add(new_completed_count)
            .checked_sub(old_completed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary completed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.ready_batch_count = summary
            .ready_batch_count
            .saturating_add(new_ready_count)
            .checked_sub(old_ready_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary ready-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.claimed_batch_count = summary
            .claimed_batch_count
            .saturating_add(new_claimed_count)
            .checked_sub(old_claimed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary claimed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        let previous_earliest_claim_lease = summary.earliest_claim_lease_expires_unix_nanos;
        summary.ready_claimed_batch_count = summary
            .ready_claimed_batch_count
            .saturating_add(new_ready_claimed_count)
            .checked_sub(old_ready_claimed_count)
            .ok_or_else(|| {
                CompileError::GpuFrontend(format!(
                    "source-pack progress summary ready-claimed-count underflow updating shard {}",
                    new_shard.shard_index
                ))
            })?;
        summary.earliest_claim_lease_expires_unix_nanos = if summary.ready_claimed_batch_count == 0
        {
            None
        } else if previous_earliest_claim_lease == old_earliest_claim_lease
            && old_earliest_claim_lease.is_some()
            && new_earliest_claim_lease.map_or(true, |new_earliest| {
                Some(new_earliest) > old_earliest_claim_lease
            })
        {
            source_pack_build_progress_earliest_claim_lease_from_summary_shards_bounded(
                self,
                new_shard.target,
                &summary,
                Some(new_shard.shard_index),
            )?
        } else {
            source_pack_progress_summary_min_lease(
                previous_earliest_claim_lease,
                new_earliest_claim_lease,
            )
        };
        summary.first_ready_batch_index = if summary.ready_batch_count == 0 {
            None
        } else {
            match (
                summary.first_ready_batch_index,
                old_first_ready,
                new_first_ready,
            ) {
                (Some(summary_first), Some(old_first), new_first)
                    if summary_first == old_first
                        && new_first.map_or(true, |new_first| new_first > old_first) =>
                {
                    source_pack_build_progress_first_ready_batch_index_from_summary_pages_bounded(
                        self,
                        new_shard.target,
                        &summary,
                    )?
                }
                (summary_first, _, Some(new_first)) => match summary_first {
                    Some(summary_first) => Some(summary_first.min(new_first)),
                    None => Some(new_first),
                },
                (Some(summary_first), _, None) => Some(summary_first),
                (None, _, None) => {
                    source_pack_build_progress_first_ready_batch_index_from_summary_pages_bounded(
                        self,
                        new_shard.target,
                        &summary,
                    )?
                }
            }
        };
        if let Some(linked_output_key) = &new_shard.linked_output_key {
            if summary
                .linked_output_key
                .as_ref()
                .is_some_and(|existing| existing != linked_output_key)
            {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack progress summary already recorded linked output {:?}, cannot replace with {:?}",
                    summary.linked_output_key.as_deref(),
                    linked_output_key
                )));
            }
            summary.linked_output_key = Some(linked_output_key.clone());
        }
        self.store_build_progress_summary(&summary)?;
        Ok(summary)
    }

    pub fn load_build_progress_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> Result<SourcePackBuildProgressShard, CompileError> {
        let path = self.build_progress_shard_path_for_target(target, shard_index);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build progress shard {}: {err}",
                path.display()
            ))
        })?;
        let shard =
            serde_json::from_slice::<SourcePackBuildProgressShard>(&bytes).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "parse source-pack build progress shard {}: {err}",
                    path.display()
                ))
            })?;
        validate_source_pack_build_progress_shard(&shard)?;
        if shard.target != target || shard.shard_index != shard_index {
            return Err(CompileError::GpuFrontend(format!(
                "loaded source-pack progress shard target {:?} index {} from {} but requested target {:?} index {}",
                shard.target,
                shard.shard_index,
                path.display(),
                target,
                shard_index
            )));
        }
        Ok(shard)
    }

    pub(in crate::compiler) fn load_or_init_build_progress_shard_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_shard: &SourcePackBuildArtifactShard,
    ) -> Result<SourcePackBuildProgressShard, CompileError> {
        let path = self.build_progress_shard_path_for_target(target, artifact_shard.shard_index);
        if !path.is_file() {
            return Ok(SourcePackBuildProgressShard::new(target, artifact_shard));
        }
        let shard =
            self.load_build_progress_shard_for_target(target, artifact_shard.shard_index)?;
        source_pack_validate_progress_shard_matches_artifact_shard(&shard, artifact_shard)?;
        Ok(shard)
    }

    pub fn store_initial_build_progress_shards(
        &self,
        index: &SourcePackBuildArtifactShardIndex,
    ) -> Result<SourcePackFilesystemBuildProgressShardStoreResult, CompileError> {
        validate_source_pack_build_artifact_shard_index(index)?;
        let mut build_progress_shard_count = 0usize;
        let mut ready_batch_count = 0usize;
        let mut first_ready_batch_index = None;
        source_pack_for_each_job_batch_artifact_shard_from_index(
            self,
            index.target,
            index,
            |shard| {
                let mut progress = SourcePackBuildProgressShard::new(index.target, shard);
                let execution_shard = self.load_build_artifact_execution_shard_for_target(
                    index.target,
                    shard.shard_index,
                )?;
                for dependency in &execution_shard.batch_dependencies {
                    if !dependency.has_dependencies() {
                        progress.record_batch_ready(dependency.batch_index)?;
                    }
                }
                ready_batch_count =
                    ready_batch_count.saturating_add(progress.ready_batch_indices.len());
                if let Some(shard_first_ready) = progress.ready_batch_indices.iter().copied().min()
                {
                    if first_ready_batch_index.map_or(true, |first| shard_first_ready < first) {
                        first_ready_batch_index = Some(shard_first_ready);
                    }
                }
                self.write_build_progress_shard_file(&progress)?;
                build_progress_shard_count += 1;
                Ok(())
            },
        )?;
        let summary = SourcePackBuildProgressSummary {
            version: SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
            target: index.target,
            job_batch_count: index.job_batch_count,
            job_batch_shard_count: build_progress_shard_count,
            completed_batch_count: 0,
            ready_batch_count,
            first_ready_batch_index,
            claimed_batch_count: 0,
            ready_claimed_batch_count: 0,
            earliest_claim_lease_expires_unix_nanos: None,
            linked_output_key: None,
        };
        self.store_build_progress_summary(&summary)?;
        self.store_build_progress_directory_pages_for_summary(&summary)?;
        Ok(SourcePackFilesystemBuildProgressShardStoreResult {
            build_progress_shard_count,
        })
    }

    pub(in crate::compiler) fn build_progress_summary_available_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> bool {
        self.build_progress_summary_path_for_target(target)
            .is_file()
    }

    pub fn store_build_state(&self, state: &SourcePackBuildState) -> Result<PathBuf, CompileError> {
        self.store_build_state_for_target(SourcePackArtifactTarget::Generic, state)
    }

    pub fn store_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_state_version(state)?;
        if self.build_progress_summary_available_for_target(target) {
            store_source_pack_build_state_progress_shards(self, target, state)?;
        }
        let stored_state = source_pack_root_build_state_marker(state);
        self.store_build_state_file_for_target(target, &stored_state)
    }

    pub(in crate::compiler) fn store_build_state_marker_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_state_version(state)?;
        self.store_build_state_file_for_target(target, &source_pack_root_build_state_marker(state))
    }

    pub(in crate::compiler) fn store_build_state_file_for_target(
        &self,
        target: SourcePackArtifactTarget,
        state: &SourcePackBuildState,
    ) -> Result<PathBuf, CompileError> {
        validate_source_pack_build_state_version(state)?;
        let path = self.build_state_path_for_target(target);
        if let Some(parent) = path.parent() {
            fs::create_dir_all(parent).map_err(|err| {
                CompileError::GpuFrontend(format!(
                    "create source-pack build state directory {}: {err}",
                    parent.display()
                ))
            })?;
        }
        let bytes = serde_json::to_vec_pretty(state).map_err(|err| {
            CompileError::GpuFrontend(format!("serialize source-pack build state: {err}"))
        })?;
        write_source_pack_filesystem_file_atomically(&path, &bytes, "source-pack build state")?;
        Ok(path)
    }

    pub fn load_build_state(&self) -> Result<SourcePackBuildState, CompileError> {
        self.load_build_state_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn load_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.build_progress_summary_available_for_target(target) {
            return load_source_pack_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        let bytes = fs::read(&path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read source-pack build state {}: {err}",
                path.display()
            ))
        })?;
        let state = serde_json::from_slice::<SourcePackBuildState>(&bytes).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "parse source-pack build state {}: {err}",
                path.display()
            ))
        })?;
        validate_source_pack_build_state_version(&state)?;
        Ok(state)
    }

    pub fn load_or_init_build_state(&self) -> Result<SourcePackBuildState, CompileError> {
        self.load_or_init_build_state_for_target(SourcePackArtifactTarget::Generic)
    }

    pub fn load_or_init_build_state_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> Result<SourcePackBuildState, CompileError> {
        if self.build_progress_summary_available_for_target(target) {
            return load_source_pack_build_state_from_progress_summary(self, target);
        }
        let path = self.build_state_path_for_target(target);
        match fs::read(&path) {
            Ok(bytes) => {
                let state =
                    serde_json::from_slice::<SourcePackBuildState>(&bytes).map_err(|err| {
                        CompileError::GpuFrontend(format!(
                            "parse source-pack build state {}: {err}",
                            path.display()
                        ))
                    })?;
                validate_source_pack_build_state_version(&state)?;
                Ok(state)
            }
            Err(err) if err.kind() == std::io::ErrorKind::NotFound => {
                Ok(SourcePackBuildState::new())
            }
            Err(err) => Err(CompileError::GpuFrontend(format!(
                "read source-pack build state {}: {err}",
                path.display()
            ))),
        }
    }
}

impl AsRef<SourcePackFilesystemArtifactStore> for SourcePackFilesystemArtifactStore {
    fn as_ref(&self) -> &SourcePackFilesystemArtifactStore {
        self
    }
}

impl SourcePackFilesystemArtifactPathStore {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self {
            inner: SourcePackFilesystemArtifactStore::new(root),
        }
    }

    pub fn root(&self) -> &Path {
        self.inner.root()
    }

    pub fn path_for_key(&self, key: &str) -> Result<PathBuf, CompileError> {
        self.inner.path_for_key(key)
    }
}

impl AsRef<SourcePackFilesystemArtifactStore> for SourcePackFilesystemArtifactPathStore {
    fn as_ref(&self) -> &SourcePackFilesystemArtifactStore {
        &self.inner
    }
}

pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_MANIFEST_FILE: &str =
    "source-pack-build.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_ARTIFACT_MANIFEST_FILE: &str =
    "source-pack-artifacts.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_INDEX_FILE: &str =
    "source-pack-library-partitions.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_PREPARE_PROGRESS_FILE: &str =
    "source-pack-library-partitions-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_FILE_STEM: &str =
    "source-pack-library-partition";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_PARTITION_LOCATOR_PAGE_FILE_STEM:
    &str = "source-pack-library-partition-locator";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_DEPENDENCY_PAGE_FILE_STEM: &str =
    "source-pack-library-dependencies";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SOURCE_FILE_PAGE_FILE_STEM: &str =
    "source-pack-library-source-files";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SOURCE_FILE_RECORD_PAGE_FILE_STEM:
    &str = "source-pack-library-source-file";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_BUILD_UNIT_PAGE_FILE_STEM: &str =
    "source-pack-library-build-units";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_FRONTEND_UNIT_PAGE_FILE_STEM: &str =
    "source-pack-library-frontend-unit";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_CODEGEN_UNIT_PAGE_FILE_STEM: &str =
    "source-pack-library-codegen-unit";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_INDEX_FILE: &str =
    "source-pack-library-schedule.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_PREPARE_PROGRESS_FILE: &str =
    "source-pack-library-schedule-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_PAGE_FILE_STEM: &str =
    "source-pack-library-schedule-page";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_FILE_STEM:
    &str = "source-pack-library-frontend-job-locator";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_FILE: &str =
    "source-pack-library-schedule-job-locators.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_FILE_STEM:
    &str = "source-pack-library-schedule-job-locator";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_PAGE_FILE_STEM: &str =
    "source-pack-library-schedule-job";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_FILE_STEM: &str =
    "source-pack-library-schedule-job-dependencies";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_PLAN_INDEX_FILE: &str =
    "source-pack-hierarchical-link-plan.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_FILE: &str =
    "source-pack-hierarchical-link-plan-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_GROUP_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-group";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_INDEX_FILE: &str =
    "source-pack-hierarchical-link-execution.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_FILE: &str =
    "source-pack-hierarchical-link-execution-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PAGE_FILE_STEM:
    &str = "source-pack-hierarchical-link-execution";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-interfaces";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-objects";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-partials";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_INDEX_FILE: &str =
    "source-pack-job-batches.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_PREPARE_PROGRESS_FILE: &str =
    "source-pack-job-batches-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_FILE: &str =
    "source-pack-job-batch-dependents-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_PAGE_FILE_STEM: &str =
    "source-pack-job-batch";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_FILE_STEM:
    &str = "source-pack-job-batch-job-locator";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENCY_PAGE_FILE_STEM:
    &str = "source-pack-job-batch-dependency";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_FILE_STEM: &str =
    "source-pack-job-batch-dependency-range";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENTS_PAGE_FILE_STEM:
    &str = "source-pack-job-batch-dependents";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_FILE_STEM: &str =
    "source-pack-job-batch-dependent-batch";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_INDEX_FILE: &str =
    "source-pack-artifact-refs.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_FILE:
    &str = "source-pack-artifact-refs-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_ARTIFACT_REF_PAGE_FILE_STEM: &str =
    "source-pack-artifact-ref";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_FILE_STEM:
    &str = "source-pack-job-artifact-input-interfaces";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_LINK_BATCH_INDEX_FILE: &str =
    "source-pack-link-batches.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_LINK_BATCH_PREPARE_PROGRESS_FILE: &str =
    "source-pack-link-batches-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_LINK_INTERFACE_BATCH_PAGE_FILE_STEM:
    &str = "source-pack-link-interface-batch";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_LINK_OBJECT_BATCH_PAGE_FILE_STEM: &str =
    "source-pack-link-object-batch";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_INDEX_FILE: &str =
    "source-pack-work-queue.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PREPARE_PROGRESS_FILE: &str =
    "source-pack-work-queue-progress-prepare.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PAGE_FILE_STEM: &str =
    "source-pack-work-item";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_DEPENDENCIES_PAGE_FILE_STEM: &str =
    "source-pack-work-dependencies";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_DEPENDENTS_PAGE_FILE_STEM: &str =
    "source-pack-work-dependents";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_INDEX_FILE: &str =
    "source-pack-work-queue-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_FILE:
    &str = "source-pack-work-queue-progress-build.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PAGE_FILE_STEM: &str =
    "source-pack-work-progress-page";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_PAGE_SUMMARY_FILE_STEM:
    &str = "source-pack-work-progress-summary";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_FILE_STEM: &str =
    "source-pack-work-progress-directory";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM: &str =
    "source-pack-work-progress-directory-index";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_INDEX_FILE: &str =
    "source-pack-artifact-shards.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_PREPARE_PROGRESS_FILE: &str =
    "source-pack-artifact-shards-progress.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_LINK_INPUT_SHARD_INDEX_FILE: &str =
    "source-pack-link-input-shards.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_ARTIFACT_SHARD_FILE_STEM: &str =
    "source-pack-artifact-shard";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_ARTIFACT_EXECUTION_SHARD_FILE_STEM: &str =
    "source-pack-artifact-execution-shard";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BATCH_SHARD_LOCATOR_FILE_STEM: &str =
    "source-pack-batch-shard-locator";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SUMMARY_FILE: &str =
    "source-pack-progress-summary.json";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SHARD_SUMMARY_FILE_STEM: &str =
    "source-pack-progress-shard-summary";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_DIRECTORY_PAGE_FILE_STEM: &str =
    "source-pack-progress-directory";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM: &str =
    "source-pack-progress-directory-index";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_PROGRESS_SHARD_FILE_STEM: &str =
    "source-pack-progress-shard";
pub(in crate::compiler) const SOURCE_PACK_FILESYSTEM_BUILD_STATE_FILE: &str =
    "source-pack-state.json";

pub(in crate::compiler) fn source_pack_filesystem_target_path(
    root: &Path,
    file_name: &str,
    target: SourcePackArtifactTarget,
) -> PathBuf {
    let Some(prefix) = target.key_prefix() else {
        return root.join(file_name);
    };
    let Some(stem) = file_name.strip_suffix(".json") else {
        return root.join(format!("{file_name}.{prefix}"));
    };
    root.join(format!("{stem}.{prefix}.json"))
}

pub(in crate::compiler) fn write_source_pack_filesystem_file_atomically(
    path: &Path,
    bytes: &[u8],
    label: &str,
) -> Result<(), CompileError> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create {label} directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    let file_name = path.file_name().ok_or_else(|| {
        CompileError::GpuFrontend(format!("{label} path {} has no file name", path.display()))
    })?;
    let mut tmp_file_name = file_name.to_os_string();
    tmp_file_name.push(format!(
        ".tmp-{}-{}",
        std::process::id(),
        source_pack_build_now_unix_nanos()?
    ));
    let tmp_path = path.with_file_name(tmp_file_name);

    fs::write(&tmp_path, bytes).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "write temporary {label} {}: {err}",
            tmp_path.display()
        ))
    })?;
    fs::rename(&tmp_path, path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        CompileError::GpuFrontend(format!(
            "replace {label} {} with {}: {err}",
            path.display(),
            tmp_path.display()
        ))
    })?;
    Ok(())
}

impl SourcePackPathArtifactStore for SourcePackFilesystemArtifactStore {
    type LibraryInterfaceArtifact = Vec<u8>;
    type CodegenObjectArtifact = Vec<u8>;
    type LinkedOutputArtifact = Vec<u8>;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        read_source_pack_filesystem_artifact(&self.root, &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        write_source_pack_filesystem_artifact(
            &self.root,
            &artifact.key,
            "library interface",
            interface,
        )
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_source_pack_filesystem_artifact(&self.root, &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        read_source_pack_filesystem_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        write_source_pack_filesystem_artifact(&self.root, &artifact.key, "codegen object", object)
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_source_pack_filesystem_artifact(&self.root, &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        write_source_pack_filesystem_artifact(&self.root, &artifact.key, "linked output", output)
    }
}

impl SourcePackPathHierarchicalLinkArtifactStore for SourcePackFilesystemArtifactStore {
    type PartialLinkArtifact = Vec<u8>;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        read_source_pack_filesystem_artifact(&self.root, key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        write_source_pack_filesystem_artifact(&self.root, key, "partial link output", output)
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        write_source_pack_filesystem_artifact(&self.root, key, "linked output", output)
    }
}

impl SourcePackPathArtifactStore for SourcePackFilesystemArtifactPathStore {
    type LibraryInterfaceArtifact = SourcePackFilesystemArtifactPath;
    type CodegenObjectArtifact = SourcePackFilesystemArtifactPath;
    type LinkedOutputArtifact = SourcePackFilesystemArtifactPath;

    fn load_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::LibraryInterfaceArtifact, CompileError> {
        source_pack_filesystem_artifact_path_handle(self.root(), &artifact.key, "library interface")
    }

    fn store_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
        interface: Self::LibraryInterfaceArtifact,
    ) -> Result<(), CompileError> {
        copy_source_pack_filesystem_artifact_file_atomically(
            self.root(),
            &artifact.key,
            "library interface",
            interface,
        )
    }

    fn release_library_interface(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_source_pack_filesystem_artifact(self.root(), &artifact.key, "library interface")
    }

    fn load_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<Self::CodegenObjectArtifact, CompileError> {
        source_pack_filesystem_artifact_path_handle(self.root(), &artifact.key, "codegen object")
    }

    fn store_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
        object: Self::CodegenObjectArtifact,
    ) -> Result<(), CompileError> {
        copy_source_pack_filesystem_artifact_file_atomically(
            self.root(),
            &artifact.key,
            "codegen object",
            object,
        )
    }

    fn release_codegen_object(
        &mut self,
        artifact: &SourcePackArtifactRef,
    ) -> Result<(), CompileError> {
        remove_source_pack_filesystem_artifact(self.root(), &artifact.key, "codegen object")
    }

    fn store_linked_output(
        &mut self,
        artifact: &SourcePackArtifactRef,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        copy_source_pack_filesystem_artifact_file_atomically(
            self.root(),
            &artifact.key,
            "linked output",
            output,
        )
    }
}

impl SourcePackPathHierarchicalLinkArtifactStore for SourcePackFilesystemArtifactPathStore {
    type PartialLinkArtifact = SourcePackFilesystemArtifactPath;

    fn load_partial_link_output(
        &mut self,
        key: &str,
    ) -> Result<Self::PartialLinkArtifact, CompileError> {
        source_pack_filesystem_artifact_path_handle(self.root(), key, "partial link output")
    }

    fn store_partial_link_output(
        &mut self,
        key: &str,
        output: Self::PartialLinkArtifact,
    ) -> Result<(), CompileError> {
        copy_source_pack_filesystem_artifact_file_atomically(
            self.root(),
            key,
            "partial link output",
            output,
        )
    }

    fn store_hierarchical_linked_output(
        &mut self,
        key: &str,
        output: Self::LinkedOutputArtifact,
    ) -> Result<(), CompileError> {
        copy_source_pack_filesystem_artifact_file_atomically(
            self.root(),
            key,
            "linked output",
            output,
        )
    }
}

impl SourcePackFilesystemExecutionShardLoader for SourcePackFilesystemArtifactStore {
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
        source_pack_stored_source_file_for_index(
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
                source_pack_library_partition_contract_error(format!(
                    "source-pack source range {first_source_index}+{source_file_count} overflows"
                ))
            })?;
        let library_partition_index = self.load_library_partition_index_for_target(target)?;
        let mut partition_cache = BTreeMap::<usize, SourcePackLibraryPartition>::new();
        let mut source_file_page_cache = BTreeMap::<usize, SourcePackLibrarySourceFilePage>::new();
        let mut files = Vec::with_capacity(source_file_count);
        for source_index in first_source_index..source_end {
            files.push(source_pack_stored_source_file_for_index(
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

impl SourcePackFilesystemExecutionShardLoader for SourcePackFilesystemArtifactPathStore {
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

pub(in crate::compiler) fn source_pack_filesystem_artifact_path(
    root: &Path,
    key: &str,
) -> Result<PathBuf, CompileError> {
    if key.is_empty() {
        return Err(CompileError::GpuFrontend(
            "source-pack artifact key cannot be empty".into(),
        ));
    }

    let mut path = root.to_path_buf();
    for component in Path::new(key).components() {
        match component {
            std::path::Component::Normal(segment) => path.push(segment),
            _ => {
                return Err(CompileError::GpuFrontend(format!(
                    "source-pack artifact key {key:?} is not relative and normal"
                )));
            }
        }
    }
    Ok(path)
}

pub(in crate::compiler) fn read_source_pack_filesystem_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<Vec<u8>, CompileError> {
    let path = source_pack_filesystem_artifact_path(root, key)?;
    fs::read(&path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "read source-pack {artifact_label} artifact {key:?} from {}: {err}",
            path.display()
        ))
    })
}

pub(in crate::compiler) fn write_source_pack_filesystem_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
    bytes: Vec<u8>,
) -> Result<(), CompileError> {
    let path = source_pack_filesystem_artifact_path(root, key)?;
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create source-pack {artifact_label} artifact directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    fs::write(&path, bytes).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "write source-pack {artifact_label} artifact {key:?} to {}: {err}",
            path.display()
        ))
    })
}

pub(in crate::compiler) fn source_pack_filesystem_artifact_path_handle(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<SourcePackFilesystemArtifactPath, CompileError> {
    let path = source_pack_filesystem_artifact_path(root, key)?;
    if !path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact {key:?} is missing at {}",
            path.display()
        )));
    }
    Ok(SourcePackFilesystemArtifactPath {
        key: key.to_string(),
        path,
    })
}

pub(in crate::compiler) fn copy_source_pack_filesystem_artifact_file_atomically(
    root: &Path,
    key: &str,
    artifact_label: &str,
    artifact: SourcePackFilesystemArtifactPath,
) -> Result<(), CompileError> {
    let path = source_pack_filesystem_artifact_path(root, key)?;
    if artifact.path == path {
        if path.is_file() {
            return Ok(());
        }
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact {key:?} was returned at {} but the file is missing",
            path.display()
        )));
    }
    if !artifact.path.is_file() {
        return Err(CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact source {} for key {:?} is missing",
            artifact.path.display(),
            artifact.key
        )));
    }
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "create source-pack {artifact_label} artifact directory {}: {err}",
                parent.display()
            ))
        })?;
    }
    let file_name = path.file_name().ok_or_else(|| {
        CompileError::GpuFrontend(format!(
            "source-pack {artifact_label} artifact path {} has no file name",
            path.display()
        ))
    })?;
    let mut tmp_file_name = file_name.to_os_string();
    tmp_file_name.push(format!(
        ".tmp-{}-{}",
        std::process::id(),
        source_pack_build_now_unix_nanos()?
    ));
    let tmp_path = path.with_file_name(tmp_file_name);
    fs::copy(&artifact.path, &tmp_path).map_err(|err| {
        CompileError::GpuFrontend(format!(
            "copy source-pack {artifact_label} artifact {:?} from {} to temporary {}: {err}",
            artifact.key,
            artifact.path.display(),
            tmp_path.display()
        ))
    })?;
    fs::rename(&tmp_path, &path).map_err(|err| {
        let _ = fs::remove_file(&tmp_path);
        CompileError::GpuFrontend(format!(
            "replace source-pack {artifact_label} artifact {key:?} at {} with temporary {}: {err}",
            path.display(),
            tmp_path.display()
        ))
    })
}

pub(in crate::compiler) fn remove_source_pack_filesystem_artifact(
    root: &Path,
    key: &str,
    artifact_label: &str,
) -> Result<(), CompileError> {
    let path = source_pack_filesystem_artifact_path(root, key)?;
    match fs::remove_file(&path) {
        Ok(()) => Ok(()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(()),
        Err(err) => Err(CompileError::GpuFrontend(format!(
            "release source-pack {artifact_label} artifact {key:?} at {}: {err}",
            path.display()
        ))),
    }
}
