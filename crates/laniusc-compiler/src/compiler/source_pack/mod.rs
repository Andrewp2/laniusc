//! Source-pack planning, persisted artifact records, and resumable work queues.
//!
//! Source packs let the compiler plan and execute multiple source files and
//! libraries as bounded frontend, codegen, and link jobs. The public re-exports
//! in this module are the persisted contract for manifests, artifact stores,
//! worker progress, package metadata, and hierarchical link inputs. The
//! compiler-author narrative for these records lives in
//! `docs/compiler/source-packs.md`.

use super::*;

mod records;
pub(in crate::compiler) use records::*;
pub use records::{
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION,
    SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP,
    SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION,
    SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP,
    SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP,
    SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION,
    SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_INDEX_VERSION,
    SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION,
    SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION,
    SourcePackHierarchicalLinkExecutionIndex,
    SourcePackHierarchicalLinkExecutionInterfacePage,
    SourcePackHierarchicalLinkExecutionObjectPage,
    SourcePackHierarchicalLinkExecutionPage,
    SourcePackHierarchicalLinkExecutionPartialPage,
    SourcePackHierarchicalLinkGroupKind,
    SourcePackHierarchicalLinkGroupPage,
    SourcePackHierarchicalLinkPlanIndex,
    SourcePackLibraryBuildUnitPage,
    SourcePackLibraryCodegenUnitPage,
    SourcePackLibraryDependencyPage,
    SourcePackLibraryFrontendJobLocatorPage,
    SourcePackLibraryFrontendUnitPage,
    SourcePackLibraryPartition,
    SourcePackLibraryPartitionIndex,
    SourcePackLibraryPartitionLocatorPage,
    SourcePackLibraryPartitionPlan,
    SourcePackLibraryScheduleIndex,
    SourcePackLibraryScheduleIndexEntry,
    SourcePackLibraryScheduleJobDependencyPage,
    SourcePackLibraryScheduleJobLocatorIndex,
    SourcePackLibraryScheduleJobLocatorPage,
    SourcePackLibraryScheduleJobPage,
    SourcePackLibrarySchedulePage,
    SourcePackLibrarySchedulePlan,
    SourcePackLibrarySourceFilePage,
    SourcePackLibrarySourceFileRecordPage,
    SourcePackLinkDescriptorSummary,
    SourcePackLinkRecordContract,
    SourcePackLinkRecordDomain,
    SourcePackLinkRecordKind,
    SourcePackWorkQueueDependenciesPage,
    SourcePackWorkQueueDependentsPage,
    SourcePackWorkQueueIndex,
    SourcePackWorkQueueItemClaim,
    SourcePackWorkQueueItemKind,
    SourcePackWorkQueuePage,
    SourcePackWorkQueueProgressDirectoryIndexPage,
    SourcePackWorkQueueProgressDirectoryPage,
    SourcePackWorkQueueProgressIndex,
    SourcePackWorkQueueProgressPage,
    SourcePackWorkQueueProgressPageSummary,
    SourcePackWorkQueueRemainingDependencyCount,
    SourcePackWorkQueueRemainingDependentCount,
};

mod inputs;
pub(in crate::compiler) use inputs::*;
pub use inputs::{
    ExplicitSourceLibrary,
    ExplicitSourceLibraryPathDependencyStream,
    ExplicitSourceLibraryPathStream,
    ExplicitSourceLibraryPaths,
    ExplicitSourcePack,
    ExplicitSourcePackPathManifest,
    ExplicitSourcePathFile,
};

mod package_manifest;
pub use package_manifest::{PACKAGE_MANIFEST_MAX_ROOTS, PackageManifest, ResolvedPackageManifest};

mod package_lock;
pub use package_lock::{
    PACKAGE_LOCKFILE_LANGUAGE_EDITION,
    PACKAGE_LOCKFILE_VERSION,
    PackageLockfile,
    PackageLockfileArtifact,
};

mod metadata;
pub(in crate::compiler) use metadata::*;

mod schedule;
pub(in crate::compiler) use schedule::*;

