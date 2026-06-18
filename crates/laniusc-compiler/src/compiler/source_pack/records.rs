use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use super::{ExplicitSourcePathFile, SourcePackShardSourceFile};
use crate::{
    codegen::unit::{
        CodegenUnit,
        CodegenUnitLimits,
        DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES,
        FrontendUnit,
        LibraryUnit,
        SourcePackArtifactRef,
        SourcePackArtifactTarget,
        SourcePackJob,
        SourcePackJobBatchLimits,
        SourcePackJobIndexRange,
        SourcePackJobPhase,
    },
    compiler::GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
};

/// Version for the persisted library partition index.
pub const SOURCE_PACK_LIBRARY_PARTITION_INDEX_VERSION: u32 = 1;
/// Version for library metadata preparation progress records.
pub const SOURCE_PACK_LIBRARY_METADATA_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for library-id to partition locator pages.
pub const SOURCE_PACK_LIBRARY_PARTITION_LOCATOR_PAGE_VERSION: u32 = 1;
/// Version for paged library dependency lists.
pub const SOURCE_PACK_LIBRARY_DEPENDENCY_PAGE_VERSION: u32 = 1;
/// Default page size for library dependency records.
pub const SOURCE_PACK_LIBRARY_DEPENDENCY_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for library source-file summary pages.
pub const SOURCE_PACK_LIBRARY_SOURCE_FILE_PAGE_VERSION: u32 = 1;
/// Version for individual source-file metadata pages.
pub const SOURCE_PACK_LIBRARY_SOURCE_FILE_RECORD_PAGE_VERSION: u32 = 1;
/// Inline source-file cap before source metadata spills to record pages.
pub const SOURCE_PACK_LIBRARY_SOURCE_FILE_INLINE_DEFAULT_RECORD_CAP: usize =
    DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Version for persisted library build-unit pages.
pub const SOURCE_PACK_LIBRARY_BUILD_UNIT_PAGE_VERSION: u32 = 1;
/// Inline build-unit cap before unit metadata spills to unit pages.
pub const SOURCE_PACK_LIBRARY_BUILD_UNIT_INLINE_DEFAULT_RECORD_CAP: usize =
    DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Version for persisted frontend-unit pages.
pub const SOURCE_PACK_LIBRARY_FRONTEND_UNIT_PAGE_VERSION: u32 = 1;
/// Version for persisted codegen-unit pages.
pub const SOURCE_PACK_LIBRARY_CODEGEN_UNIT_PAGE_VERSION: u32 = 1;
/// Version for the persisted library schedule index.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_INDEX_VERSION: u32 = 1;
/// Version for library schedule preparation progress records.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for persisted per-library schedule pages.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_PAGE_VERSION: u32 = 1;
/// Inline job cap before schedule jobs spill to job pages.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_INLINE_JOB_DEFAULT_RECORD_CAP: usize =
    DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES;
