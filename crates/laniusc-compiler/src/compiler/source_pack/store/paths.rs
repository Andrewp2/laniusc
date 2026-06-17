use super::*;

const STORE_BUILD_MANIFEST_FILE: &str = "source-pack-build.json";
const STORE_ARTIFACT_MANIFEST_FILE: &str = "source-pack-artifacts.json";
const STORE_LIBRARY_PARTITION_INDEX_FILE: &str = "source-pack-library-partitions.json";
const STORE_LIBRARY_PARTITION_PREPARE_PROGRESS_FILE: &str =
    "source-pack-library-partitions-progress.json";
const STORE_LIBRARY_PARTITION_FILE_STEM: &str = "source-pack-library-partition";
const STORE_LIBRARY_PARTITION_LOCATOR_PAGE_FILE_STEM: &str =
    "source-pack-library-partition-locator";
const STORE_LIBRARY_DEPENDENCY_PAGE_FILE_STEM: &str = "source-pack-library-dependencies";
const STORE_LIBRARY_SOURCE_FILE_PAGE_FILE_STEM: &str = "source-pack-library-source-files";
const STORE_LIBRARY_SOURCE_FILE_RECORD_PAGE_FILE_STEM: &str = "source-pack-library-source-file";
const STORE_LIBRARY_BUILD_UNIT_PAGE_FILE_STEM: &str = "source-pack-library-build-units";
const STORE_LIBRARY_FRONTEND_UNIT_PAGE_FILE_STEM: &str = "source-pack-library-frontend-unit";
const STORE_LIBRARY_CODEGEN_UNIT_PAGE_FILE_STEM: &str = "source-pack-library-codegen-unit";
const STORE_LIBRARY_SCHEDULE_INDEX_FILE: &str = "source-pack-library-schedule.json";
const STORE_LIBRARY_SCHEDULE_PREPARE_PROGRESS_FILE: &str =
    "source-pack-library-schedule-progress.json";
const STORE_LIBRARY_SCHEDULE_PAGE_FILE_STEM: &str = "source-pack-library-schedule-page";
const STORE_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_FILE_STEM: &str =
    "source-pack-library-frontend-job-locator";
const STORE_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_FILE: &str =
    "source-pack-library-schedule-job-locators.json";
const STORE_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_FILE_STEM: &str =
    "source-pack-library-schedule-job-locator";
const STORE_LIBRARY_SCHEDULE_JOB_PAGE_FILE_STEM: &str = "source-pack-library-schedule-job";
const STORE_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_FILE_STEM: &str =
    "source-pack-library-schedule-job-dependencies";
const STORE_HIERARCHICAL_LINK_PLAN_INDEX_FILE: &str = "source-pack-hierarchical-link-plan.json";
const STORE_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_FILE: &str =
    "source-pack-hierarchical-link-plan-progress.json";
const STORE_HIERARCHICAL_LINK_GROUP_PAGE_FILE_STEM: &str = "source-pack-hierarchical-link-group";
const STORE_HIERARCHICAL_LINK_EXECUTION_INDEX_FILE: &str =
    "source-pack-hierarchical-link-execution.json";
const STORE_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_FILE: &str =
    "source-pack-hierarchical-link-execution-progress.json";
const STORE_HIERARCHICAL_LINK_EXECUTION_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution";
const STORE_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-interfaces";
const STORE_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-objects";
const STORE_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_FILE_STEM: &str =
    "source-pack-hierarchical-link-execution-partials";
const STORE_BUILD_JOB_BATCH_INDEX_FILE: &str = "source-pack-job-batches.json";
const STORE_BUILD_JOB_BATCH_PREPARE_PROGRESS_FILE: &str = "source-pack-job-batches-progress.json";
const STORE_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_FILE: &str =
    "source-pack-job-batch-dependents-progress.json";
const STORE_BUILD_JOB_BATCH_PAGE_FILE_STEM: &str = "source-pack-job-batch";
const STORE_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_FILE_STEM: &str = "source-pack-job-batch-job-locator";
const STORE_BUILD_JOB_BATCH_DEPENDENCY_PAGE_FILE_STEM: &str = "source-pack-job-batch-dependency";
const STORE_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_FILE_STEM: &str =
    "source-pack-job-batch-dependency-range";
const STORE_BUILD_JOB_BATCH_DEPENDENTS_PAGE_FILE_STEM: &str = "source-pack-job-batch-dependents";
const STORE_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_FILE_STEM: &str =
    "source-pack-job-batch-dependent-batch";
const STORE_BUILD_ARTIFACT_REF_INDEX_FILE: &str = "source-pack-artifact-refs.json";
const STORE_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_FILE: &str =
    "source-pack-artifact-refs-progress.json";
const STORE_BUILD_ARTIFACT_REF_PAGE_FILE_STEM: &str = "source-pack-artifact-ref";
const STORE_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_FILE_STEM: &str =
    "source-pack-job-artifact-input-interfaces";
