use super::*;
use crate::codegen::{
    lowering_ir::LoweringArtifactKind,
    unit::DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES,
};

mod backends;
pub use backends::GpuCompilerBackends;
mod benchmarks;
mod bounded_path_codegen;
mod buffers;
mod descriptor_work_queue;
mod typecheck;
mod wasm_codegen;
mod x86_codegen;

mod helpers;
mod host_timer;
mod resident_source_pack_executor;
mod stable_unit_plan;
mod unit_cache;
use helpers::{
    StageExecutionFailure,
    first_nonempty_source_span,
    parser_execution_failed_for_source,
    parser_execution_failed_for_source_pack,
    source_tokenization_failed_for_source,
    source_tokenization_failed_for_source_pack,
    stage_execution_failed_for_source,
    stage_execution_failed_for_source_pack,
    trace_wasm_compile,
    type_mismatch_label,
    type_mismatch_note,
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
    pub(super) wasm_linker: Result<Box<wasm::GpuWasmLinker>, String>,
    pub(super) x86_linker: Result<Box<x86::GpuX86Linker>, String>,
    pub(super) wasm_lowering: Result<Box<GpuLoweringWorkspaceCache>, String>,
    pub(super) x86_lowering: Result<Box<GpuLoweringWorkspaceCache>, String>,
    stable_unit_plan: std::sync::Mutex<Option<stable_unit_plan::StableUnitPlan>>,
    compiled_unit_cache: std::sync::Mutex<unit_cache::CompiledUnitCache>,
    parser_shape_cache: std::sync::Mutex<ParserShapeCache>,
    codegen_kernels: Option<Box<crate::gpu::kernels::KernelRegistry>>,
}

// A worst-case 10,000-file project may place each file in its own bounded
// compilation unit. Keep one complete warm-project working set while bounding
// daemon metadata to a few megabytes.
const MAX_CACHED_PARSER_SHAPES: usize = 16_384;

#[derive(Clone, Copy)]
struct CachedParserShape {
    shape: crate::parser::driver::ResidentParserJobShape,
    last_used: u64,
}

#[derive(Default)]
struct ParserShapeCache {
    entries: std::collections::HashMap<blake3::Hash, CachedParserShape>,
    clock: u64,
}

impl ParserShapeCache {
    fn get(&mut self, key: &blake3::Hash) -> Option<crate::parser::driver::ResidentParserJobShape> {
        self.clock = self.clock.wrapping_add(1);
        let entry = self.entries.get_mut(key)?;
        entry.last_used = self.clock;
        Some(entry.shape)
    }

    fn insert(&mut self, key: blake3::Hash, shape: crate::parser::driver::ResidentParserJobShape) {
        self.clock = self.clock.wrapping_add(1);
        if self.entries.len() >= MAX_CACHED_PARSER_SHAPES && !self.entries.contains_key(&key) {
            if let Some(oldest) = self
                .entries
                .iter()
                .min_by_key(|(_, entry)| entry.last_used)
                .map(|(key, _)| *key)
            {
                self.entries.remove(&oldest);
            }
        }
        self.entries.insert(
            key,
            CachedParserShape {
                shape,
                last_used: self.clock,
            },
        );
    }
}

fn prepare_codegen_kernels(
    device: &wgpu::Device,
    backends: GpuCompilerBackends,
) -> anyhow::Result<crate::gpu::kernels::KernelRegistry> {
    crate::gpu::kernels::KernelRegistry::prepare_prefixes(
        device,
        crate::codegen::lowering::LOWERING_KERNEL_PREFIXES,
        |key| {
            let target_enabled = if key.contains("/x86/") {
                backends.x86
            } else if key.contains("/wasm/") {
                backends.wasm
            } else {
                backends.x86 || backends.wasm
            };
            target_enabled
        },
    )
}

type PipelineFamilyInitialization = (
    gpu_type_checker::GpuTypeChecker,
    Result<Box<wasm::GpuWasmLinker>, String>,
    Result<Box<x86::GpuX86Linker>, String>,
    Result<Box<GpuLoweringWorkspaceCache>, String>,
    Result<Box<GpuLoweringWorkspaceCache>, String>,
    Option<Box<crate::gpu::kernels::KernelRegistry>>,
);