/// Version for library-id to frontend-job locator pages.
pub const SOURCE_PACK_LIBRARY_FRONTEND_JOB_LOCATOR_PAGE_VERSION: u32 = 1;
/// Version for the persisted job-locator index.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_INDEX_VERSION: u32 = 1;
/// Version for source-pack job-locator pages.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_JOB_LOCATOR_PAGE_VERSION: u32 = 1;
/// Version for persisted source-pack job pages.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_JOB_PAGE_VERSION: u32 = 1;
/// Version for paged source-pack job dependency lists.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_PAGE_VERSION: u32 = 1;
/// Default page size for source-pack job dependency records.
pub const SOURCE_PACK_LIBRARY_SCHEDULE_JOB_DEPENDENCY_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for the persisted hierarchical-link plan index.
pub const SOURCE_PACK_HIERARCHICAL_LINK_PLAN_INDEX_VERSION: u32 = 1;
/// Version for persisted hierarchical-link group pages.
pub const SOURCE_PACK_HIERARCHICAL_LINK_GROUP_PAGE_VERSION: u32 = 1;
/// Version for hierarchical-link planning progress records.
pub const SOURCE_PACK_HIERARCHICAL_LINK_PLAN_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Default page size for hierarchical-link group inputs.
pub const SOURCE_PACK_HIERARCHICAL_LINK_GROUP_INPUT_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for the persisted hierarchical-link execution index.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INDEX_VERSION: u32 = 1;
/// Version for hierarchical-link execution pages.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PAGE_VERSION: u32 = 1;
/// Version for hierarchical-link execution preparation progress records.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for paged interface inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_PAGE_VERSION: u32 = 1;
/// Version for paged object inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_PAGE_VERSION: u32 = 1;
/// Version for paged partial-link inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_PAGE_VERSION: u32 = 1;
/// Default page size for interface inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_INTERFACE_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for object inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_OBJECT_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for partial-link inputs to hierarchical-link execution.
pub const SOURCE_PACK_HIERARCHICAL_LINK_EXECUTION_PARTIAL_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for the persisted work-queue index.
pub const SOURCE_PACK_WORK_QUEUE_INDEX_VERSION: u32 = 1;
/// Version for persisted work-queue item pages.
pub const SOURCE_PACK_WORK_QUEUE_PAGE_VERSION: u32 = 1;
/// Version for work-queue preparation progress records.
pub const SOURCE_PACK_WORK_QUEUE_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Default page size for work-queue item inputs.
pub const SOURCE_PACK_WORK_QUEUE_INPUT_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for paged work-queue dependency lists.
pub const SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_PAGE_VERSION: u32 = 1;
/// Default page size for work-queue dependency lists.
pub const SOURCE_PACK_WORK_QUEUE_DEPENDENCIES_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for paged work-queue dependent lists.
pub const SOURCE_PACK_WORK_QUEUE_DEPENDENTS_PAGE_VERSION: u32 = 1;
/// Default page size for work-queue dependent lists.
pub const SOURCE_PACK_WORK_QUEUE_DEPENDENTS_DEFAULT_PAGE_SIZE: usize = 64;
/// Version for the persisted work-queue progress index.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_INDEX_VERSION: u32 = 1;
/// Version for persisted work-queue progress pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_PAGE_VERSION: u32 = 1;
/// Version for work-queue progress preparation records.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_PREPARE_PROGRESS_VERSION: u32 = 1;
/// Version for work-queue progress directory pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_PAGE_VERSION: u32 = 1;
/// Version for work-queue progress directory-index pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_PAGE_VERSION: u32 = 1;
/// Default page size for work-queue progress pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for work-queue progress directory pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_DEFAULT_PAGE_SIZE: usize = 64;
/// Default page size for work-queue progress directory-index pages.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_DIRECTORY_INDEX_DEFAULT_PAGE_SIZE: usize = 64;
/// Maximum changed progress pages processed in one update batch.
pub const SOURCE_PACK_WORK_QUEUE_PROGRESS_CHANGED_PAGE_BATCH_LIMIT: usize = 64;

/// Persisted library partition summary produced during metadata preparation.
///
/// A partition corresponds to one source library for one target. It records the
/// source range, aggregate source size, and dependency counts used by later
/// schedule and execution stages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryPartition {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    pub dependency_library_ids: Vec<u32>,
    #[serde(default)]
    pub dependency_library_count: usize,
    #[serde(default)]
    pub dependency_page_count: usize,
}

/// Persisted index summarizing all library partitions for a target.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryPartitionIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_count: usize,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
}

/// In-memory result of library partition planning before pages are stored.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackLibraryPartitionPlan {
    pub index: SourcePackLibraryPartitionIndex,
    pub partitions: Vec<SourcePackLibraryPartition>,
}

/// Locator page mapping one library id to its partition index.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryPartitionLocatorPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub library_id: u32,
    pub partition_index: usize,
}

/// Paged dependency library ids for one library partition.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryDependencyPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub page_index: usize,
    pub first_dependency_position: usize,
    pub dependency_count: usize,
    pub dependency_library_ids: Vec<u32>,
}

/// Source-file summary page for one library partition.
///
/// Small partitions may include file metadata inline. Larger partitions spill
/// each file into [`SourcePackLibrarySourceFileRecordPage`].
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibrarySourceFilePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub source_files: Vec<SourcePackShardSourceFile>,
}

/// Source-file metadata page for one source in a partition.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibrarySourceFileRecordPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_index: usize,
    pub file: ExplicitSourcePathFile,
}

/// Persisted build-unit summary for one library partition.
///
/// The page stores the frontend library unit and, when small enough, inline
/// frontend/codegen unit records. Larger unit sets spill into unit pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryBuildUnitPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub dependency_library_ids: Vec<u32>,
    pub first_source_index: usize,
    pub source_file_count: usize,
    pub source_byte_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    pub limits: CodegenUnitLimits,
    pub frontend_unit: LibraryUnit,
    #[serde(default)]
    pub frontend_unit_count: usize,
    #[serde(default)]
    pub codegen_unit_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub frontend_units: Vec<FrontendUnit>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub codegen_units: Vec<CodegenUnit>,
}

