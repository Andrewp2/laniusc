use super::*;

/// Version for persisted artifact execution shard records.
pub const SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION: u32 = 1;
/// Version for batch-to-shard locator records.
pub const SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION: u32 = 1;
/// Version for artifact-shard preparation progress records.
pub const SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for persisted job-batch pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION: u32 = 1;
/// Version for persisted job-batch page indexes.
pub const SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION: u32 = 1;
/// Version for job-batch preparation progress records.
pub const SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for job-to-batch locator pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION: u32 = 1;
/// Version for explicit job-batch dependency pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION: u32 = 1;
/// Version for compact job-batch dependency-range pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION: u32 = 1;
/// Version for job-batch dependent summary pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION: u32 = 1;
/// Version for paged job-batch dependent lists.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION: u32 = 1;
/// Inline job cap used before job-batch records spill into separate pages.
pub const SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP: usize =
    DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Default page size for explicit job-batch dependency lists.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for compact job-batch dependency ranges.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for job-batch dependent lists.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for job-batch dependents preparation progress records.
pub const SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for persisted artifact-reference indexes.
pub const SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION: u32 = 1;
/// Version for persisted artifact-reference pages.
pub const SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION: u32 = 1;
/// Version for artifact-reference preparation progress records.
pub const SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for link-batch page indexes.
pub const SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION: u32 = 1;
/// Version for link-batch preparation progress records.
pub const SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for interface-link batch pages.
pub const SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION: u32 = 1;
/// Version for object-link batch pages.
pub const SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION: u32 = 1;
/// Version for link-input shard indexes.
pub const SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION: u32 = 1;
/// Version for paged interface inputs consumed by a job artifact.
pub const SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION: u32 = 1;
/// Default page size for paged interface inputs consumed by a job artifact.
pub const SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE: usize = 64;
/// Default source-file record cap for one artifact execution shard.
pub const SOURCE_PACK_EXECUTION_SHARD_SOURCE_FILE_DEFAULT_RECORD_CAP: usize =
    DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES * DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;

/// Source-file metadata stored inside an artifact execution shard.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackShardSourceFile {
    pub source_index: usize,
    pub file: ExplicitSourcePathFile,
}

/// Locator from a job batch to the artifact execution shard containing it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildBatchShardLocator {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub shard_index: usize,
}

/// Summary index for all persisted job-batch pages in a build.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchPageIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_count: usize,
    pub scheduled_job_count: usize,
    pub dependency_edge_count: usize,
}

/// Persisted page for one executable job batch and its batch dependency summary.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub batch: SourcePackJobBatch,
    pub dependency: SourcePackJobBatchDependency,
}

/// Paged explicit dependency list for one job batch.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchDependencyPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub page_index: usize,
    pub first_dependency_position: usize,
    pub dependency_count: usize,
    pub dependency_batch_indices: Vec<usize>,
}

/// Paged dependency ranges for one job batch.
///
/// Range pages are used when dependencies can be represented more compactly
/// than an explicit batch-index list.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchDependencyRangePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub page_index: usize,
    pub first_range_position: usize,
    pub range_count: usize,
    pub dependency_batch_count: usize,
    pub dependency_batch_ranges: Vec<SourcePackJobBatchDependencyRange>,
}

/// Locator from a source-pack job index to the batch that executes it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchJobLocatorPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_index: usize,
    pub batch_index: usize,
}

/// Summary index for all artifact references produced by a build plan.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildArtifactRefIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub artifact_count: usize,
    pub interface_artifact_count: usize,
    pub object_artifact_count: usize,
    pub final_output_artifact_index: usize,
    pub final_output_key: String,
    pub total_source_file_count: usize,
    pub total_source_byte_count: usize,
    #[serde(default)]
    pub total_source_line_count: usize,
}

/// Persisted artifact reference plus source-size metadata for one output.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildArtifactRefPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub artifact_index: usize,
    pub artifact_ref: SourcePackArtifactRef,
    pub source_bytes: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_lines: usize,
}

/// Summary index for persisted link-batch pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildLinkBatchPageIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub link_interface_batch_count: usize,
    pub link_object_batch_count: usize,
}

/// Persisted batch of interface artifacts consumed by linking.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildLinkInterfaceBatchPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub batch: SourcePackLinkInterfaceBatch,
}

/// Persisted batch of object artifacts consumed by linking.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildLinkObjectBatchPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_index: usize,
    pub batch: SourcePackLinkObjectBatch,
}

/// Inclusive-start, exclusive-end shard range in the link-input shard index.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkInputShardRange {
    pub first_shard_index: usize,
    pub shard_count: usize,
}

impl SourcePackLinkInputShardRange {
    /// Returns the exclusive end shard index, or `None` on overflow.
    pub fn end_shard_index(&self) -> Option<usize> {
        self.first_shard_index.checked_add(self.shard_count)
    }