const STORE_BUILD_LINK_BATCH_INDEX_FILE: &str = "source-pack-link-batches.json";
const STORE_BUILD_LINK_BATCH_PREPARE_PROGRESS_FILE: &str = "source-pack-link-batches-progress.json";
const STORE_BUILD_LINK_INTERFACE_BATCH_PAGE_FILE_STEM: &str = "source-pack-link-interface-batch";
const STORE_BUILD_LINK_OBJECT_BATCH_PAGE_FILE_STEM: &str = "source-pack-link-object-batch";
const STORE_WORK_QUEUE_INDEX_FILE: &str = "source-pack-work-queue.json";
const STORE_WORK_QUEUE_PREPARE_PROGRESS_FILE: &str = "source-pack-work-queue-progress-prepare.json";
const STORE_WORK_QUEUE_PAGE_FILE_STEM: &str = "source-pack-work-item";
const STORE_WORK_QUEUE_DEPENDENCIES_PAGE_FILE_STEM: &str = "source-pack-work-dependencies";
const STORE_WORK_QUEUE_DEPENDENTS_PAGE_FILE_STEM: &str = "source-pack-work-dependents";
const STORE_WORK_QUEUE_PROGRESS_INDEX_FILE: &str = "source-pack-work-queue-progress.json";
const STORE_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_FILE: &str =
    "source-pack-work-queue-progress-build.json";
const STORE_WORK_QUEUE_PROGRESS_PAGE_FILE_STEM: &str = "source-pack-work-progress-page";
const STORE_WORK_QUEUE_PROGRESS_PAGE_SUMMARY_FILE_STEM: &str = "source-pack-work-progress-summary";
const STORE_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_FILE_STEM: &str =
    "source-pack-work-progress-directory";
const STORE_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM: &str =
    "source-pack-work-progress-directory-index";
const STORE_ARTIFACT_SHARD_INDEX_FILE: &str = "source-pack-artifact-shards.json";
const STORE_ARTIFACT_SHARD_PREPARE_PROGRESS_FILE: &str =
    "source-pack-artifact-shards-progress.json";
const STORE_LINK_INPUT_SHARD_INDEX_FILE: &str = "source-pack-link-input-shards.json";
const STORE_ARTIFACT_SHARD_FILE_STEM: &str = "source-pack-artifact-shard";
const STORE_ARTIFACT_EXECUTION_SHARD_FILE_STEM: &str = "source-pack-artifact-execution-shard";
const STORE_BATCH_SHARD_LOCATOR_FILE_STEM: &str = "source-pack-batch-shard-locator";
const STORE_BUILD_PROGRESS_SUMMARY_FILE: &str = "source-pack-progress-summary.json";
const STORE_BUILD_PROGRESS_SHARD_SUMMARY_FILE_STEM: &str = "source-pack-progress-shard-summary";
const STORE_BUILD_PROGRESS_DIRECTORY_PAGE_FILE_STEM: &str = "source-pack-progress-directory";
const STORE_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM: &str =
    "source-pack-progress-directory-index";
const STORE_BUILD_PROGRESS_SHARD_FILE_STEM: &str = "source-pack-progress-shard";
const STORE_BUILD_STATE_FILE: &str = "source-pack-state.json";

