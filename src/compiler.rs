use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
    time::{SystemTime, UNIX_EPOCH},
};

use futures_intrusive::sync::Mutex;
use serde::{Deserialize, Serialize};

use crate::{
    codegen::{
        unit::{
            CodegenUnit,
            CodegenUnitLimits,
            CodegenUnitPlan,
            DEFAULT_CODEGEN_UNIT_MAX_SOURCE_FILES,
            DEFAULT_SOURCE_PACK_BUILD_SHARD_MAX_BATCHES,
            FrontendUnit,
            FrontendUnitPlan,
            LibraryUnit,
            SOURCE_PACK_BUILD_ARTIFACT_MANIFEST_VERSION,
            SOURCE_PACK_BUILD_ARTIFACT_SHARD_INDEX_VERSION,
            SOURCE_PACK_LINK_BATCH_INPUT_DEFAULT_PAGE_SIZE,
            SourceFileUnitInput,
            SourcePackArtifactIndexRange,
            SourcePackArtifactKind,
            SourcePackArtifactManifest,
            SourcePackArtifactManifestEntry,
            SourcePackArtifactPlan,
            SourcePackArtifactRef,
            SourcePackArtifactTarget,
            SourcePackBuildArtifactManifest,
            SourcePackBuildArtifactShard,
            SourcePackBuildArtifactShardIndex,
            SourcePackBuildArtifactShardKind,
            SourcePackBuildArtifactShardPlan,
            SourcePackBuildPlan,
            SourcePackBuildShardLimits,
            SourcePackJob,
            SourcePackJobArtifactManifest,
            SourcePackJobArtifactManifestPlan,
            SourcePackJobBatch,
            SourcePackJobBatchDependency,
            SourcePackJobBatchDependencyRange,
            SourcePackJobBatchLimits,
            SourcePackJobIndexRange,
            SourcePackJobPhase,
            SourcePackJobPlan,
            SourcePackJobPlanBuilder,
            SourcePackJobSchedule,
            SourcePackLibraryDependency,
            SourcePackLinkInterfaceBatch,
            SourcePackLinkObjectBatch,
            SourcePackScheduleError,
            source_pack_artifact_key_for_output,
            source_pack_link_batch_input_limit,
        },
        wasm,
        x86,
    },
    gpu::{
        device::{self, GpuDevice},
        timer::GpuTimer,
    },
    lexer::{
        buffers::GpuBuffers as LexerBuffers,
        driver::{GpuLexer, ResidentLexerParserInputs},
    },
    parser::{
        buffers::ParserBuffers,
        driver::{GpuParser, Ll1AcceptResult},
        tables::PrecomputedParseTables,
    },
    type_checker as gpu_type_checker,
};

mod artifact_descriptor;
pub use artifact_descriptor::{
    GPU_SOURCE_PACK_ARTIFACT_DESCRIPTOR_VERSION,
    GpuSourcePackArtifactDescriptor,
    GpuSourcePackArtifactStage,
    GpuSourcePackDependencyInterfaceSummary,
    GpuSourcePackRecordArrayDescriptor,
};

mod source_pack;
pub use source_pack::*;

mod work_queue_progress;
use work_queue_progress::*;

mod build_progress;
use build_progress::*;

#[derive(Debug)]
pub enum CompileError {
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::GpuFrontend(err) => write!(f, "GPU frontend error: {err}"),
            CompileError::GpuSyntax(err) => write!(f, "GPU syntax error: {err}"),
            CompileError::GpuTypeCheck(err) => write!(f, "GPU type check error: {err}"),
            CompileError::GpuCodegen(err) => write!(f, "GPU codegen error: {err}"),
        }
    }
}

impl std::error::Error for CompileError {}

pub struct GpuParseBenchmarkResult {
    pub ll1: Ll1AcceptResult,
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub semantic_hir_count: u32,
}

pub struct GpuLiveCapacityEstimateResult {
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub parser_emit_len: u32,
    pub semantic_hir_count: u32,
}

mod gpu_compiler;
pub use gpu_compiler::*;

mod public_planning_api;
pub use public_planning_api::*;

mod public_execution_api;
pub use public_execution_api::*;

mod gpu_public_api;
pub use gpu_public_api::*;

#[cfg(test)]
mod tests;