/// Persisted frontend unit page for a library partition.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryFrontendUnitPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub limits: CodegenUnitLimits,
    pub frontend_unit_index: usize,
    pub frontend_unit_count: usize,
    pub unit: FrontendUnit,
}

/// Persisted codegen unit page for a library partition.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryCodegenUnitPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub limits: CodegenUnitLimits,
    pub codegen_unit_index: usize,
    pub codegen_unit_count: usize,
    pub unit: CodegenUnit,
}

/// Entry in the library schedule index for one partition.
///
/// This connects partition-local unit planning to global source-pack job
/// indices used by artifact manifests and work queues.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleIndexEntry {
    pub partition_index: usize,
    pub library_id: u32,
    #[serde(default)]
    pub first_frontend_job_index: usize,
    #[serde(default)]
    pub frontend_job_count: usize,
    pub frontend_job_index: usize,
    pub first_codegen_job_index: usize,
    pub codegen_job_count: usize,
}

/// Persisted index summarizing all source-pack jobs derived from library planning.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_count: usize,
    #[serde(default)]
    pub frontend_job_count: usize,
    pub codegen_job_count: usize,
    pub link_job_index: usize,
    pub job_count: usize,
}

/// In-memory result of library schedule planning before pages are stored.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct SourcePackLibrarySchedulePlan {
    pub index: SourcePackLibraryScheduleIndex,
    pub entries: Vec<SourcePackLibraryScheduleIndexEntry>,
}

/// Locator from a library id to the frontend job range that builds it.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryFrontendJobLocatorPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub library_id: u32,
    pub partition_index: usize,
    pub frontend_job_index: usize,
    #[serde(default)]
    pub frontend_job_count: usize,
}

/// Persisted schedule page for one library partition.
///
/// This page records the frontend and codegen jobs owned by a partition plus
/// the link job that eventually consumes their artifacts.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibrarySchedulePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub partition_index: usize,
    pub library_id: u32,
    pub dependency_library_ids: Vec<u32>,
    pub frontend_job_index: usize,
    #[serde(default)]
    pub first_frontend_unit_index: usize,
    #[serde(default)]
    pub frontend_job_count: usize,
    pub first_codegen_unit_index: usize,
    pub first_codegen_job_index: usize,
    pub codegen_job_count: usize,
    pub link_job_index: usize,
    pub frontend_job: SourcePackJob,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub frontend_jobs: Vec<SourcePackJob>,
    pub codegen_jobs: Vec<SourcePackJob>,
}

/// Persisted index describing source-pack job locator pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleJobLocatorIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_count: usize,
    pub locator_count: usize,
}

/// Locator from a global source-pack job index to partition-local ownership.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleJobLocatorPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_index: usize,
    pub phase: SourcePackJobPhase,
    pub partition_index: Option<usize>,
    pub codegen_job_offset: Option<usize>,
}

/// Persisted source-pack job page plus its dependency summary.
///
/// Job pages are the stable lookup records used after library schedule pages
/// have been compacted into a global job index space.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleJobPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_index: usize,
    pub job: SourcePackJob,
    #[serde(default)]
    pub dependency_job_count: usize,
    #[serde(default)]
    pub dependency_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependency_job_ranges: Vec<SourcePackJobIndexRange>,
}

/// Returns the explicit dependency count represented by a job page.
pub(in crate::compiler) fn schedule_job_explicit_dependency_count(
    page: &SourcePackLibraryScheduleJobPage,
) -> usize {
    page.dependency_job_count
        .max(page.job.dependency_job_indices.len())
}

/// Counts the number of jobs represented by dependency ranges.
pub(in crate::compiler) fn job_index_range_dependency_count(
    ranges: &[SourcePackJobIndexRange],
) -> usize {
    ranges.iter().map(|range| range.job_count).sum()
}

/// Paged explicit dependency job indices for one source-pack job.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLibraryScheduleJobDependencyPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub job_index: usize,
    pub page_index: usize,
    pub first_dependency_position: usize,
    pub dependency_count: usize,
    pub dependency_job_indices: Vec<usize>,
}

