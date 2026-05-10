use std::{
    collections::{HashMap, HashSet},
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
};

use crate::{
    codegen::{cpu_native, cpu_wasm, gpu_wasm, gpu_x86},
    gpu::device::{self, GpuDevice},
    hir::{
        HirAssignOp,
        HirBinaryOp,
        HirBlock,
        HirExpr,
        HirExprKind,
        HirFile,
        HirItem,
        HirLiteralKind,
        HirMatchArm,
        HirPattern,
        HirPatternKind,
        HirStmt,
        HirStmtKind,
        HirStructLiteralField,
        HirType,
        HirTypeKind,
        HirTypeParamBound,
        HirUnaryOp,
        parse_source,
    },
    lexer::{
        cpu::{lex_on_cpu, normalize_nested_generic_closers},
        gpu::driver::GpuLexer,
        tables::tokens::TokenKind,
    },
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
        if std::env::var("LANIUS_USE_GPU_WASM_CODEGEN").ok().as_deref() != Some("1") {
            let type_check_src = erase_match_expressions_for_type_check(src)?;
            self.type_check_expanded_source(&type_check_src).await?;
            return cpu_wasm::compile_source(src)
                .map_err(|err| CompileError::GpuCodegen(format!("CPU WASM fallback: {err}")));
        }

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
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    async fn compile_expanded_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        if std::env::var("LANIUS_USE_GPU_X86_CODEGEN").ok().as_deref() != Some("1") {
            let type_check_src = erase_match_expressions_for_type_check(src)?;
            self.type_check_expanded_source(&type_check_src).await?;
            return cpu_native::compile_source(src)
                .map_err(|err| CompileError::GpuCodegen(format!("CPU native fallback: {err}")));
        }

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

enum ImportSpec {
    Path(String),
    Module(String),
}

struct ImportExpander {
    expanded: HashSet<PathBuf>,
    stack: Vec<PathBuf>,
    modules: HashMap<String, ModuleDecls>,
}

#[derive(Clone, Debug, Default)]
struct ModuleDecls {
    all: HashSet<String>,
    public: HashSet<String>,
}

#[derive(Clone, Debug)]
struct ModuleInfo {
    path: String,
    decls: ModuleDecls,
}

impl ImportExpander {
    fn new() -> Self {
        Self {
            expanded: HashSet::new(),
            stack: Vec::new(),
            modules: HashMap::new(),
        }
    }

    fn expand_source(
        &mut self,
        src: &str,
        context: ImportContext,
        imported: bool,
    ) -> Result<String, CompileError> {
        let scanned_module = scan_module_info(src, &context)?;
        let active_module = if imported {
            scanned_module.as_ref()
        } else {
            None
        };
        let mut expanded = String::new();
        let mut module: Option<String> = None;

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
                    expanded.push_str(&self.expand_file(&import_path, true)?);
                    if !expanded.ends_with('\n') {
                        expanded.push('\n');
                    }
                }
                Ok(None) => {
                    match parse_module_directive(line) {
                        Ok(Some(module_path)) => {
                            if module.replace(module_path).is_some() {
                                return Err(CompileError::Import(format!(
                                    "duplicate module declaration at {}:{}",
                                    context.display(),
                                    line_index + 1
                                )));
                            }
                            continue;
                        }
                        Ok(None) => {}
                        Err(err) => {
                            return Err(CompileError::Import(format!(
                                "{err} at {}:{}",
                                context.display(),
                                line_index + 1
                            )));
                        }
                    }

                    let line = if imported {
                        if let Some(module) = active_module {
                            rewrite_module_line(line, module)?
                        } else {
                            line.to_string()
                        }
                    } else {
                        line.to_string()
                    };
                    let line = rewrite_namespaced_paths(&line, &self.modules, active_module)?;
                    expanded.push_str(&line);
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

        if imported {
            if let Some(module) = scanned_module {
                self.modules.insert(module.path, module.decls);
            }
        }

        Ok(expanded)
    }

    fn expand_file(&mut self, path: &Path, imported: bool) -> Result<String, CompileError> {
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
        let result = self.expand_source(&src, ImportContext::File(canonical.clone()), imported);
        self.stack.pop();
        let expanded = result?;
        self.expanded.insert(canonical);
        Ok(expanded)
    }

    fn resolve_import(
        &self,
        spec: &ImportSpec,
        context: &ImportContext,
    ) -> Result<PathBuf, String> {
        match spec {
            ImportSpec::Path(path) => self.resolve_path_import(path, context),
            ImportSpec::Module(module) => self.resolve_module_import(module),
        }
    }

    fn resolve_path_import(&self, spec: &str, context: &ImportContext) -> Result<PathBuf, String> {
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

    fn resolve_module_import(&self, module: &str) -> Result<PathBuf, String> {
        let segments = module.split("::").collect::<Vec<_>>();
        let mut candidates = Vec::new();

        let mut module_path = manifest_root().join("stdlib");
        for segment in &segments {
            module_path.push(segment);
        }
        module_path.set_extension("lani");
        candidates.push(module_path);

        if segments.first() == Some(&"core") {
            if let Some(last) = segments.last() {
                candidates.push(manifest_root().join("stdlib").join(format!("{last}.lani")));
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
        Err(format!("module import {module:?} not found; tried {tried}"))
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
    ImportExpander::new().expand_source(src, ImportContext::SourceOnly, false)
}

pub fn expand_source_imports_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    ImportExpander::new().expand_file(path.as_ref(), false)
}

fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    let src = expand_source_imports(src)?;
    let src = normalize_nested_generic_closers(&src).map_err(|err| {
        CompileError::GpuFrontend(format!("normalize nested generic closers: {err}"))
    })?;
    let src = expand_type_aliases_in_source(&src)?;
    let src = strip_type_alias_declarations_from_source(&src)?;
    precheck_hir_semantics_in_source(&src)?;
    Ok(src)
}

fn prepare_source_for_gpu_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    let src = expand_source_imports_from_path(path)?;
    let src = normalize_nested_generic_closers(&src).map_err(|err| {
        CompileError::GpuFrontend(format!("normalize nested generic closers: {err}"))
    })?;
    let src = expand_type_aliases_in_source(&src)?;
    let src = strip_type_alias_declarations_from_source(&src)?;
    precheck_hir_semantics_in_source(&src)?;
    Ok(src)
}

fn prepare_source_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    let src = prepare_source_for_gpu(src)?;
    lower_sum_types_for_gpu_codegen(&src)
}

fn prepare_source_for_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    let src = prepare_source_for_gpu_from_path(path)?;
    lower_sum_types_for_gpu_codegen(&src)
}

fn prepare_source_for_gpu_type_check(src: &str) -> Result<String, CompileError> {
    let src = prepare_source_for_gpu(src)?;
    erase_match_expressions_for_type_check(&src)
}

fn prepare_source_for_gpu_type_check_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    let src = prepare_source_for_gpu_from_path(path)?;
    erase_match_expressions_for_type_check(&src)
}

#[derive(Clone, Debug)]
struct TypeAliasDef {
    type_params: Vec<String>,
    const_params: Vec<String>,
    target: HirType,
}

pub fn expand_type_aliases_in_source(src: &str) -> Result<String, CompileError> {
    let file = parse_source(src).map_err(|err| {
        CompileError::GpuFrontend(format!("parse source for type alias expansion: {err}"))
    })?;
    let aliases = collect_type_aliases(&file)?;
    if aliases.is_empty() {
        return Ok(src.to_string());
    }

    let mut types = Vec::new();
    collect_file_types(&file, &mut types);

    let mut replacements = Vec::new();
    for ty in types {
        let replacement = render_type_with_aliases(ty, &aliases)?;
        let original = src
            .get(ty.span.start..ty.span.end())
            .unwrap_or_default()
            .trim();
        if replacement != original {
            replacements.push((ty.span.start, ty.span.end(), replacement));
        }
    }

    Ok(apply_replacements(src, replacements))
}

fn strip_type_alias_declarations_from_source(src: &str) -> Result<String, CompileError> {
    let file = parse_source(src).map_err(|err| {
        CompileError::GpuFrontend(format!("parse source for type alias stripping: {err}"))
    })?;
    let replacements = file
        .items
        .iter()
        .filter_map(|item| {
            let HirItem::TypeAlias(alias) = item else {
                return None;
            };
            Some((alias.span.start, alias.span.end(), String::new()))
        })
        .collect::<Vec<_>>();
    Ok(apply_replacements(src, replacements))
}

fn collect_type_aliases(file: &HirFile) -> Result<HashMap<String, TypeAliasDef>, CompileError> {
    let mut aliases = HashMap::new();
    for item in &file.items {
        let HirItem::TypeAlias(alias) = item else {
            continue;
        };
        if aliases
            .insert(
                alias.name.clone(),
                TypeAliasDef {
                    type_params: alias.type_params.clone(),
                    const_params: alias
                        .const_params
                        .iter()
                        .map(|param| param.name.clone())
                        .collect(),
                    target: alias.target.clone(),
                },
            )
            .is_some()
        {
            return Err(CompileError::GpuFrontend(format!(
                "duplicate type alias `{}`",
                alias.name
            )));
        }
    }
    Ok(aliases)
}

fn collect_file_types<'a>(file: &'a HirFile, out: &mut Vec<&'a HirType>) {
    for item in &file.items {
        collect_item_types(item, out);
    }
}

fn collect_item_types<'a>(item: &'a HirItem, out: &mut Vec<&'a HirType>) {
    match item {
        HirItem::Fn(function) => {
            for bound in &function.type_param_bounds {
                out.push(&bound.bound);
            }
            for param in &function.params {
                out.push(&param.ty);
            }
            out.push(&function.ret);
            collect_block_types(&function.body, out);
        }
        HirItem::ExternFn(function) => {
            for bound in &function.type_param_bounds {
                out.push(&bound.bound);
            }
            for param in &function.params {
                out.push(&param.ty);
            }
            out.push(&function.ret);
        }
        HirItem::Const(constant) => out.push(&constant.ty),
        HirItem::TypeAlias(alias) => {
            for bound in &alias.type_param_bounds {
                out.push(&bound.bound);
            }
            out.push(&alias.target);
        }
        HirItem::Enum(enumeration) => {
            for bound in &enumeration.type_param_bounds {
                out.push(&bound.bound);
            }
            for variant in &enumeration.variants {
                for field in &variant.fields {
                    out.push(field);
                }
            }
        }
        HirItem::Struct(structure) => {
            for bound in &structure.type_param_bounds {
                out.push(&bound.bound);
            }
            for field in &structure.fields {
                out.push(&field.ty);
            }
        }
        HirItem::Impl(implementation) => {
            for bound in &implementation.type_param_bounds {
                out.push(&bound.bound);
            }
            if let Some(trait_ref) = &implementation.trait_ref {
                out.push(trait_ref);
            }
            out.push(&implementation.target);
            for method in &implementation.methods {
                for bound in &method.type_param_bounds {
                    out.push(&bound.bound);
                }
                for param in &method.params {
                    out.push(&param.ty);
                }
                out.push(&method.ret);
                collect_block_types(&method.body, out);
            }
        }
        HirItem::Trait(trait_item) => {
            for bound in &trait_item.type_param_bounds {
                out.push(&bound.bound);
            }
            for method in &trait_item.methods {
                for bound in &method.type_param_bounds {
                    out.push(&bound.bound);
                }
                for param in &method.params {
                    out.push(&param.ty);
                }
                out.push(&method.ret);
            }
        }
        HirItem::Stmt(stmt) => collect_stmt_types(stmt, out),
        HirItem::Import(_) | HirItem::Module(_) => {}
    }
}

fn collect_block_types<'a>(block: &'a HirBlock, out: &mut Vec<&'a HirType>) {
    for stmt in &block.stmts {
        collect_stmt_types(stmt, out);
    }
}

fn collect_stmt_types<'a>(stmt: &'a HirStmt, out: &mut Vec<&'a HirType>) {
    match &stmt.kind {
        HirStmtKind::Let { ty, .. } => {
            if let Some(ty) = ty {
                out.push(ty);
            }
        }
        HirStmtKind::If {
            then_block,
            else_block,
            ..
        } => {
            collect_block_types(then_block, out);
            if let Some(block) = else_block {
                collect_block_types(block, out);
            }
        }
        HirStmtKind::While { body, .. } | HirStmtKind::For { body, .. } => {
            collect_block_types(body, out);
        }
        HirStmtKind::Block(block) => collect_block_types(block, out),
        HirStmtKind::Return(_)
        | HirStmtKind::Break
        | HirStmtKind::Continue
        | HirStmtKind::Expr(_) => {}
    }
}

fn render_type_with_aliases(
    ty: &HirType,
    aliases: &HashMap<String, TypeAliasDef>,
) -> Result<String, CompileError> {
    render_type_with_context(ty, aliases, &HashMap::new(), &mut Vec::new())
}

fn render_type_with_context(
    ty: &HirType,
    aliases: &HashMap<String, TypeAliasDef>,
    substitutions: &HashMap<String, HirType>,
    stack: &mut Vec<String>,
) -> Result<String, CompileError> {
    match &ty.kind {
        HirTypeKind::Void => Ok(String::new()),
        HirTypeKind::Name(name) => {
            if let Some(substituted) = substitutions.get(name) {
                return render_type_with_context(substituted, aliases, substitutions, stack);
            }
            expand_alias_name(name, Vec::new(), aliases, stack)
        }
        HirTypeKind::Generic { name, args } => {
            if let Some(alias) = aliases.get(name) {
                if !alias.const_params.is_empty() {
                    return Err(CompileError::GpuFrontend(format!(
                        "const-generic type alias `{name}` expansion is not supported yet"
                    )));
                }
                if alias.type_params.len() != args.len() {
                    return Err(CompileError::GpuFrontend(format!(
                        "type alias `{name}` expected {} type argument(s), got {}",
                        alias.type_params.len(),
                        args.len()
                    )));
                }
                let mut local_substitutions = HashMap::new();
                for (param, arg) in alias.type_params.iter().zip(args.iter()) {
                    local_substitutions.insert(param.clone(), arg.clone());
                }
                return expand_alias_target(name, alias, aliases, &local_substitutions, stack);
            }

            let args = args
                .iter()
                .map(|arg| render_type_with_context(arg, aliases, substitutions, stack))
                .collect::<Result<Vec<_>, _>>()?;
            Ok(format!("{name}<{}>", args.join(", ")))
        }
        HirTypeKind::Ref { inner } => Ok(format!(
            "&{}",
            render_type_with_context(inner, aliases, substitutions, stack)?
        )),
        HirTypeKind::Slice { elem } => Ok(format!(
            "[{}]",
            render_type_with_context(elem, aliases, substitutions, stack)?
        )),
        HirTypeKind::Array { elem, len } => Ok(format!(
            "[{}; {len}]",
            render_type_with_context(elem, aliases, substitutions, stack)?
        )),
    }
}

fn expand_alias_name(
    name: &str,
    args: Vec<HirType>,
    aliases: &HashMap<String, TypeAliasDef>,
    stack: &mut Vec<String>,
) -> Result<String, CompileError> {
    let Some(alias) = aliases.get(name) else {
        return Ok(name.to_string());
    };
    if !alias.const_params.is_empty() {
        return Err(CompileError::GpuFrontend(format!(
            "const-generic type alias `{name}` expansion is not supported yet"
        )));
    }
    if alias.type_params.len() != args.len() {
        return Err(CompileError::GpuFrontend(format!(
            "type alias `{name}` expected {} type argument(s), got {}",
            alias.type_params.len(),
            args.len()
        )));
    }
    let substitutions = alias
        .type_params
        .iter()
        .cloned()
        .zip(args)
        .collect::<HashMap<_, _>>();
    expand_alias_target(name, alias, aliases, &substitutions, stack)
}

