use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
};

use crate::{
    codegen::{gpu_wasm, gpu_x86},
    gpu::device::{self, GpuDevice},
    lexer::gpu::driver::GpuLexer,
    parser::{gpu::driver::GpuParser, tables::PrecomputedParseTables},
    type_checker::gpu as gpu_type_checker,
};

#[derive(Debug)]
pub enum CompileError {
    Import(String),
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::Import(err) => write!(f, "import error: {err}"),
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
    x86_generator: OnceLock<Result<gpu_x86::GpuX86CodeGenerator, String>>,
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
            x86_generator: OnceLock::new(),
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = expand_source_imports(src)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = expand_source_imports_from_path(path)?;
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
        let src = expand_source_imports(src)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = expand_source_imports_from_path(path)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    async fn compile_expanded_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        trace_wasm_compile("compile.x86.start");
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
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let x86_check = self
                                    .type_checker
                                    .with_codegen_buffers(
                                        |visible_decl,
                                         visible_type,
                                         call_fn_index,
                                         call_return_type| {
                                            self.x86_generator()?
                                                .record_x86_from_gpu_token_buffer(
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
                                Ok::<_, CompileError>((recorded, x86_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (type_check, x86_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "x86.codegen.done");
                    }
                    Ok((parser_check, type_check, x86_check))
                },
                |device, queue, _bufs, (parser_check, type_check, x86_check)| {
                    self.parser
                        .finish_recorded_resident_syntax_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    self.x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    fn x86_generator(&self) -> Result<&gpu_x86::GpuX86CodeGenerator, CompileError> {
        self.x86_generator
            .get_or_init(|| {
                let generator = gpu_x86::GpuX86CodeGenerator::new_with_device(self.gpu)
                    .map_err(|err| err.to_string())?;
                self.gpu.persist_pipeline_cache();
                Ok(generator)
            })
            .as_ref()
            .map_err(|err| {
                CompileError::GpuCodegen(format!("initialize GPU x86 code generator: {err}"))
            })
    }
}

fn trace_wasm_compile(stage: &str) {
    if std::env::var("LANIUS_WASM_TRACE").ok().as_deref() == Some("1") {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

#[derive(Clone)]
enum ImportContext {
    SourceOnly,
    File(PathBuf),
}

struct ImportExpander {
    expanded: HashSet<PathBuf>,
    stack: Vec<PathBuf>,
}

impl ImportExpander {
    fn new() -> Self {
        Self {
            expanded: HashSet::new(),
            stack: Vec::new(),
        }
    }

    fn expand_source(&mut self, src: &str, context: ImportContext) -> Result<String, CompileError> {
        let mut expanded = String::new();

        for (line_index, line) in src.lines().enumerate() {
            match parse_import_directive(line) {
                Ok(Some(spec)) => {
                    let import_path = self.resolve_import(&spec, &context).map_err(|err| {
                        CompileError::Import(format!(
                            "{err} at {}:{}",
                            context.display(),
                            line_index + 1
                        ))
                    })?;
                    expanded.push_str(&self.expand_file(&import_path)?);
                    if !expanded.ends_with('\n') {
                        expanded.push('\n');
                    }
                }
                Ok(None) => {
                    expanded.push_str(line);
                    expanded.push('\n');
                }
                Err(err) => {
                    return Err(CompileError::Import(format!(
                        "{err} at {}:{}",
                        context.display(),
                        line_index + 1
                    )));
                }
            }
        }

        Ok(expanded)
    }

    fn expand_file(&mut self, path: &Path) -> Result<String, CompileError> {
        let canonical = fs::canonicalize(path)
            .map_err(|err| CompileError::Import(format!("resolve {}: {err}", path.display())))?;

        if let Some(cycle_start) = self.stack.iter().position(|entry| entry == &canonical) {
            let mut cycle = self.stack[cycle_start..]
                .iter()
                .map(|path| path.display().to_string())
                .collect::<Vec<_>>();
            cycle.push(canonical.display().to_string());
            return Err(CompileError::Import(format!(
                "import cycle detected: {}",
                cycle.join(" -> ")
            )));
        }

        if self.expanded.contains(&canonical) {
            return Ok(String::new());
        }

        let src = fs::read_to_string(&canonical)
            .map_err(|err| CompileError::Import(format!("read {}: {err}", canonical.display())))?;
        self.stack.push(canonical.clone());
        let result = self.expand_source(&src, ImportContext::File(canonical.clone()));
        self.stack.pop();
        let expanded = result?;
        self.expanded.insert(canonical);
        Ok(expanded)
    }

    fn resolve_import(&self, spec: &str, context: &ImportContext) -> Result<PathBuf, String> {
        let spec_path = Path::new(spec);
        if spec_path.is_absolute() {
            if spec_path.exists() {
                return Ok(spec_path.to_path_buf());
            }
            return Err(format!(
                "import {spec:?} not found; tried {}",
                spec_path.display()
            ));
        }

        let mut candidates = Vec::new();
        match context {
            ImportContext::File(path) => {
                if let Some(parent) = path.parent() {
                    candidates.push(parent.join(spec_path));
                }
                if spec_path.starts_with("stdlib") {
                    candidates.push(manifest_root().join(spec_path));
                }
            }
            ImportContext::SourceOnly => {
                if let Ok(cwd) = std::env::current_dir() {
                    candidates.push(cwd.join(spec_path));
                }
                candidates.push(manifest_root().join(spec_path));
            }
        }

        for candidate in &candidates {
            if candidate.exists() {
                return Ok(candidate.clone());
            }
        }

        let tried = candidates
            .iter()
            .map(|path| path.display().to_string())
            .collect::<Vec<_>>()
            .join(", ");
        Err(format!("import {spec:?} not found; tried {tried}"))
    }
}

impl ImportContext {
    fn display(&self) -> String {
        match self {
            ImportContext::SourceOnly => "<source>".to_string(),
            ImportContext::File(path) => path.display().to_string(),
        }
    }
}

pub fn expand_source_imports(src: &str) -> Result<String, CompileError> {
    ImportExpander::new().expand_source(src, ImportContext::SourceOnly)
}

pub fn expand_source_imports_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    ImportExpander::new().expand_file(path.as_ref())
}

fn parse_import_directive(line: &str) -> Result<Option<String>, String> {
    let trimmed = line.trim();
    let Some(rest) = trimmed.strip_prefix("import") else {
        return Ok(None);
    };
    if !rest.starts_with(char::is_whitespace) {
        return Ok(None);
    }
    let rest = rest.trim_start();
    let Some(rest) = rest.strip_prefix('"') else {
        return Err("expected import path string".to_string());
    };
    let Some(closing_quote) = rest.find('"') else {
        return Err("unterminated import path string".to_string());
    };
    let (spec, rest) = rest.split_at(closing_quote);
    let rest = rest[1..].trim();
    if rest != ";" {
        return Err("expected `;` after import path".to_string());
    }
    if spec.is_empty() {
        return Err("import path must not be empty".to_string());
    }
    Ok(Some(spec.to_string()))
}

fn manifest_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

fn global_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    GPU_COMPILER
        .get_or_init(|| pollster::block_on(GpuCompiler::new()).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU compiler: {err}")))
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports(src)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports_from_path(path)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports(src)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports_from_path(path)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports(src)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports_from_path(path)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports(src)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = expand_source_imports_from_path(path)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}