mod executors;
pub use executors::{
    ArtifactBuildExecutor,
    ArtifactStore,
    ArtifactStoreBatchExecutionResult,
    ArtifactStoreBuildExecutionResult,
    AsyncHierarchicalLinkExecutor,
    AsyncPagedArtifactBuildExecutor,
    AsyncPagedHierarchicalLinkExecutor,
    BuildExecutionResult,
    BuildExecutor,
    ExecutionShardLoader,
    HandleBuildExecutionResult,
    HierarchicalLinkArtifactStore,
    HierarchicalLinkExecutor,
    PagedArtifactBuildExecutor,
    PagedHierarchicalLinkExecutor,
    PathBuildExecutor,
    PathHandleBatchedLinkBuildExecutor,
    PathHandleBuildExecutor,
    SourcePackBoxFuture,
};

mod build_state;
pub(in crate::compiler) use build_state::*;
pub use build_state::{
    ARTIFACT_BUILD_FULL_PREPARE_DEFAULT_STEP_LIMIT,
    ARTIFACT_BUILD_PREPARE_DEFAULT_CHUNK_LIMIT,
    SOURCE_PACK_ARTIFACT_MANIFEST_FULL_BUILD_DEFAULT_BATCH_LIMIT,
    SOURCE_PACK_ARTIFACT_MANIFEST_WORKER_RUN_DEFAULT_BATCH_LIMIT,
    SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION,
    SOURCE_PACK_BUILD_PROGRESS_DIRECTORY_PAGE_VERSION,
    SOURCE_PACK_BUILD_PROGRESS_SHARD_SUMMARY_VERSION,
    SOURCE_PACK_BUILD_PROGRESS_SHARD_VERSION,
    SOURCE_PACK_BUILD_PROGRESS_SUMMARY_VERSION,
    SOURCE_PACK_BUILD_STATE_VERSION,
    SOURCE_PACK_LIBRARY_METADATA_FULL_PREPARE_DEFAULT_LIBRARY_LIMIT,
    SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_CHUNK_LIMIT,
    SOURCE_PACK_LIBRARY_METADATA_PREPARE_DEFAULT_SOURCE_FILE_LIMIT,
    SOURCE_PACK_READY_STATE_BATCH_DEFAULT_LIMIT,
    SOURCE_PACK_READY_STATE_ITEM_DEFAULT_LIMIT,
    SOURCE_PACK_WORK_QUEUE_WORKER_RUN_DEFAULT_ITEM_LIMIT,
    SourcePackBuildBatchClaim,
    SourcePackBuildProgressDirectoryIndexPage,
    SourcePackBuildProgressDirectoryPage,
    SourcePackBuildProgressShard,
    SourcePackBuildProgressShardSummary,
    SourcePackBuildProgressSummary,
    SourcePackBuildState,
};

mod prepare_types;
pub(in crate::compiler) use prepare_types::*;
pub use prepare_types::{
    BuildPrepareStage,
    BuildPrepareStepResult,
    FilesystemArtifactExecutionShardStoreResult,
    FilesystemArtifactRefPrepareStepResult,
    FilesystemArtifactShardPrepareStepResult,
    FilesystemArtifactShardStoreResult,
    FilesystemBuildProgressShardStoreResult,
    FilesystemHierarchicalLinkExecutionPrepareStepResult,
    FilesystemHierarchicalLinkLeafPrepareStepResult,
    FilesystemHierarchicalLinkPlanPrepareStepResult,
    FilesystemJobBatchDependentsPrepareStepResult,
    FilesystemJobBatchPrepareStepResult,
    FilesystemLibraryMetadataPrepareProgress,
    FilesystemLibraryMetadataPrepareResult,
    FilesystemLibraryMetadataPrepareStepResult,
    FilesystemLibraryPartitionStoreResult,
    FilesystemLibrarySchedulePageStoreResult,
    FilesystemLibrarySchedulePreparePhase,
    FilesystemLibrarySchedulePrepareProgress,
    FilesystemLibrarySchedulePrepareStepResult,
    FilesystemLibrarySourceFilePageStoreResult,
    FilesystemLinkBatchPrepareStepResult,
    FilesystemWorkQueuePrepareStepResult,
    FilesystemWorkQueueProgressPrepareStepResult,
    PrepareResult,
    PreparedBuild,
    PreparedBuildSummary,
};

