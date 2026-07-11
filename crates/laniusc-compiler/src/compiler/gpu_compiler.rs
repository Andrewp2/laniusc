use super::*;

mod backends;
pub use backends::GpuCompilerBackends;
mod benchmarks;
mod buffers;
mod descriptor_work_queue;
mod typecheck;
pub(in crate::compiler::gpu_compiler) use typecheck::{
    type_check_diagnostic_at_span,
    type_check_execution_failed_for_source,
    type_check_execution_failed_for_source_pack,
};
mod wasm_codegen;
mod x86_codegen;
use buffers::{OwnedTypecheckParserBuffers, OwnedX86DiagnosticBuffers, OwnedX86ParserBuffers};

mod helpers;
mod host_timer;
use helpers::{
    StageExecutionFailure,
    buffer_if_wgpu_u32_words,
    first_nonempty_source_span,
    hir_node_capacity_for_parser_emit,
    parser_execution_failed_for_source,
    parser_execution_failed_for_source_pack,
    source_tokenization_failed_for_source,
    source_tokenization_failed_for_source_pack,
    stage_execution_failed_for_source,
    stage_execution_failed_for_source_pack,
    trace_wasm_compile,
    type_mismatch_label,
    type_mismatch_note,
    x86_inst_hir_node_count_for_backend_capacity,
};
pub(in crate::compiler) use helpers::{prepare_source_for_gpu, prepare_source_for_gpu_from_path};
use host_timer::CompilerHostTimer;

mod source_pack_executor;
pub use source_pack_executor::{
    GpuSourcePackArtifactExecutor,
    GpuSourcePackCodegenObjectBuildHandle,
    GpuSourcePackLibraryInterfaceBuildHandle,
    GpuSourcePackLinkHandle,
};
#[cfg(test)]
pub(in crate::compiler) use source_pack_executor::{
    validate_gpu_source_pack_descriptor_artifact_paths,
    validate_gpu_source_pack_descriptor_job_source_file_records,
};

/// GPU-resident compiler instance for frontend checks and backend compilation.
///
/// A compiler owns phase drivers and resident caches tied to one `GpuDevice`.
/// Public methods serialize resident pipeline use through `resident_pipeline_lock`
/// because lexer/parser/type-check/backend buffers are reused across operations.
pub struct GpuCompiler<'gpu> {
    pub(super) gpu: &'gpu GpuDevice,
    pub(super) lexer: GpuLexer,
    pub(super) parser: GpuParser,
    pub(super) parse_tables: PrecomputedParseTables,
    pub(super) type_checker: gpu_type_checker::GpuTypeChecker,
    pub(super) resident_pipeline_lock: Mutex<()>,
    source_pack_tree_capacity_cache: std::sync::Mutex<Option<SourcePackTreeCapacityCache>>,
    pub(super) wasm_generator: Result<Box<wasm::GpuWasmCodeGenerator>, String>,
    pub(super) x86_generator: Result<Box<x86::GpuX86CodeGenerator>, String>,
}

struct SourcePackTreeCapacityCache {
    sources: Vec<String>,
    tree_capacity: u32,
    parser_feature_flags: u32,
    x86_plan: Option<SourcePackX86Plan>,
}

#[derive(Clone, Copy)]
struct SourcePackX86Plan {
    feature_summary: x86::X86FeatureSummary,
    active_tree_capacity: u32,
    semantic_hir_count: u32,
}

impl SourcePackTreeCapacityCache {
    fn matches<S: AsRef<str>>(&self, sources: &[S]) -> bool {
        self.sources.len() == sources.len()
            && self
                .sources
                .iter()
                .zip(sources)
                .all(|(cached, source)| cached == source.as_ref())
    }
}