const PIPELINE_INIT_STACK_BYTES: usize = 32 * 1024 * 1024;

// This coordinator intentionally runs on the same explicit large-stack policy
// as the pipeline constructors it launches. Its debug-build frame contains
// all three scoped join handles and their result variants; keeping that frame
// out of an arbitrary async executor thread makes compiler initialization safe
// without imposing a stack-size requirement on callers.
#[inline(never)]
fn initialize_pipeline_families(
    gpu: &GpuDevice,
    backends: GpuCompilerBackends,
) -> Result<PipelineFamilyInitialization, CompileError> {
    std::thread::scope(|scope| {
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
                    let linker = wasm::GpuWasmLinker::new_with_device(gpu)
                        .map(Box::new)
                        .map_err(|err| err.to_string());
                    let lowering = Ok(Box::new(GpuLoweringWorkspaceCache::new(
                        LoweringTarget::Wasm,
                    )));
                    ((linker, lowering), start.elapsed())
                })
                .expect("spawn Wasm pipeline initialization worker")
        });
        let x86 = backends.x86.then(|| {
            std::thread::Builder::new()
                .name("lanius-x86-init".into())
                .stack_size(PIPELINE_INIT_STACK_BYTES)
                .spawn_scoped(scope, || {
                    let start = std::time::Instant::now();
                    let linker = x86::GpuX86Linker::new_with_device(gpu)
                        .map(Box::new)
                        .map_err(|err| err.to_string());
                    let lowering = Ok(Box::new(GpuLoweringWorkspaceCache::new(
                        LoweringTarget::X86_64,
                    )));
                    ((linker, lowering), start.elapsed())
                })
                .expect("spawn x86 pipeline initialization worker")
        });
        let codegen_kernels = (backends.x86 || backends.wasm).then(|| {
            std::thread::Builder::new()
                .name("lanius-codegen-kernel-init".into())
                .stack_size(PIPELINE_INIT_STACK_BYTES)
                .spawn_scoped(scope, || prepare_codegen_kernels(&gpu.device, backends))
                .expect("spawn codegen kernel initialization worker")
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
        let (wasm_linker, wasm_lowering) = match wasm.map(std::thread::ScopedJoinHandle::join) {
            Some(Ok(((linker, lowering), _elapsed))) => (linker, lowering),
            Some(Err(_)) => (
                Err("WASM linker initialization thread panicked".into()),
                Err("WASM lowering initialization thread panicked".into()),
            ),
            None => (
                Err("WASM linker was not initialized for this compiler".into()),
                Err("WASM lowering pipeline was not initialized for this compiler".into()),
            ),
        };
        let (x86_linker, x86_lowering) = match x86.map(std::thread::ScopedJoinHandle::join) {
            Some(Ok(((linker, lowering), _elapsed))) => (linker, lowering),
            Some(Err(_)) => (
                Err("x86 linker initialization thread panicked".into()),
                Err("x86 lowering initialization thread panicked".into()),
            ),
            None => (
                Err("x86 linker was not initialized for this compiler".into()),
                Err("x86 lowering pipeline was not initialized for this compiler".into()),
            ),
        };
        let codegen_kernels = match codegen_kernels.map(std::thread::ScopedJoinHandle::join) {
            Some(Ok(Ok(kernels))) => Some(Box::new(kernels)),
            Some(Ok(Err(err))) => {
                return Err(compiler_initialization_failed_error(
                    "the compiler stopped while initializing GPU code-generation pipelines",
                    "initialize code-generation kernels",
                    err,
                ));
            }
            Some(Err(_)) => {
                return Err(compiler_initialization_failed_error(
                    "the compiler stopped while initializing GPU code-generation pipelines",
                    "initialize code-generation kernel worker",
                    anyhow::anyhow!("code-generation kernel initialization thread panicked"),
                ));
            }
            None => None,
        };
        Ok((
            type_checker,
            wasm_linker,
            x86_linker,
            wasm_lowering,
            x86_lowering,
            codegen_kernels,
        ))
    })
}