    /// Returns whether `shard_index` falls inside this range.
    pub fn contains(&self, shard_index: usize) -> bool {
        self.end_shard_index()
            .is_some_and(|end| self.first_shard_index <= shard_index && shard_index < end)
    }

    /// Returns an iterator range over shard indices, or `None` on overflow.
    pub fn iter(&self) -> Option<std::ops::Range<usize>> {
        self.end_shard_index()
            .map(|end| self.first_shard_index..end)
    }
}

/// Index pointing to interface/object shard ranges used as link inputs.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildLinkInputShardIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_interface_shard_range: Option<SourcePackLinkInputShardRange>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub link_object_shard_range: Option<SourcePackLinkInputShardRange>,
}

/// Dependent batches that become closer to ready after one batch completes.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobBatchDependents {
    pub batch_index: usize,
    pub dependent_batch_indices: Vec<usize>,
}

/// Persisted dependent-batch summary for one job batch.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchDependentsPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_count: usize,
    pub batch_index: usize,
    pub dependents: SourcePackJobBatchDependents,
    #[serde(default)]
    pub dependent_batch_count: usize,
    #[serde(default)]
    pub dependent_page_count: usize,
}

/// Paged dependent-batch list for one job batch.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildJobBatchDependentBatchPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub batch_count: usize,
    pub batch_index: usize,
    pub page_index: usize,
    pub first_dependent_position: usize,
    pub dependent_count: usize,
    pub dependent_batch_indices: Vec<usize>,
}

/// Self-contained executable shard for artifact-manifest execution.
///
/// Shards copy the source files, job batches, dependency summaries, artifacts,
/// and link batches needed by a bounded worker step.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackBuildArtifactExecutionShard {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub shard: SourcePackBuildArtifactShard,
    pub source_files: Vec<SourcePackShardSourceFile>,
    pub job_batches: Vec<SourcePackJobBatch>,
    pub batch_dependencies: Vec<SourcePackJobBatchDependency>,
    #[serde(default)]
    pub batch_dependents: Vec<SourcePackJobBatchDependents>,
    pub jobs: Vec<SourcePackJob>,
    pub job_artifacts: Vec<SourcePackJobArtifactManifest>,
    pub artifact_refs: Vec<SourcePackArtifactRef>,
    pub link_interface_batches: Vec<SourcePackLinkInterfaceBatch>,
    pub link_object_batches: Vec<SourcePackLinkObjectBatch>,
}

/// Paged interface artifact inputs required by one job artifact.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackJobArtifactInputInterfacePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_index: usize,
    pub page_index: usize,
    pub first_input_position: usize,
    pub input_count: usize,
    pub input_interfaces: Vec<SourcePackArtifactRef>,
}

/// Result returned after a filesystem artifact build completes.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactBuildExecutionResult {
    pub linked_output_key: String,
    pub linked_output_path: PathBuf,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Result returned after executing one artifact-manifest job batch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactBatchExecutionResult {
    pub batch_index: usize,
    pub job_count: usize,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Result returned after attempting to claim a ready artifact batch.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactBatchClaimResult {
    pub claimed_batch_index: Option<usize>,
    pub worker_id: String,
    pub completed_batch_count: usize,
    pub claimed_batch_count: usize,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Point-in-time summary of artifact-manifest execution progress.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactProgressSnapshot {
    pub target: SourcePackArtifactTarget,
    pub job_batch_count: usize,
    pub completed_batch_count: usize,
    pub ready_batch_count: usize,
    pub claimed_batch_count: usize,
    pub ready_claimed_batch_count: usize,
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
    pub first_ready_batch_index: Option<usize>,
    pub ready_batch_indices: Vec<usize>,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub complete: bool,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
    pub progress_summary_path: PathBuf,
}

/// Progress details for one persisted artifact progress shard.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactProgressPage {
    pub target: SourcePackArtifactTarget,
    pub shard_index: usize,
    pub batch_indices: Vec<usize>,
    pub completed_batch_indices: Vec<usize>,
    pub ready_batch_indices: Vec<usize>,
    pub claimed_batch_indices: Vec<usize>,
    pub claimed_batches: Vec<SourcePackBuildBatchClaim>,
    pub linked_output_key: Option<String>,
    pub progress_shard_path: PathBuf,
    pub progress_summary_path: PathBuf,
}

/// Batch-claim result bundled with the current progress snapshot.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactBatchClaimProgressResult {
    pub claimed_batch_index: Option<usize>,
    pub worker_id: String,
    pub progress: FilesystemArtifactProgressSnapshot,
}