fn expand_alias_target(
    name: &str,
    alias: &TypeAliasDef,
    aliases: &HashMap<String, TypeAliasDef>,
    substitutions: &HashMap<String, HirType>,
    stack: &mut Vec<String>,
) -> Result<String, CompileError> {
    if stack.iter().any(|entry| entry == name) {
        let mut cycle = stack.clone();
        cycle.push(name.to_string());
        return Err(CompileError::GpuFrontend(format!(
            "type alias cycle detected: {}",
            cycle.join(" -> ")
        )));
    }
    stack.push(name.to_string());
    let rendered = render_type_with_context(&alias.target, aliases, substitutions, stack);
    stack.pop();
    rendered
}

#[derive(Clone, Debug, PartialEq, Eq)]
enum SimpleType {
    Unknown,
    Void,
    Bool,
    Int,
    UInt,
    Float,
    Char,
    String,
    Param(String),
    Named(String),
    Generic { name: String, args: Vec<SimpleType> },
    Ref(Box<SimpleType>),
    Slice(Box<SimpleType>),
    Array { elem: Box<SimpleType>, len: String },
}

impl SimpleType {
    fn is_array(&self) -> bool {
        matches!(self, Self::Array { .. })
    }
}

#[derive(Clone, Debug)]
struct EnumInfo {
    type_params: Vec<String>,
    variants: Vec<String>,
}

#[derive(Clone, Debug)]
struct VariantInfo {
    enum_name: String,
    fields: Vec<SimpleType>,
}

#[derive(Clone, Debug)]
struct StructInfo {
    type_params: Vec<String>,
    fields: Vec<StructFieldInfo>,
}

#[derive(Clone, Debug)]
struct StructFieldInfo {
    name: String,
    ty: SimpleType,
}

#[derive(Clone, Debug)]
struct FunctionInfo {
    type_params: Vec<String>,
    const_params: Vec<String>,
    params: Vec<SimpleType>,
    ret: SimpleType,
}

#[derive(Clone, Debug)]
struct MethodInfo {
    name: String,
    target: SimpleType,
    info: FunctionInfo,
}

#[derive(Clone, Debug)]
struct TraitInfo {
    type_params: Vec<String>,
    const_params: Vec<String>,
    methods: Vec<TraitMethodInfo>,
}

#[derive(Clone, Debug)]
struct TraitMethodInfo {
    name: String,
    type_params: Vec<String>,
    const_params: Vec<String>,
    params: Vec<SimpleType>,
    ret: SimpleType,
}

#[derive(Clone, Debug, Default)]
struct HirPrecheckContext {
    functions: HashMap<String, FunctionInfo>,
    consts: HashMap<String, SimpleType>,
    enums: HashMap<String, EnumInfo>,
    variants: HashMap<String, VariantInfo>,
    structs: HashMap<String, StructInfo>,
    methods: Vec<MethodInfo>,
    traits: HashMap<String, TraitInfo>,
}

#[derive(Clone, Debug, Default)]
struct TypeEnv {
    values: HashMap<String, SimpleType>,
    bounds: HashMap<String, Vec<SimpleType>>,
    type_params: HashSet<String>,
}

impl TypeEnv {
    fn new() -> Self {
        Self::default()
    }

    fn with_bounds(bounds: HashMap<String, Vec<SimpleType>>, type_params: HashSet<String>) -> Self {
        Self {
            values: HashMap::new(),
            bounds,
            type_params,
        }
    }

    fn get(&self, name: &str) -> Option<&SimpleType> {
        self.values.get(name)
    }

    fn insert(&mut self, name: String, ty: SimpleType) -> Option<SimpleType> {
        self.values.insert(name, ty)
    }

    fn extend_bounds(&mut self, bounds: HashMap<String, Vec<SimpleType>>) {
        for (param, new_bounds) in bounds {
            self.bounds.entry(param).or_default().extend(new_bounds);
        }
    }

    fn bounds_for(&self, param: &str) -> impl Iterator<Item = &SimpleType> {
        self.bounds
            .get(param)
            .into_iter()
            .flat_map(|bounds| bounds.iter())
    }

    fn type_params(&self) -> &HashSet<String> {
        &self.type_params
    }

    fn iter(&self) -> impl Iterator<Item = (&String, &SimpleType)> {
        self.values.iter()
    }
}

fn precheck_hir_semantics_in_source(src: &str) -> Result<(), CompileError> {
    let file = parse_source(src).map_err(|err| {
        CompileError::GpuFrontend(format!("parse source for HIR semantic precheck: {err}"))
    })?;
    let context = HirPrecheckContext::from_file(&file);
    context.precheck_file(&file)
}

fn erase_match_expressions_for_type_check(src: &str) -> Result<String, CompileError> {
    let file = parse_source(src).map_err(|err| {
        CompileError::GpuFrontend(format!("parse source for match type-check erasure: {err}"))
    })?;
    let context = HirPrecheckContext::from_file(&file);
    let mut replacements = Vec::new();
    context.collect_array_return_erasure_replacements(&file, &mut replacements)?;
    context.collect_generic_function_call_erasure_replacements(&file, &mut replacements)?;
    context.collect_method_call_erasure_replacements(&file, &mut replacements)?;
    context.collect_generic_struct_value_erasure_replacements(&file, &mut replacements)?;
    context.collect_for_loop_erasure_replacements(&file, &mut replacements)?;
    context.collect_generic_enum_type_erasure_replacements(&file, &mut replacements);
    context.collect_generic_struct_type_erasure_replacements(&file, &mut replacements);
    context.collect_match_erasure_replacements(&file, &mut replacements)?;
    context.collect_impl_erasure_replacements(&file, &mut replacements);
    context.collect_trait_erasure_replacements(&file, &mut replacements);
    Ok(apply_replacements(src, replacements))
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum CodegenVariantEncoding {
    OddPayload,
    EvenPayload,
    UnitTag(i64),
}

struct LoweredCodegenMatchArm {
    condition: Option<String>,
    value: String,
}

fn lower_sum_types_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    let file = parse_source(src).map_err(|err| {
        CompileError::GpuFrontend(format!("parse source for sum type codegen lowering: {err}"))
    })?;
    let context = HirPrecheckContext::from_file(&file);
    let mut replacements = Vec::new();
    context.collect_enum_type_codegen_replacements(&file, &mut replacements);
    context.collect_type_param_codegen_replacements(&file, &mut replacements);
    context.collect_sum_type_value_codegen_replacements(src, &file, &mut replacements)?;
    Ok(apply_replacements(src, replacements))
}

