use std::{
    collections::{BTreeMap, BTreeSet},
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
    time::{SystemTime, UNIX_EPOCH},
};

use futures_intrusive::sync::Mutex;
use serde::{Deserialize, Serialize};

#[cfg(test)]
use crate::codegen::unit::artifact_key_for_output as source_pack_artifact_key_for_output;
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
    GPU_SOURCE_PACK_FIRST_RUNTIME_SERVICE_ID,
    GPU_SOURCE_PACK_LAST_RUNTIME_SERVICE_ID,
    GPU_SOURCE_PACK_RUNTIME_ABI_VERSION,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_ALLOCATOR_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_CLOCK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_COUNT,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_ENV_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_FILESYSTEM_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_GPU_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_HOST_SERVICES_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_IDS,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_NETWORK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_PANIC_HOOK_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_PROCESS_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_SECURE_RNG_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_STDIO_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_TEST_HARNESS_ID,
    GPU_SOURCE_PACK_RUNTIME_SERVICE_THREADS_ID,
    GPU_SOURCE_PACK_UNKNOWN_RUNTIME_ABI_VERSION,
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

mod diagnostics;
pub use diagnostics::*;

#[derive(Debug)]
pub enum CompileError {
    Diagnostic(Diagnostic),
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::Diagnostic(diagnostic) => write!(f, "{diagnostic}"),
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
mod test_support;
#[cfg(test)]
mod tests;
