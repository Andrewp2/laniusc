use std::{
    collections::HashSet,
    fs,
    path::{Path, PathBuf},
    sync::OnceLock,
};

use crate::{
    codegen::{gpu_wasm, gpu_x86},
    gpu::device::{self, GpuDevice},
    lexer::{cpu::lex_on_cpu, gpu::driver::GpuLexer, tables::tokens::TokenKind},
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

enum ImportSpec {
    Path(String),
    Module(String),
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

    fn expand_source(
        &mut self,
        src: &str,
        context: ImportContext,
        imported: bool,
    ) -> Result<String, CompileError> {
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
                        if let Some(module) = &module {
                            rewrite_module_decl_name(line, module)?
                        } else {
                            line.to_string()
                        }
                    } else {
                        line.to_string()
                    };
                    let line = rewrite_namespaced_paths(&line)?;
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

fn rewrite_module_decl_name(line: &str, module: &str) -> Result<String, CompileError> {
    let Ok(tokens) = lex_on_cpu(line) else {
        return Ok(line.to_string());
    };
    let Some(first) = tokens.first() else {
        return Ok(line.to_string());
    };

    let name_i = if first.kind == TokenKind::Pub {
        let Some(keyword) = tokens.get(1).map(|token| token.kind) else {
            return Ok(line.to_string());
        };
        if matches!(
            keyword,
            TokenKind::Fn | TokenKind::Const | TokenKind::Enum | TokenKind::Struct
        ) {
            Some(2)
        } else {
            None
        }
    } else if matches!(
        first.kind,
        TokenKind::Fn | TokenKind::Const | TokenKind::Enum | TokenKind::Struct
    ) {
        Some(1)
    } else {
        None
    };

    let Some(name_i) = name_i else {
        return Ok(line.to_string());
    };
    let Some(name_token) = tokens.get(name_i) else {
        return Ok(line.to_string());
    };
    if !is_path_segment_token(name_token.kind) {
        return Ok(line.to_string());
    }

    let name = line
        .get(name_token.start..name_token.start.saturating_add(name_token.len))
        .unwrap_or("");
    let replacement = mangle_module_member(module, name);
    Ok(apply_replacements(
        line,
        vec![(
            name_token.start,
            name_token.start.saturating_add(name_token.len),
            replacement,
        )],
    ))
}

fn rewrite_namespaced_paths(src: &str) -> Result<String, CompileError> {
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
            replacements.push((start, end, mangle_path_segments(&segments)));
            i = j;
        } else {
            i += 1;
        }
    }

    Ok(apply_replacements(src, replacements))
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
