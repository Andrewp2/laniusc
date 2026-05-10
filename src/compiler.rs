use std::{fs, path::Path, sync::OnceLock};

use crate::{
    codegen::gpu_wasm,
    gpu::device::{self, GpuDevice},
    lexer::gpu::driver::GpuLexer,
    parser::{gpu::driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::gpu as gpu_type_checker,
};

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

pub struct GpuCompiler<'gpu> {
    gpu: &'gpu GpuDevice,
    lexer: GpuLexer,
    parser: GpuParser,
    parse_tables: PrecomputedParseTables,
    type_checker: gpu_type_checker::GpuTypeChecker,
    wasm_generator: OnceLock<Result<gpu_wasm::GpuWasmCodeGenerator, String>>,
}

impl GpuCompiler<'static> {
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        let lexer = GpuLexer::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU lexer: {err}")))?;
        let parser = GpuParser::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU parser: {err}")))?;
        let parse_tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .map_err(|err| {
                    CompileError::GpuFrontend(format!("load GPU parse tables: {err}"))
                })?;
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                CompileError::GpuFrontend(format!("initialize GPU type checker: {err}"))
            })?;
        gpu.persist_pipeline_cache();
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            wasm_generator: OnceLock::new(),
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        self.type_check_expanded_source(&src).await
    }

    pub async fn type_check_source_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check_from_path(path)?;
        self.type_check_expanded_source(&src).await
    }

    async fn type_check_expanded_source(&self, src: &str) -> Result<(), CompileError> {
        self.lexer
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder, mut timer| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_syntax_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            &self.parse_tables,
                            |parse_bufs, encoder| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.direct_hir.done");
                                }
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.n,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.ll1_status,
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                Ok::<_, CompileError>(recorded)
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let type_check = type_check?;
                    Ok((parser_check, type_check))
                },
                |device, _queue, _bufs, (parser_check, type_check)| {
                    self.parser
                        .finish_recorded_resident_syntax_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    async fn compile_expanded_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        trace_wasm_compile("compile.start");
        self.lexer
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder, mut timer| {
                    trace_wasm_compile("lex.recorded");
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_syntax_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            &self.parse_tables,
                            |parse_bufs, encoder| {
                                trace_wasm_compile("parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.direct_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.n,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        hir_status,
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(
                                        |visible_decl,
                                         visible_type,
                                         call_fn_index,
                                         call_return_type| {
                                            self.wasm_generator()?
                                                .record_wasm_from_gpu_token_buffer(
                                                    device,
                                                    queue,
                                                    encoder,
                                                    bufs.n,
                                                    bufs.n,
                                                    &bufs.tokens_out,
                                                    &bufs.token_count,
                                                    &bufs.in_bytes,
                                                    parse_bufs.tree_capacity,
                                                    &parse_bufs.hir_kind,
                                                    &parse_bufs.hir_token_pos,
                                                    &parse_bufs.hir_token_end,
                                                    hir_status,
                                                    visible_decl,
                                                    visible_type,
                                                    call_fn_index,
                                                    call_return_type,
                                                )
                                                .map_err(|err| {
                                                    CompileError::GpuCodegen(err.to_string())
                                                })
                                        },
                                    )
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("wasm.recorded");
                                Ok::<_, CompileError>((recorded, wasm_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("parser.typecheck.recorded");
                    let (type_check, wasm_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check))
                },
                |device, queue, _bufs, (parser_check, type_check, wasm_check)| {
                    trace_wasm_compile("finish.parser.start");
                    self.parser
                        .finish_recorded_resident_syntax_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    fn wasm_generator(&self) -> Result<&gpu_wasm::GpuWasmCodeGenerator, CompileError> {
        trace_wasm_compile("wasm.generator");
        self.wasm_generator
            .get_or_init(|| {
                let generator = gpu_wasm::GpuWasmCodeGenerator::new_with_device(self.gpu)
                    .map_err(|err| err.to_string())?;
                self.gpu.persist_pipeline_cache();
                Ok(generator)
            })
            .as_ref()
            .map_err(|err| {
                CompileError::GpuCodegen(format!("initialize GPU WASM code generator: {err}"))
            })
    }

    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _ = src;
        self.compile_expanded_source_to_x86_64("").await
    }

    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let _ = path;
        self.compile_expanded_source_to_x86_64("").await
    }

    async fn compile_expanded_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _ = src;
        Err(gpu_x86_unavailable_error())
    }
}

fn gpu_x86_unavailable_error() -> CompileError {
    CompileError::GpuCodegen(
        "GPU x86_64 codegen is not currently available; the CPU backend route has been removed"
            .to_string(),
    )
}

fn trace_wasm_compile(stage: &str) {
    if std::env::var("LANIUS_WASM_TRACE").ok().as_deref() == Some("1") {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

fn prepare_source_for_gpu_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    fs::read_to_string(path.as_ref()).map_err(|err| {
        CompileError::GpuFrontend(format!("read {}: {err}", path.as_ref().display()))
    })
}

fn prepare_source_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn prepare_source_for_gpu_type_check(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_type_check_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn global_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    GPU_COMPILER
        .get_or_init(|| pollster::block_on(GpuCompiler::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU compiler: {err}")))
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    global_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    global_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_with_gpu_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn type_check_source_with_gpu_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let _ = src;
    Err(gpu_x86_unavailable_error())
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let _ = path;
    Err(gpu_x86_unavailable_error())
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let _ = (src, compiler);
    Err(gpu_x86_unavailable_error())
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let _ = (path, compiler);
    Err(gpu_x86_unavailable_error())
}