/// Kind of hierarchical link group represented by a link plan page.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackHierarchicalLinkGroupKind {
    /// Link source artifacts into a first-level partial or final output.
    Leaf,
    /// Link previously produced group outputs into a higher-level output.
    Reduce,
}

/// Persisted index for the hierarchical link plan.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkPlanIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub limits: SourcePackJobBatchLimits,
    pub input_partition_count: usize,
    pub first_link_job_index: usize,
    pub final_link_group_index: usize,
    pub final_link_job_index: usize,
    pub link_group_count: usize,
}

/// Persisted planning page for one hierarchical link group.
///
/// Link groups cap fan-in by grouping frontend/codegen artifacts and earlier
/// link groups into leaf and reduce stages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkGroupPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub group_index: usize,
    pub kind: SourcePackHierarchicalLinkGroupKind,
    pub level: usize,
    pub job_index: usize,
    #[serde(default)]
    pub input_partition_count: usize,
    pub input_partition_indices: Vec<usize>,
    #[serde(default)]
    pub input_frontend_job_count: usize,
    pub input_frontend_job_indices: Vec<usize>,
    pub input_codegen_job_indices: Vec<usize>,
    pub input_link_group_indices: Vec<usize>,
    pub source_byte_count: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    pub oversized_input: bool,
}

/// Persisted index for executable hierarchical link pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkExecutionIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub first_link_job_index: usize,
    pub final_link_group_index: usize,
    pub final_link_job_index: usize,
    pub link_group_count: usize,
    pub final_output_key: String,
}

/// Artifact domain summarized by a link descriptor record contract.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum SourcePackLinkRecordDomain {
    /// Records belonging to a compiled library interface artifact.
    Interface,
    /// Records belonging to a backend object artifact.
    Object,
    /// Records belonging to the final linked output artifact.
    LinkedOutput,
}

/// Record kind summarized by a link descriptor record contract.
#[derive(Clone, Copy, Debug, PartialEq, Eq, PartialOrd, Ord, Serialize, Deserialize)]
pub enum SourcePackLinkRecordKind {
    /// Section table records.
    Section,
    /// Defined or exported symbol records.
    Symbol,
    /// Referenced symbol records that must be resolved by linking.
    UnresolvedSymbol,
    /// Relocation records.
    Relocation,
}

/// Expected count for one link descriptor record family.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkRecordContract {
    pub domain: SourcePackLinkRecordDomain,
    pub kind: SourcePackLinkRecordKind,
    pub record_count: usize,
}

impl SourcePackLinkRecordContract {
    /// Creates a record-contract entry for one domain/kind pair.
    pub fn new(
        domain: SourcePackLinkRecordDomain,
        kind: SourcePackLinkRecordKind,
        record_count: usize,
    ) -> Self {
        Self {
            domain,
            kind,
            record_count,
        }
    }
}

/// Summary of link descriptor records produced or consumed by a link group.
///
/// Descriptor summaries let descriptor executors validate link inputs without
/// loading the full linked artifact contents.
#[derive(Clone, Debug, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackLinkDescriptorSummary {
    #[serde(default)]
    pub interface_symbol_count: usize,
    #[serde(default)]
    pub object_section_count: usize,
    #[serde(default)]
    pub object_symbol_count: usize,
    #[serde(default)]
    pub unresolved_symbol_count: usize,
    #[serde(default)]
    pub relocation_count: usize,
    #[serde(default)]
    pub export_symbol_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub required_runtime_abi_version: Option<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub required_runtime_service_ids: Vec<u32>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub record_contracts: Vec<SourcePackLinkRecordContract>,
}

impl SourcePackLinkDescriptorSummary {
    /// Returns total interface/object/export symbol count, or `None` on overflow.
    pub fn total_symbol_count(&self) -> Option<usize> {
        self.interface_symbol_count
            .checked_add(self.object_symbol_count)?
            .checked_add(self.export_symbol_count)
    }

    /// Returns total descriptor record count, or `None` on overflow.
    pub fn total_descriptor_record_count(&self) -> Option<usize> {
        self.total_symbol_count()?
            .checked_add(self.object_section_count)?
            .checked_add(self.unresolved_symbol_count)?
            .checked_add(self.relocation_count)
    }