impl GpuCompiler<'static> {
    /// Create a compiler backed by the process-global GPU device.
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    /// Create a compiler for an existing GPU device with all backend families
    /// initialized.
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        Self::new_with_device_and_backends(gpu, GpuCompilerBackends::all()).await
    }

    /// Create a compiler for an existing GPU device and a selected backend set.
    ///
    /// Frontend phases are always initialized. Disabled or failed backends are
    /// stored as deferred errors so frontend-only operations can still run.
    pub async fn new_with_device_and_backends(
        gpu: &'gpu GpuDevice,
        backends: GpuCompilerBackends,
    ) -> Result<Self, CompileError> {
        let mut host_timer = CompilerHostTimer::new("compiler.init");
        host_timer.pipeline_cache_size(gpu, "start");
        let lexer = GpuLexer::new_with_device(gpu).await.map_err(|err| {
            compiler_execution_failed_error(
                "the compiler stopped while initializing GPU frontend pipelines",
                "initialize lexer",
                err,
            )
        })?;
        host_timer.stamp("lexer");
        host_timer.pipeline_cache_size(gpu, "after_lexer");
        let parser = GpuParser::new_with_device(gpu).await.map_err(|err| {
            compiler_execution_failed_error(
                "the compiler stopped while initializing GPU frontend pipelines",
                "initialize parser",
                err,
            )
        })?;
        host_timer.stamp("parser");
        host_timer.pipeline_cache_size(gpu, "after_parser");
        let parse_tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../tables/parse_tables.bin"
        )))
        .map_err(|err| {
            compiler_execution_failed_error(
                "the compiler stopped while loading parser tables",
                "load parse tables",
                err,
            )
        })?;
        host_timer.stamp("parse_tables");
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
                    eprintln!("[gpu_compile_host_timer] compiler.init.type_checker.error: {err:#}");
                }
                compiler_execution_failed_error(
                    "the compiler stopped while initializing GPU type-check pipelines",
                    "initialize type checker",
                    err,
                )
            })?;
        host_timer.stamp("type_checker");
        host_timer.pipeline_cache_size(gpu, "after_type_checker");
        let wasm_generator = if backends.wasm {
            let generator = wasm::GpuWasmCodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing WASM code generator failed; WASM compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("wasm_generator");
            host_timer.pipeline_cache_size(gpu, "after_wasm_generator");
            generator
        } else {
            host_timer.stamp("wasm_generator.skipped");
            Err("WASM code generator was not initialized for this compiler".into())
        };
        let x86_generator = if backends.x86 {
            let generator = x86::GpuX86CodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing x86 code generator failed; x86 compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("x86_generator");
            host_timer.pipeline_cache_size(gpu, "after_x86_generator");
            generator
        } else {
            host_timer.stamp("x86_generator.skipped");
            Err("x86 code generator was not initialized for this compiler".into())
        };
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            source_pack_tree_capacity_cache: std::sync::Mutex::new(None),
            wasm_generator,
            x86_generator,
        })
    }

    /// Return the GPU device used by this compiler and all resident phase
    /// drivers.
    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    fn cached_source_pack_parser_capacity<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Option<ResidentParserCapacity> {
        self.source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned")
            .as_ref()
            .filter(|cached| cached.matches(sources))
            .map(|cached| ResidentParserCapacity {
                tree_capacity: cached.tree_capacity,
                parser_feature_flags: cached.parser_feature_flags,
            })
    }

    fn remember_source_pack_parser_capacity<S: AsRef<str>>(
        &self,
        sources: &[S],
        capacity: ResidentParserCapacity,
    ) {
        *self
            .source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned") =
            Some(SourcePackTreeCapacityCache {
                sources: sources
                    .iter()
                    .map(|source| source.as_ref().to_owned())
                    .collect(),
                tree_capacity: capacity.tree_capacity,
                parser_feature_flags: capacity.parser_feature_flags,
                x86_plan: None,
            });
    }

    fn cached_source_pack_x86_plan<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Option<SourcePackX86Plan> {
        self.source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned")
            .as_ref()
            .filter(|cached| cached.matches(sources))
            .and_then(|cached| cached.x86_plan)
    }

    fn remember_source_pack_x86_plan<S: AsRef<str>>(&self, sources: &[S], plan: SourcePackX86Plan) {
        let mut cache = self
            .source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned");
        if let Some(cached) = cache.as_mut().filter(|cached| cached.matches(sources)) {
            cached.x86_plan = Some(plan);
        }
    }
}

#[cfg(test)]
mod tests {
    use super::SourcePackTreeCapacityCache;

    #[test]
    fn source_pack_tree_capacity_cache_requires_exact_source_contents() {
        let cache = SourcePackTreeCapacityCache {
            sources: vec!["fn a() {}".into(), "fn b() {}".into()],
            tree_capacity: 17,
            parser_feature_flags: 0x12,
            x86_plan: None,
        };

        assert!(cache.matches(&["fn a() {}", "fn b() {}"]));
        assert!(!cache.matches(&["fn a() {}", "fn c() {}"]));
        assert!(!cache.matches(&["fn a() {}"]));
    }
}