mod artifact_model;
pub use artifact_model::{
    FilesystemArtifactBatchClaimProgressResult,
    FilesystemArtifactBatchClaimResult,
    FilesystemArtifactBatchExecutionResult,
    FilesystemArtifactBuildExecutionResult,
    FilesystemArtifactProgressPage,
    FilesystemArtifactProgressSnapshot,
    FilesystemArtifactResumeExecutionResult,
    FilesystemArtifactWorkerRunExecutionResult,
    FilesystemArtifactWorkerRunProgressExecutionResult,
    FilesystemArtifactWorkerStepExecutionResult,
    FilesystemArtifactWorkerStepProgressExecutionResult,
    FilesystemHierarchicalLinkGroupExecutionResult,
    FilesystemWorkQueueArtifactItemExecutionResult,
    FilesystemWorkQueueExecutedItem,
    FilesystemWorkQueueItemClaimResult,
    FilesystemWorkQueueItemCompletionResult,
    FilesystemWorkQueueItemExecutionResult,
    FilesystemWorkQueueLinkItemExecutionResult,
    FilesystemWorkQueueProgressSnapshot,
    FilesystemWorkQueueWorkerRunExecutionResult,
    FilesystemWorkQueueWorkerStepExecutionResult,
    SOURCE_PACK_BUILD_ARTIFACT_EXECUTION_SHARD_VERSION,
    SOURCE_PACK_BUILD_ARTIFACT_REF_INDEX_VERSION,
    SOURCE_PACK_BUILD_ARTIFACT_REF_PAGE_VERSION,
    SOURCE_PACK_BUILD_ARTIFACT_REF_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_BUILD_ARTIFACT_SHARD_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_BUILD_BATCH_SHARD_LOCATOR_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENCY_RANGE_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENT_BATCH_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_DEPENDENTS_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_INLINE_JOB_DEFAULT_RECORD_CAP,
    SOURCE_PACK_BUILD_JOB_BATCH_JOB_LOCATOR_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_PAGE_INDEX_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_PAGE_VERSION,
    SOURCE_PACK_BUILD_JOB_BATCH_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_BUILD_LINK_BATCH_PAGE_INDEX_VERSION,
    SOURCE_PACK_BUILD_LINK_BATCH_PREPARE_PROGRESS_VERSION,
    SOURCE_PACK_BUILD_LINK_INPUT_SHARD_INDEX_VERSION,
    SOURCE_PACK_BUILD_LINK_INTERFACE_BATCH_PAGE_VERSION,
    SOURCE_PACK_BUILD_LINK_OBJECT_BATCH_PAGE_VERSION,
    SOURCE_PACK_EXECUTION_SHARD_SOURCE_FILE_DEFAULT_RECORD_CAP,
    SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_DEFAULT_PAGE_SIZE,
    SOURCE_PACK_JOB_ARTIFACT_INPUT_INTERFACE_PAGE_VERSION,
    SourcePackBuildArtifactExecutionShard,
    SourcePackBuildArtifactRefIndex,
    SourcePackBuildArtifactRefPage,
    SourcePackBuildBatchShardLocator,
    SourcePackBuildJobBatchDependencyPage,
    SourcePackBuildJobBatchDependencyRangePage,
    SourcePackBuildJobBatchDependentBatchPage,
    SourcePackBuildJobBatchDependentsPage,
    SourcePackBuildJobBatchJobLocatorPage,
    SourcePackBuildJobBatchPage,
    SourcePackBuildJobBatchPageIndex,
    SourcePackBuildLinkBatchPageIndex,
    SourcePackBuildLinkInputShardIndex,
    SourcePackBuildLinkInterfaceBatchPage,
    SourcePackBuildLinkObjectBatchPage,
    SourcePackJobArtifactInputInterfacePage,
    SourcePackJobBatchDependents,
    SourcePackLinkInputShardRange,
    SourcePackShardSourceFile,
};

mod manifest;
pub(in crate::compiler) use manifest::*;
pub use manifest::{SOURCE_PACK_PATH_BUILD_MANIFEST_VERSION, SourcePackPathBuildManifest};

mod library_pages;
pub(in crate::compiler) use library_pages::*;

mod link_plan;
pub(in crate::compiler) use link_plan::*;

mod work_queue_plan;
pub(in crate::compiler) use work_queue_plan::*;

mod batches;
pub(in crate::compiler) use batches::*;

mod validation;
pub(in crate::compiler) use validation::*;

mod store;
pub(in crate::compiler) use store::*;
pub use store::{ArtifactPath, ArtifactPathStore, FilesystemArtifactStore};

mod execution;
pub(in crate::compiler) use execution::*;