    /// Sets required runtime services and records the runtime ABI version when needed.
    pub fn set_required_runtime_services<I>(&mut self, service_ids: I)
    where
        I: IntoIterator<Item = u32>,
    {
        self.required_runtime_service_ids = service_ids.into_iter().collect();
        self.required_runtime_service_ids.sort_unstable();
        self.required_runtime_service_ids.dedup();
        self.required_runtime_abi_version = if self.required_runtime_service_ids.is_empty() {
            None
        } else {
            Some(GPU_SOURCE_PACK_RUNTIME_ABI_VERSION)
        };
    }

    /// Rebuilds record contracts from the summary count fields.
    pub fn sync_record_contracts_from_counts(&mut self) {
        self.record_contracts = self.record_contracts_from_counts();
    }

    /// Returns this summary with record contracts rebuilt from count fields.
    pub fn with_record_contracts_from_counts(mut self) -> Self {
        self.sync_record_contracts_from_counts();
        self
    }

    /// Builds nonzero record-contract entries from the summary count fields.
    pub fn record_contracts_from_counts(&self) -> Vec<SourcePackLinkRecordContract> {
        let mut contracts = Vec::new();
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::Interface,
            SourcePackLinkRecordKind::Symbol,
            self.interface_symbol_count,
        );
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::Object,
            SourcePackLinkRecordKind::Section,
            self.object_section_count,
        );
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::Object,
            SourcePackLinkRecordKind::Symbol,
            self.object_symbol_count,
        );
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::Object,
            SourcePackLinkRecordKind::UnresolvedSymbol,
            self.unresolved_symbol_count,
        );
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::Object,
            SourcePackLinkRecordKind::Relocation,
            self.relocation_count,
        );
        push_link_record_contract(
            &mut contracts,
            SourcePackLinkRecordDomain::LinkedOutput,
            SourcePackLinkRecordKind::Symbol,
            self.export_symbol_count,
        );
        contracts
    }

    /// Returns this summary with sorted, deduplicated required runtime services.
    pub fn with_required_runtime_services<I>(mut self, service_ids: I) -> Self
    where
        I: IntoIterator<Item = u32>,
    {
        self.set_required_runtime_services(service_ids);
        self
    }
}

fn push_link_record_contract(
    contracts: &mut Vec<SourcePackLinkRecordContract>,
    domain: SourcePackLinkRecordDomain,
    kind: SourcePackLinkRecordKind,
    record_count: usize,
) {
    if record_count != 0 {
        contracts.push(SourcePackLinkRecordContract::new(
            domain,
            kind,
            record_count,
        ));
    }
}

/// Executable page for one hierarchical link group.
///
/// The page lists inline link inputs when they fit and points to paged input
/// records when fan-in exceeds the inline capacity.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkExecutionPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub group_index: usize,
    pub kind: SourcePackHierarchicalLinkGroupKind,
    pub job_index: usize,
    #[serde(default)]
    pub input_interface_count: usize,
    #[serde(default)]
    pub input_interface_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub input_interface_ranges: Vec<SourcePackJobIndexRange>,
    pub input_interfaces: Vec<SourcePackArtifactRef>,
    #[serde(default)]
    pub input_object_count: usize,
    #[serde(default)]
    pub input_object_page_count: usize,
    pub input_objects: Vec<SourcePackArtifactRef>,
    #[serde(default)]
    pub input_group_count: usize,
    #[serde(default)]
    pub input_group_page_count: usize,
    pub input_group_indices: Vec<usize>,
    pub input_group_output_keys: Vec<String>,
    pub source_byte_count: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
    pub output_key: String,
    pub final_output: bool,
    #[serde(default)]
    pub descriptor_summary: SourcePackLinkDescriptorSummary,
}

/// Paged interface inputs consumed by one hierarchical link execution group.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkExecutionInterfacePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub group_index: usize,
    pub job_index: usize,
    pub page_index: usize,
    pub first_input_position: usize,
    pub input_count: usize,
    pub input_interfaces: Vec<SourcePackArtifactRef>,
}

/// Paged object inputs consumed by one hierarchical link execution group.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkExecutionObjectPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub group_index: usize,
    pub job_index: usize,
    pub page_index: usize,
    pub first_input_position: usize,
    pub input_count: usize,
    pub input_objects: Vec<SourcePackArtifactRef>,
}

/// Paged partial-link inputs consumed by one hierarchical link execution group.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackHierarchicalLinkExecutionPartialPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub group_index: usize,
    pub job_index: usize,
    pub page_index: usize,
    pub first_input_position: usize,
    pub input_count: usize,
    pub input_group_indices: Vec<usize>,
    pub input_group_output_keys: Vec<String>,
}

