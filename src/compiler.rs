use std::sync::OnceLock;

use crate::{
    codegen::{c, gpu_c},
    gpu::device::{self, GpuDevice},
    hir::{self, HirError, HirToken},
    lexer::gpu::driver::GpuLexer,
    parser::{gpu::driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::gpu as gpu_type_checker,
};

#[derive(Debug)]
pub enum CompileError {
    Hir(HirError),
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::Hir(err) => write!(f, "{err}"),
            CompileError::GpuFrontend(err) => write!(f, "GPU frontend error: {err}"),
            CompileError::GpuSyntax(err) => write!(f, "GPU syntax error: {err}"),
            CompileError::GpuTypeCheck(err) => write!(f, "GPU type check error: {err}"),
            CompileError::GpuCodegen(err) => write!(f, "GPU codegen error: {err}"),
        }
    }
}

impl std::error::Error for CompileError {}

impl From<HirError> for CompileError {
    fn from(err: HirError) -> Self {
        Self::Hir(err)
    }
}

pub fn compile_source_to_c(src: &str) -> Result<String, CompileError> {
    let hir = hir::parse_source(src)?;
    Ok(c::emit_c(&hir))
}

pub async fn compile_source_to_c_with_gpu_frontend(src: &str) -> Result<String, CompileError> {
    global_gpu_compiler()?
        .compile_source_to_c_with_gpu_frontend(src)
        .await
}

pub async fn compile_simple_source_to_c_with_gpu_codegen(
    src: &str,
) -> Result<String, CompileError> {
    compile_source_to_c_with_gpu_codegen(src).await
}

pub async fn compile_source_to_c_with_gpu_codegen(src: &str) -> Result<String, CompileError> {
    global_gpu_compiler()?.compile_source_to_c(src).await
}

pub struct GpuCompiler<'gpu> {
    gpu: &'gpu GpuDevice,
    lexer: GpuLexer,
    parser: GpuParser,
    parse_tables: PrecomputedParseTables,
    type_checker: gpu_type_checker::GpuTypeChecker,
    code_generator: OnceLock<Result<gpu_c::GpuCCodeGenerator, String>>,
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
            code_generator: OnceLock::new(),
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn compile_source_to_c(&self, src: &str) -> Result<String, CompileError> {
        self.lexer
            .with_recorded_resident_tokens(
                src,
                |device, queue, bufs, encoder| {
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts(
                            encoder,
                            bufs.n,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            &self.parse_tables,
                            |parse_bufs, encoder| {
                                let hir_status = &parse_bufs.ll1_status;
                                self.type_checker
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
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let type_check = type_check?;
                    let codegen_check = self
                        .type_checker
                        .with_codegen_buffers(
                            |visible_decl, visible_type, call_fn_index, call_return_type| {
                                let parse_bufs = self.parser.with_current_resident_buffers(
                                    bufs.n,
                                    &self.parse_tables,
                                    |parse_bufs| {
                                        let code_generator = self.code_generator()?;
                                        code_generator
                                            .record_c_from_gpu_token_buffer_with_hir(
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
                                                visible_decl,
                                                visible_type,
                                                call_fn_index,
                                                call_return_type,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    },
                                );
                                parse_bufs
                            },
                        )
                        .ok_or_else(|| {
                            CompileError::GpuCodegen("GPU visible declaration table missing".into())
                        })??;
                    Ok((parser_check, type_check, codegen_check))
                },
                |device, _queue, _bufs, (parser_check, type_check, codegen_check)| {
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    self.code_generator()?
                        .finish_recorded_c_codegen(device, &codegen_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    pub async fn compile_source_to_c_with_gpu_frontend(
        &self,
        src: &str,
    ) -> Result<String, CompileError> {
        compile_source_to_c_with_gpu_frontend_using(src, &self.lexer).await
    }

    fn code_generator(&self) -> Result<&gpu_c::GpuCCodeGenerator, CompileError> {
        self.code_generator
            .get_or_init(|| {
                let generator = gpu_c::GpuCCodeGenerator::new_with_device(self.gpu)
                    .map_err(|err| err.to_string())?;
                self.gpu.persist_pipeline_cache();
                Ok(generator)
            })
            .as_ref()
            .map_err(|err| {
                CompileError::GpuCodegen(format!("initialize GPU C code generator: {err}"))
            })
    }
}

fn global_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    GPU_COMPILER
        .get_or_init(|| pollster::block_on(GpuCompiler::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU compiler: {err}")))
}

pub async fn compile_source_to_c_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<String, CompileError> {
    compiler.compile_source_to_c(src).await
}

pub async fn compile_source_to_c_with_gpu_frontend_using(
    src: &str,
    lexer: &GpuLexer,
) -> Result<String, CompileError> {
    let tokens = run_gpu_frontend(src, lexer).await?;

    let hir_tokens = tokens
        .iter()
        .map(|token| HirToken {
            kind: token.kind,
            start: token.start,
            len: token.len,
        })
        .collect::<Vec<_>>();
    let hir = hir::parse_tokens(src, &hir_tokens)?;
    Ok(c::emit_c(&hir))
}

async fn run_gpu_frontend(
    src: &str,
    lexer: &GpuLexer,
) -> Result<Vec<crate::lexer::gpu::types::Token>, CompileError> {
    let tokens = lexer
        .lex(src)
        .await
        .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?;
    Ok(tokens)
}