fn initialize_pipeline_families_on_coordinator(
    gpu: &GpuDevice,
    backends: GpuCompilerBackends,
) -> Result<PipelineFamilyInitialization, CompileError> {
    let initialized = std::thread::scope(|scope| {
        std::thread::Builder::new()
            .name("lanius-pipeline-init".into())
            .stack_size(PIPELINE_INIT_STACK_BYTES)
            .spawn_scoped(scope, || {
                initialize_pipeline_families(gpu, backends).map(Box::new)
            })
            .expect("spawn pipeline initialization coordinator")
            .join()
            .map_err(|_| {
                compiler_initialization_failed_error(
                    "the compiler stopped while initializing GPU pipelines",
                    "initialize pipeline coordinator",
                    anyhow::anyhow!("pipeline initialization coordinator panicked"),
                )
            })?
    })?;
    Ok(*initialized)
}

/// Resources released by one compiler-wide resident job-buffer trim.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct GpuResidentJobBufferTrim;

impl GpuCompiler<'static> {
    /// Create a compiler backed by the process-global GPU device.
    pub fn new()
    -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, CompileError>> + 'static>>
    {
        Self::new_with_backends(GpuCompilerBackends::all())
    }

    /// Create a compiler backed by the process-global GPU with selected backends.
    pub fn new_with_backends(
        backends: GpuCompilerBackends,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, CompileError>> + 'static>>
    {
        Box::pin(async move {
            let gpu = device::global_result().map_err(|err| {
                compiler_initialization_failed_error(
                    "the compiler stopped while selecting a GPU adapter",
                    "initialize GPU device",
                    anyhow::Error::new((*err).clone()),
                )
            })?;
            Self::new_with_device_and_backends(gpu, backends).await
        })
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    /// Create a compiler for an existing GPU device with all backend families
    /// initialized.
    pub fn new_with_device(
        gpu: &'gpu GpuDevice,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, CompileError>> + 'gpu>>
    {
        Self::new_with_device_and_backends(gpu, GpuCompilerBackends::all())
    }

    /// Create a compiler for an existing GPU device and a selected backend set.
    ///
    /// Frontend phases are always initialized. Disabled or failed backends are
    /// stored as deferred errors so frontend-only operations can still run.
    pub fn new_with_device_and_backends(
        gpu: &'gpu GpuDevice,
        backends: GpuCompilerBackends,
    ) -> std::pin::Pin<Box<dyn std::future::Future<Output = Result<Self, CompileError>> + 'gpu>>
    {
        Box::pin(async move {
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
            let (
                type_checker,
                wasm_linker,
                x86_linker,
                wasm_lowering,
                x86_lowering,
                codegen_kernels,
            ) = initialize_pipeline_families_on_coordinator(gpu, backends)?;
            if let Err(err) = &wasm_linker {
                if backends.wasm {
                    log::warn!("preinitializing WASM linker failed: {err}");
                }
            }
            if let Err(err) = &x86_linker {
                if backends.x86 {
                    log::warn!("preinitializing x86 linker failed: {err}");
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
                wasm_linker,
                x86_linker,
                wasm_lowering,
                x86_lowering,
                stable_unit_plan: std::sync::Mutex::new(None),
                compiled_unit_cache: std::sync::Mutex::new(unit_cache::CompiledUnitCache::default()),
                parser_shape_cache: std::sync::Mutex::new(ParserShapeCache::default()),
                codegen_kernels,
            })
        })
    }

    /// Return the GPU device used by this compiler and all resident phase
    /// drivers.
    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub(super) fn ensure_lowering_pipeline(
        &self,
        target: LoweringTarget,
        source_bytes: u32,
        tokens: u32,
        hir_nodes: u32,
        artifact_kind: LoweringArtifactKind,
        upstream_workspace: &[crate::gpu::buffers::TrackedBufferView<'_>],
        hir: crate::codegen::lowering::GpuSemanticHirInputs<'_>,
        semantic: crate::type_checker::GpuSemanticArtifactView<'_>,
    ) -> Result<std::sync::Arc<crate::codegen::lowering_pipeline::GpuLoweringPipeline>, String>
    {
        let maximum = u32::try_from(DEFAULT_CODEGEN_UNIT_MAX_SOURCE_BYTES)
            .map_err(|_| "default codegen-unit capacity exceeds u32".to_string())?;
        if source_bytes > maximum {
            return Err(format!(
                "compilation unit is {source_bytes} source bytes, exceeding the configured {maximum}-byte frontend compilation-unit capacity"
            ));
        }
        let cache = match target {
            LoweringTarget::X86_64 => &self.x86_lowering,
            LoweringTarget::Wasm => &self.wasm_lowering,
        }
        .as_deref()
        .map_err(Clone::clone)?;
        let kernels = self.codegen_kernels.as_deref().ok_or_else(|| {
            "code-generation kernels were not initialized for this compiler".to_string()
        })?;
        cache.ensure(
            &self.gpu.device,
            kernels,
            source_bytes,
            tokens,
            hir_nodes,
            artifact_kind,
            upstream_workspace,
            hir,
            semantic,
        )
    }

    pub(super) fn lowering_pipeline(
        &self,
        target: LoweringTarget,
    ) -> Result<std::sync::Arc<crate::codegen::lowering_pipeline::GpuLoweringPipeline>, String>
    {
        match target {
            LoweringTarget::X86_64 => &self.x86_lowering,
            LoweringTarget::Wasm => &self.wasm_lowering,
        }
        .as_deref()
        .map_err(Clone::clone)?
        .current()
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
        self.type_checker.release_current_resident_workspace();
        if let Ok(cache) = &self.wasm_lowering {
            cache.release();
        }
        if let Ok(cache) = &self.x86_lowering {
            cache.release();
        }
        if let Ok(linker) = &self.x86_linker {
            linker.release_job_buffers();
        }
        if let Ok(linker) = &self.wasm_linker {
            linker.release_job_buffers();
        }
        crate::gpu::passes_core::release_reflected_bind_group_caches();
        let _ = self.gpu.device.poll(wgpu::PollType::wait_indefinitely());
        GpuResidentJobBufferTrim
    }
}

#[cfg(test)]
mod tests {
    use super::{GpuCompiler, GpuCompilerBackends};
    use crate::{
        codegen::lowering_ir::{LoweringArtifactKind, LoweringTarget},
        gpu::{
            buffers::readback_bytes,
            passes_core::{map_readback_blocking, submit_with_progress},
        },
    };

    #[test]
    fn physical_gpu_lowers_the_compilers_checked_compact_hir_for_both_targets() {
        std::thread::Builder::new()
            .name("checked-hir lowering integration".into())
            .stack_size(64 * 1024 * 1024)
            .spawn(run_checked_hir_lowering_integration)
            .expect("spawn checked-HIR lowering integration")
            .join()
            .expect("checked-HIR lowering integration panicked");
    }

    fn run_checked_hir_lowering_integration() {
        let gpu = crate::gpu::device::global();
        let compiler = pollster::block_on(GpuCompiler::new_with_device_and_backends(
            gpu,
            GpuCompilerBackends::all(),
        ))
        .expect("initialize compiler");
        let production_source = "fn main() -> i32 { return 42; }";
        let production_x86 =
            pollster::block_on(compiler.compile_expanded_source_to_x86_64(production_source))
                .expect("production x86 lowering pipeline");
        assert_lowered_program_result(
            LoweringTarget::X86_64,
            "production_entrypoint",
            &production_x86,
            42,
        );
        let production_wasm =
            pollster::block_on(compiler.compile_expanded_source_to_wasm(production_source))
                .expect("production Wasm lowering pipeline");
        assert_lowered_program_result(
            LoweringTarget::Wasm,
            "production_entrypoint",
            &production_wasm,
            42,
        );
        let production_pack = [
            "module core::math; pub fn add(a: i32, b: i32) -> i32 { return a + b; }",
            "module app::main; import core::math; fn main() -> i32 { return add(20, 22); }",
        ];
        let production_pack_x86 =
            pollster::block_on(compiler.compile_source_pack_to_x86_64(&production_pack))
                .expect("production source-pack x86 lowering pipeline");
        assert_lowered_program_result(
            LoweringTarget::X86_64,
            "production_source_pack",
            &production_pack_x86,
            42,
        );
        let production_pack_wasm =
            pollster::block_on(compiler.compile_source_pack_to_wasm(&production_pack))
                .expect("production source-pack Wasm lowering pipeline");
        assert_lowered_program_result(
            LoweringTarget::Wasm,
            "production_source_pack",
            &production_pack_wasm,
            42,
        );
        let cases = [
            ("constant", "fn main() -> i32 { return 42; }", 42),
            (
                "locals_arithmetic",
                "fn main() -> i32 { let x: i32 = 6; let y: i32 = 7; return x * y; }",
                42,
            ),
            (
                "direct_call",
                "fn add(a: i32, b: i32) -> i32 { return a + b; } fn main() -> i32 { return add(20, 22); }",
                42,
            ),
            (
                "if_else",
                "fn main() -> i32 { if (1 < 2) { return 42; } else { return 7; } }",
                42,
            ),
            (
                "nested_expression",
                "fn main() -> i32 { return (2 + 3) * (4 + 5); }",
                45,
            ),
            (
                "while_assignment",
                "fn main() -> i32 { let i: i32 = 0; let total: i32 = 0; while (i < 4) { total = total + i; i = i + 1; } return total; }",
                6,
            ),
            (
                "float_arithmetic_compare",
                "fn main() -> i32 { let x: f32 = 1.5; let y: f32 = 2.0; if (x * y == 3.0) { return 42; } else { return 7; } }",
                42,
            ),
            (
                "i32_to_f32_conversion",
                "extern \"lanius_std\" fn i32_to_f32(value: i32) -> f32; fn main() -> i32 { if (i32_to_f32(7) == 7.0) { return 42; } else { return 7; } }",
                42,
            ),
            (
                "shared_host_runtime_calls",
                "extern \"lanius_std\" fn argc() -> i32; extern \"lanius_std\" fn write_stdout(ptr: u32, len: usize) -> i32; fn main() -> i32 { return argc() + write_stdout(0, 0) + 41; }",
                42,
            ),
            (
                "string_rodata_host_abi",
                "extern \"lanius_std\" fn write_text(handle: i32, text: str) -> i32; fn main() -> i32 { return write_text(1, \"hello\") + 37; }",
                42,
            ),
            (
                "break_continue",
                "fn main() -> i32 { let i: i32 = 0; let total: i32 = 0; while (i < 8) { i = i + 1; if (i == 3) { continue; } if (i == 6) { break; } total = total + i; } return total; }",
                12,
            ),
            (
                "for_range",
                "fn main() -> i32 { let total: i32 = 0; for value in 2 .. 5 { total = total + value; } return total; }",
                9,
            ),
            (
                "for_range_control",
                "fn main() -> i32 { let total: i32 = 0; for value in 2 .. 8 { if (value == 3) { continue; } if (value == 6) { break; } total = total + value; } return total; }",
                11,
            ),
            (
                "for_snapshots_end_bound",
                "fn main() -> i32 { let end: i32 = 5; let total: i32 = 0; for value in 2 .. end { end = 3; total = total + value; } return total; }",
                9,
            ),
            (
                "array_literal_index",
                "fn main() -> i32 { let values: [i32; 3] = [10, 20, 12]; return values[2]; }",
                12,
            ),
            (
                "array_dynamic_index",
                "fn main() -> i32 { let index: i32 = 1; let values: [i32; 3] = [10, 20, 12]; return values[index]; }",
                20,
            ),
            (
                "float_array_dynamic_index",
                "fn main() -> i32 { let index: i32 = 1; let values: [f32; 3] = [1.5, 2.5, 3.5]; if (values[index] == 2.5) { return 42; } else { return 7; } }",
                42,
            ),
            (
                "array_parameter",
                "fn pick(values: [i32; 3], index: i32) -> i32 { return values[index]; } fn main() -> i32 { let values: [i32; 3] = [10, 20, 12]; return pick(values, 2); }",
                12,
            ),
            (
                "array_allocation_in_loop",
                "fn main() -> i32 { let i: i32 = 0; let total: i32 = 0; while (i < 3) { let values: [i32; 3] = [i, i + 1, i + 2]; total = total + values[1]; i = i + 1; } return total; }",
                6,
            ),
            (
                "struct_literal_checked_field_order",
                "struct Pair { left: i32, right: i32, } fn main() -> i32 { let pair: Pair = Pair { right: 25, left: 17 }; return pair.left + pair.right; }",
                42,
            ),
            (
                "struct_return",
                "struct Pair { left: i32, right: i32, } fn make() -> Pair { return Pair { right: 25, left: 17 }; } fn main() -> i32 { let pair: Pair = make(); return pair.left + pair.right; }",
                42,
            ),
            (
                "same_module_enum_unit_match",
                "enum Choice { First, Second, } fn main() -> i32 { let value: Choice = Second; return match (value) { First -> 7, Second -> 42, }; }",
                42,
            ),
            (
                "same_module_enum_payload_arm_constant",
                "enum Adjustment { Add(i32), Hold, } fn main() -> i32 { let value: Adjustment = Add(41); return match (value) { Add(amount) -> 42, Hold -> 7, }; }",
                42,
            ),
            (
                "same_module_enum_direct_match",
                "enum Adjustment { Add(i32), Hold, } fn main() -> i32 { let value: Adjustment = Add(41); return match (value) { Add(amount) -> amount + 1, Hold -> 0, }; }",
                42,
            ),
            (
                "same_module_enum_return_match",
                "enum Adjustment { Add(i32), Hold, } fn choose(seed: i32) -> Adjustment { if (seed == 1) { return Add(41); } return Hold; } fn score(value: Adjustment) -> i32 { return match (value) { Add(amount) -> amount + 1, Hold -> 0, }; } fn main() -> i32 { let value: Adjustment = choose(1); return score(value); }",
                42,
            ),
            (
                "method_receiver_and_explicit_argument",
                "struct Counter { value: i32, } impl Counter { fn add(self, amount: i32) -> i32 { return self.value + amount; } } fn main() -> i32 { let counter: Counter = Counter { value: 37 }; return counter.add(5); }",
                42,
            ),
            (
                "associated_constructor_and_aggregate_method",
                "struct Vec2 { x: i32, y: i32, } impl Vec2 { fn new(x: i32, y: i32) -> Vec2 { return Vec2 { x: x, y: y }; } fn add(self, right: Vec2) -> Vec2 { return Vec2::new(self.x + right.x, self.y + right.y); } } fn main() -> i32 { let left: Vec2 = Vec2::new(1, 2); let right: Vec2 = Vec2::new(4, 5); let sum: Vec2 = left.add(right); return sum.y * 6; }",
                42,
            ),
            (
                "large_aggregate_sret_method",
                "struct Quad { a: i32, b: i32, c: i32, d: i32, } impl Quad { fn new(a: i32, b: i32, c: i32, d: i32) -> Quad { return Quad { a: a, b: b, c: c, d: d }; } fn bump(self, amount: i32) -> Quad { return Quad::new(self.a + amount, self.b + amount, self.c + amount, self.d + amount); } } fn main() -> i32 { let value: Quad = Quad::new(1, 2, 3, 4); let bumped: Quad = value.bump(5); return bumped.a + bumped.b + bumped.c + bumped.d; }",
                30,
            ),
            (
                "nested_aggregate_fields",
                "struct Vec2 { x: i32, y: i32, } struct Ray { origin: Vec2, direction: Vec2, } fn main() -> i32 { let origin: Vec2 = Vec2 { x: 1, y: 2 }; let direction: Vec2 = Vec2 { x: 3, y: 42 }; let ray: Ray = Ray { origin: origin, direction: direction }; return ray.direction.y; }",
                42,
            ),
            (
                "nested_aggregate_return_and_method",
                "struct Vec2 { x: i32, y: i32, } struct Ray { origin: Vec2, direction: Vec2, } impl Ray { fn sample(self) -> i32 { return self.direction.y; } } fn make_ray() -> Ray { let origin: Vec2 = Vec2 { x: 1, y: 2 }; let direction: Vec2 = Vec2 { x: 3, y: 42 }; return Ray { origin: origin, direction: direction }; } fn main() -> i32 { let ray: Ray = make_ray(); return ray.sample(); }",
                42,
            ),
            (
                "nested_aggregate_sret",
                "struct Vec2 { x: i32, y: i32, } struct Bundle { first: Vec2, tag: i32, last: Vec2, } fn make_bundle() -> Bundle { let first: Vec2 = Vec2 { x: 1, y: 2 }; let last: Vec2 = Vec2 { x: 3, y: 42 }; return Bundle { first: first, tag: 7, last: last }; } fn main() -> i32 { let bundle: Bundle = make_bundle(); return bundle.last.y; }",
                42,
            ),
        ];

        let selected_case = std::env::var("LANIUS_CHECKED_HIR_TEST_CASE").ok();
        for (case, source, expected) in cases {
            if selected_case
                .as_deref()
                .is_some_and(|selected| selected != case)
            {
                continue;
            }
            pollster::block_on(compiler.type_check_source(source)).unwrap_or_else(|error| {
                panic!("produce checked frontend artifacts for {case}: {error}")
            });
            let hir = compiler
                .parser
                .current_resident_hir()
                .unwrap_or_else(|| panic!("parser should retain compact HIR for {case}"));
            if case == "break_continue" {
                assert_checked_branch_control_depths(&gpu.device, &gpu.queue, &hir, &compiler);
            }

            for target in [LoweringTarget::X86_64, LoweringTarget::Wasm] {
                let mut encoder =
                    gpu.device
                        .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("checked-hir lowering integration"),
                        });
                let semantic = compiler
                    .type_checker
                    .semantic_artifact()
                    .expect("type checker should retain semantic artifact");
                let pipeline = compiler
                    .type_checker
                    .with_post_typecheck_workspace(&semantic, |workspace| {
                        compiler.ensure_lowering_pipeline(
                            target,
                            u32::try_from(source.len()).unwrap(),
                            u32::try_from(source.len()).unwrap(),
                            hir.capacity,
                            LoweringArtifactKind::Executable,
                            workspace,
                            (&hir).into(),
                            semantic.view(),
                        )
                    })
                    .expect("type-check workspace should remain available")
                    .expect("lowering workspace");
                pipeline.record(&mut encoder, None).unwrap_or_else(|error| {
                    panic!("record {target:?} lowering for {case}: {error}")
                });
                crate::gpu::passes_core::submit_with_progress(
                    &gpu.queue,
                    "checked-hir lowering integration",
                    encoder.finish(),
                );

                let artifact_result = pipeline.finish_artifact(&gpu.device, &gpu.queue);
                let artifact = artifact_result.unwrap_or_else(|error| {
                    panic!("finish {target:?} artifact for {case}: {error}")
                });
                assert_lowered_program_result(target, case, &artifact, expected);
            }
        }
    }

    fn readback_words(
        device: &wgpu::Device,
        buffer: &crate::gpu::buffers::LaniusBuffer<u8>,
    ) -> Vec<u32> {
        let slice = buffer.slice(..);
        map_readback_blocking(device, &slice, "checked control-depth readback")
            .expect("map checked control-depth readback");
        let mapped = slice.get_mapped_range();
        let words = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect();
        drop(mapped);
        buffer.unmap();
        words
    }

    fn assert_checked_branch_control_depths(
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        hir: &crate::parser::buffers::GpuHirView,
        compiler: &GpuCompiler,
    ) {
        let semantic = compiler
            .type_checker
            .semantic_artifact()
            .expect("type checker should retain semantic artifact");
        let semantic = semantic.view();
        let count_readback = readback_bytes(device, "test.control_depth.count.rb", 4, 1);
        let core_bytes =
            hir.capacity as usize * std::mem::size_of::<crate::parser::buffers::HirCore>();
        let core_readback = readback_bytes(
            device,
            "test.control_depth.core.rb",
            core_bytes,
            hir.capacity as usize * 4,
        );
        let depth_bytes = hir.capacity as usize * 4;
        let depth_readback = readback_bytes(
            device,
            "test.control_depth.depth.rb",
            depth_bytes,
            hir.capacity as usize,
        );
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("test.control_depth.encoder"),
        });
        hir.count.copy_to(&mut encoder, 0, &count_readback, 0, 4);
        hir.core
            .copy_to(&mut encoder, 0, &core_readback, 0, core_bytes as u64);
        semantic.control_depth_by_hir.copy_to(
            &mut encoder,
            0,
            &depth_readback,
            0,
            depth_bytes as u64,
        );
        submit_with_progress(queue, "checked control-depth readback", encoder.finish());

        let count = readback_words(device, &count_readback)[0] as usize;
        let cores = readback_words(device, &core_readback);
        let depths = readback_words(device, &depth_readback);
        let control_rows = (0..count)
            .filter_map(|row| {
                let core = &cores[row * 4..row * 4 + 4];
                matches!(core[0], 10..=13).then_some((row, core.to_vec(), depths[row]))
            })
            .collect::<Vec<_>>();
        let branches = (0..count)
            .filter_map(|row| {
                let kind = cores[row * 4];
                matches!(kind, 12 | 13).then_some((kind, depths[row]))
            })
            .collect::<Vec<_>>();
        assert_eq!(
            branches,
            [(13, 1), (12, 1)],
            "control_rows={control_rows:?}"
        );
    }

    fn assert_lowered_program_result(
        target: LoweringTarget,
        case: &str,
        artifact: &[u8],
        expected: i32,
    ) {
        match target {
            LoweringTarget::X86_64 => {
                assert_eq!(&artifact[..4], b"\x7fELF");
                #[cfg(all(unix, target_arch = "x86_64"))]
                {
                    use std::os::unix::fs::PermissionsExt;

                    let path = std::env::temp_dir()
                        .join(format!("lanius-checked-hir-{}-{case}", std::process::id()));
                    std::fs::write(&path, artifact).expect("write x86 artifact");
                    let mut permissions = std::fs::metadata(&path)
                        .expect("stat x86 artifact")
                        .permissions();
                    permissions.set_mode(0o755);
                    std::fs::set_permissions(&path, permissions)
                        .expect("make x86 artifact executable");
                    let status = std::process::Command::new(&path)
                        .status()
                        .expect("run x86 artifact");
                    if status.code() == Some(expected) {
                        let _ = std::fs::remove_file(&path);
                    } else {
                        panic!("x86 case {case} artifact {path:?} exited with {status}");
                    }
                }
            }
            LoweringTarget::Wasm => {
                assert_eq!(&artifact[..4], b"\0asm");
                let path = std::env::temp_dir().join(format!(
                    "lanius-checked-hir-{}-{case}.wasm",
                    std::process::id()
                ));
                std::fs::write(&path, artifact).expect("write Wasm artifact");
                let output = std::process::Command::new("node")
                    .arg("-e")
                    .arg(
                        "const fs=require('fs');const bytes=fs.readFileSync(process.argv[1]);const module=new WebAssembly.Module(bytes);let instance;const env={};for(const entry of WebAssembly.Module.imports(module)){if(entry.module==='env'&&entry.kind==='function')env[entry.name]=entry.name==='argc'?()=>1:entry.name==='write_text'?(fd,ptr,len)=>{const text=Buffer.from(instance.exports.memory.buffer,ptr,len).toString();return fd===1&&text==='hello'?len:-1}:()=>0;}WebAssembly.instantiate(module,{env}).then(result=>{instance=result;process.exit(instance.exports.main()===Number(process.argv[2])?0:1)}).catch(error=>{console.error(error);process.exit(2)})",
                    )
                    .arg(&path)
                    .arg(expected.to_string())
                    .output();
                if let Ok(output) = output {
                    if output.status.success() {
                        let _ = std::fs::remove_file(&path);
                    } else {
                        panic!(
                            "Wasm case {case} artifact {path:?} did not return {expected}: {}",
                            String::from_utf8_lossy(&output.stderr)
                        );
                    }
                }
            }
        }
    }
}
