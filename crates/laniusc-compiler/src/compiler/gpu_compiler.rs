use super::*;

mod backends;
pub use backends::GpuCompilerBackends;
mod benchmarks;
mod bounded_path_codegen;
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
    source_pack_parser_capacity_high_water: std::sync::Mutex<Option<ResidentParserCapacity>>,
    source_pack_typecheck_capacity_high_water:
        std::sync::Mutex<Option<gpu_type_checker::TypeCheckPreflightCapacities>>,
    pub(super) wasm_generator: Result<Box<wasm::GpuWasmCodeGenerator>, String>,
    pub(super) x86_generator: Result<Box<x86::GpuX86CodeGenerator>, String>,
}

struct SourcePackTreeCapacityCache {
    sources: Vec<String>,
    tree_capacity: u32,
    parser_feature_flags: u32,
    typecheck_preflight: Option<gpu_type_checker::TypeCheckPreflightCapacities>,
    x86_plan: Option<SourcePackX86Plan>,
}

#[derive(Clone, Copy)]
struct SourcePackX86Plan {
    feature_summary: x86::X86FeatureSummary,
    active_tree_capacity: u32,
    semantic_hir_count: u32,
    pointer_jump_steps: u32,
}

/// Resources released by one compiler-wide resident job-buffer trim.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct GpuResidentJobBufferTrim {
    /// Raw wgpu x86 pool buffers, which are not included in LaniusBuffer metrics.
    pub x86_pooled_buffer_count: usize,
    /// Total capacity of the released raw x86 pool buffers.
    pub x86_pooled_buffer_bytes: u64,
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

    fn typecheck_preflight_for<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Option<gpu_type_checker::TypeCheckPreflightCapacities> {
        self.matches(sources)
            .then_some(self.typecheck_preflight)
            .flatten()
    }
}