/// Result returned by one artifact-manifest worker step with progress details.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactWorkerStepProgressExecutionResult {
    pub worker_id: String,
    pub claimed_batch_index: Option<usize>,
    pub executed_batch: Option<FilesystemArtifactBatchExecutionResult>,
    pub progress: FilesystemArtifactProgressSnapshot,
}

/// Result returned by a bounded artifact-manifest worker run with progress.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactWorkerRunProgressExecutionResult {
    pub worker_id: String,
    pub executed_batch_count: usize,
    pub progress: FilesystemArtifactProgressSnapshot,
}

/// Result returned by one artifact-manifest worker step.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactWorkerStepExecutionResult {
    pub worker_id: String,
    pub claimed_batch_index: Option<usize>,
    pub executed_batch: Option<FilesystemArtifactBatchExecutionResult>,
    pub completed_batch_count: usize,
    pub ready_batch_count: usize,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub complete: bool,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Result returned by a bounded artifact-manifest worker run.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactWorkerRunExecutionResult {
    pub worker_id: String,
    pub executed_batch_count: usize,
    pub completed_batch_count: usize,
    pub ready_batch_count: usize,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub complete: bool,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Result returned after resuming artifact-manifest execution.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemArtifactResumeExecutionResult {
    pub executed_batch_count: usize,
    pub completed_batch_count: usize,
    pub ready_batch_count: usize,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub complete: bool,
    pub build_manifest_path: PathBuf,
    pub artifact_manifest_path: PathBuf,
    pub build_state_path: PathBuf,
}

/// Point-in-time summary of work-queue execution progress.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueProgressSnapshot {
    pub target: SourcePackArtifactTarget,
    pub work_item_count: usize,
    pub completed_item_count: usize,
    pub ready_item_count: usize,
    pub claimed_item_count: usize,
    pub first_ready_item_index: Option<usize>,
    pub ready_item_indices: Vec<usize>,
    pub complete: bool,
    pub work_queue_index_path: PathBuf,
    pub progress_index_path: PathBuf,
}

/// Result returned after attempting to claim a ready work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueItemClaimResult {
    pub claimed_item_index: Option<usize>,
    pub worker_id: String,
    pub progress: FilesystemWorkQueueProgressSnapshot,
}

/// Result returned after completing a claimed work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueItemCompletionResult {
    pub completed_item_index: usize,
    pub worker_id: String,
    pub newly_completed: bool,
    pub newly_ready_item_count: usize,
    pub progress: FilesystemWorkQueueProgressSnapshot,
}

/// Result returned after executing an artifact-backed work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueArtifactItemExecutionResult {
    pub item_index: usize,
    pub worker_id: String,
    pub executed_batch: FilesystemArtifactBatchExecutionResult,
    pub completion: FilesystemWorkQueueItemCompletionResult,
}

/// Result returned after executing one hierarchical link group.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemHierarchicalLinkGroupExecutionResult {
    pub group_index: usize,
    pub job_index: usize,
    pub kind: SourcePackHierarchicalLinkGroupKind,
    pub input_interface_count: usize,
    pub input_object_count: usize,
    pub input_group_count: usize,
    pub descriptor_summary: SourcePackLinkDescriptorSummary,
    pub output_key: String,
    pub output_path: PathBuf,
    pub final_output: bool,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
}

/// Result returned after executing a link-backed work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueLinkItemExecutionResult {
    pub item_index: usize,
    pub worker_id: String,
    pub executed_link_group: FilesystemHierarchicalLinkGroupExecutionResult,
    pub completion: FilesystemWorkQueueItemCompletionResult,
}

/// Work payload executed by a work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub enum FilesystemWorkQueueExecutedItem {
    /// A library-interface or codegen artifact batch.
    ArtifactBatch(FilesystemArtifactBatchExecutionResult),
    /// A hierarchical link leaf or reduce group.
    HierarchicalLinkGroup(FilesystemHierarchicalLinkGroupExecutionResult),
}

/// Result returned after executing and completing one work-queue item.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueItemExecutionResult {
    pub item_index: usize,
    pub worker_id: String,
    pub executed: FilesystemWorkQueueExecutedItem,
    pub completion: FilesystemWorkQueueItemCompletionResult,
}

/// Result returned by one work-queue worker step.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueWorkerStepExecutionResult {
    pub worker_id: String,
    pub claimed_item_index: Option<usize>,
    pub executed_item: Option<FilesystemWorkQueueItemExecutionResult>,
    pub progress: FilesystemWorkQueueProgressSnapshot,
}

/// Result returned by a bounded work-queue worker run.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct FilesystemWorkQueueWorkerRunExecutionResult {
    pub worker_id: String,
    pub executed_item_count: usize,
    pub executed_artifact_batch_count: usize,
    pub executed_link_group_count: usize,
    pub linked_output_key: Option<String>,
    pub linked_output_path: Option<PathBuf>,
    pub progress: FilesystemWorkQueueProgressSnapshot,
}