/// Work-queue item class used to dispatch a claimed item to an executor path.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub enum SourcePackWorkQueueItemKind {
    /// Build a library interface artifact.
    LibraryFrontend,
    /// Build a backend codegen object artifact.
    Codegen,
    /// Execute a leaf hierarchical link group.
    LinkLeaf,
    /// Execute a reduce hierarchical link group.
    LinkReduce,
}

/// Returns whether a work item executes through the artifact-batch path.
pub(in crate::compiler) fn work_queue_item_kind_is_artifact_backed(
    kind: SourcePackWorkQueueItemKind,
) -> bool {
    matches!(
        kind,
        SourcePackWorkQueueItemKind::LibraryFrontend | SourcePackWorkQueueItemKind::Codegen
    )
}

/// Persisted index summarizing all work-queue items for a target.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub work_item_count: usize,
    #[serde(default)]
    pub artifact_item_count: usize,
    pub final_item_index: usize,
    pub final_job_index: usize,
}

/// Persisted work-queue item page.
///
/// Work items unify artifact batches and hierarchical link groups behind a
/// claimable dependency graph.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueuePage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub item_index: usize,
    pub kind: SourcePackWorkQueueItemKind,
    pub job_index: usize,
    pub dependency_item_indices: Vec<usize>,
    #[serde(default)]
    pub dependency_item_count: usize,
    #[serde(default)]
    pub dependency_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependency_item_ranges: Vec<SourcePackJobIndexRange>,
    #[serde(default)]
    pub dependent_item_indices: Vec<usize>,
    #[serde(default)]
    pub dependent_item_count: usize,
    #[serde(default)]
    pub dependent_page_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub dependent_item_ranges: Vec<SourcePackJobIndexRange>,
    #[serde(default)]
    pub artifact_batch_index: Option<usize>,
    #[serde(default)]
    pub partition_count: usize,
    pub partition_indices: Vec<usize>,
    pub link_group_index: Option<usize>,
    #[serde(default)]
    pub input_frontend_job_count: usize,
    pub input_frontend_job_indices: Vec<usize>,
    #[serde(default)]
    pub input_codegen_job_count: usize,
    pub input_codegen_job_indices: Vec<usize>,
    #[serde(default)]
    pub input_link_group_count: usize,
    pub input_link_group_indices: Vec<usize>,
    pub source_byte_count: usize,
    pub source_file_count: usize,
    #[serde(default)]
    pub source_line_count: usize,
}

/// Paged dependency item indices for one work-queue item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueDependenciesPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub item_index: usize,
    pub page_index: usize,
    pub first_dependency_position: usize,
    pub dependency_count: usize,
    pub dependency_item_indices: Vec<usize>,
}

/// Paged dependent item indices for one work-queue item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueDependentsPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub item_index: usize,
    pub page_index: usize,
    pub first_dependent_position: usize,
    pub dependent_count: usize,
    pub dependent_item_indices: Vec<usize>,
}

/// Lease claim for a work-queue item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueItemClaim {
    pub item_index: usize,
    pub worker_id: String,
    pub lease_expires_unix_nanos: Option<u128>,
}

impl SourcePackWorkQueueItemClaim {
    /// Returns whether this claim has expired at `now_unix_nanos`.
    ///
    /// Claims without an expiry do not expire through this predicate.
    pub fn is_expired(&self, now_unix_nanos: Option<u128>) -> bool {
        matches!(
            (now_unix_nanos, self.lease_expires_unix_nanos),
            (Some(now), Some(expires)) if expires <= now
        )
    }
}

/// Summary for one work-queue progress page.
///
/// Directory pages use these summaries to find ready or expiring work without
/// scanning every progress page.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueProgressPageSummary {
    pub page_index: usize,
    pub first_item_index: usize,
    pub item_count: usize,
    #[serde(default)]
    pub artifact_item_count: usize,
    pub completed_item_count: usize,
    pub ready_item_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_item_index: Option<usize>,
    #[serde(default)]
    pub ready_artifact_item_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_artifact_item_index: Option<usize>,
    #[serde(default)]
    pub blocked_item_count: usize,
    #[serde(default)]
    pub pending_dependent_item_count: usize,
    pub claimed_item_count: usize,
    #[serde(default)]
    pub ready_claimed_item_count: usize,
    #[serde(default)]
    pub ready_artifact_claimed_item_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

