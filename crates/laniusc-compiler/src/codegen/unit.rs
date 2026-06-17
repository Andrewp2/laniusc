//! Bounded codegen-unit planning.
//!
//! A source pack can be arbitrarily large only if later compiler stages can
//! operate on bounded jobs. This module keeps that policy independent from the
//! current GPU backend implementation: it groups contiguous source files into
//! natural library/file-bounded units, never splits a file, and marks files that
//! exceed the unit budget so callers can route them to a separate large-file
//! strategy.

use std::{
    collections::{BTreeMap, BTreeSet},
    ops::Range,
};

use serde::{Deserialize, Serialize};

pub const DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES: usize = 512 * 1024;
pub const DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES: usize = 64;
pub const SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE: usize = 64;

mod units;
pub use units::{
    CodegenUnit,
    CodegenUnitLimits,
    CodegenUnitPlan,
    FrontendUnit,
    FrontendUnitPlan,
    LibraryUnit,
    LibraryUnitPlan,
    SourceFileUnitInput,
};
pub(in crate::codegen::unit) use units::{LibraryBuilder, UnitBuilder};

mod jobs;
pub use jobs::{
    SourcePackArtifactIndexRange,
    SourcePackJob,
    SourcePackJobBatch,
    SourcePackJobBatchDependency,
    SourcePackJobBatchDependencyPlan,
    SourcePackJobBatchDependencyRange,
    SourcePackJobBatchDependencySummary,
    SourcePackJobBatchLimits,
    SourcePackJobBatchSchedule,
    SourcePackJobBatchSummary,
    SourcePackJobIndexRange,
    SourcePackJobPhase,
    SourcePackJobPlan,
    SourcePackJobPlanBuilder,
    SourcePackJobSchedule,
    SourcePackJobWave,
    SourcePackJobWaveSchedule,
    SourcePackJobWaveSummary,
    SourcePackLibraryDependency,
    SourcePackScheduleError,
    link_batch_input_limit,
    link_batch_input_limit as source_pack_link_batch_input_limit,
};

mod artifacts;
pub use artifacts::{
    SourcePackArtifactKind,
    SourcePackArtifactLastUse,
    SourcePackArtifactLastUseIndex,
    SourcePackArtifactLastUsePlan,
    SourcePackArtifactLifetimeSummary,
    SourcePackArtifactManifest,
    SourcePackArtifactManifestEntry,
    SourcePackArtifactManifestSummary,
    SourcePackArtifactPlan,
    SourcePackArtifactRef,
    SourcePackArtifactUse,
    SourcePackArtifactUsePlan,
    SourcePackJobArtifactIo,
    SourcePackJobArtifactIoPlan,
    SourcePackJobArtifactIoSummary,
    SourcePackJobArtifactManifest,
    SourcePackJobArtifactManifestPlan,
    SourcePackJobArtifactManifestSummary,
    SourcePackLinkInterfaceBatch,
    SourcePackLinkInterfaceBatchPlan,
    SourcePackLinkInterfaceBatchSummary,
    SourcePackLinkObjectBatch,
    SourcePackLinkObjectBatchPlan,
    SourcePackLinkObjectBatchSummary,
    SourcePackLinkPlan,
};

mod build_plan;
pub use build_plan::{
    SourcePackBuildArtifactEstimateSummary,
    SourcePackBuildPlan,
    artifact_key_for_output,
    artifact_key_for_output as source_pack_artifact_key_for_output,
};

mod build_manifest;
pub use build_manifest::{
    DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_ARTIFACTS,
    DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES,
    DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_JOBS,
    SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
    SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
    SourcePackArtifactTarget,
    SourcePackBuildArtifactManifest,
    SourcePackBuildArtifactShard,
    SourcePackBuildArtifactShardIndex,
    SourcePackBuildArtifactShardKind,
    SourcePackBuildArtifactShardPlan,
    SourcePackBuildShardLimits,
};

mod ranges;
pub(in crate::codegen::unit) use ranges::*;

#[cfg(test)]
mod tests;