impl FilesystemArtifactStore {
    pub fn build_manifest_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        target_path(&self.root, STORE_BUILD_MANIFEST_FILE, target)
    }

    pub fn artifact_manifest_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        target_path(&self.root, STORE_ARTIFACT_MANIFEST_FILE, target)
    }

    pub fn library_partition_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_LIBRARY_PARTITION_INDEX_FILE, target)
    }

    pub fn library_metadata_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_LIBRARY_PARTITION_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn library_partition_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_LIBRARY_PARTITION_FILE_STEM}-{partition_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_partition_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_PARTITION_LOCATOR_PAGE_FILE_STEM}-{library_id:010}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_LIBRARY_DEPENDENCY_PAGE_FILE_STEM}-{partition_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn library_source_file_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_SOURCE_FILE_PAGE_FILE_STEM}-{partition_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_source_file_record_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        source_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_SOURCE_FILE_RECORD_PAGE_FILE_STEM}-{source_index:010}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_build_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_BUILD_UNIT_PAGE_FILE_STEM}-{partition_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_frontend_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        frontend_unit_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_LIBRARY_FRONTEND_UNIT_PAGE_FILE_STEM}-{partition_index:08}-{frontend_unit_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn library_codegen_unit_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
        codegen_unit_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_LIBRARY_CODEGEN_UNIT_PAGE_FILE_STEM}-{partition_index:08}-{codegen_unit_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_LIBRARY_SCHEDULE_INDEX_FILE, target)
    }

    pub fn library_schedule_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_LIBRARY_SCHEDULE_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn library_schedule_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        partition_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_SCHEDULE_PAGE_FILE_STEM}-{partition_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_frontend_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        library_id: u32,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_FILE_STEM}-{library_id:010}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_locator_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_FILE,
            target,
        )
    }

    pub fn library_schedule_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_FILE_STEM}-{job_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_LIBRARY_SCHEDULE_JOB_PAGE_FILE_STEM}-{job_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn library_schedule_job_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_FILE_STEM}-{job_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_plan_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_HIERARCHICAL_LINK_PLAN_INDEX_FILE, target)
    }

    pub fn hierarchical_link_plan_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn hierarchical_link_group_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_HIERARCHICAL_LINK_GROUP_PAGE_FILE_STEM}-{group_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_HIERARCHICAL_LINK_EXECUTION_INDEX_FILE,
            target,
        )
    }

    pub fn link_execution_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn hierarchical_link_execution_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_HIERARCHICAL_LINK_EXECUTION_PAGE_FILE_STEM}-{group_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_interface_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_object_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn hierarchical_link_execution_partial_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        group_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_FILE_STEM}-{group_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_BUILD_JOB_BATCH_INDEX_FILE, target)
    }

    pub fn build_job_batch_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_BUILD_JOB_BATCH_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_job_batch_dependents_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_job_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_BUILD_JOB_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_job_locator_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_FILE_STEM}-{job_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependency_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_BUILD_JOB_BATCH_DEPENDENCY_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependency_range_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependents_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_JOB_BATCH_DEPENDENTS_PAGE_FILE_STEM}-{batch_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_job_batch_dependent_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_FILE_STEM}-{batch_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_artifact_ref_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_BUILD_ARTIFACT_REF_INDEX_FILE, target)
    }

    pub fn build_artifact_ref_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_artifact_ref_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        artifact_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_ARTIFACT_REF_PAGE_FILE_STEM}-{artifact_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn job_artifact_input_interface_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        job_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_FILE_STEM}-{job_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_link_batch_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_BUILD_LINK_BATCH_INDEX_FILE, target)
    }

    pub fn build_link_batch_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_BUILD_LINK_BATCH_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn build_link_interface_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_LINK_INTERFACE_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_link_object_batch_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_LINK_OBJECT_BATCH_PAGE_FILE_STEM}-{batch_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_index_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        target_path(&self.root, STORE_WORK_QUEUE_INDEX_FILE, target)
    }

    pub fn work_queue_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_WORK_QUEUE_PREPARE_PROGRESS_FILE, target)
    }

    pub fn work_queue_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_WORK_QUEUE_PAGE_FILE_STEM}-{item_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_dependencies_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_WORK_QUEUE_DEPENDENCIES_PAGE_FILE_STEM}-{item_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_dependents_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        item_index: usize,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_WORK_QUEUE_DEPENDENTS_PAGE_FILE_STEM}-{item_index:08}-{page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_WORK_QUEUE_PROGRESS_INDEX_FILE, target)
    }

    pub fn work_queue_progress_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn work_queue_progress_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_WORK_QUEUE_PROGRESS_PAGE_FILE_STEM}-{page_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_page_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        page_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_WORK_QUEUE_PROGRESS_PAGE_SUMMARY_FILE_STEM}-{page_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_directory_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_FILE_STEM}-{directory_page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn work_queue_progress_directory_index_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM}-{directory_index_page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn artifact_shard_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_ARTIFACT_SHARD_INDEX_FILE, target)
    }

    pub fn artifact_shard_prepare_progress_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(
            &self.root,
            STORE_ARTIFACT_SHARD_PREPARE_PROGRESS_FILE,
            target,
        )
    }

    pub fn link_input_shard_index_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_LINK_INPUT_SHARD_INDEX_FILE, target)
    }

    pub fn artifact_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_ARTIFACT_SHARD_FILE_STEM}-{shard_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn artifact_execution_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_ARTIFACT_EXECUTION_SHARD_FILE_STEM}-{shard_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn batch_shard_locator_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        batch_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_BATCH_SHARD_LOCATOR_FILE_STEM}-{batch_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
    ) -> PathBuf {
        target_path(&self.root, STORE_BUILD_PROGRESS_SUMMARY_FILE, target)
    }

    pub fn build_progress_shard_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name = format!("{STORE_BUILD_PROGRESS_SHARD_FILE_STEM}-{shard_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_shard_summary_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        shard_index: usize,
    ) -> PathBuf {
        let file_name =
            format!("{STORE_BUILD_PROGRESS_SHARD_SUMMARY_FILE_STEM}-{shard_index:08}.json");
        target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_directory_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_BUILD_PROGRESS_DIRECTORY_PAGE_FILE_STEM}-{directory_page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_progress_directory_index_page_path_for_target(
        &self,
        target: SourcePackArtifactTarget,
        directory_index_page_index: usize,
    ) -> PathBuf {
        let file_name = format!(
            "{STORE_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_FILE_STEM}-{directory_index_page_index:08}.json"
        );
        target_path(&self.root, &file_name, target)
    }

    pub fn build_state_path_for_target(&self, target: SourcePackArtifactTarget) -> PathBuf {
        target_path(&self.root, STORE_BUILD_STATE_FILE, target)
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
}

fn target_path(root: &Path, file_name: &str, target: SourcePackArtifactTarget) -> PathBuf {
    let Some(prefix) = target.key_prefix() else {
        return root.join(file_name);
    };
    let Some(stem) = file_name.strip_suffix(".json") else {
        return root.join(format!("{file_name}.{prefix}"));
    };
    root.join(format!("{stem}.{prefix}.json"))
}