/// Directory page summarizing a range of work-queue progress pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueProgressDirectoryPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub directory_page_index: usize,
    pub first_progress_page_index: usize,
    pub progress_page_count: usize,
    pub ready_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_page_index: Option<usize>,
    #[serde(default)]
    pub ready_artifact_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_artifact_page_index: Option<usize>,
    #[serde(default)]
    pub ready_claimed_page_count: usize,
    #[serde(default)]
    pub ready_artifact_claimed_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

/// Higher-level directory page summarizing work-queue progress directories.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueProgressDirectoryIndexPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub directory_index_page_index: usize,
    pub first_directory_page_index: usize,
    pub directory_page_count: usize,
    pub ready_directory_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_directory_page_index: Option<usize>,
    #[serde(default)]
    pub ready_artifact_directory_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_artifact_directory_page_index: Option<usize>,
    #[serde(default)]
    pub ready_claimed_directory_page_count: usize,
    #[serde(default)]
    pub ready_artifact_claimed_directory_page_count: usize,
    #[serde(default)]
    pub fully_claimed_ready_directory_page_count: usize,
    #[serde(default)]
    pub fully_claimed_ready_artifact_directory_page_count: usize,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub earliest_claim_lease_expires_unix_nanos: Option<u128>,
}

/// Remaining dependency count for one work-queue item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueRemainingDependencyCount {
    pub item_index: usize,
    pub remaining_dependency_count: usize,
}

/// Remaining dependent count for one work-queue item.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueRemainingDependentCount {
    pub item_index: usize,
    pub remaining_dependent_count: usize,
}

/// Persisted index summarizing all work-queue progress pages.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueProgressIndex {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub work_item_count: usize,
    pub page_size: usize,
    pub page_count: usize,
    #[serde(default)]
    pub artifact_item_count: usize,
    pub completed_item_count: usize,
    pub ready_item_count: usize,
    #[serde(default)]
    pub ready_artifact_item_count: usize,
    pub claimed_item_count: usize,
    pub first_ready_item_index: Option<usize>,
    #[serde(default, skip_serializing_if = "Option::is_none")]
    pub first_ready_artifact_item_index: Option<usize>,
}

/// Persisted progress page for a range of work-queue items.
///
/// Progress pages track completed, ready, claimed, and remaining dependency
/// state. Updating these pages is the core work-queue mutation boundary.
#[derive(Clone, Debug, PartialEq, Eq, Serialize, Deserialize)]
pub struct SourcePackWorkQueueProgressPage {
    pub version: u32,
    pub target: SourcePackArtifactTarget,
    pub page_index: usize,
    pub first_item_index: usize,
    pub item_count: usize,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub artifact_item_indices: Vec<usize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub remaining_dependency_counts: Vec<SourcePackWorkQueueRemainingDependencyCount>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub remaining_dependent_counts: Vec<SourcePackWorkQueueRemainingDependentCount>,
    pub completed_item_indices: Vec<usize>,
    pub ready_item_indices: Vec<usize>,
    #[serde(default, skip_serializing_if = "Vec::is_empty")]
    pub ready_artifact_item_indices: Vec<usize>,
    pub claimed_items: Vec<SourcePackWorkQueueItemClaim>,
}

/// Internal normalized library manifest entry used during input validation.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct ExplicitSourceLibraryManifestEntry {
    pub(in crate::compiler) library_id: u32,
    pub(in crate::compiler) source_file_count: usize,
    pub(in crate::compiler) dependency_library_ids: Vec<u32>,
}

/// Internal bundle returned after library schedule pages have been prepared.
#[derive(Clone, Debug, PartialEq, Eq)]
pub(in crate::compiler) struct PreparedLibrarySchedulePages {
    pub(in crate::compiler) library_partition_index: SourcePackLibraryPartitionIndex,
    pub(in crate::compiler) library_partition_index_path: PathBuf,
    pub(in crate::compiler) library_source_file_page_count: usize,
    pub(in crate::compiler) library_build_unit_page_count: usize,
    pub(in crate::compiler) library_schedule_index: SourcePackLibraryScheduleIndex,
    pub(in crate::compiler) library_schedule_index_path: PathBuf,
    pub(in crate::compiler) library_schedule_page_count: usize,
}
