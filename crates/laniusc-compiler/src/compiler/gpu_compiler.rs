use super::*;

mod backends;
pub use backends::GpuCompilerBackends;
mod benchmarks;
mod buffers;
mod descriptor_work_queue;
mod typecheck;
mod wasm_codegen;
mod x86_codegen;
use buffers::{OwnedTypecheckParserBuffers, OwnedX86DiagnosticBuffers, OwnedX86ParserBuffers};

mod helpers;
mod host_timer;
use helpers::{
    buffer_if_wgpu_u32_words,
    hir_node_capacity_for_parser_emit,
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

pub struct GpuCompiler<'gpu> {
    pub(super) gpu: &'gpu GpuDevice,
    pub(super) lexer: GpuLexer,
    pub(super) parser: GpuParser,
    pub(super) parse_tables: PrecomputedParseTables,
    pub(super) type_checker: gpu_type_checker::GpuTypeChecker,
    pub(super) resident_pipeline_lock: Mutex<()>,
    pub(super) wasm_generator: Result<Box<wasm::GpuWasmCodeGenerator>, String>,
    pub(super) x86_generator: Result<Box<x86::GpuX86CodeGenerator>, String>,
}

impl GpuCompiler<'static> {
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        Self::new_with_device_and_backends(gpu, GpuCompilerBackends::all()).await
    }

    pub async fn new_with_device_and_backends(
        gpu: &'gpu GpuDevice,
        backends: GpuCompilerBackends,
    ) -> Result<Self, CompileError> {
        let mut host_timer = CompilerHostTimer::new("compiler.init");
        host_timer.pipeline_cache_size(gpu, "start");
        let lexer = GpuLexer::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU lexer: {err}")))?;
        host_timer.stamp("lexer");
        host_timer.pipeline_cache_size(gpu, "after_lexer");
        let parser = GpuParser::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU parser: {err}")))?;
        host_timer.stamp("parser");
        host_timer.pipeline_cache_size(gpu, "after_parser");
        let parse_tables = PrecomputedParseTables::load_bin_bytes(include_bytes!(concat!(
            env!("CARGO_MANIFEST_DIR"),
            "/../../tables/parse_tables.bin"
        )))
        .map_err(|err| CompileError::GpuFrontend(format!("load GPU parse tables: {err}")))?;
        host_timer.stamp("parse_tables");
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                CompileError::GpuFrontend(format!("initialize GPU type checker: {err}"))
            })?;
        host_timer.stamp("type_checker");
        host_timer.pipeline_cache_size(gpu, "after_type_checker");
        let wasm_generator = if backends.wasm {
            let generator = wasm::GpuWasmCodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU WASM code generator failed; WASM compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("wasm_generator");
            host_timer.pipeline_cache_size(gpu, "after_wasm_generator");
            generator
        } else {
            host_timer.stamp("wasm_generator.skipped");
            Err("GPU WASM code generator was not initialized for this compiler".into())
        };
        let x86_generator = if backends.x86 {
            let generator = x86::GpuX86CodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU x86 code generator failed; x86 compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("x86_generator");
            host_timer.pipeline_cache_size(gpu, "after_x86_generator");
            generator
        } else {
            host_timer.stamp("x86_generator.skipped");
            Err("GPU x86 code generator was not initialized for this compiler".into())
        };
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            wasm_generator,
            x86_generator,
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }
}