impl GpuCompiler<'static> {
    /// Create a compiler backed by the process-global GPU device.
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_backends(GpuCompilerBackends::all()).await
    }

    /// Create a compiler backed by the process-global GPU with selected backends.
    pub async fn new_with_backends(backends: GpuCompilerBackends) -> Result<Self, CompileError> {
        let gpu = device::global_result().map_err(|err| {
            compiler_initialization_failed_error(
                "the compiler stopped while selecting a GPU adapter",
                "initialize GPU device",
                anyhow::Error::new((*err).clone()),
            )
        })?;
        Self::new_with_device_and_backends(gpu, backends).await
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
            compiler_initialization_failed_error(
                "the compiler stopped while initializing GPU frontend pipelines",
                "initialize lexer",
                err,
            )
        })?;
        host_timer.stamp("lexer");
        host_timer.pipeline_cache_size(gpu, "after_lexer");
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
        let parser = GpuParser::new_with_device(gpu).await.map_err(|err| {
            compiler_initialization_failed_error(
                "the compiler stopped while initializing GPU frontend pipelines",
                "initialize parser",
                err,
            )
        })?;
        host_timer.stamp("parser");
        host_timer.pipeline_cache_size(gpu, "after_parser");
        // These eager pipeline families have no construction-time data
        // dependencies. Build them concurrently in every profile so debug
        // daemon jobs exercise the same readiness contract as release jobs.
        let (type_checker, wasm_generator, x86_generator) = {
            // Pipeline compilation is CPU/driver-heavy and these families have
            // no construction-time data dependencies.
            std::thread::scope(|scope| {
                const PIPELINE_INIT_STACK_BYTES: usize = 32 * 1024 * 1024;
                let type_checker = std::thread::Builder::new()
                    .name("lanius-typecheck-init".into())
                    .stack_size(PIPELINE_INIT_STACK_BYTES)
                    .spawn_scoped(scope, || {
                        let start = std::time::Instant::now();
                        (
                            gpu_type_checker::GpuTypeChecker::new_with_device(gpu),
                            start.elapsed(),
                        )
                    })
                    .expect("spawn type-check pipeline initialization worker");
                let wasm = backends.wasm.then(|| {
                    std::thread::Builder::new()
                        .name("lanius-wasm-init".into())
                        .stack_size(PIPELINE_INIT_STACK_BYTES)
                        .spawn_scoped(scope, || {
                            let start = std::time::Instant::now();
                            (
                                wasm::GpuWasmCodeGenerator::new_with_device(gpu)
                                    .map(Box::new)
                                    .map_err(|err| err.to_string()),
                                start.elapsed(),
                            )
                        })
                        .expect("spawn Wasm pipeline initialization worker")
                });
                let x86 = backends.x86.then(|| {
                    std::thread::Builder::new()
                        .name("lanius-x86-init".into())
                        .stack_size(PIPELINE_INIT_STACK_BYTES)
                        .spawn_scoped(scope, || {
                            let start = std::time::Instant::now();
                            (
                                x86::GpuX86CodeGenerator::new_with_device(gpu)
                                    .map(Box::new)
                                    .map_err(|err| err.to_string()),
                                start.elapsed(),
                            )
                        })
                        .expect("spawn x86 pipeline initialization worker")
                });
                let (type_checker, type_checker_elapsed) = type_checker.join().map_err(|_| {
                    compiler_initialization_failed_error(
                        "the compiler stopped while initializing GPU type-check pipelines",
                        "initialize type checker worker",
                        anyhow::anyhow!("type checker initialization thread panicked"),
                    )
                })?;
                let type_checker = type_checker.map_err(|err| {
                    compiler_initialization_failed_error(
                        "the compiler stopped while initializing GPU type-check pipelines",
                        "initialize type checker",
                        err,
                    )
                })?;
                if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
                    eprintln!(
                        "[gpu_compile_host_timer] compiler.init.parallel.type_checker: {:.3}ms",
                        type_checker_elapsed.as_secs_f64() * 1000.0
                    );
                }
                let wasm_generator = match wasm.map(std::thread::ScopedJoinHandle::join) {
                    Some(Ok((generator, _elapsed))) => generator,
                    Some(Err(_)) => Err("WASM generator initialization thread panicked".into()),
                    None => Err("WASM code generator was not initialized for this compiler".into()),
                };
                let x86_generator = match x86.map(std::thread::ScopedJoinHandle::join) {
                    Some(Ok((generator, _elapsed))) => generator,
                    Some(Err(_)) => Err("x86 generator initialization thread panicked".into()),
                    None => Err("x86 code generator was not initialized for this compiler".into()),
                };
                Ok::<_, CompileError>((type_checker, wasm_generator, x86_generator))
            })?
        };
        if let Err(err) = &wasm_generator {
            if backends.wasm {
                log::warn!("preinitializing WASM code generator failed: {err}");
            }
        }
        if let Err(err) = &x86_generator {
            if backends.x86 {
                log::warn!("preinitializing x86 code generator failed: {err}");
            }
        }
        host_timer.stamp("parallel_pipeline_families");
        host_timer.pipeline_cache_size(gpu, "after_parallel_pipeline_families");
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            source_pack_tree_capacity_cache: std::sync::Mutex::new(None),
            source_pack_parser_capacity_high_water: std::sync::Mutex::new(None),
            source_pack_typecheck_capacity_high_water: std::sync::Mutex::new(None),
            wasm_generator,
            x86_generator,
        })
    }

    /// Return the GPU device used by this compiler and all resident phase
    /// drivers.
    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    /// Releases source/job-sized GPU buffers across every compiler phase while
    /// retaining shader pipelines, immutable compiler tables, and the device.
    ///
    /// This is the memory-pressure boundary for a long-lived daemon. It uses
    /// the same lock as compilation, so no phase can observe a partially
    /// released resident graph.
    pub async fn release_resident_job_buffers(&self) -> GpuResidentJobBufferTrim {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer.release_current_resident_buffers();
        self.parser.release_current_resident_buffers();
        self.type_checker.release_current_resident_state();
        if let Ok(generator) = self.wasm_generator.as_ref() {
            generator.release_current_resident_buffers();
        }
        let (x86_pooled_buffer_count, x86_pooled_buffer_bytes) = self
            .x86_generator
            .as_ref()
            .map(|generator| generator.release_pooled_buffers(&self.gpu.device))
            .unwrap_or_default();

        *self
            .source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned") = None;
        *self
            .source_pack_parser_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_parser_capacity_high_water poisoned") = None;
        *self
            .source_pack_typecheck_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_typecheck_capacity_high_water poisoned") = None;

        let _ = self.gpu.device.poll(wgpu::PollType::wait_indefinitely());
        GpuResidentJobBufferTrim {
            x86_pooled_buffer_count,
            x86_pooled_buffer_bytes,
        }
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
                typecheck_preflight: None,
                x86_plan: None,
            });
        let mut high_water = self
            .source_pack_parser_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_parser_capacity_high_water poisoned");
        *high_water = Some(
            (*high_water)
                .map(|current| ResidentParserCapacity {
                    tree_capacity: current.tree_capacity.max(capacity.tree_capacity),
                    parser_feature_flags: current.parser_feature_flags
                        | capacity.parser_feature_flags,
                })
                .unwrap_or(capacity),
        );
    }

    fn source_pack_parser_capacity_high_water(&self) -> Option<ResidentParserCapacity> {
        *self
            .source_pack_parser_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_parser_capacity_high_water poisoned")
    }

    fn cached_source_pack_typecheck_preflight<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Option<gpu_type_checker::TypeCheckPreflightCapacities> {
        self.source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned")
            .as_ref()
            .and_then(|cached| cached.typecheck_preflight_for(sources))
    }

    fn remember_source_pack_typecheck_preflight<S: AsRef<str>>(
        &self,
        sources: &[S],
        capacities: gpu_type_checker::TypeCheckPreflightCapacities,
    ) {
        let mut cache = self
            .source_pack_tree_capacity_cache
            .lock()
            .expect("GpuCompiler.source_pack_tree_capacity_cache poisoned");
        if let Some(cached) = cache.as_mut().filter(|cached| cached.matches(sources)) {
            cached.typecheck_preflight = Some(capacities);
        }
        let mut high_water = self
            .source_pack_typecheck_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_typecheck_capacity_high_water poisoned");
        *high_water = Some(
            (*high_water)
                .map(|current| current.union(capacities))
                .unwrap_or(capacities),
        );
    }

    fn source_pack_typecheck_capacity_high_water(
        &self,
    ) -> Option<gpu_type_checker::TypeCheckPreflightCapacities> {
        *self
            .source_pack_typecheck_capacity_high_water
            .lock()
            .expect("GpuCompiler.source_pack_typecheck_capacity_high_water poisoned")
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
    use crate::type_checker::TypeCheckPreflightCapacities;

    #[test]
    fn source_pack_tree_capacity_cache_requires_exact_source_contents() {
        let cache = SourcePackTreeCapacityCache {
            sources: vec!["fn a() {}".into(), "fn b() {}".into()],
            tree_capacity: 17,
            parser_feature_flags: 0x12,
            typecheck_preflight: None,
            x86_plan: None,
        };

        assert!(cache.matches(&["fn a() {}", "fn b() {}"]));
        assert!(!cache.matches(&["fn a() {}", "fn c() {}"]));
        assert!(!cache.matches(&["fn a() {}"]));
    }

    #[test]
    fn source_pack_typecheck_preflight_cache_is_content_exact() {
        let capacities = TypeCheckPreflightCapacities {
            module_records: 7,
            call_param_rows: 5,
            call_arg_rows: 3,
        };
        let cache = SourcePackTreeCapacityCache {
            sources: vec!["fn a() {}".into(), "fn b() {}".into()],
            tree_capacity: 17,
            parser_feature_flags: 0x12,
            typecheck_preflight: Some(capacities),
            x86_plan: None,
        };

        let cached = cache
            .typecheck_preflight_for(&["fn a() {}", "fn b() {}"])
            .expect("exact source pack should reuse preflight capacities");
        assert_eq!(cached.module_records, 7);
        assert_eq!(cached.call_param_rows, 5);
        assert_eq!(cached.call_arg_rows, 3);
        assert!(
            cache
                .typecheck_preflight_for(&["fn a() {}", "fn c() {}"])
                .is_none()
        );
    }
}