impl HirPrecheckContext {
    fn from_file(file: &HirFile) -> Self {
        let mut context = Self::default();
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    context.functions.insert(
                        function.name.clone(),
                        FunctionInfo {
                            type_params: function.type_params.clone(),
                            const_params: function
                                .const_params
                                .iter()
                                .map(|param| param.name.clone())
                                .collect(),
                            params: function
                                .params
                                .iter()
                                .map(|param| simple_type_from_hir_type(&param.ty, &params))
                                .collect(),
                            ret: simple_type_from_hir_type(&function.ret, &params),
                        },
                    );
                }
                HirItem::ExternFn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    context.functions.insert(
                        function.name.clone(),
                        FunctionInfo {
                            type_params: function.type_params.clone(),
                            const_params: function
                                .const_params
                                .iter()
                                .map(|param| param.name.clone())
                                .collect(),
                            params: function
                                .params
                                .iter()
                                .map(|param| simple_type_from_hir_type(&param.ty, &params))
                                .collect(),
                            ret: simple_type_from_hir_type(&function.ret, &params),
                        },
                    );
                }
                HirItem::Const(constant) => {
                    context.consts.insert(
                        constant.name.clone(),
                        simple_type_from_hir_type(&constant.ty, &HashSet::new()),
                    );
                }
                HirItem::Enum(enumeration) => {
                    let params = enumeration
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    context.enums.insert(
                        enumeration.name.clone(),
                        EnumInfo {
                            type_params: enumeration.type_params.clone(),
                            variants: enumeration
                                .variants
                                .iter()
                                .map(|variant| variant.name.clone())
                                .collect(),
                        },
                    );
                    for variant in &enumeration.variants {
                        context.variants.insert(
                            variant.name.clone(),
                            VariantInfo {
                                enum_name: enumeration.name.clone(),
                                fields: variant
                                    .fields
                                    .iter()
                                    .map(|field| simple_type_from_hir_type(field, &params))
                                    .collect(),
                            },
                        );
                    }
                }
                HirItem::Struct(structure) => {
                    let params = structure
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    context.structs.insert(
                        structure.name.clone(),
                        StructInfo {
                            type_params: structure.type_params.clone(),
                            fields: structure
                                .fields
                                .iter()
                                .map(|field| StructFieldInfo {
                                    name: field.name.clone(),
                                    ty: simple_type_from_hir_type(&field.ty, &params),
                                })
                                .collect(),
                        },
                    );
                }
                HirItem::Impl(implementation) => {
                    let impl_params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    let impl_const_params = implementation
                        .const_params
                        .iter()
                        .map(|param| param.name.clone())
                        .collect::<Vec<_>>();
                    let target = simple_type_from_hir_type(&implementation.target, &impl_params);

                    for method in &implementation.methods {
                        let mut params = impl_params.clone();
                        params.extend(method.type_params.iter().cloned());
                        let mut const_params = impl_const_params.clone();
                        const_params
                            .extend(method.const_params.iter().map(|param| param.name.clone()));
                        context.methods.push(MethodInfo {
                            name: method.name.clone(),
                            target: target.clone(),
                            info: FunctionInfo {
                                type_params: implementation
                                    .type_params
                                    .iter()
                                    .chain(method.type_params.iter())
                                    .cloned()
                                    .collect(),
                                const_params,
                                params: method
                                    .params
                                    .iter()
                                    .map(|param| simple_type_from_hir_type(&param.ty, &params))
                                    .collect(),
                                ret: simple_type_from_hir_type(&method.ret, &params),
                            },
                        });
                    }
                }
                HirItem::Trait(trait_item) => {
                    let trait_params = trait_item
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    context.traits.insert(
                        trait_item.name.clone(),
                        TraitInfo {
                            type_params: trait_item.type_params.clone(),
                            const_params: trait_item
                                .const_params
                                .iter()
                                .map(|param| param.name.clone())
                                .collect(),
                            methods: trait_item
                                .methods
                                .iter()
                                .map(|method| {
                                    let mut params = trait_params.clone();
                                    params.extend(method.type_params.iter().cloned());
                                    TraitMethodInfo {
                                        name: method.name.clone(),
                                        type_params: method.type_params.clone(),
                                        const_params: method
                                            .const_params
                                            .iter()
                                            .map(|param| param.name.clone())
                                            .collect(),
                                        params: method
                                            .params
                                            .iter()
                                            .map(|param| {
                                                simple_type_from_hir_type(&param.ty, &params)
                                            })
                                            .collect(),
                                        ret: simple_type_from_hir_type(&method.ret, &params),
                                    }
                                })
                                .collect(),
                        },
                    );
                }
                _ => {}
            }
        }
        context
    }

    fn precheck_file(&self, file: &HirFile) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    self.precheck_block(&function.body, &mut env, &ret)?;
                }
                HirItem::ExternFn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    self.type_bounds_from_hir(&function.type_param_bounds, &params)?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    self.precheck_trait_impl_conformance(implementation, &params)?;
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        let ret = simple_type_from_hir_type(&method.ret, &method_params);
                        self.precheck_block(&method.body, &mut env, &ret)?;
                    }
                }
                HirItem::TypeAlias(alias) => {
                    let params = alias.type_params.iter().cloned().collect::<HashSet<_>>();
                    self.type_bounds_from_hir(&alias.type_param_bounds, &params)?;
                }
                HirItem::Enum(enumeration) => {
                    let params = enumeration
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    self.type_bounds_from_hir(&enumeration.type_param_bounds, &params)?;
                }
                HirItem::Struct(structure) => {
                    let params = structure
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    self.type_bounds_from_hir(&structure.type_param_bounds, &params)?;
                }
                HirItem::Trait(trait_item) => {
                    let params = trait_item
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    self.type_bounds_from_hir(&trait_item.type_param_bounds, &params)?;
                    for method in &trait_item.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?;
                    }
                }
                HirItem::Const(constant) => {
                    let expected = simple_type_from_hir_type(&constant.ty, &HashSet::new());
                    let actual = self.infer_expr(&constant.value, &mut TypeEnv::new())?;
                    ensure_types_compatible(&expected, &actual, constant.value.span, "const")?;
                }
                HirItem::Stmt(stmt) => {
                    self.precheck_stmt(stmt, &mut TypeEnv::new(), &SimpleType::Void)?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn precheck_trait_impl_conformance(
        &self,
        implementation: &crate::hir::HirImpl,
        impl_params: &HashSet<String>,
    ) -> Result<(), CompileError> {
        let Some(trait_ref) = &implementation.trait_ref else {
            return Ok(());
        };

        let trait_ty = simple_type_from_hir_type(trait_ref, impl_params);
        let (trait_name, trait_args) = trait_type_parts(&trait_ty).ok_or_else(|| {
            CompileError::GpuTypeCheck(format!(
                "trait impl target must name a trait, got {}",
                simple_type_label(&trait_ty)
            ))
        })?;
        let info = self.traits.get(trait_name).ok_or_else(|| {
            CompileError::GpuTypeCheck(format!("trait `{trait_name}` not found for impl"))
        })?;
        if !info.const_params.is_empty() {
            return Err(CompileError::GpuTypeCheck(format!(
                "trait `{trait_name}` const parameters are not supported in impl conformance yet"
            )));
        }
        if trait_args.len() != info.type_params.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "trait `{trait_name}` expected {} type argument(s), got {}",
                info.type_params.len(),
                trait_args.len()
            )));
        }

        let mut trait_substitutions = HashMap::new();
        for (param, arg) in info.type_params.iter().zip(trait_args.iter()) {
            trait_substitutions.insert(param.clone(), arg.clone());
        }

        for required in &info.methods {
            let Some(method) = implementation
                .methods
                .iter()
                .find(|method| method.name == required.name)
            else {
                return Err(CompileError::GpuTypeCheck(format!(
                    "impl of trait `{trait_name}` for {} is missing method `{}`",
                    simple_type_label(&simple_type_from_hir_type(
                        &implementation.target,
                        impl_params
                    )),
                    required.name
                )));
            };
            self.precheck_trait_method_conformance(
                trait_name,
                required,
                method,
                impl_params,
                &trait_substitutions,
            )?;
        }

        Ok(())
    }

    fn precheck_trait_method_conformance(
        &self,
        trait_name: &str,
        required: &TraitMethodInfo,
        method: &crate::hir::HirFn,
        impl_params: &HashSet<String>,
        trait_substitutions: &HashMap<String, SimpleType>,
    ) -> Result<(), CompileError> {
        if required.type_params.len() != method.type_params.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "method `{}` in impl of trait `{trait_name}` expected {} type parameter(s), got {}",
                required.name,
                required.type_params.len(),
                method.type_params.len()
            )));
        }
        if required.const_params.len() != method.const_params.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "method `{}` in impl of trait `{trait_name}` expected {} const parameter(s), got {}",
                required.name,
                required.const_params.len(),
                method.const_params.len()
            )));
        }
        if required.params.len() != method.params.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "method `{}` in impl of trait `{trait_name}` expected {} parameter(s), got {}",
                required.name,
                required.params.len(),
                method.params.len()
            )));
        }

        let mut method_params = impl_params.clone();
        method_params.extend(method.type_params.iter().cloned());
        let const_params = method
            .const_params
            .iter()
            .map(|param| param.name.clone())
            .collect::<Vec<_>>();

        for (index, (expected, actual)) in
            required.params.iter().zip(method.params.iter()).enumerate()
        {
            let expected = substitute_simple_type(expected, trait_substitutions);
            let actual = simple_type_from_hir_type(&actual.ty, &method_params);
            if !simple_types_compatible_for_function(&expected, &actual, &const_params) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "method `{}` parameter {} in impl of trait `{trait_name}` expected {}, got {}",
                    required.name,
                    index + 1,
                    simple_type_label(&expected),
                    simple_type_label(&actual)
                )));
            }
        }

        let expected_ret = substitute_simple_type(&required.ret, trait_substitutions);
        let actual_ret = simple_type_from_hir_type(&method.ret, &method_params);
        if !simple_types_compatible_for_function(&expected_ret, &actual_ret, &const_params) {
            return Err(CompileError::GpuTypeCheck(format!(
                "method `{}` return type in impl of trait `{trait_name}` expected {}, got {}",
                required.name,
                simple_type_label(&expected_ret),
                simple_type_label(&actual_ret)
            )));
        }

        Ok(())
    }

    fn type_bounds_from_hir(
        &self,
        bounds: &[HirTypeParamBound],
        params: &HashSet<String>,
    ) -> Result<HashMap<String, Vec<SimpleType>>, CompileError> {
        let mut out: HashMap<String, Vec<SimpleType>> = HashMap::new();
        for bound in bounds {
            if !params.contains(&bound.param) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "trait bound target `{}` is not a type parameter at byte {}",
                    bound.param, bound.span.start
                )));
            }

            let bound_ty = simple_type_from_hir_type(&bound.bound, params);
            let (trait_name, trait_args) = trait_type_parts(&bound_ty).ok_or_else(|| {
                CompileError::GpuTypeCheck(format!(
                    "trait bound for `{}` must name a trait, got {}",
                    bound.param,
                    simple_type_label(&bound_ty)
                ))
            })?;
            let info = self.traits.get(trait_name).ok_or_else(|| {
                CompileError::GpuTypeCheck(format!(
                    "trait `{trait_name}` not found for bound on `{}`",
                    bound.param
                ))
            })?;
            if !info.const_params.is_empty() {
                return Err(CompileError::GpuTypeCheck(format!(
                    "trait `{trait_name}` const parameters are not supported in bounds yet"
                )));
            }
            if trait_args.len() != info.type_params.len() {
                return Err(CompileError::GpuTypeCheck(format!(
                    "trait `{trait_name}` bound expected {} type argument(s), got {}",
                    info.type_params.len(),
                    trait_args.len()
                )));
            }

            out.entry(bound.param.clone()).or_default().push(bound_ty);
        }
        Ok(out)
    }

    fn type_env_for_bounds(
        &self,
        bounds: &[HirTypeParamBound],
        params: &HashSet<String>,
    ) -> Result<TypeEnv, CompileError> {
        Ok(TypeEnv::with_bounds(
            self.type_bounds_from_hir(bounds, params)?,
            params.clone(),
        ))
    }

    fn collect_enum_type_codegen_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        let mut types = Vec::new();
        collect_file_types(file, &mut types);
        for ty in types {
            if self.is_enum_type_use(ty) {
                replacements.push((ty.span.start, ty.span.end(), "i32".to_string()));
            }
        }
    }

    fn is_enum_type_use(&self, ty: &HirType) -> bool {
        match &ty.kind {
            HirTypeKind::Name(name) | HirTypeKind::Generic { name, .. } => {
                self.enums.contains_key(name)
            }
            _ => false,
        }
    }

    fn collect_type_param_codegen_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    self.collect_fn_type_param_codegen_replacements(
                        function,
                        &params,
                        replacements,
                    );
                }
                HirItem::ExternFn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    for param in &function.params {
                        collect_type_param_replacements_in_type(&param.ty, &params, replacements);
                    }
                    collect_type_param_replacements_in_type(&function.ret, &params, replacements);
                }
                HirItem::Impl(implementation) => {
                    let impl_params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut params = impl_params.clone();
                        params.extend(method.type_params.iter().cloned());
                        self.collect_fn_type_param_codegen_replacements(
                            method,
                            &params,
                            replacements,
                        );
                    }
                }
                _ => {}
            }
        }
    }

    fn collect_fn_type_param_codegen_replacements(
        &self,
        function: &crate::hir::HirFn,
        params: &HashSet<String>,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        for param in &function.params {
            collect_type_param_replacements_in_type(&param.ty, params, replacements);
        }
        collect_type_param_replacements_in_type(&function.ret, params, replacements);
        collect_block_type_param_codegen_replacements(&function.body, params, replacements);
    }

    fn collect_sum_type_value_codegen_replacements(
        &self,
        src: &str,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    self.collect_block_sum_type_codegen(
                        src,
                        &function.body,
                        &mut env,
                        replacements,
                    )?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        self.collect_block_sum_type_codegen(
                            src,
                            &method.body,
                            &mut env,
                            replacements,
                        )?;
                    }
                }
                HirItem::Const(constant) => {
                    self.collect_expr_sum_type_codegen(
                        src,
                        &constant.value,
                        &mut TypeEnv::new(),
                        replacements,
                    )?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_sum_type_codegen(
                        src,
                        stmt,
                        &mut TypeEnv::new(),
                        replacements,
                    )?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_sum_type_codegen(
        &self,
        src: &str,
        block: &HirBlock,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_sum_type_codegen(src, stmt, env, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_sum_type_codegen(
        &self,
        src: &str,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                if let Some(value) = value {
                    self.collect_expr_sum_type_codegen(src, value, env, replacements)?;
                }
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    if let HirExprKind::Match { expr, arms } = &value.kind
                        && let Some(lowered) =
                            self.lower_return_match_for_codegen(src, expr, arms, env)?
                    {
                        replacements.push((stmt.span.start, stmt.span.end(), lowered));
                        return Ok(());
                    }
                    self.collect_expr_sum_type_codegen(src, value, env, replacements)?;
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_sum_type_codegen(src, value, env, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_sum_type_codegen(src, cond, env, replacements)?;
                self.collect_block_sum_type_codegen(
                    src,
                    then_block,
                    &mut env.clone(),
                    replacements,
                )?;
                if let Some(block) = else_block {
                    self.collect_block_sum_type_codegen(
                        src,
                        block,
                        &mut env.clone(),
                        replacements,
                    )?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_sum_type_codegen(src, cond, env, replacements)?;
                self.collect_block_sum_type_codegen(src, body, &mut env.clone(), replacements)?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_sum_type_codegen(src, iter, env, replacements)?;
                self.collect_block_sum_type_codegen(src, body, &mut env.clone(), replacements)?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_sum_type_codegen(src, block, &mut env.clone(), replacements)?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_sum_type_codegen(
        &self,
        src: &str,
        expr: &HirExpr,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Name(name) = &callee.kind
                    && let Some(encoded) = self.lower_variant_call_for_codegen(src, name, args)
                {
                    replacements.push((expr.span.start, expr.span.end(), encoded));
                    return Ok(());
                }
                self.collect_expr_sum_type_codegen(src, callee, env, replacements)?;
                for arg in args {
                    self.collect_expr_sum_type_codegen(src, arg, env, replacements)?;
                }
            }
            HirExprKind::Name(name) => {
                if let Some(encoded) = self.lower_unit_variant_for_codegen(name) {
                    replacements.push((expr.span.start, expr.span.end(), encoded));
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_sum_type_codegen(src, elem, env, replacements)?;
                }
            }
            HirExprKind::StructLiteral { fields, .. } => {
                for field in fields {
                    self.collect_expr_sum_type_codegen(src, &field.value, env, replacements)?;
                }
            }
            HirExprKind::Match { expr: inner, arms } => {
                self.collect_expr_sum_type_codegen(src, inner, env, replacements)?;
                let scrutinee = self.infer_expr(inner, env)?;
                for arm in arms {
                    let mut arm_env = env.clone();
                    self.bind_pattern(&arm.pattern, &scrutinee, &mut arm_env)?;
                    self.collect_expr_sum_type_codegen(
                        src,
                        &arm.value,
                        &mut arm_env,
                        replacements,
                    )?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_sum_type_codegen(src, base, env, replacements)?;
                self.collect_expr_sum_type_codegen(src, index, env, replacements)?;
            }
            HirExprKind::Member { base, .. } | HirExprKind::Unary { expr: base, .. } => {
                self.collect_expr_sum_type_codegen(src, base, env, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_sum_type_codegen(src, lhs, env, replacements)?;
                self.collect_expr_sum_type_codegen(src, rhs, env, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                self.collect_expr_sum_type_codegen(src, target, env, replacements)?;
                self.collect_expr_sum_type_codegen(src, value, env, replacements)?;
            }
            HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn lower_return_match_for_codegen(
        &self,
        src: &str,
        expr: &HirExpr,
        arms: &[HirMatchArm],
        env: &TypeEnv,
    ) -> Result<Option<String>, CompileError> {
        if arms.len() != 2 {
            return Ok(None);
        }
        let scrutinee_src = source_fragment(src, expr.span).trim().to_string();
        if scrutinee_src.is_empty() {
            return Ok(None);
        }
        let scrutinee_ty = self.infer_expr(expr, &mut env.clone())?;
        let first =
            self.lower_match_arm_for_codegen(src, &scrutinee_src, &scrutinee_ty, &arms[0])?;
        let second =
            self.lower_match_arm_for_codegen(src, &scrutinee_src, &scrutinee_ty, &arms[1])?;
        let Some(condition) = first.condition else {
            return Ok(Some(format!("return {};", first.value)));
        };
        Ok(Some(format!(
            "if ({condition}) {{ return {}; }} else {{ return {}; }}",
            first.value, second.value
        )))
    }

    fn lower_match_arm_for_codegen(
        &self,
        src: &str,
        scrutinee_src: &str,
        scrutinee_ty: &SimpleType,
        arm: &HirMatchArm,
    ) -> Result<LoweredCodegenMatchArm, CompileError> {
        let mut bindings = HashMap::new();
        let condition = self.codegen_condition_for_pattern(
            &arm.pattern,
            scrutinee_src,
            scrutinee_ty,
            &mut bindings,
        );
        let value_src = source_fragment(src, arm.value.span).trim();
        Ok(LoweredCodegenMatchArm {
            condition,
            value: replace_bound_names_in_source(value_src, &bindings),
        })
    }

    fn codegen_condition_for_pattern(
        &self,
        pattern: &HirPattern,
        scrutinee_src: &str,
        scrutinee_ty: &SimpleType,
        bindings: &mut HashMap<String, String>,
    ) -> Option<String> {
        match &pattern.kind {
            HirPatternKind::Wildcard | HirPatternKind::Literal { .. } => None,
            HirPatternKind::Name(name) => {
                if name == "_" {
                    return None;
                }
                if let Some(encoded) = self.variant_encoding(name) {
                    return Some(match encoded {
                        CodegenVariantEncoding::UnitTag(tag) => {
                            format!("{scrutinee_src} == {tag}")
                        }
                        CodegenVariantEncoding::OddPayload => {
                            format!("{scrutinee_src} % 2 == 1")
                        }
                        CodegenVariantEncoding::EvenPayload => {
                            format!("{scrutinee_src} % 2 == 0")
                        }
                    });
                }
                bindings.insert(name.clone(), scrutinee_src.to_string());
                None
            }
            HirPatternKind::Tuple { name, fields } => {
                let encoded = self.variant_encoding(name)?;
                let condition = match encoded {
                    CodegenVariantEncoding::UnitTag(tag) => {
                        format!("{scrutinee_src} == {tag}")
                    }
                    CodegenVariantEncoding::OddPayload => {
                        format!("{scrutinee_src} % 2 == 1")
                    }
                    CodegenVariantEncoding::EvenPayload => {
                        format!("{scrutinee_src} % 2 == 0")
                    }
                };
                let variant = self.variants.get(name)?;
                if enum_pattern_can_match(scrutinee_ty, &variant.enum_name) {
                    for field in fields {
                        if let HirPatternKind::Name(field_name) = &field.kind
                            && field_name != "_"
                        {
                            bindings.insert(field_name.clone(), format!("({scrutinee_src} >> 1)"));
                        }
                    }
                }
                Some(condition)
            }
        }
    }

    fn lower_variant_call_for_codegen(
        &self,
        src: &str,
        name: &str,
        args: &[HirExpr],
    ) -> Option<String> {
        let encoded = self.variant_encoding(name)?;
        match encoded {
            CodegenVariantEncoding::OddPayload if args.len() == 1 => {
                let arg = source_fragment(src, args[0].span).trim();
                Some(format!("(({arg} << 1) | 1)"))
            }
            CodegenVariantEncoding::EvenPayload if args.len() == 1 => {
                let arg = source_fragment(src, args[0].span).trim();
                Some(format!("({arg} << 1)"))
            }
            CodegenVariantEncoding::UnitTag(tag) if args.is_empty() => Some(tag.to_string()),
            _ => None,
        }
    }

    fn lower_unit_variant_for_codegen(&self, name: &str) -> Option<String> {
        let CodegenVariantEncoding::UnitTag(tag) = self.variant_encoding(name)? else {
            return None;
        };
        Some(tag.to_string())
    }

    fn variant_encoding(&self, name: &str) -> Option<CodegenVariantEncoding> {
        let variant = self.variants.get(name)?;
        let info = self.enums.get(&variant.enum_name)?;
        if variant.fields.len() == 1 {
            if name.ends_with("Some") || name.ends_with("Ok") {
                return Some(CodegenVariantEncoding::OddPayload);
            }
            if name.ends_with("Err") {
                return Some(CodegenVariantEncoding::EvenPayload);
            }
            return None;
        }
        if !variant.fields.is_empty() {
            return None;
        }
        if name.ends_with("None") {
            return Some(CodegenVariantEncoding::UnitTag(0));
        }
        if self
            .variants
            .values()
            .filter(|candidate| candidate.enum_name == variant.enum_name)
            .all(|candidate| candidate.fields.is_empty())
        {
            let tag = info
                .variants
                .iter()
                .position(|candidate| candidate == name)? as i64;
            return Some(CodegenVariantEncoding::UnitTag(tag));
        }
        None
    }

    fn collect_match_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    self.collect_block_match_erasure(&function.body, &mut env, replacements)?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        self.collect_block_match_erasure(&method.body, &mut env, replacements)?;
                    }
                }
                HirItem::Const(constant) => {
                    self.collect_expr_match_erasure(
                        &constant.value,
                        &mut TypeEnv::new(),
                        replacements,
                    )?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_match_erasure(stmt, &mut TypeEnv::new(), replacements)?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_generic_enum_type_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        let mut types = Vec::new();
        collect_file_types(file, &mut types);
        for ty in types {
            if self.is_generic_enum_type_use(ty) {
                replacements.push((ty.span.start, ty.span.end(), "i32".to_string()));
            }
        }
    }

    fn is_generic_enum_type_use(&self, ty: &HirType) -> bool {
        let HirTypeKind::Generic { name, .. } = &ty.kind else {
            return false;
        };
        self.enums
            .get(name)
            .is_some_and(|info| !info.type_params.is_empty())
    }

    fn collect_generic_struct_type_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        let mut types = Vec::new();
        collect_file_types(file, &mut types);
        for ty in types {
            if self.is_generic_struct_type_use(ty) {
                replacements.push((ty.span.start, ty.span.end(), "i32".to_string()));
            }
        }
    }

    fn is_generic_struct_type_use(&self, ty: &HirType) -> bool {
        let HirTypeKind::Generic { name, .. } = &ty.kind else {
            return false;
        };
        self.structs
            .get(name)
            .is_some_and(|info| !info.type_params.is_empty())
    }

    fn collect_impl_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        for item in &file.items {
            if let HirItem::Impl(implementation) = item {
                replacements.push((
                    implementation.span.start,
                    implementation.span.end(),
                    String::new(),
                ));
            }
        }
    }

    fn collect_trait_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) {
        for item in &file.items {
            if let HirItem::Trait(trait_item) = item {
                replacements.push((trait_item.span.start, trait_item.span.end(), String::new()));
            }
        }
    }

    fn collect_method_call_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    self.collect_block_method_call_erasure(
                        &function.body,
                        &mut env,
                        &ret,
                        replacements,
                    )?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        let ret = simple_type_from_hir_type(&method.ret, &method_params);
                        self.collect_block_method_call_erasure(
                            &method.body,
                            &mut env,
                            &ret,
                            replacements,
                        )?;
                    }
                }
                HirItem::Const(constant) => {
                    let expected = simple_type_from_hir_type(&constant.ty, &HashSet::new());
                    self.collect_expr_method_call_erasure(
                        &constant.value,
                        &mut TypeEnv::new(),
                        Some(&expected),
                        replacements,
                    )?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_method_call_erasure(
                        stmt,
                        &mut TypeEnv::new(),
                        &SimpleType::Void,
                        replacements,
                    )?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_method_call_erasure(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_method_call_erasure(stmt, env, ret, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_method_call_erasure(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                if let Some(value) = value {
                    self.collect_expr_method_call_erasure(
                        value,
                        env,
                        annotated.as_ref(),
                        replacements,
                    )?;
                }
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr_method_call_erasure(value, env, Some(ret), replacements)?;
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_method_call_erasure(value, env, None, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_method_call_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_method_call_erasure(
                    then_block,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
                if let Some(block) = else_block {
                    self.collect_block_method_call_erasure(
                        block,
                        &mut env.clone(),
                        ret,
                        replacements,
                    )?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_method_call_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_method_call_erasure(body, &mut env.clone(), ret, replacements)?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_method_call_erasure(iter, env, None, replacements)?;
                self.collect_block_method_call_erasure(body, &mut env.clone(), ret, replacements)?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_method_call_erasure(block, &mut env.clone(), ret, replacements)?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_method_call_erasure(
        &self,
        expr: &HirExpr,
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Member { base, member } = &callee.kind {
                    let ret = self.infer_method_call(base, member, args, env, expected)?;
                    if let Some(dummy) = self.dummy_expr_for_type_check(&ret) {
                        replacements.push((expr.span.start, expr.span.end(), dummy));
                        return Ok(());
                    }
                }
                self.collect_expr_method_call_erasure(callee, env, None, replacements)?;
                for arg in args {
                    self.collect_expr_method_call_erasure(arg, env, None, replacements)?;
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_method_call_erasure(elem, env, None, replacements)?;
                }
            }
            HirExprKind::StructLiteral { fields, .. } => {
                for field in fields {
                    self.collect_expr_method_call_erasure(&field.value, env, None, replacements)?;
                }
            }
            HirExprKind::Match { expr: inner, arms } => {
                self.collect_expr_method_call_erasure(inner, env, None, replacements)?;
                let scrutinee = self.infer_expr(inner, env)?;
                for arm in arms {
                    let mut arm_env = env.clone();
                    self.bind_pattern(&arm.pattern, &scrutinee, &mut arm_env)?;
                    self.collect_expr_method_call_erasure(
                        &arm.value,
                        &mut arm_env,
                        expected,
                        replacements,
                    )?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_method_call_erasure(base, env, None, replacements)?;
                self.collect_expr_method_call_erasure(
                    index,
                    env,
                    Some(&SimpleType::Int),
                    replacements,
                )?;
            }
            HirExprKind::Member { base, .. } | HirExprKind::Unary { expr: base, .. } => {
                self.collect_expr_method_call_erasure(base, env, None, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_method_call_erasure(lhs, env, None, replacements)?;
                self.collect_expr_method_call_erasure(rhs, env, None, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                self.collect_expr_method_call_erasure(target, env, None, replacements)?;
                let target_ty = self.infer_expr(target, env)?;
                self.collect_expr_method_call_erasure(value, env, Some(&target_ty), replacements)?;
            }
            HirExprKind::Name(_) | HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn collect_generic_struct_value_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    self.collect_block_generic_struct_value_erasure(
                        &function.body,
                        &mut env,
                        &ret,
                        replacements,
                    )?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        let ret = simple_type_from_hir_type(&method.ret, &method_params);
                        self.collect_block_generic_struct_value_erasure(
                            &method.body,
                            &mut env,
                            &ret,
                            replacements,
                        )?;
                    }
                }
                HirItem::Const(constant) => {
                    let expected = simple_type_from_hir_type(&constant.ty, &HashSet::new());
                    self.collect_expr_generic_struct_value_erasure(
                        &constant.value,
                        &mut TypeEnv::new(),
                        Some(&expected),
                        replacements,
                    )?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_generic_struct_value_erasure(
                        stmt,
                        &mut TypeEnv::new(),
                        &SimpleType::Void,
                        replacements,
                    )?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_generic_struct_value_erasure(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_generic_struct_value_erasure(stmt, env, ret, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_generic_struct_value_erasure(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                if let Some(value) = value {
                    self.collect_expr_generic_struct_value_erasure(
                        value,
                        env,
                        annotated.as_ref(),
                        replacements,
                    )?;
                }
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr_generic_struct_value_erasure(
                        value,
                        env,
                        Some(ret),
                        replacements,
                    )?;
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_generic_struct_value_erasure(value, env, None, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_generic_struct_value_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_generic_struct_value_erasure(
                    then_block,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
                if let Some(block) = else_block {
                    self.collect_block_generic_struct_value_erasure(
                        block,
                        &mut env.clone(),
                        ret,
                        replacements,
                    )?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_generic_struct_value_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_generic_struct_value_erasure(
                    body,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_generic_struct_value_erasure(iter, env, None, replacements)?;
                self.collect_block_generic_struct_value_erasure(
                    body,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_generic_struct_value_erasure(
                    block,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_generic_struct_value_erasure(
        &self,
        expr: &HirExpr,
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::StructLiteral { name, fields } => {
                if self
                    .structs
                    .get(name)
                    .is_some_and(|info| !info.type_params.is_empty())
                {
                    let ty = self.infer_struct_literal(name, fields, env, expected)?;
                    if let Some(dummy) = self.dummy_expr_for_type_check(&ty) {
                        replacements.push((expr.span.start, expr.span.end(), dummy));
                        return Ok(());
                    }
                }
                if let Some(info) = self.structs.get(name) {
                    let substitutions = expected
                        .and_then(|expected| self.struct_expected_substitutions(expected, name))
                        .unwrap_or_default();
                    for field in fields {
                        if let Some(expected_field) = info
                            .fields
                            .iter()
                            .find(|candidate| candidate.name == field.name)
                        {
                            let expected_ty =
                                substitute_simple_type(&expected_field.ty, &substitutions);
                            if let Some(dummy) = self.dummy_expr_for_type_check(&expected_ty) {
                                replacements.push((
                                    field.value.span.start,
                                    field.value.span.end(),
                                    dummy,
                                ));
                                continue;
                            }
                        }
                        self.collect_expr_generic_struct_value_erasure(
                            &field.value,
                            env,
                            None,
                            replacements,
                        )?;
                    }
                } else {
                    for field in fields {
                        self.collect_expr_generic_struct_value_erasure(
                            &field.value,
                            env,
                            None,
                            replacements,
                        )?;
                    }
                }
            }
            HirExprKind::Member { base, .. } => {
                let base_ty = self.infer_expr(base, env)?;
                if self.is_generic_struct_simple_type(&base_ty) {
                    let ty = self.infer_expr(expr, env)?;
                    if let Some(dummy) = self.dummy_expr_for_type_check(&ty) {
                        replacements.push((expr.span.start, expr.span.end(), dummy));
                        return Ok(());
                    }
                }
                self.collect_expr_generic_struct_value_erasure(base, env, None, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                if let HirExprKind::Member { base, .. } = &target.kind {
                    let base_ty = self.infer_expr(base, env)?;
                    if self.is_generic_struct_simple_type(&base_ty) {
                        let target_ty = self.infer_expr(target, env)?;
                        self.collect_expr_generic_struct_value_erasure(
                            value,
                            env,
                            Some(&target_ty),
                            replacements,
                        )?;
                        replacements.push((expr.span.start, expr.span.end(), "0".to_string()));
                        return Ok(());
                    }
                }
                self.collect_expr_generic_struct_value_erasure(target, env, None, replacements)?;
                let target_ty = self.infer_expr(target, env)?;
                self.collect_expr_generic_struct_value_erasure(
                    value,
                    env,
                    Some(&target_ty),
                    replacements,
                )?;
            }
            HirExprKind::Name(name) => {
                if env
                    .get(name)
                    .is_some_and(|ty| self.is_generic_struct_simple_type(ty))
                {
                    replacements.push((expr.span.start, expr.span.end(), "0".to_string()));
                }
            }
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Member { base, member } = &callee.kind
                    && self
                        .infer_method_call(base, member, args, env, expected)
                        .is_ok()
                {
                    return Ok(());
                }
                self.collect_expr_generic_struct_value_erasure(callee, env, None, replacements)?;
                for arg in args {
                    self.collect_expr_generic_struct_value_erasure(arg, env, None, replacements)?;
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_generic_struct_value_erasure(elem, env, None, replacements)?;
                }
            }
            HirExprKind::Match { expr: inner, arms } => {
                self.collect_expr_generic_struct_value_erasure(inner, env, None, replacements)?;
                let scrutinee = self.infer_expr(inner, env)?;
                for arm in arms {
                    let mut arm_env = env.clone();
                    self.bind_pattern(&arm.pattern, &scrutinee, &mut arm_env)?;
                    self.collect_expr_generic_struct_value_erasure(
                        &arm.value,
                        &mut arm_env,
                        expected,
                        replacements,
                    )?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_generic_struct_value_erasure(base, env, None, replacements)?;
                self.collect_expr_generic_struct_value_erasure(
                    index,
                    env,
                    Some(&SimpleType::Int),
                    replacements,
                )?;
            }
            HirExprKind::Unary { expr: inner, .. } => {
                self.collect_expr_generic_struct_value_erasure(inner, env, expected, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_generic_struct_value_erasure(lhs, env, None, replacements)?;
                self.collect_expr_generic_struct_value_erasure(rhs, env, None, replacements)?;
            }
            HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn collect_for_loop_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    self.collect_block_for_loop_erasure(&function.body, &mut env, replacements)?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        self.collect_block_for_loop_erasure(&method.body, &mut env, replacements)?;
                    }
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_for_loop_erasure(stmt, &mut TypeEnv::new(), replacements)?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_for_loop_erasure(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_for_loop_erasure(stmt, env, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_for_loop_erasure(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::If {
                then_block,
                else_block,
                ..
            } => {
                self.collect_block_for_loop_erasure(then_block, &mut env.clone(), replacements)?;
                if let Some(block) = else_block {
                    self.collect_block_for_loop_erasure(block, &mut env.clone(), replacements)?;
                }
            }
            HirStmtKind::While { body, .. } | HirStmtKind::Block(body) => {
                self.collect_block_for_loop_erasure(body, &mut env.clone(), replacements)?;
            }
            HirStmtKind::For { name, iter, body } => {
                let iter_ty = self.infer_expr(iter, env)?;
                let Some(item_ty) = self.infer_for_item_type(&iter_ty) else {
                    return Err(CompileError::GpuTypeCheck(format!(
                        "for iterable type mismatch at byte {}: got {}",
                        iter.span.start,
                        simple_type_label(&iter_ty)
                    )));
                };
                let item_source_ty = simple_type_source_name(&item_ty);
                let item_dummy = dummy_expr_for_type(&item_ty).unwrap_or_else(|| "0".to_string());
                replacements.push((
                    stmt.span.start,
                    body.span.start,
                    "while (false) ".to_string(),
                ));
                replacements.push((
                    body.span.start + 1,
                    body.span.start + 1,
                    format!(" let {name}: {item_source_ty} = {item_dummy};"),
                ));

                let mut body_env = env.clone();
                body_env.insert(name.clone(), item_ty);
                self.collect_block_for_loop_erasure(body, &mut body_env, replacements)?;
            }
            HirStmtKind::Return(_)
            | HirStmtKind::Expr(_)
            | HirStmtKind::Break
            | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_array_return_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    let erase_returns = ret.is_array();
                    if erase_returns {
                        replacements.push((
                            function.ret.span.start,
                            function.ret.span.end(),
                            "i32".to_string(),
                        ));
                    }
                    self.collect_block_array_return_erasure(
                        &function.body,
                        erase_returns,
                        replacements,
                    )?;
                }
                HirItem::ExternFn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    if ret.is_array() {
                        replacements.push((
                            function.ret.span.start,
                            function.ret.span.end(),
                            "i32".to_string(),
                        ));
                    }
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let ret = simple_type_from_hir_type(&method.ret, &params);
                        let erase_returns = ret.is_array();
                        if erase_returns {
                            replacements.push((
                                method.ret.span.start,
                                method.ret.span.end(),
                                "i32".to_string(),
                            ));
                        }
                        self.collect_block_array_return_erasure(
                            &method.body,
                            erase_returns,
                            replacements,
                        )?;
                    }
                }
                HirItem::Const(constant) => {
                    self.collect_expr_array_return_erasure(&constant.value, replacements)?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_array_return_erasure(stmt, false, replacements)?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_array_return_erasure(
        &self,
        block: &HirBlock,
        erase_returns: bool,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_array_return_erasure(stmt, erase_returns, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_array_return_erasure(
        &self,
        stmt: &HirStmt,
        erase_returns: bool,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { value, .. } => {
                if let Some(value) = value {
                    self.collect_expr_array_return_erasure(value, replacements)?;
                }
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    if erase_returns {
                        replacements.push((value.span.start, value.span.end(), "0".to_string()));
                    } else {
                        self.collect_expr_array_return_erasure(value, replacements)?;
                    }
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_array_return_erasure(value, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_array_return_erasure(cond, replacements)?;
                self.collect_block_array_return_erasure(then_block, erase_returns, replacements)?;
                if let Some(block) = else_block {
                    self.collect_block_array_return_erasure(block, erase_returns, replacements)?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_array_return_erasure(cond, replacements)?;
                self.collect_block_array_return_erasure(body, erase_returns, replacements)?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_array_return_erasure(iter, replacements)?;
                self.collect_block_array_return_erasure(body, erase_returns, replacements)?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_array_return_erasure(block, erase_returns, replacements)?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_array_return_erasure(
        &self,
        expr: &HirExpr,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Name(name) = &callee.kind {
                    if let Some(info) = self.functions.get(name).filter(|info| info.ret.is_array())
                    {
                        let dummy =
                            dummy_expr_for_type(&info.ret).unwrap_or_else(|| "0".to_string());
                        replacements.push((expr.span.start, expr.span.end(), dummy));
                        return Ok(());
                    }
                }
                self.collect_expr_array_return_erasure(callee, replacements)?;
                for arg in args {
                    self.collect_expr_array_return_erasure(arg, replacements)?;
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_array_return_erasure(elem, replacements)?;
                }
            }
            HirExprKind::StructLiteral { fields, .. } => {
                for field in fields {
                    self.collect_expr_array_return_erasure(&field.value, replacements)?;
                }
            }
            HirExprKind::Match { expr: inner, arms } => {
                self.collect_expr_array_return_erasure(inner, replacements)?;
                for arm in arms {
                    self.collect_expr_array_return_erasure(&arm.value, replacements)?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_array_return_erasure(base, replacements)?;
                self.collect_expr_array_return_erasure(index, replacements)?;
            }
            HirExprKind::Member { base, .. } | HirExprKind::Unary { expr: base, .. } => {
                self.collect_expr_array_return_erasure(base, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_array_return_erasure(lhs, replacements)?;
                self.collect_expr_array_return_erasure(rhs, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                self.collect_expr_array_return_erasure(target, replacements)?;
                self.collect_expr_array_return_erasure(value, replacements)?;
            }
            HirExprKind::Name(_) | HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn collect_generic_function_call_erasure_replacements(
        &self,
        file: &HirFile,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for item in &file.items {
            match item {
                HirItem::Fn(function) => {
                    let params = function.type_params.iter().cloned().collect::<HashSet<_>>();
                    let mut env = self.type_env_for_bounds(&function.type_param_bounds, &params)?;
                    for param in &function.params {
                        env.insert(
                            param.name.clone(),
                            simple_type_from_hir_type(&param.ty, &params),
                        );
                    }
                    let ret = simple_type_from_hir_type(&function.ret, &params);
                    self.collect_block_generic_call_erasure(
                        &function.body,
                        &mut env,
                        &ret,
                        replacements,
                    )?;
                }
                HirItem::Impl(implementation) => {
                    let params = implementation
                        .type_params
                        .iter()
                        .cloned()
                        .collect::<HashSet<_>>();
                    for method in &implementation.methods {
                        let mut method_params = params.clone();
                        method_params.extend(method.type_params.iter().cloned());
                        let mut env =
                            self.type_env_for_bounds(&implementation.type_param_bounds, &params)?;
                        env.extend_bounds(
                            self.type_bounds_from_hir(&method.type_param_bounds, &method_params)?,
                        );
                        for param in &method.params {
                            env.insert(
                                param.name.clone(),
                                simple_type_from_hir_type(&param.ty, &method_params),
                            );
                        }
                        let ret = simple_type_from_hir_type(&method.ret, &method_params);
                        self.collect_block_generic_call_erasure(
                            &method.body,
                            &mut env,
                            &ret,
                            replacements,
                        )?;
                    }
                }
                HirItem::Const(constant) => {
                    let expected = simple_type_from_hir_type(&constant.ty, &HashSet::new());
                    self.collect_expr_generic_call_erasure(
                        &constant.value,
                        &mut TypeEnv::new(),
                        Some(&expected),
                        replacements,
                    )?;
                }
                HirItem::Stmt(stmt) => {
                    self.collect_stmt_generic_call_erasure(
                        stmt,
                        &mut TypeEnv::new(),
                        &SimpleType::Void,
                        replacements,
                    )?;
                }
                _ => {}
            }
        }
        Ok(())
    }

    fn collect_block_generic_call_erasure(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_generic_call_erasure(stmt, env, ret, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_generic_call_erasure(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        ret: &SimpleType,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                if let Some(value) = value {
                    self.collect_expr_generic_call_erasure(
                        value,
                        env,
                        annotated.as_ref(),
                        replacements,
                    )?;
                }
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr_generic_call_erasure(value, env, Some(ret), replacements)?;
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_generic_call_erasure(value, env, None, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_generic_call_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_generic_call_erasure(
                    then_block,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
                if let Some(block) = else_block {
                    self.collect_block_generic_call_erasure(
                        block,
                        &mut env.clone(),
                        ret,
                        replacements,
                    )?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_generic_call_erasure(
                    cond,
                    env,
                    Some(&SimpleType::Bool),
                    replacements,
                )?;
                self.collect_block_generic_call_erasure(body, &mut env.clone(), ret, replacements)?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_generic_call_erasure(iter, env, None, replacements)?;
                self.collect_block_generic_call_erasure(body, &mut env.clone(), ret, replacements)?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_generic_call_erasure(
                    block,
                    &mut env.clone(),
                    ret,
                    replacements,
                )?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_generic_call_erasure(
        &self,
        expr: &HirExpr,
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Name(name) = &callee.kind {
                    if let Some(info) = self
                        .functions
                        .get(name)
                        .filter(|info| !info.type_params.is_empty())
                    {
                        let ret = self.infer_function_call(name, info, args, env, expected)?;
                        if let Some(dummy) = self.dummy_expr_for_type_check(&ret) {
                            replacements.push((expr.span.start, expr.span.end(), dummy));
                            return Ok(());
                        }
                    }
                }
                self.collect_expr_generic_call_erasure(callee, env, None, replacements)?;
                for arg in args {
                    self.collect_expr_generic_call_erasure(arg, env, None, replacements)?;
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_generic_call_erasure(elem, env, None, replacements)?;
                }
            }
            HirExprKind::StructLiteral { fields, .. } => {
                for field in fields {
                    self.collect_expr_generic_call_erasure(&field.value, env, None, replacements)?;
                }
            }
            HirExprKind::Match { expr: inner, arms } => {
                self.collect_expr_generic_call_erasure(inner, env, None, replacements)?;
                let scrutinee = self.infer_expr(inner, env)?;
                for arm in arms {
                    let mut arm_env = env.clone();
                    self.bind_pattern(&arm.pattern, &scrutinee, &mut arm_env)?;
                    self.collect_expr_generic_call_erasure(
                        &arm.value,
                        &mut arm_env,
                        expected,
                        replacements,
                    )?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_generic_call_erasure(base, env, None, replacements)?;
                self.collect_expr_generic_call_erasure(
                    index,
                    env,
                    Some(&SimpleType::Int),
                    replacements,
                )?;
            }
            HirExprKind::Member { base, .. } | HirExprKind::Unary { expr: base, .. } => {
                self.collect_expr_generic_call_erasure(base, env, None, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_generic_call_erasure(lhs, env, None, replacements)?;
                self.collect_expr_generic_call_erasure(rhs, env, None, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                self.collect_expr_generic_call_erasure(target, env, None, replacements)?;
                let target_ty = self.infer_expr(target, env)?;
                self.collect_expr_generic_call_erasure(value, env, Some(&target_ty), replacements)?;
            }
            HirExprKind::Name(_) | HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn dummy_expr_for_type_check(&self, ty: &SimpleType) -> Option<String> {
        if self.is_generic_enum_simple_type(ty) || self.is_generic_struct_simple_type(ty) {
            Some("0".to_string())
        } else {
            dummy_expr_for_type(ty)
        }
    }

    fn collect_block_match_erasure(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.collect_stmt_match_erasure(stmt, env, replacements)?;
        }
        Ok(())
    }

    fn collect_stmt_match_erasure(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                if let Some(value) = value {
                    self.collect_expr_match_erasure(value, env, replacements)?;
                }
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                let inferred = if let Some(value) = value {
                    self.infer_expr_with_expected(value, env, annotated.as_ref())?
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    self.collect_expr_match_erasure(value, env, replacements)?;
                }
            }
            HirStmtKind::Expr(value) => {
                self.collect_expr_match_erasure(value, env, replacements)?;
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.collect_expr_match_erasure(cond, env, replacements)?;
                self.collect_block_match_erasure(then_block, &mut env.clone(), replacements)?;
                if let Some(block) = else_block {
                    self.collect_block_match_erasure(block, &mut env.clone(), replacements)?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.collect_expr_match_erasure(cond, env, replacements)?;
                self.collect_block_match_erasure(body, &mut env.clone(), replacements)?;
            }
            HirStmtKind::For { iter, body, .. } => {
                self.collect_expr_match_erasure(iter, env, replacements)?;
                self.collect_block_match_erasure(body, &mut env.clone(), replacements)?;
            }
            HirStmtKind::Block(block) => {
                self.collect_block_match_erasure(block, &mut env.clone(), replacements)?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn collect_expr_match_erasure(
        &self,
        expr: &HirExpr,
        env: &mut TypeEnv,
        replacements: &mut Vec<(usize, usize, String)>,
    ) -> Result<(), CompileError> {
        match &expr.kind {
            HirExprKind::Match { expr: inner, arms } => {
                let ty = self.infer_expr(expr, env)?;
                if let Some(dummy) = dummy_expr_for_type_in_env(&ty, env) {
                    replacements.push((expr.span.start, expr.span.end(), dummy));
                    return Ok(());
                }
                let scrutinee = self.infer_expr(inner, env)?;
                self.collect_expr_match_erasure(inner, env, replacements)?;
                for arm in arms {
                    let mut arm_env = env.clone();
                    self.bind_pattern(&arm.pattern, &scrutinee, &mut arm_env)?;
                    self.collect_expr_match_erasure(&arm.value, &mut arm_env, replacements)?;
                }
            }
            HirExprKind::Array(elems) => {
                for elem in elems {
                    self.collect_expr_match_erasure(elem, env, replacements)?;
                }
            }
            HirExprKind::StructLiteral { fields, .. } => {
                for field in fields {
                    self.collect_expr_match_erasure(&field.value, env, replacements)?;
                }
            }
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Name(name) = &callee.kind {
                    if let Some(variant) = self.variants.get(name) {
                        if args.len() == variant.fields.len()
                            && self
                                .enums
                                .get(&variant.enum_name)
                                .is_some_and(|info| !info.type_params.is_empty())
                        {
                            replacements.push((expr.span.start, expr.span.end(), "0".to_string()));
                            return Ok(());
                        }
                    }
                }
                self.collect_expr_match_erasure(callee, env, replacements)?;
                for arg in args {
                    self.collect_expr_match_erasure(arg, env, replacements)?;
                }
            }
            HirExprKind::Index { base, index } => {
                self.collect_expr_match_erasure(base, env, replacements)?;
                self.collect_expr_match_erasure(index, env, replacements)?;
            }
            HirExprKind::Member { base, .. } | HirExprKind::Unary { expr: base, .. } => {
                self.collect_expr_match_erasure(base, env, replacements)?;
            }
            HirExprKind::Binary { lhs, rhs, .. } => {
                self.collect_expr_match_erasure(lhs, env, replacements)?;
                self.collect_expr_match_erasure(rhs, env, replacements)?;
            }
            HirExprKind::Assign { target, value, .. } => {
                self.collect_expr_match_erasure(target, env, replacements)?;
                self.collect_expr_match_erasure(value, env, replacements)?;
            }
            HirExprKind::Name(name) => {
                if self.is_generic_enum_variant(name) {
                    replacements.push((expr.span.start, expr.span.end(), "0".to_string()));
                }
            }
            HirExprKind::Literal { .. } => {}
        }
        Ok(())
    }

    fn precheck_block(
        &self,
        block: &HirBlock,
        env: &mut TypeEnv,
        ret: &SimpleType,
    ) -> Result<(), CompileError> {
        for stmt in &block.stmts {
            self.precheck_stmt(stmt, env, ret)?;
        }
        Ok(())
    }

    fn precheck_stmt(
        &self,
        stmt: &HirStmt,
        env: &mut TypeEnv,
        ret: &SimpleType,
    ) -> Result<(), CompileError> {
        match &stmt.kind {
            HirStmtKind::Let { name, ty, value } => {
                let annotated = ty
                    .as_ref()
                    .map(|ty| simple_type_from_hir_type(ty, env.type_params()));
                let inferred = if let Some(value) = value {
                    let actual = self.infer_expr_with_expected(value, env, annotated.as_ref())?;
                    if let Some(expected) = &annotated {
                        ensure_types_compatible(expected, &actual, value.span, "let")?;
                    }
                    actual
                } else {
                    SimpleType::Unknown
                };
                env.insert(name.clone(), annotated.unwrap_or(inferred));
            }
            HirStmtKind::Return(value) => {
                if let Some(value) = value {
                    if *ret != SimpleType::Void {
                        let actual = self.infer_expr_with_expected(value, env, Some(ret))?;
                        ensure_types_compatible(ret, &actual, value.span, "return")?;
                    } else {
                        self.infer_expr(value, env)?;
                    }
                }
            }
            HirStmtKind::If {
                cond,
                then_block,
                else_block,
            } => {
                self.infer_expr(cond, env)?;
                self.precheck_block(then_block, &mut env.clone(), ret)?;
                if let Some(block) = else_block {
                    self.precheck_block(block, &mut env.clone(), ret)?;
                }
            }
            HirStmtKind::While { cond, body } => {
                self.infer_expr(cond, env)?;
                self.precheck_block(body, &mut env.clone(), ret)?;
            }
            HirStmtKind::For { name, iter, body } => {
                let iter_ty = self.infer_expr(iter, env)?;
                let Some(item_ty) = self.infer_for_item_type(&iter_ty) else {
                    return Err(CompileError::GpuTypeCheck(format!(
                        "for iterable type mismatch at byte {}: got {}",
                        iter.span.start,
                        simple_type_label(&iter_ty)
                    )));
                };
                let mut body_env = env.clone();
                body_env.insert(name.clone(), item_ty);
                self.precheck_block(body, &mut body_env, ret)?;
            }
            HirStmtKind::Block(block) => self.precheck_block(block, &mut env.clone(), ret)?,
            HirStmtKind::Expr(expr) => {
                self.infer_expr(expr, env)?;
            }
            HirStmtKind::Break | HirStmtKind::Continue => {}
        }
        Ok(())
    }

    fn infer_expr(&self, expr: &HirExpr, env: &mut TypeEnv) -> Result<SimpleType, CompileError> {
        self.infer_expr_with_expected(expr, env, None)
    }

    fn infer_expr_with_expected(
        &self,
        expr: &HirExpr,
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<SimpleType, CompileError> {
        match &expr.kind {
            HirExprKind::Name(name) => Ok(env
                .get(name)
                .or_else(|| self.consts.get(name))
                .cloned()
                .or_else(|| self.unit_variant_type(name))
                .unwrap_or(SimpleType::Unknown)),
            HirExprKind::Literal { kind, .. } => Ok(match kind {
                HirLiteralKind::Int => SimpleType::Int,
                HirLiteralKind::Bool => SimpleType::Bool,
                HirLiteralKind::Float => SimpleType::Float,
                HirLiteralKind::String => SimpleType::String,
                HirLiteralKind::Char => SimpleType::Char,
            }),
            HirExprKind::Array(elems) => {
                let mut elem_ty = SimpleType::Unknown;
                for elem in elems {
                    let actual = self.infer_expr(elem, env)?;
                    if elem_ty == SimpleType::Unknown {
                        elem_ty = actual;
                    } else {
                        ensure_types_compatible(&elem_ty, &actual, elem.span, "array literal")?;
                    }
                }
                Ok(SimpleType::Array {
                    elem: Box::new(elem_ty),
                    len: elems.len().to_string(),
                })
            }
            HirExprKind::StructLiteral { name, fields } => {
                self.infer_struct_literal(name, fields, env, expected)
            }
            HirExprKind::Match { expr: inner, arms } => {
                let scrutinee = self.infer_expr(inner, env)?;
                self.infer_match_expr(&scrutinee, arms, env)
            }
            HirExprKind::Call { callee, args } => {
                if let HirExprKind::Member { base, member } = &callee.kind {
                    return self.infer_method_call(base, member, args, env, expected);
                }
                if let HirExprKind::Name(name) = &callee.kind {
                    if let Some(variant) = self.variants.get(name) {
                        return self
                            .infer_enum_constructor_call(name, variant, args, env, expected);
                    }
                    if let Some(info) = self.functions.get(name) {
                        return self.infer_function_call(name, info, args, env, expected);
                    }
                }
                for arg in args {
                    self.infer_expr(arg, env)?;
                }
                Ok(SimpleType::Unknown)
            }
            HirExprKind::Index { base, index } => {
                self.infer_expr(index, env)?;
                Ok(match self.infer_expr(base, env)? {
                    SimpleType::Array { elem, .. } | SimpleType::Slice(elem) => *elem,
                    _ => SimpleType::Unknown,
                })
            }
            HirExprKind::Member { base, member } => self.infer_member_access(base, member, env),
            HirExprKind::Unary { op, expr: inner } => {
                let ty = self.infer_expr(inner, env)?;
                Ok(match op {
                    HirUnaryOp::Not => SimpleType::Bool,
                    _ => ty,
                })
            }
            HirExprKind::Binary { op, lhs, rhs } => {
                let left = self.infer_expr(lhs, env)?;
                let right = self.infer_expr(rhs, env)?;
                Ok(match op {
                    HirBinaryOp::Lt
                    | HirBinaryOp::Gt
                    | HirBinaryOp::Le
                    | HirBinaryOp::Ge
                    | HirBinaryOp::Eq
                    | HirBinaryOp::Ne
                    | HirBinaryOp::And
                    | HirBinaryOp::Or => SimpleType::Bool,
                    _ if left != SimpleType::Unknown => left,
                    _ => right,
                })
            }
            HirExprKind::Assign { op, target, value } => {
                let dst = self.infer_expr(target, env)?;
                let src = self.infer_expr_with_expected(value, env, Some(&dst))?;
                if *op == HirAssignOp::Assign {
                    ensure_types_compatible(&dst, &src, value.span, "assignment")?;
                }
                Ok(dst)
            }
        }
    }

    fn infer_struct_literal(
        &self,
        name: &str,
        fields: &[HirStructLiteralField],
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<SimpleType, CompileError> {
        let Some(info) = self.structs.get(name) else {
            for field in fields {
                self.infer_expr(&field.value, env)?;
            }
            return Ok(SimpleType::Named(name.to_string()));
        };

        let mut substitutions = expected
            .and_then(|expected| self.struct_expected_substitutions(expected, name))
            .unwrap_or_default();
        let mut seen = HashSet::new();

        for field in fields {
            if !info
                .fields
                .iter()
                .any(|candidate| candidate.name == field.name)
            {
                return Err(CompileError::GpuTypeCheck(format!(
                    "InvalidMemberAccess: struct `{name}` has no field `{}` at byte {}",
                    field.name, field.span.start
                )));
            }
            if !seen.insert(field.name.clone()) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "InvalidMemberAccess: duplicate field `{}` in struct `{name}` at byte {}",
                    field.name, field.span.start
                )));
            }
        }

        for expected_field in &info.fields {
            let Some(field) = fields
                .iter()
                .find(|candidate| candidate.name == expected_field.name)
            else {
                return Err(CompileError::GpuTypeCheck(format!(
                    "InvalidMemberAccess: missing field `{}` for struct `{name}`",
                    expected_field.name
                )));
            };
            let expected_ty = substitute_simple_type(&expected_field.ty, &substitutions);
            let actual = self.infer_expr_with_expected(&field.value, env, Some(&expected_ty))?;
            if !simple_types_compatible_for_function(&expected_ty, &actual, &[]) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "AssignMismatch: struct `{name}` field `{}` type mismatch at byte {}: expected {}, got {}",
                    expected_field.name,
                    field.value.span.start,
                    simple_type_label(&expected_ty),
                    simple_type_label(&actual)
                )));
            }
            unify_simple_type(&expected_field.ty, &actual, &mut substitutions);
        }

        if info.type_params.is_empty() {
            return Ok(SimpleType::Named(name.to_string()));
        }

        Ok(SimpleType::Generic {
            name: name.to_string(),
            args: info
                .type_params
                .iter()
                .map(|param| {
                    substitutions
                        .get(param)
                        .cloned()
                        .unwrap_or(SimpleType::Unknown)
                })
                .collect(),
        })
    }

    fn infer_member_access(
        &self,
        base: &HirExpr,
        member: &str,
        env: &mut TypeEnv,
    ) -> Result<SimpleType, CompileError> {
        let base_ty = self.infer_expr(base, env)?;
        let struct_name = match &base_ty {
            SimpleType::Named(name) | SimpleType::Generic { name, .. } => name.as_str(),
            SimpleType::Unknown => return Ok(SimpleType::Unknown),
            _ => {
                return Err(CompileError::GpuTypeCheck(format!(
                    "InvalidMemberAccess: non-struct member access at byte {}",
                    base.span.start
                )));
            }
        };
        let Some(info) = self.structs.get(struct_name) else {
            return Ok(SimpleType::Unknown);
        };
        let Some(field) = info.fields.iter().find(|field| field.name == member) else {
            return Err(CompileError::GpuTypeCheck(format!(
                "InvalidMemberAccess: struct `{struct_name}` has no field `{member}` at byte {}",
                base.span.start
            )));
        };
        let substitutions = self.struct_substitutions(&base_ty, struct_name);
        Ok(substitute_simple_type(&field.ty, &substitutions))
    }

    fn infer_for_item_type(&self, iter_ty: &SimpleType) -> Option<SimpleType> {
        match iter_ty {
            SimpleType::Array { elem, .. } | SimpleType::Slice(elem) => Some((**elem).clone()),
            SimpleType::Generic { name, args }
                if args.len() == 1 && self.is_range_like_struct_name(name) =>
            {
                Some(args[0].clone())
            }
            SimpleType::Unknown => Some(SimpleType::Unknown),
            _ => None,
        }
    }

    fn is_range_like_struct_name(&self, name: &str) -> bool {
        if !self
            .structs
            .get(name)
            .is_some_and(|info| info.type_params.len() == 1)
        {
            return false;
        }
        name.ends_with("Range")
            || name.ends_with("RangeInclusive")
            || name.ends_with("RangeFrom")
            || name.ends_with("RangeTo")
    }

    fn infer_enum_constructor_call(
        &self,
        name: &str,
        variant: &VariantInfo,
        args: &[HirExpr],
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<SimpleType, CompileError> {
        let Some(info) = self.enums.get(&variant.enum_name) else {
            return Ok(SimpleType::Unknown);
        };

        if args.len() != variant.fields.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "enum constructor `{name}` argument count mismatch at byte {}: expected {}, got {}",
                args.first().map(|arg| arg.span.start).unwrap_or(0),
                variant.fields.len(),
                args.len()
            )));
        }

        let mut substitutions = expected
            .and_then(|expected| self.enum_expected_substitutions(expected, &variant.enum_name))
            .unwrap_or_default();
        for (arg, field_ty) in args.iter().zip(variant.fields.iter()) {
            let expected_arg = substitute_simple_type(field_ty, &substitutions);
            let actual = self.infer_expr_with_expected(arg, env, Some(&expected_arg))?;
            if !simple_types_compatible(&expected_arg, &actual) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "enum constructor `{name}` argument type mismatch at byte {}: expected {}, got {}",
                    arg.span.start,
                    simple_type_label(&expected_arg),
                    simple_type_label(&actual)
                )));
            }
            unify_simple_type(field_ty, &actual, &mut substitutions);
        }

        if info.type_params.is_empty() {
            return Ok(SimpleType::Named(variant.enum_name.clone()));
        }

        Ok(SimpleType::Generic {
            name: variant.enum_name.clone(),
            args: info
                .type_params
                .iter()
                .map(|param| {
                    substitutions
                        .get(param)
                        .cloned()
                        .unwrap_or(SimpleType::Unknown)
                })
                .collect(),
        })
    }

    fn infer_function_call(
        &self,
        name: &str,
        info: &FunctionInfo,
        args: &[HirExpr],
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<SimpleType, CompileError> {
        if args.len() != info.params.len() {
            return Err(CompileError::GpuTypeCheck(format!(
                "function `{name}` argument count mismatch at byte {}: expected {}, got {}",
                args.first().map(|arg| arg.span.start).unwrap_or(0),
                info.params.len(),
                args.len()
            )));
        }

        let mut substitutions = HashMap::new();
        if let Some(expected) = expected {
            unify_simple_type(&info.ret, expected, &mut substitutions);
        }

        for (index, (arg, param_ty)) in args.iter().zip(info.params.iter()).enumerate() {
            let expected_arg = substitute_simple_type(param_ty, &substitutions);
            let actual = self.infer_expr_with_expected(arg, env, Some(&expected_arg))?;
            if !simple_types_compatible_for_function(&expected_arg, &actual, &info.const_params) {
                return Err(CompileError::GpuTypeCheck(format!(
                    "function `{name}` argument {index} type mismatch at byte {}: expected {}, got {}",
                    arg.span.start,
                    simple_type_label(&expected_arg),
                    simple_type_label(&actual)
                )));
            }
            unify_simple_type(param_ty, &actual, &mut substitutions);
        }

        Ok(substitute_simple_type(&info.ret, &substitutions))
    }

    fn infer_method_call(
        &self,
        base: &HirExpr,
        method: &str,
        args: &[HirExpr],
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<SimpleType, CompileError> {
        let receiver = self.infer_expr(base, env)?;
        for candidate in self
            .methods
            .iter()
            .filter(|candidate| candidate.name == method)
        {
            let info = &candidate.info;
            if info.params.is_empty() || args.len() + 1 != info.params.len() {
                continue;
            }

            let mut substitutions = HashMap::new();
            unify_simple_type(&candidate.target, &receiver, &mut substitutions);
            if let Some(expected) = expected {
                unify_simple_type(&info.ret, expected, &mut substitutions);
            }

            let expected_receiver = substitute_simple_type(&info.params[0], &substitutions);
            if !simple_types_compatible_for_function(
                &expected_receiver,
                &receiver,
                &info.const_params,
            ) {
                continue;
            }
            unify_simple_type(&info.params[0], &receiver, &mut substitutions);

            let mut mismatch = None;
            for (index, (arg, param_ty)) in args.iter().zip(info.params.iter().skip(1)).enumerate()
            {
                let expected_arg = substitute_simple_type(param_ty, &substitutions);
                let actual = self.infer_expr_with_expected(arg, env, Some(&expected_arg))?;
                if !simple_types_compatible_for_function(&expected_arg, &actual, &info.const_params)
                {
                    mismatch = Some((
                        index,
                        arg.span.start,
                        simple_type_label(&expected_arg),
                        simple_type_label(&actual),
                    ));
                    break;
                }
                unify_simple_type(param_ty, &actual, &mut substitutions);
            }
            if let Some((index, span, expected, actual)) = mismatch {
                return Err(CompileError::GpuTypeCheck(format!(
                    "method `{method}` argument {index} type mismatch at byte {span}: expected {expected}, got {actual}",
                )));
            }

            return Ok(substitute_simple_type(&info.ret, &substitutions));
        }

        if let Some(ret) =
            self.infer_trait_bound_method_call(&receiver, method, args, env, expected)?
        {
            return Ok(ret);
        }

        Err(CompileError::GpuTypeCheck(format!(
            "method `{method}` not found for type {} at byte {}",
            simple_type_label(&receiver),
            base.span.start
        )))
    }

    fn infer_trait_bound_method_call(
        &self,
        receiver: &SimpleType,
        method: &str,
        args: &[HirExpr],
        env: &mut TypeEnv,
        expected: Option<&SimpleType>,
    ) -> Result<Option<SimpleType>, CompileError> {
        let SimpleType::Param(param_name) = receiver else {
            return Ok(None);
        };
        let bounds = env.bounds_for(param_name).cloned().collect::<Vec<_>>();

        for bound_ty in bounds {
            let Some((trait_name, trait_args)) = trait_type_parts(&bound_ty) else {
                continue;
            };
            let Some(info) = self.traits.get(trait_name) else {
                continue;
            };
            if trait_args.len() != info.type_params.len() {
                continue;
            }

            let mut trait_substitutions = HashMap::new();
            for (param, arg) in info.type_params.iter().zip(trait_args.iter()) {
                trait_substitutions.insert(param.clone(), arg.clone());
            }

            for required in info
                .methods
                .iter()
                .filter(|candidate| candidate.name == method)
            {
                if required.params.is_empty() || args.len() + 1 != required.params.len() {
                    continue;
                }

                let expected_receiver =
                    substitute_simple_type(&required.params[0], &trait_substitutions);
                if !trait_bound_types_compatible(&expected_receiver, receiver) {
                    continue;
                }

                let expected_ret = substitute_simple_type(&required.ret, &trait_substitutions);
                if let Some(expected) = expected {
                    if !trait_bound_types_compatible(expected, &expected_ret) {
                        continue;
                    }
                }

                for (index, (arg, param_ty)) in
                    args.iter().zip(required.params.iter().skip(1)).enumerate()
                {
                    let expected_arg = substitute_simple_type(param_ty, &trait_substitutions);
                    let actual = self.infer_expr_with_expected(arg, env, Some(&expected_arg))?;
                    if !trait_bound_types_compatible(&expected_arg, &actual) {
                        return Err(CompileError::GpuTypeCheck(format!(
                            "method `{method}` argument {index} type mismatch at byte {}: expected {}, got {}",
                            arg.span.start,
                            simple_type_label(&expected_arg),
                            simple_type_label(&actual)
                        )));
                    }
                }

                return Ok(Some(expected_ret));
            }
        }

        Ok(None)
    }

    fn infer_match_expr(
        &self,
        scrutinee: &SimpleType,
        arms: &[HirMatchArm],
        env: &TypeEnv,
    ) -> Result<SimpleType, CompileError> {
        let mut result = SimpleType::Unknown;
        for arm in arms {
            let mut arm_env = env.clone();
            self.bind_pattern(&arm.pattern, scrutinee, &mut arm_env)?;
            let actual = self.infer_expr(&arm.value, &mut arm_env)?;
            if result == SimpleType::Unknown {
                result = actual;
            } else {
                ensure_types_compatible(&result, &actual, arm.value.span, "match arm")?;
            }
        }
        Ok(result)
    }

    fn bind_pattern(
        &self,
        pattern: &HirPattern,
        scrutinee: &SimpleType,
        env: &mut TypeEnv,
    ) -> Result<(), CompileError> {
        match &pattern.kind {
            HirPatternKind::Wildcard | HirPatternKind::Literal { .. } => {}
            HirPatternKind::Name(name) => {
                if name == "_" || self.unit_variant_type(name).is_some() {
                    return Ok(());
                }
                env.insert(name.clone(), scrutinee.clone());
            }
            HirPatternKind::Tuple { name, fields } => {
                let Some(variant) = self.variants.get(name) else {
                    return Ok(());
                };
                if !enum_pattern_can_match(scrutinee, &variant.enum_name) {
                    return Ok(());
                }
                let substitutions = self.enum_substitutions(scrutinee, &variant.enum_name);
                for (field_pattern, field_ty) in fields.iter().zip(variant.fields.iter()) {
                    let field_ty = substitute_simple_type(field_ty, &substitutions);
                    self.bind_pattern(field_pattern, &field_ty, env)?;
                }
            }
        }
        Ok(())
    }

    fn unit_variant_type(&self, name: &str) -> Option<SimpleType> {
        let variant = self.variants.get(name)?;
        if !variant.fields.is_empty() {
            return None;
        }
        let info = self.enums.get(&variant.enum_name)?;
        if info.type_params.is_empty() {
            Some(SimpleType::Named(variant.enum_name.clone()))
        } else {
            Some(SimpleType::Generic {
                name: variant.enum_name.clone(),
                args: vec![SimpleType::Unknown; info.type_params.len()],
            })
        }
    }

    fn is_generic_enum_variant(&self, name: &str) -> bool {
        let Some(variant) = self.variants.get(name) else {
            return false;
        };
        self.enums
            .get(&variant.enum_name)
            .is_some_and(|info| !info.type_params.is_empty())
    }

    fn is_generic_enum_simple_type(&self, ty: &SimpleType) -> bool {
        match ty {
            SimpleType::Generic { name, .. } => self
                .enums
                .get(name)
                .is_some_and(|info| !info.type_params.is_empty()),
            _ => false,
        }
    }

    fn is_generic_struct_simple_type(&self, ty: &SimpleType) -> bool {
        match ty {
            SimpleType::Generic { name, .. } => self
                .structs
                .get(name)
                .is_some_and(|info| !info.type_params.is_empty()),
            _ => false,
        }
    }

    fn enum_substitutions(
        &self,
        scrutinee: &SimpleType,
        enum_name: &str,
    ) -> HashMap<String, SimpleType> {
        let Some(info) = self.enums.get(enum_name) else {
            return HashMap::new();
        };
        let args = match scrutinee {
            SimpleType::Generic { name, args } if name == enum_name => args.as_slice(),
            _ => &[],
        };
        info.type_params
            .iter()
            .cloned()
            .zip(args.iter().cloned())
            .collect()
    }

    fn enum_expected_substitutions(
        &self,
        expected: &SimpleType,
        enum_name: &str,
    ) -> Option<HashMap<String, SimpleType>> {
        match expected {
            SimpleType::Generic { name, args } if name == enum_name => {
                let info = self.enums.get(enum_name)?;
                Some(
                    info.type_params
                        .iter()
                        .cloned()
                        .zip(args.iter().cloned())
                        .collect(),
                )
            }
            SimpleType::Named(name) if name == enum_name => Some(HashMap::new()),
            SimpleType::Unknown => Some(HashMap::new()),
            _ => None,
        }
    }

    fn struct_substitutions(
        &self,
        ty: &SimpleType,
        struct_name: &str,
    ) -> HashMap<String, SimpleType> {
        let Some(info) = self.structs.get(struct_name) else {
            return HashMap::new();
        };
        let args = match ty {
            SimpleType::Generic { name, args } if name == struct_name => args.as_slice(),
            _ => &[],
        };
        info.type_params
            .iter()
            .cloned()
            .zip(args.iter().cloned())
            .collect()
    }

    fn struct_expected_substitutions(
        &self,
        expected: &SimpleType,
        struct_name: &str,
    ) -> Option<HashMap<String, SimpleType>> {
        match expected {
            SimpleType::Generic { name, args } if name == struct_name => {
                let info = self.structs.get(struct_name)?;
                Some(
                    info.type_params
                        .iter()
                        .cloned()
                        .zip(args.iter().cloned())
                        .collect(),
                )
            }
            SimpleType::Named(name) if name == struct_name => Some(HashMap::new()),
            SimpleType::Unknown => Some(HashMap::new()),
            _ => None,
        }
    }
}

fn collect_type_param_replacements_in_type(
    ty: &HirType,
    params: &HashSet<String>,
    replacements: &mut Vec<(usize, usize, String)>,
) {
    match &ty.kind {
        HirTypeKind::Name(name) if params.contains(name) => {
            replacements.push((ty.span.start, ty.span.end(), "i32".to_string()));
        }
        HirTypeKind::Generic { args, .. } => {
            for arg in args {
                collect_type_param_replacements_in_type(arg, params, replacements);
            }
        }
        HirTypeKind::Ref { inner } => {
            collect_type_param_replacements_in_type(inner, params, replacements);
        }
        HirTypeKind::Slice { elem } => {
            collect_type_param_replacements_in_type(elem, params, replacements);
        }
        HirTypeKind::Array { elem, .. } => {
            collect_type_param_replacements_in_type(elem, params, replacements);
        }
        HirTypeKind::Void | HirTypeKind::Name(_) => {}
    }
}

fn collect_block_type_param_codegen_replacements(
    block: &HirBlock,
    params: &HashSet<String>,
    replacements: &mut Vec<(usize, usize, String)>,
) {
    for stmt in &block.stmts {
        collect_stmt_type_param_codegen_replacements(stmt, params, replacements);
    }
}

fn collect_stmt_type_param_codegen_replacements(
    stmt: &HirStmt,
    params: &HashSet<String>,
    replacements: &mut Vec<(usize, usize, String)>,
) {
    match &stmt.kind {
        HirStmtKind::Let { ty, .. } => {
            if let Some(ty) = ty {
                collect_type_param_replacements_in_type(ty, params, replacements);
            }
        }
        HirStmtKind::If {
            then_block,
            else_block,
            ..
        } => {
            collect_block_type_param_codegen_replacements(then_block, params, replacements);
            if let Some(block) = else_block {
                collect_block_type_param_codegen_replacements(block, params, replacements);
            }
        }
        HirStmtKind::While { body, .. } | HirStmtKind::For { body, .. } => {
            collect_block_type_param_codegen_replacements(body, params, replacements);
        }
        HirStmtKind::Block(block) => {
            collect_block_type_param_codegen_replacements(block, params, replacements);
        }
        HirStmtKind::Return(_)
        | HirStmtKind::Expr(_)
        | HirStmtKind::Break
        | HirStmtKind::Continue => {}
    }
}

fn source_fragment(src: &str, span: crate::hir::Span) -> &str {
    src.get(span.start..span.end()).unwrap_or_default()
}

fn replace_bound_names_in_source(src: &str, bindings: &HashMap<String, String>) -> String {
    if bindings.is_empty() {
        return src.to_string();
    }
    let Ok(tokens) = lex_on_cpu(src) else {
        return src.to_string();
    };
    let mut replacements = Vec::new();
    for (index, token) in tokens.iter().enumerate() {
        if !is_path_segment_token(token.kind)
            || token_before_is_path_separator(&tokens, index)
            || token_after_is_path_separator(&tokens, index)
        {
            continue;
        }
        let text = token_text(src, token);
        if let Some(replacement) = bindings.get(text) {
            replacements.push((
                token.start,
                token.start.saturating_add(token.len),
                replacement.clone(),
            ));
        }
    }
    apply_replacements(src, replacements)
}

fn simple_type_from_hir_type(ty: &HirType, params: &HashSet<String>) -> SimpleType {
    match &ty.kind {
        HirTypeKind::Void => SimpleType::Void,
        HirTypeKind::Name(name) => primitive_simple_type(name).unwrap_or_else(|| {
            if params.contains(name) {
                SimpleType::Param(name.clone())
            } else {
                SimpleType::Named(name.clone())
            }
        }),
        HirTypeKind::Generic { name, args } => SimpleType::Generic {
            name: name.clone(),
            args: args
                .iter()
                .map(|arg| simple_type_from_hir_type(arg, params))
                .collect(),
        },
        HirTypeKind::Ref { inner } => {
            SimpleType::Ref(Box::new(simple_type_from_hir_type(inner, params)))
        }
        HirTypeKind::Slice { elem } => {
            SimpleType::Slice(Box::new(simple_type_from_hir_type(elem, params)))
        }
        HirTypeKind::Array { elem, len } => SimpleType::Array {
            elem: Box::new(simple_type_from_hir_type(elem, params)),
            len: len.clone(),
        },
    }
}

fn trait_type_parts(ty: &SimpleType) -> Option<(&str, Vec<SimpleType>)> {
    match ty {
        SimpleType::Named(name) => Some((name.as_str(), Vec::new())),
        SimpleType::Generic { name, args } => Some((name.as_str(), args.clone())),
        _ => None,
    }
}

fn primitive_simple_type(name: &str) -> Option<SimpleType> {
    match name {
        "bool" => Some(SimpleType::Bool),
        "i8" | "i16" | "i32" | "i64" | "isize" => Some(SimpleType::Int),
        "u8" | "u16" | "u32" | "u64" | "usize" => Some(SimpleType::UInt),
        "f32" | "f64" => Some(SimpleType::Float),
        "char" => Some(SimpleType::Char),
        "str" => Some(SimpleType::String),
        _ => None,
    }
}

fn substitute_simple_type(
    ty: &SimpleType,
    substitutions: &HashMap<String, SimpleType>,
) -> SimpleType {
    match ty {
        SimpleType::Param(name) => substitutions
            .get(name)
            .cloned()
            .unwrap_or_else(|| ty.clone()),
        SimpleType::Generic { name, args } => SimpleType::Generic {
            name: name.clone(),
            args: args
                .iter()
                .map(|arg| substitute_simple_type(arg, substitutions))
                .collect(),
        },
        SimpleType::Ref(inner) => {
            SimpleType::Ref(Box::new(substitute_simple_type(inner, substitutions)))
        }
        SimpleType::Slice(elem) => {
            SimpleType::Slice(Box::new(substitute_simple_type(elem, substitutions)))
        }
        SimpleType::Array { elem, len } => SimpleType::Array {
            elem: Box::new(substitute_simple_type(elem, substitutions)),
            len: len.clone(),
        },
        _ => ty.clone(),
    }
}

fn unify_simple_type(
    pattern: &SimpleType,
    actual: &SimpleType,
    substitutions: &mut HashMap<String, SimpleType>,
) {
    match (pattern, actual) {
        (SimpleType::Param(name), actual) if *actual != SimpleType::Unknown => {
            substitutions
                .entry(name.clone())
                .or_insert_with(|| actual.clone());
        }
        (
            SimpleType::Generic {
                name: pattern_name,
                args: pattern_args,
            },
            SimpleType::Generic {
                name: actual_name,
                args: actual_args,
            },
        ) if pattern_name == actual_name => {
            for (pattern_arg, actual_arg) in pattern_args.iter().zip(actual_args.iter()) {
                unify_simple_type(pattern_arg, actual_arg, substitutions);
            }
        }
        (SimpleType::Ref(pattern_inner), SimpleType::Ref(actual_inner))
        | (SimpleType::Slice(pattern_inner), SimpleType::Slice(actual_inner)) => {
            unify_simple_type(pattern_inner, actual_inner, substitutions);
        }
        (
            SimpleType::Slice(pattern_inner),
            SimpleType::Array {
                elem: actual_inner, ..
            },
        ) => {
            unify_simple_type(pattern_inner, actual_inner, substitutions);
        }
        (
            SimpleType::Array {
                elem: pattern_elem, ..
            },
            SimpleType::Array {
                elem: actual_elem, ..
            },
        ) => unify_simple_type(pattern_elem, actual_elem, substitutions),
        _ => {}
    }
}

fn enum_pattern_can_match(scrutinee: &SimpleType, enum_name: &str) -> bool {
    match scrutinee {
        SimpleType::Unknown => true,
        SimpleType::Named(name) | SimpleType::Generic { name, .. } => name == enum_name,
        _ => false,
    }
}

fn ensure_types_compatible(
    expected: &SimpleType,
    actual: &SimpleType,
    span: crate::hir::Span,
    context: &str,
) -> Result<(), CompileError> {
    if simple_types_compatible(expected, actual) {
        return Ok(());
    }
    Err(CompileError::GpuTypeCheck(format!(
        "{context} type mismatch at byte {}: expected {}, got {}",
        span.start,
        simple_type_label(expected),
        simple_type_label(actual)
    )))
}

fn simple_types_compatible(expected: &SimpleType, actual: &SimpleType) -> bool {
    if matches!(expected, SimpleType::Unknown) || matches!(actual, SimpleType::Unknown) {
        return true;
    }
    if expected == actual {
        return true;
    }
    matches!(
        (expected, actual),
        (SimpleType::Int, SimpleType::UInt | SimpleType::Char)
            | (SimpleType::UInt, SimpleType::Int | SimpleType::Char)
            | (
                SimpleType::Float,
                SimpleType::Int | SimpleType::UInt | SimpleType::Char
            )
            | (SimpleType::Char, SimpleType::Int | SimpleType::UInt)
    ) || match (expected, actual) {
        (
            SimpleType::Generic {
                name: expected_name,
                args: expected_args,
            },
            SimpleType::Generic {
                name: actual_name,
                args: actual_args,
            },
        ) if expected_name == actual_name && expected_args.len() == actual_args.len() => {
            expected_args
                .iter()
                .zip(actual_args.iter())
                .all(|(expected_arg, actual_arg)| simple_types_compatible(expected_arg, actual_arg))
        }
        (SimpleType::Ref(expected_inner), SimpleType::Ref(actual_inner))
        | (SimpleType::Slice(expected_inner), SimpleType::Slice(actual_inner)) => {
            simple_types_compatible(expected_inner, actual_inner)
        }
        (
            SimpleType::Slice(expected_inner),
            SimpleType::Array {
                elem: actual_inner, ..
            },
        ) => simple_types_compatible(expected_inner, actual_inner),
        (
            SimpleType::Array {
                elem: expected_elem,
                len: expected_len,
            },
            SimpleType::Array {
                elem: actual_elem,
                len: actual_len,
            },
        ) => {
            (expected_len == actual_len || expected_len == "?" || actual_len == "?")
                && simple_types_compatible(expected_elem, actual_elem)
        }
        _ => false,
    }
}

fn simple_types_compatible_for_function(
    expected: &SimpleType,
    actual: &SimpleType,
    const_params: &[String],
) -> bool {
    if matches!(expected, SimpleType::Unknown) || matches!(actual, SimpleType::Unknown) {
        return true;
    }
    if matches!(expected, SimpleType::Param(_)) || matches!(actual, SimpleType::Param(_)) {
        return true;
    }
    if expected == actual {
        return true;
    }
    match (expected, actual) {
        (
            SimpleType::Generic {
                name: expected_name,
                args: expected_args,
            },
            SimpleType::Generic {
                name: actual_name,
                args: actual_args,
            },
        ) if expected_name == actual_name && expected_args.len() == actual_args.len() => {
            expected_args
                .iter()
                .zip(actual_args.iter())
                .all(|(expected_arg, actual_arg)| {
                    simple_types_compatible_for_function(expected_arg, actual_arg, const_params)
                })
        }
        (SimpleType::Ref(expected_inner), SimpleType::Ref(actual_inner))
        | (SimpleType::Slice(expected_inner), SimpleType::Slice(actual_inner)) => {
            simple_types_compatible_for_function(expected_inner, actual_inner, const_params)
        }
        (
            SimpleType::Slice(expected_inner),
            SimpleType::Array {
                elem: actual_inner, ..
            },
        ) => simple_types_compatible_for_function(expected_inner, actual_inner, const_params),
        (
            SimpleType::Array {
                elem: expected_elem,
                len: expected_len,
            },
            SimpleType::Array {
                elem: actual_elem,
                len: actual_len,
            },
        ) => {
            array_lengths_compatible_for_function(expected_len, actual_len, const_params)
                && simple_types_compatible_for_function(expected_elem, actual_elem, const_params)
        }
        _ => simple_types_compatible(expected, actual),
    }
}

fn trait_bound_types_compatible(expected: &SimpleType, actual: &SimpleType) -> bool {
    if matches!(expected, SimpleType::Unknown) || matches!(actual, SimpleType::Unknown) {
        return true;
    }
    if expected == actual {
        return true;
    }
    match (expected, actual) {
        (SimpleType::Param(expected), SimpleType::Param(actual)) => expected == actual,
        (
            SimpleType::Generic {
                name: expected_name,
                args: expected_args,
            },
            SimpleType::Generic {
                name: actual_name,
                args: actual_args,
            },
        ) if expected_name == actual_name && expected_args.len() == actual_args.len() => {
            expected_args
                .iter()
                .zip(actual_args.iter())
                .all(|(expected_arg, actual_arg)| {
                    trait_bound_types_compatible(expected_arg, actual_arg)
                })
        }
        (SimpleType::Ref(expected_inner), SimpleType::Ref(actual_inner))
        | (SimpleType::Slice(expected_inner), SimpleType::Slice(actual_inner)) => {
            trait_bound_types_compatible(expected_inner, actual_inner)
        }
        (
            SimpleType::Slice(expected_inner),
            SimpleType::Array {
                elem: actual_inner, ..
            },
        ) => trait_bound_types_compatible(expected_inner, actual_inner),
        (
            SimpleType::Array {
                elem: expected_elem,
                len: expected_len,
            },
            SimpleType::Array {
                elem: actual_elem,
                len: actual_len,
            },
        ) => {
            (expected_len == actual_len || expected_len == "?" || actual_len == "?")
                && trait_bound_types_compatible(expected_elem, actual_elem)
        }
        (SimpleType::Param(_), _) | (_, SimpleType::Param(_)) => false,
        _ => simple_types_compatible(expected, actual),
    }
}

fn array_lengths_compatible_for_function(
    expected_len: &str,
    actual_len: &str,
    const_params: &[String],
) -> bool {
    expected_len == actual_len
        || expected_len == "?"
        || actual_len == "?"
        || const_params.iter().any(|param| param == expected_len)
        || const_params.iter().any(|param| param == actual_len)
}

fn dummy_expr_for_type(ty: &SimpleType) -> Option<String> {
    match ty {
        SimpleType::Bool => Some("false".to_string()),
        SimpleType::Int | SimpleType::UInt | SimpleType::Char => Some("0".to_string()),
        SimpleType::Float => Some("0.0".to_string()),
        SimpleType::String => Some(r#""""#.to_string()),
        SimpleType::Array { elem, len } => {
            let len = len.parse::<usize>().ok()?;
            if len > 64 {
                return None;
            }
            let elem = dummy_expr_for_type(elem)?;
            Some(format!("[{}]", vec![elem; len].join(", ")))
        }
        _ => None,
    }
}

fn dummy_expr_for_type_in_env(ty: &SimpleType, env: &TypeEnv) -> Option<String> {
    dummy_expr_for_type(ty).or_else(|| {
        let mut candidates = env.iter().collect::<Vec<_>>();
        candidates.sort_by(|(left, _), (right, _)| left.cmp(right));
        candidates
            .into_iter()
            .find(|(_, candidate_ty)| simple_types_compatible(ty, candidate_ty))
            .map(|(name, _)| name.clone())
    })
}

fn simple_type_label(ty: &SimpleType) -> String {
    match ty {
        SimpleType::Unknown => "unknown".to_string(),
        SimpleType::Void => "void".to_string(),
        SimpleType::Bool => "bool".to_string(),
        SimpleType::Int => "int".to_string(),
        SimpleType::UInt => "uint".to_string(),
        SimpleType::Float => "float".to_string(),
        SimpleType::Char => "char".to_string(),
        SimpleType::String => "str".to_string(),
        SimpleType::Param(name) | SimpleType::Named(name) => name.clone(),
        SimpleType::Generic { name, args } => format!(
            "{name}<{}>",
            args.iter()
                .map(simple_type_label)
                .collect::<Vec<_>>()
                .join(", ")
        ),
        SimpleType::Ref(inner) => format!("&{}", simple_type_label(inner)),
        SimpleType::Slice(elem) => format!("[{}]", simple_type_label(elem)),
        SimpleType::Array { elem, len } => format!("[{}; {len}]", simple_type_label(elem)),
    }
}

fn simple_type_source_name(ty: &SimpleType) -> String {
    match ty {
        SimpleType::Unknown | SimpleType::Int => "i32".to_string(),
        SimpleType::Void => String::new(),
        SimpleType::Bool => "bool".to_string(),
        SimpleType::UInt => "u32".to_string(),
        SimpleType::Float => "f32".to_string(),
        SimpleType::Char => "char".to_string(),
        SimpleType::String => "str".to_string(),
        SimpleType::Param(_) => "i32".to_string(),
        SimpleType::Named(name) => name.clone(),
        SimpleType::Generic { name, args } => format!(
            "{name}<{}>",
            args.iter()
                .map(simple_type_source_name)
                .collect::<Vec<_>>()
                .join(", ")
        ),
        SimpleType::Ref(inner) => format!("&{}", simple_type_source_name(inner)),
        SimpleType::Slice(elem) => format!("[{}]", simple_type_source_name(elem)),
        SimpleType::Array { elem, len } => format!("[{}; {len}]", simple_type_source_name(elem)),
    }
}

fn parse_import_directive(line: &str) -> Result<Option<ImportSpec>, String> {
    let trimmed = line.trim();
    let Some(rest) = trimmed.strip_prefix("import") else {
        return Ok(None);
    };
    if !rest.starts_with(char::is_whitespace) {
        return Ok(None);
    }
    let rest = rest.trim_start();
    if let Some(rest) = rest.strip_prefix('"') {
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
        return Ok(Some(ImportSpec::Path(spec.to_string())));
    }

    let Some(module) = rest.strip_suffix(';') else {
        return Err("expected `;` after import module".to_string());
    };
    let module = module.trim();
    if !is_valid_import_module(module) {
        return Err("expected import path string or module path".to_string());
    }
    Ok(Some(ImportSpec::Module(module.to_string())))
}

fn parse_module_directive(line: &str) -> Result<Option<String>, String> {
    let trimmed = line.trim();
    let Some(rest) = trimmed.strip_prefix("module") else {
        return Ok(None);
    };
    if !rest.starts_with(char::is_whitespace) {
        return Ok(None);
    }
    let Some(module) = rest.trim_start().strip_suffix(';') else {
        return Err("expected `;` after module path".to_string());
    };
    let module = module.trim();
    if !is_valid_import_module(module) {
        return Err("expected module path".to_string());
    }
    Ok(Some(module.to_string()))
}

fn is_valid_import_module(module: &str) -> bool {
    if module.is_empty() || !module.contains("::") {
        return false;
    }
    module.split("::").all(is_valid_module_segment)
}

fn is_valid_module_segment(segment: &str) -> bool {
    let mut chars = segment.chars();
    let Some(first) = chars.next() else {
        return false;
    };
    (first == '_' || first.is_ascii_alphabetic())
        && chars.all(|ch| ch == '_' || ch.is_ascii_alphanumeric())
}

fn scan_module_info(
    src: &str,
    context: &ImportContext,
) -> Result<Option<ModuleInfo>, CompileError> {
    let mut module: Option<String> = None;
    let mut decls = ModuleDecls::default();

    for (line_index, line) in src.lines().enumerate() {
        match parse_module_directive(line) {
            Ok(Some(module_path)) => {
                if module.replace(module_path).is_some() {
                    return Err(CompileError::Import(format!(
                        "duplicate module declaration at {}:{}",
                        context.display(),
                        line_index + 1
                    )));
                }
            }
            Ok(None) => {}
            Err(err) => {
                return Err(CompileError::Import(format!(
                    "{err} at {}:{}",
                    context.display(),
                    line_index + 1
                )));
            }
        }

        if let Some((public, name)) = parse_module_member_decl(line) {
            decls.all.insert(name.clone());
            if public {
                decls.public.insert(name);
            }
        }
    }

    if module.is_some() {
        if let Ok(file) = parse_source(src) {
            decls = collect_module_decls_from_hir(&file);
        }
    }

    Ok(module.map(|path| ModuleInfo { path, decls }))
}

fn collect_module_decls_from_hir(file: &HirFile) -> ModuleDecls {
    let mut decls = ModuleDecls::default();
    for item in &file.items {
        match item {
            HirItem::Fn(function) => {
                insert_module_decl(&mut decls, &function.name, function.public);
            }
            HirItem::ExternFn(function) => {
                insert_module_decl(&mut decls, &function.name, function.public);
            }
            HirItem::Const(constant) => {
                insert_module_decl(&mut decls, &constant.name, constant.public);
            }
            HirItem::TypeAlias(alias) => {
                insert_module_decl(&mut decls, &alias.name, alias.public);
            }
            HirItem::Enum(enumeration) => {
                insert_module_decl(&mut decls, &enumeration.name, enumeration.public);
                for variant in &enumeration.variants {
                    insert_module_decl(&mut decls, &variant.name, enumeration.public);
                }
            }
            HirItem::Struct(structure) => {
                insert_module_decl(&mut decls, &structure.name, structure.public);
            }
            HirItem::Trait(trait_item) => {
                insert_module_decl(&mut decls, &trait_item.name, trait_item.public);
            }
            HirItem::Import(_) | HirItem::Module(_) | HirItem::Impl(_) | HirItem::Stmt(_) => {}
        }
    }
    decls
}

fn insert_module_decl(decls: &mut ModuleDecls, name: &str, public: bool) {
    decls.all.insert(name.to_string());
    if public {
        decls.public.insert(name.to_string());
    }
}

fn parse_module_member_decl(line: &str) -> Option<(bool, String)> {
    let tokens = lex_on_cpu(line).ok()?;
    let (public, name_i) = module_decl_name_index(&tokens)?;
    let name_token = tokens.get(name_i)?;
    if !is_path_segment_token(name_token.kind) {
        return None;
    }
    Some((public, token_text(line, name_token).to_string()))
}

fn module_decl_name_index(tokens: &[crate::lexer::cpu::CpuToken]) -> Option<(bool, usize)> {
    let first = tokens.first()?;
    if first.kind == TokenKind::Pub {
        let keyword = tokens.get(1).map(|token| token.kind)?;
        if matches!(
            keyword,
            TokenKind::Fn
                | TokenKind::Const
                | TokenKind::Type
                | TokenKind::Enum
                | TokenKind::Struct
                | TokenKind::Trait
        ) {
            return Some((true, 2));
        }
        if keyword == TokenKind::Extern {
            let offset = match tokens.get(2).map(|token| token.kind) {
                Some(TokenKind::Fn) => 3,
                Some(TokenKind::String)
                    if tokens.get(3).map(|token| token.kind) == Some(TokenKind::Fn) =>
                {
                    4
                }
                _ => return None,
            };
            return Some((true, offset));
        }
        return None;
    }

    if matches!(
        first.kind,
        TokenKind::Fn
            | TokenKind::Const
            | TokenKind::Type
            | TokenKind::Enum
            | TokenKind::Struct
            | TokenKind::Trait
    ) {
        return Some((false, 1));
    }
    if first.kind == TokenKind::Extern {
        let offset = match tokens.get(1).map(|token| token.kind) {
            Some(TokenKind::Fn) => 2,
            Some(TokenKind::String)
                if tokens.get(2).map(|token| token.kind) == Some(TokenKind::Fn) =>
            {
                3
            }
            _ => return None,
        };
        return Some((false, offset));
    }

    None
}

fn rewrite_module_line(line: &str, module: &ModuleInfo) -> Result<String, CompileError> {
    let Ok(tokens) = lex_on_cpu(line) else {
        return Ok(line.to_string());
    };
    let decl_name_i = module_decl_name_index(&tokens).map(|(_, index)| index);
    let mut replacements = Vec::new();

    for (i, token) in tokens.iter().enumerate() {
        if !is_path_segment_token(token.kind) {
            continue;
        }
        let name = token_text(line, token);
        if !module.decls.all.contains(name) {
            continue;
        }
        if skip_unqualified_module_member_rewrite(&tokens, i, decl_name_i) {
            continue;
        }
        replacements.push((
            token.start,
            token.start.saturating_add(token.len),
            mangle_module_member(&module.path, name),
        ));
    }

    Ok(apply_replacements(line, replacements))
}

fn skip_unqualified_module_member_rewrite(
    tokens: &[crate::lexer::cpu::CpuToken],
    index: usize,
    decl_name_i: Option<usize>,
) -> bool {
    if Some(index) == decl_name_i {
        return false;
    }

    if token_before_is_path_separator(tokens, index) || token_after_is_path_separator(tokens, index)
    {
        return true;
    }

    let prev = index.checked_sub(1).and_then(|i| tokens.get(i));
    let next = tokens.get(index + 1);

    if prev.is_some_and(|token| matches!(token.kind, TokenKind::Let | TokenKind::Dot)) {
        return true;
    }

    if next.is_some_and(|token| token.kind == TokenKind::Colon) {
        return true;
    }

    false
}

fn token_before_is_path_separator(tokens: &[crate::lexer::cpu::CpuToken], index: usize) -> bool {
    index >= 2
        && tokens[index - 2].kind == TokenKind::Colon
        && tokens[index - 1].kind == TokenKind::Colon
}

fn token_after_is_path_separator(tokens: &[crate::lexer::cpu::CpuToken], index: usize) -> bool {
    tokens
        .get(index + 1)
        .is_some_and(|token| token.kind == TokenKind::Colon)
        && tokens
            .get(index + 2)
            .is_some_and(|token| token.kind == TokenKind::Colon)
}

fn rewrite_namespaced_paths(
    src: &str,
    modules: &HashMap<String, ModuleDecls>,
    current_module: Option<&ModuleInfo>,
) -> Result<String, CompileError> {
    let Ok(tokens) = lex_on_cpu(src) else {
        return Ok(src.to_string());
    };
    let mut replacements = Vec::new();
    let mut i = 0usize;

    while i < tokens.len() {
        if !is_path_segment_token(tokens[i].kind) {
            i += 1;
            continue;
        }

        let mut segments = vec![token_text(src, &tokens[i]).to_string()];
        let start = tokens[i].start;
        let mut end = tokens[i].start.saturating_add(tokens[i].len);
        let mut j = i + 1;

        while j + 2 < tokens.len()
            && tokens[j].kind == TokenKind::Colon
            && tokens[j + 1].kind == TokenKind::Colon
            && is_path_segment_token(tokens[j + 2].kind)
        {
            segments.push(token_text(src, &tokens[j + 2]).to_string());
            end = tokens[j + 2].start.saturating_add(tokens[j + 2].len);
            j += 3;
        }

        if segments.len() > 1 {
            validate_namespaced_visibility(&segments, modules, current_module)?;
            replacements.push((start, end, mangle_path_segments(&segments)));
            i = j;
        } else {
            i += 1;
        }
    }

    Ok(apply_replacements(src, replacements))
}

fn validate_namespaced_visibility(
    segments: &[String],
    modules: &HashMap<String, ModuleDecls>,
    current_module: Option<&ModuleInfo>,
) -> Result<(), CompileError> {
    let Some((member, module_segments)) = segments.split_last() else {
        return Ok(());
    };
    let module_path = module_segments.join("::");

    if let Some(current) = current_module {
        if current.path == module_path {
            return Ok(());
        }
    }

    if let Some(decls) = modules.get(&module_path) {
        if decls.all.contains(member) && !decls.public.contains(member) {
            return Err(CompileError::Import(format!(
                "module member `{module_path}::{member}` is private"
            )));
        }
    }

    Ok(())
}

fn is_path_segment_token(kind: TokenKind) -> bool {
    matches!(
        kind,
        TokenKind::Ident | TokenKind::TypeIdent | TokenKind::ParamIdent | TokenKind::LetIdent
    )
}

fn token_text<'a>(src: &'a str, token: &crate::lexer::cpu::CpuToken) -> &'a str {
    src.get(token.start..token.start.saturating_add(token.len))
        .unwrap_or("")
}

fn mangle_module_member(module: &str, name: &str) -> String {
    let mut segments = module.split("::").map(str::to_string).collect::<Vec<_>>();
    segments.push(name.to_string());
    mangle_path_segments(&segments)
}

fn mangle_path_segments(segments: &[String]) -> String {
    let mut mangled = String::from("__lanius");
    for segment in segments {
        mangled.push('_');
        mangled.push_str(segment);
    }
    mangled
}

fn apply_replacements(src: &str, mut replacements: Vec<(usize, usize, String)>) -> String {
    if replacements.is_empty() {
        return src.to_string();
    }

    replacements.sort_by_key(|(start, _, _)| *start);
    let mut out = String::with_capacity(src.len());
    let mut cursor = 0usize;
    for (start, end, replacement) in replacements {
        if start < cursor || end < start || end > src.len() {
            continue;
        }
        out.push_str(&src[cursor..start]);
        out.push_str(&replacement);
        cursor = end;
    }
    out.push_str(&src[cursor..]);
    out
}

fn manifest_root() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn codegen_lowering_encodes_option_and_result_seed_helpers() {
        let src = r#"
import core::option;
import core::result;

fn main() {
    let some: core::option::Option<i32> = core::option::Some(7);
    let none: core::option::Option<i32> = core::option::None;
    let ok: core::result::Result<i32, i32> = core::result::Ok(9);
    let err: core::result::Result<i32, i32> = core::result::Err(4);
    print(core::option::unwrap_or(some, 0));
    print(core::option::unwrap_or(none, 5));
    print(core::result::unwrap_or(ok, 0));
    print(core::result::unwrap_or(err, 6));
    return 0;
}
"#;

        let lowered = prepare_source_for_gpu_codegen(src).expect("lower sum types for codegen");

        assert!(lowered.contains("pub fn __lanius_core_option_is_some<T>(value: i32) -> bool"));
        assert!(lowered.contains(
            "pub fn __lanius_core_option_unwrap_or<T>(value: i32, fallback: i32) -> i32"
        ));
        assert!(lowered.contains(
            "pub fn __lanius_core_result_unwrap_or<T, E>(value: i32, fallback: i32) -> i32"
        ));
        assert!(lowered.contains("if (value % 2 == 1) { return true; } else { return false; }"));
        assert!(lowered.contains("return (value >> 1);"));
        assert!(lowered.contains("let some: i32 = ((7 << 1) | 1);"));
        assert!(lowered.contains("let none: i32 = 0;"));
        assert!(lowered.contains("let ok: i32 = ((9 << 1) | 1);"));
        assert!(lowered.contains("let err: i32 = (4 << 1);"));
    }

    #[test]
    fn codegen_lowering_encodes_unit_enum_variants() {
        let src = r#"
import core::ordering;

fn main() {
    let less: core::ordering::Ordering = core::ordering::Less;
    let equal: core::ordering::Ordering = core::ordering::Equal;
    let greater: core::ordering::Ordering = core::ordering::Greater;
    print(less);
    print(equal);
    print(greater);
    return 0;
}
"#;

        let lowered = prepare_source_for_gpu_codegen(src).expect("lower unit enum for codegen");

        assert!(
            lowered.contains(
                "pub fn __lanius_core_ordering_compare_i32(left: i32, right: i32) -> i32"
            )
        );
        assert!(lowered.contains("let less: i32 = 0;"));
        assert!(lowered.contains("let equal: i32 = 1;"));
        assert!(lowered.contains("let greater: i32 = 2;"));
        assert!(lowered.contains("return 0;"));
        assert!(lowered.contains("return 1;"));
        assert!(lowered.contains("return 2;"));
    }
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
    let src = prepare_source_for_gpu_codegen(src)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}
