// src/compiler/gpu_compiler/typecheck.rs

use super::*;
use crate::{
    gpu::buffers::LaniusBuffer,
    lexer::{
        types::{GpuToken, Token},
        util::read_tokens_from_mapped,
    },
    type_checker::{GpuTypeCheckCode, GpuTypeCheckError},
};

#[derive(Clone, Copy)]
enum DependencyInterfacePages<'a> {
    Flat(&'a [crate::compiler::GpuSemanticInterfaceArtifact]),
    Paged(&'a [Vec<crate::compiler::GpuSemanticInterfaceArtifact>]),
}

#[derive(Clone, Copy, PartialEq, Eq)]
enum FrontendWorkspaceReplacement {
    Lexer,
    Parser,
}

#[derive(Clone, Copy)]
struct ParserBoundaryInput<'a> {
    token_capacity: u32,
    token_buffer: &'a wgpu::Buffer,
    token_count_buffer: &'a wgpu::Buffer,
    token_file_id_buffer: Option<&'a wgpu::Buffer>,
    source_capacity: u32,
    source_buffer: &'a wgpu::Buffer,
}

impl<'a> DependencyInterfacePages<'a> {
    fn is_empty(self) -> bool {
        match self {
            Self::Flat(interfaces) => interfaces.is_empty(),
            Self::Paged(pages) => pages.iter().all(Vec::is_empty),
        }
    }

    fn slices(self) -> Vec<&'a [crate::compiler::GpuSemanticInterfaceArtifact]> {
        match self {
            Self::Flat(interfaces) if interfaces.is_empty() => Vec::new(),
            Self::Flat(interfaces) => vec![interfaces],
            Self::Paged(pages) => pages
                .iter()
                .filter(|page| !page.is_empty())
                .map(Vec::as_slice)
                .collect(),
        }
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    fn release_for_frontend_workspace_replacement(
        &self,
        device: &wgpu::Device,
        replacement: FrontendWorkspaceReplacement,
    ) {
        self.type_checker.release_current_resident_workspace();
        if let Ok(cache) = &self.wasm_lowering {
            cache.release();
        }
        if let Ok(cache) = &self.x86_lowering {
            cache.release();
        }
        self.parser.release_current_resident_buffers();
        if replacement == FrontendWorkspaceReplacement::Lexer {
            self.lexer.release_current_resident_buffers();
        }
        crate::gpu::passes_core::release_reflected_bind_group_caches();
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
    }

    fn run_parser_boundary(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: ParserBoundaryInput<'_>,
        tree_capacity: u32,
        parser_feature_flags: u32,
        submission_label: &'static str,
        host_timer: &mut CompilerHostTimer,
    ) -> anyhow::Result<crate::parser::driver::Ll1AcceptResult> {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some(submission_label),
        });
        let timing_enabled = crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
            && device.features().contains(wgpu::Features::TIMESTAMP_QUERY);
        let mut owned_parser_timer = timing_enabled.then(|| GpuTimer::new(device, queue, 2_048));
        if let Some(timer) = owned_parser_timer.as_mut() {
            timer.stamp(&mut encoder, "parser.begin");
        }
        let mut parser_timer = owned_parser_timer.as_mut();
        let (check, recorded) = self
            .parser
            .record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features(
                &mut encoder,
                input.token_capacity,
                input.token_buffer,
                input.token_count_buffer,
                input.token_file_id_buffer,
                input.source_capacity,
                input.source_buffer,
                &self.parse_tables,
                Some(tree_capacity),
                parser_feature_flags,
                &mut parser_timer,
                |_parse_bufs, encoder, timer| {
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "parser.ll1_hir.done");
                    }
                    Ok::<_, anyhow::Error>(())
                },
            )?;
        recorded?;
        drop(parser_timer);
        host_timer.stamp("parser_record");
        if let Some(timer) = owned_parser_timer.as_mut() {
            timer.stamp(&mut encoder, "parser.end");
            timer.resolve(&mut encoder);
        }
        let command_buffer = encoder.finish();
        host_timer.stamp("parser_encoder_finish");
        let gpu_anchor = std::time::Instant::now();
        crate::gpu::passes_core::submit_with_progress(queue, submission_label, command_buffer);
        host_timer.stamp("parser_submit");
        let result = check.read_status_result(device);
        host_timer.stamp("parser_status");
        if let Some(timer) = owned_parser_timer.as_ref()
            && let Some(stamps) = timer.try_read(device)
        {
            crate::lexer::driver::timing::print_timer_trace(&stamps, timer.period_ns(), gpu_anchor);
        }
        result
    }

    fn run_parser_boundary_with_capacity_reuse(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        input: ParserBoundaryInput<'_>,
        parser_feature_flags: u32,
        submission_label: &'static str,
        host_timer: &mut CompilerHostTimer,
    ) -> anyhow::Result<(u32, crate::parser::driver::Ll1AcceptResult)> {
        let reusable_capacity = self.parser.reusable_tree_capacity(
            input.token_capacity,
            input.source_capacity,
            &self.parse_tables,
            false,
            parser_feature_flags,
        );
        let tree_capacity = match reusable_capacity {
            Some(capacity) => capacity,
            None => {
                self.parser
                    .measure_resident_partial_parse_capacity(
                        input.token_capacity,
                        input.token_buffer,
                        input.token_count_buffer,
                        input.token_file_id_buffer,
                        &self.parse_tables,
                    )?
                    .tree_capacity
            }
        };
        host_timer.stamp(if reusable_capacity.is_some() {
            "parser_capacity_reused"
        } else {
            "parser_capacity_measured"
        });

        if !self.parser.current_resident_allocation_covers(
            input.token_capacity,
            input.source_capacity,
            &self.parse_tables,
            tree_capacity,
            false,
            parser_feature_flags,
        ) {
            self.release_for_frontend_workspace_replacement(
                device,
                FrontendWorkspaceReplacement::Parser,
            );
        }
        let mut result = self.run_parser_boundary(
            device,
            queue,
            input,
            tree_capacity,
            parser_feature_flags,
            submission_label,
            host_timer,
        )?;

        if !result.accepted && result.error_code == 3 && result.detail > tree_capacity {
            let grown_capacity = result.detail;
            self.release_for_frontend_workspace_replacement(
                device,
                FrontendWorkspaceReplacement::Parser,
            );
            result = self.run_parser_boundary(
                device,
                queue,
                input,
                grown_capacity,
                parser_feature_flags,
                submission_label,
                host_timer,
            )?;
            host_timer.stamp("parser_capacity_retry");
            return Ok((grown_capacity, result));
        }
        Ok((tree_capacity, result))
    }

    /// Type-check one in-memory source string using `<source>` as the diagnostic
    /// path.
    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.type_check_expanded_source_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    /// Read a source file from disk and type-check it with diagnostics labeled
    /// by that path.
    pub async fn type_check_source_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.type_check_expanded_source_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    /// Type-check an in-memory source pack after validating it fits the bounded
    /// default codegen-unit limits.
    pub async fn type_check_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "type check source pack",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack(sources).await
    }

    /// Type-checks one bounded library against already-materialized dependency
    /// semantic interfaces.
    pub async fn type_check_source_pack_with_dependencies<S: AsRef<str>>(
        &self,
        library_id: u32,
        sources: &[S],
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<(), CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "type check source pack with dependencies",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            0,
            DependencyInterfacePages::Flat(dependency_interfaces),
            false,
            None,
            None,
        )
        .await
        .map(|_| ())
    }

    /// Type-checks one bounded library unit and exports its complete canonical
    /// public semantic interface.
    pub async fn semantic_interface_for_source_pack<S: AsRef<str>>(
        &self,
        library_id: u32,
        sources: &[S],
    ) -> Result<crate::compiler::GpuSemanticInterfaceArtifact, CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "semantic interface source pack",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            0,
            DependencyInterfacePages::Flat(&[]),
            true,
            None,
            None,
        )
        .await?
        .semantic_interface
        .ok_or_else(|| {
            CompileError::GpuFrontend(
                "semantic-interface export did not produce an artifact".to_string(),
            )
        })
    }

    /// Type-checks one bounded library against persisted dependency interfaces
    /// and exports its own complete canonical public interface.
    pub async fn semantic_interface_for_source_pack_with_dependencies<S: AsRef<str>>(
        &self,
        library_id: u32,
        sources: &[S],
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<crate::compiler::GpuSemanticInterfaceArtifact, CompileError> {
        self.semantic_interface_for_source_pack_unit_with_dependencies(
            library_id,
            0,
            sources,
            dependency_interfaces,
        )
        .await
    }

    /// Exports one bounded frontend unit with its source-pack-global unit id.
    pub(in crate::compiler) async fn semantic_interface_for_source_pack_unit_with_dependencies<
        S: AsRef<str>,
    >(
        &self,
        library_id: u32,
        unit_id: u32,
        sources: &[S],
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<crate::compiler::GpuSemanticInterfaceArtifact, CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "semantic interface source pack with dependencies",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            unit_id,
            DependencyInterfacePages::Flat(dependency_interfaces),
            true,
            None,
            None,
        )
        .await?
        .semantic_interface
        .ok_or_else(|| {
            CompileError::GpuFrontend(
                "semantic-interface export did not produce an artifact".to_string(),
            )
        })
    }

    pub(in crate::compiler) async fn semantic_interface_for_source_pack_unit_with_dependency_pages<
        S: AsRef<str>,
    >(
        &self,
        library_id: u32,
        unit_id: u32,
        sources: &[S],
        dependency_pages: &[Vec<crate::compiler::GpuSemanticInterfaceArtifact>],
    ) -> Result<crate::compiler::GpuSemanticInterfaceArtifact, CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "semantic interface source pack with dependency pages",
            sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            unit_id,
            DependencyInterfacePages::Paged(dependency_pages),
            true,
            None,
            None,
        )
        .await?
        .semantic_interface
        .ok_or_else(|| {
            CompileError::GpuFrontend(
                "semantic-interface export did not produce an artifact".to_string(),
            )
        })
    }

    /// Type-check an explicit in-memory source-pack manifest and preserve any
    /// manifest source paths for diagnostics.
    pub async fn type_check_source_pack_manifest(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<(), CompileError> {
        validate_in_memory_source_pack_fits_codegen_unit(
            "type check source pack",
            &source_pack.sources,
            self.resident_source_unit_limits(),
        )?;
        self.type_check_explicit_source_pack_with_paths(
            &source_pack.sources,
            Some(&source_pack.source_paths),
        )
        .await
    }
    /// Type-checks already-prepared source text using the default synthetic path.
    pub(in crate::compiler) async fn type_check_expanded_source(
        &self,
        src: &str,
    ) -> Result<(), CompileError> {
        self.type_check_expanded_source_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }
    /// Type-checks one prepared source string while preserving a diagnostic path.
    pub(super) async fn type_check_expanded_source_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<(), CompileError> {
        self.compile_checked_source_with_lowering(src, diagnostic_path, None)
            .await
            .map(|_| ())
    }

    /// Shared production frontend boundary. A selected target appends the
    /// graph-owned semantic and target lowering passes to the same ordered job
    /// that produced the checked compact HIR. With no target this is the
    /// ordinary type-check operation.
    pub(super) async fn compile_checked_source_with_lowering(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
        target: Option<LoweringTarget>,
    ) -> Result<Option<Vec<u8>>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_feature_flags = crate::lexer::features::parser_allocation_features(
                        bufs.parser_feature_flags_value,
                    );
                    let mut parser_host_timer = CompilerHostTimer::new("compile.source.parser");
                    let (parser_tree_capacity, ll1) = self
                        .run_parser_boundary_with_capacity_reuse(
                            device,
                            queue,
                            ParserBoundaryInput {
                                token_capacity,
                                token_buffer: &bufs.tokens_out,
                                token_count_buffer: &bufs.token_count,
                                token_file_id_buffer: Some(&bufs.token_file_id),
                                source_capacity: bufs.n,
                                source_buffer: &bufs.in_bytes,
                            },
                            parser_feature_flags,
                            "compiler.typecheck.parser-boundary",
                            &mut parser_host_timer,
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source(&diagnostic_path, src, err)
                        })?;
                    if !ll1.accepted {
                        let parser_failure = self
                            .parser
                            .current_resident_parser_failure_for_ll1_rejection(
                                token_capacity,
                                &self.parse_tables,
                                Some(parser_tree_capacity),
                                ll1,
                            );
                        debug_parser_rejection(&parser_failure);
                        return Err(parser_failure_to_compile_error_for_source(
                            device,
                            queue,
                            &bufs.tokens_out.buffer,
                            src,
                            &diagnostic_path,
                            &parser_failure,
                        ));
                    }
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let (typecheck_hir, type_check) = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            |parse_bufs| {
                                let hir = crate::parser::buffers::GpuHirView::from_parser_buffers(
                                    parse_bufs,
                                );
                                let type_check = self.record_typecheck_from_parse_buffers(
                                    device,
                                    queue,
                                    encoder,
                                    bufs.n,
                                    1,
                                    token_capacity,
                                    bufs,
                                    parse_bufs,
                                    &hir,
                                    active_tree_capacity,
                                    parser_tree_capacity,
                                    None,
                                    timer.as_deref_mut(),
                                    |err| {
                                        type_check_execution_failed_for_source(
                                            &diagnostic_path,
                                            src,
                                            err,
                                        )
                                    },
                                )?;
                                Ok::<_, CompileError>((hir, type_check))
                            },
                        )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    if let Some(target) = target {
                        let pipeline = self
                            .ensure_lowering_pipeline(
                                target,
                                bufs.n,
                                token_capacity,
                                typecheck_hir.capacity,
                            )
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                        let semantic = self.type_checker.semantic_artifact().ok_or_else(|| {
                            CompileError::GpuCodegen(
                                "semantic lowering buffers are unavailable".into(),
                            )
                        })?;
                        pipeline
                            .record_checked_hir(device, encoder, &typecheck_hir, semantic.view())
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    }
                    Ok(type_check)
                },
                |device, queue, bufs, type_check| {
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| {
                            type_check_error_to_compile_error_for_source(
                                device,
                                queue,
                                bufs,
                                src,
                                &diagnostic_path,
                                err,
                            )
                        })?;
                    target
                        .map(|target| {
                            self.lowering_pipeline(target)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))?
                                .finish_artifact(device, queue)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                        })
                        .transpose()
                },
            )
            .await
            .map_err(|err| source_tokenization_failed_for_source(&diagnostic_path, src, err))?
    }
    /// Type-checks source-pack text without explicit diagnostic paths.
    pub(super) async fn type_check_explicit_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        self.type_check_explicit_source_pack_with_paths(sources, None)
            .await
    }

    /// Type-checks source-pack text with optional file paths for diagnostics.
    pub(super) async fn type_check_explicit_source_pack_with_paths<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<(), CompileError> {
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            source_paths,
            None,
            0,
            DependencyInterfacePages::Flat(&[]),
            false,
            None,
            None,
        )
        .await
        .map(|_| ())
    }

    /// Compiles one already-bounded source-pack unit through the same compact
    /// HIR and graph-owned lowering boundary used by a single source file.
    pub(super) async fn compile_checked_source_pack_with_lowering<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
        target: LoweringTarget,
    ) -> Result<Vec<u8>, CompileError> {
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            source_paths,
            None,
            0,
            DependencyInterfacePages::Flat(&[]),
            false,
            Some(target),
            None,
        )
        .await?
        .target_artifact
        .ok_or_else(|| CompileError::GpuCodegen("lowering produced no target artifact".into()))
    }

    /// Compiles one bounded unit once, producing both artifacts needed by the
    /// remaining project: its public semantic interface and its target object.
    pub(in crate::compiler) async fn compile_source_pack_unit_with_dependency_pages<
        S: AsRef<str>,
    >(
        &self,
        sources: &[S],
        library_id: u32,
        unit_id: u32,
        dependency_pages: &[Vec<crate::compiler::GpuSemanticInterfaceArtifact>],
        target: SourcePackArtifactTarget,
    ) -> Result<CompiledSourcePackUnit, CompileError> {
        if target == SourcePackArtifactTarget::X86_64 && sources.is_empty() {
            return Err(super::x86_codegen::x86_empty_source_pack_compile_error());
        }
        validate_in_memory_source_pack_fits_codegen_unit(
            "compile source-pack unit",
            sources,
            self.resident_source_unit_limits(),
        )?;
        let object_request = match target {
            SourcePackArtifactTarget::X86_64 => LoweringObjectRequest::X86_64 {
                library_id,
                unit_id,
            },
            SourcePackArtifactTarget::Wasm => LoweringObjectRequest::Wasm {
                library_id,
                unit_id,
            },
            SourcePackArtifactTarget::Generic => {
                return Err(CompileError::GpuCodegen(
                    "a compiled source-pack unit requires a concrete target".into(),
                ));
            }
        };
        let artifacts = self
            .type_check_explicit_source_pack_with_paths_and_interface(
                sources,
                None,
                Some(library_id),
                unit_id,
                DependencyInterfacePages::Paged(dependency_pages),
                true,
                None,
                Some(object_request),
            )
            .await?;
        let interface = artifacts.semantic_interface.ok_or_else(|| {
            CompileError::GpuFrontend(
                "compiled source-pack unit produced no semantic interface".into(),
            )
        })?;
        let object = match target {
            SourcePackArtifactTarget::X86_64 => {
                CompiledSourcePackObject::X86_64(artifacts.x86_object.ok_or_else(|| {
                    CompileError::GpuCodegen("lowering produced no x86 object".into())
                })?)
            }
            SourcePackArtifactTarget::Wasm => {
                CompiledSourcePackObject::Wasm(artifacts.wasm_object.ok_or_else(|| {
                    CompileError::GpuCodegen("lowering produced no Wasm object".into())
                })?)
            }
            SourcePackArtifactTarget::Generic => unreachable!(),
        };
        Ok(CompiledSourcePackUnit { interface, object })
    }

    async fn type_check_explicit_source_pack_with_paths_and_interface<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
        library_id: Option<u32>,
        unit_id: u32,
        dependency_interfaces: DependencyInterfacePages<'_>,
        emit_semantic_interface: bool,
        lowering_target: Option<LoweringTarget>,
        object_request: Option<LoweringObjectRequest>,
    ) -> Result<CheckedSourcePackArtifacts, CompileError> {
        let diagnostic_files = source_pack_diagnostic_files(sources, source_paths);
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        let source_bytes = sources.iter().try_fold(0u32, |total, source| {
            let len = u32::try_from(source.as_ref().len()).map_err(|_| {
                CompileError::GpuFrontend("source-pack file exceeds lexer capacity".to_string())
            })?;
            total.checked_add(len).ok_or_else(|| {
                CompileError::GpuFrontend("source-pack byte length exceeds lexer capacity".into())
            })
        })?;
        let source_files = u32::try_from(sources.len()).map_err(|_| {
            CompileError::GpuFrontend("source pack has too many files for the lexer".into())
        })?;
        if !self
            .lexer
            .current_resident_source_pack_capacity_covers(source_bytes, source_files)
        {
            self.release_for_frontend_workspace_replacement(
                &self.gpu.device,
                FrontendWorkspaceReplacement::Lexer,
            );
        }
        let dependency_page_slices = dependency_interfaces.slices();
        let dependency_pages = match library_id {
            Some(library_id) => Some(
                self.type_checker
                    .dependency_interface_pages(
                        &self.gpu.device,
                        &self.gpu.queue,
                        library_id,
                        unit_id,
                        &dependency_page_slices,
                    )
                    .map_err(|err| {
                        CompileError::GpuFrontend(format!(
                            "dependency semantic-interface preparation failed: {err}"
                        ))
                    })?,
            ),
            None if dependency_interfaces.is_empty() => None,
            None => {
                return Err(CompileError::GpuFrontend(
                    "dependency semantic interfaces require an owning library id".to_string(),
                ));
            }
        };
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut record_host_timer =
                        CompilerHostTimer::new("compile.source-pack.record");
                    let token_capacity = token_count.max(1);
                    let parser_feature_flags = crate::lexer::features::parser_allocation_features(
                        bufs.parser_feature_flags_value,
                    );
                    let (parser_tree_capacity, ll1) = self
                        .run_parser_boundary_with_capacity_reuse(
                            device,
                            queue,
                            ParserBoundaryInput {
                                token_capacity,
                                token_buffer: &bufs.tokens_out,
                                token_count_buffer: &bufs.token_count,
                                token_file_id_buffer: Some(&bufs.token_file_id),
                                source_capacity: bufs.n,
                                source_buffer: &bufs.in_bytes,
                            },
                            parser_feature_flags,
                            "compiler.typecheck.source_pack.parser-boundary",
                            &mut record_host_timer,
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source_pack(&diagnostic_files, err)
                        })?;
                    if !ll1.accepted {
                        let parser_failure = self
                            .parser
                            .current_resident_parser_failure_for_ll1_rejection(
                                token_capacity,
                                &self.parse_tables,
                                Some(parser_tree_capacity),
                                ll1,
                            );
                        debug_parser_rejection(&parser_failure);
                        return Err(parser_failure_to_compile_error_for_source_pack(
                            device,
                            queue,
                            &bufs.tokens_out.buffer,
                            &diagnostic_files,
                            &parser_failure,
                        ));
                    }
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let (typecheck_hir, type_check) = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            |parse_bufs| {
                                let hir = crate::parser::buffers::GpuHirView::from_parser_buffers(
                                    parse_bufs,
                                );
                                let type_check = self.record_typecheck_from_parse_buffers(
                                    device,
                                    queue,
                                    encoder,
                                    bufs.n,
                                    diagnostic_files.len().max(1) as u32,
                                    token_capacity,
                                    bufs,
                                    parse_bufs,
                                    &hir,
                                    active_tree_capacity,
                                    parser_tree_capacity,
                                    dependency_pages.as_ref(),
                                    timer.as_deref_mut(),
                                    |err| {
                                        type_check_execution_failed_for_source_pack(
                                            &diagnostic_files,
                                            err,
                                        )
                                    },
                                )?;
                                Ok::<_, CompileError>((hir, type_check))
                            },
                        )?;
                    record_host_timer.stamp("typecheck");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    let semantic_interface = emit_semantic_interface
                        .then_some(library_id)
                        .flatten()
                        .map(|library_id| {
                            self.type_checker
                                .record_semantic_interface(
                                    device,
                                    queue,
                                    encoder,
                                    library_id,
                                    unit_id,
                                    bufs.n,
                                    token_capacity,
                                    &bufs.in_bytes,
                                    buffers::semantic_interface_hir_buffers(&typecheck_hir),
                                )
                                .map_err(|err| {
                                    CompileError::GpuFrontend(format!(
                                        "semantic-interface identity recording failed: {err}"
                                    ))
                                })
                        })
                        .transpose()?;
                    record_host_timer.stamp("semantic_interface");
                    if lowering_target.is_some() && object_request.is_some() {
                        return Err(CompileError::GpuCodegen(
                            "one lowering job cannot request both an executable and an object"
                                .into(),
                        ));
                    }
                    if let Some(target) = lowering_target {
                        let pipeline = self
                            .ensure_lowering_pipeline(
                                target,
                                bufs.n,
                                token_capacity,
                                typecheck_hir.capacity,
                            )
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                        let semantic = self.type_checker.semantic_artifact().ok_or_else(|| {
                            CompileError::GpuCodegen(
                                "semantic lowering buffers are unavailable".into(),
                            )
                        })?;
                        pipeline
                            .record_checked_hir(device, encoder, &typecheck_hir, semantic.view())
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    }
                    if let Some(request) = object_request {
                        let pipeline = self
                            .ensure_lowering_pipeline(
                                request.target(),
                                bufs.n,
                                token_capacity,
                                typecheck_hir.capacity,
                            )
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                        let semantic = self.type_checker.semantic_artifact().ok_or_else(|| {
                            CompileError::GpuCodegen(
                                "semantic lowering buffers are unavailable".into(),
                            )
                        })?;
                        let (library_id, unit_id) = request.ids();
                        pipeline
                            .record_checked_hir_object(
                                device,
                                queue,
                                encoder,
                                &typecheck_hir,
                                semantic.view(),
                                library_id,
                                unit_id,
                            )
                            .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    }
                    record_host_timer.stamp("lowering");
                    Ok(RecordedTypeCheckWithDiagnosticBuffers {
                        type_check,
                        diagnostic_tokens: DiagnosticTokenBuffer::from_lexer_buffers(bufs),
                        semantic_interface,
                    })
                },
                |device, queue, recorded| {
                    let mut finish_timer = CompilerHostTimer::new("compile.source-pack.finish");
                    self.type_checker
                        .finish_recorded_check(device, &recorded.type_check)
                        .map_err(|err| {
                            type_check_error_to_compile_error_for_source_pack(
                                device,
                                queue,
                                &recorded.diagnostic_tokens,
                                &diagnostic_files,
                                err,
                            )
                        })?;
                    finish_timer.stamp("typecheck_status");
                    let semantic_interface = recorded
                        .semantic_interface
                        .as_ref()
                        .map(|identity| {
                            self.type_checker
                                .finish_semantic_interface(device, queue, identity)
                                .map_err(|err| {
                                    CompileError::GpuFrontend(format!(
                                        "semantic-interface readback failed: {err}"
                                    ))
                                })
                        })
                        .transpose()?;
                    finish_timer.stamp("semantic_interface");
                    let target_artifact = lowering_target
                        .map(|target| {
                            self.lowering_pipeline(target)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))?
                                .finish_artifact(device, queue)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                        })
                        .transpose()?;
                    finish_timer.stamp("target_artifact");
                    let x86_object = object_request
                        .and_then(|request| match request {
                            LoweringObjectRequest::X86_64 {
                                library_id,
                                unit_id,
                            } => Some((library_id, unit_id)),
                            LoweringObjectRequest::Wasm { .. } => None,
                        })
                        .map(|(library_id, unit_id)| {
                            self.lowering_pipeline(LoweringTarget::X86_64)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))?
                                .finish_x86_object(device, queue, library_id, unit_id)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                        })
                        .transpose()?;
                    finish_timer.stamp("x86_object");
                    let wasm_object = object_request
                        .and_then(|request| match request {
                            LoweringObjectRequest::Wasm {
                                library_id,
                                unit_id,
                            } => Some((library_id, unit_id)),
                            LoweringObjectRequest::X86_64 { .. } => None,
                        })
                        .map(|(library_id, unit_id)| {
                            self.lowering_pipeline(LoweringTarget::Wasm)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))?
                                .finish_wasm_object(device, queue, library_id, unit_id)
                                .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                        })
                        .transpose()?;
                    finish_timer.stamp("wasm_object");
                    Ok(CheckedSourcePackArtifacts {
                        semantic_interface,
                        target_artifact,
                        x86_object,
                        wasm_object,
                    })
                },
            )
            .await
            .map_err(|err| source_tokenization_failed_for_source_pack(&diagnostic_files, err))?
    }
    #[allow(clippy::too_many_arguments)]
    /// Records type-check GPU work from retained lexer/parser buffers.
    pub(in crate::compiler::gpu_compiler) fn record_typecheck_from_parse_buffers(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        lexer_bufs: &crate::lexer::buffers::GpuBuffers,
        parse_bufs: &crate::parser::buffers::ParserBuffers,
        hir: &crate::parser::buffers::GpuHirView,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        dependency_pages: Option<&gpu_type_checker::GpuDependencyInterfacePages>,
        timer: Option<&mut GpuTimer>,
        map_execution_error: impl FnOnce(GpuTypeCheckError) -> CompileError,
    ) -> Result<gpu_type_checker::RecordedTypeCheck, CompileError> {
        let phase_workspace = parse_bufs.post_hir_workspace(hir);
        let upstream_workspace = buffers::typecheck_workspace(&phase_workspace, lexer_bufs);
        let hir_items = buffers::typecheck_hir_item_buffers(
            hir,
            &upstream_workspace,
            parse_bufs.parser_feature_flags,
            parse_bufs.n_tokens.saturating_sub(2).max(1),
            parse_bufs.n_tokens.saturating_sub(2).max(1),
            parse_bufs.n_tokens.saturating_sub(2).max(1),
        );
        self.type_checker
            .record_resident_token_buffer_with_hir_items_on_gpu(
                device,
                queue,
                encoder,
                source_len,
                source_file_capacity,
                token_capacity,
                (&lexer_bufs.tokens_out).into(),
                (&lexer_bufs.token_count).into(),
                (&lexer_bufs.token_file_id).into(),
                (&lexer_bufs.in_bytes).into(),
                hir_node_capacity,
                parser_hir_node_capacity,
                hir_items,
                dependency_pages,
                timer,
            )
            .map_err(map_execution_error)
    }
}

fn debug_parser_rejection(failure: &crate::parser::driver::ParserFailure) {
    if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_none() {
        return;
    }
    let status = failure.ll1();
    let start = status.error_pos.saturating_sub(4) as usize;
    let context = failure.semantic_token_kinds().map(|kinds| {
        let end = (status.error_pos as usize)
            .saturating_add(5)
            .min(kinds.len());
        kinds.get(start.min(end)..end).unwrap_or_default()
    });
    eprintln!(
        "GPU parser rejection: error_pos={} code={} detail={} steps={} emit_len={} semantic_kinds={context:?}",
        status.error_pos, status.error_code, status.detail, status.steps, status.emit_len,
    );
}

struct RecordedTypeCheckWithDiagnosticBuffers {
    type_check: gpu_type_checker::RecordedTypeCheck,
    diagnostic_tokens: DiagnosticTokenBuffer,
    semantic_interface: Option<gpu_type_checker::RecordedSemanticInterface>,
}

#[derive(Clone, Copy)]
enum LoweringObjectRequest {
    X86_64 { library_id: u32, unit_id: u32 },
    Wasm { library_id: u32, unit_id: u32 },
}

impl LoweringObjectRequest {
    fn target(self) -> LoweringTarget {
        match self {
            Self::X86_64 { .. } => LoweringTarget::X86_64,
            Self::Wasm { .. } => LoweringTarget::Wasm,
        }
    }

    fn ids(self) -> (u32, u32) {
        match self {
            Self::X86_64 {
                library_id,
                unit_id,
            }
            | Self::Wasm {
                library_id,
                unit_id,
            } => (library_id, unit_id),
        }
    }
}

struct CheckedSourcePackArtifacts {
    semantic_interface: Option<crate::compiler::GpuSemanticInterfaceArtifact>,
    target_artifact: Option<Vec<u8>>,
    x86_object: Option<crate::codegen::x86::GpuX86RelocatableObject>,
    wasm_object: Option<crate::codegen::wasm::GpuWasmRelocatableObject>,
}

#[derive(Clone)]
pub(in crate::compiler) struct CompiledSourcePackUnit {
    pub(in crate::compiler) interface: crate::compiler::GpuSemanticInterfaceArtifact,
    pub(in crate::compiler) object: CompiledSourcePackObject,
}

#[derive(Clone)]
pub(in crate::compiler) enum CompiledSourcePackObject {
    X86_64(crate::codegen::x86::GpuX86RelocatableObject),
    Wasm(crate::codegen::wasm::GpuWasmRelocatableObject),
}

#[cfg(test)]
impl CompiledSourcePackObject {
    pub(in crate::compiler) fn into_x86_64(
        self,
    ) -> Result<crate::codegen::x86::GpuX86RelocatableObject, CompileError> {
        match self {
            Self::X86_64(object) => Ok(object),
            Self::Wasm(_) => Err(CompileError::GpuCodegen(
                "compiled source-pack unit returned a Wasm object for x86_64".into(),
            )),
        }
    }

    pub(in crate::compiler) fn into_wasm(
        self,
    ) -> Result<crate::codegen::wasm::GpuWasmRelocatableObject, CompileError> {
        match self {
            Self::Wasm(object) => Ok(object),
            Self::X86_64(_) => Err(CompileError::GpuCodegen(
                "compiled source-pack unit returned an x86_64 object for Wasm".into(),
            )),
        }
    }
}

struct DiagnosticTokenBuffer {
    buffer: LaniusBuffer<crate::lexer::GpuToken>,
    byte_size: usize,
}

impl DiagnosticTokenBuffer {
    fn from_lexer_buffers(bufs: &crate::lexer::buffers::GpuBuffers) -> Self {
        Self {
            buffer: bufs.tokens_out.clone(),
            byte_size: bufs.tokens_out.byte_size,
        }
    }
}

/// Maps one GPU type-check error for a single source file into a compiler error.
pub(super) fn type_check_error_to_compile_error_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    bufs: &crate::lexer::buffers::GpuBuffers,
    src: &str,
    diagnostic_path: &Path,
    err: GpuTypeCheckError,
) -> CompileError {
    match err {
        GpuTypeCheckError::Rejected {
            token,
            code,
            detail,
        } => {
            if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_some() {
                eprintln!("GPU type-check rejection: token={token} code={code:?} detail={detail}");
            }
            let (start, len) = read_single_token_for_diagnostic(device, queue, bufs, token)
                .map(|token_record| (token_record.start, token_record.len))
                .unwrap_or_else(|_| first_nonempty_source_span(src));
            type_check_diagnostic_at_span(diagnostic_path, src, start, len, code, detail)
        }
        _ => type_check_execution_failed_for_source(diagnostic_path, src, err),
    }
}

fn type_check_error_to_compile_error_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    diagnostic_tokens: &DiagnosticTokenBuffer,
    diagnostic_files: &[DiagnosticSourceFile],
    err: GpuTypeCheckError,
) -> CompileError {
    match err {
        GpuTypeCheckError::Rejected {
            token,
            code,
            detail,
        } => {
            if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_some() {
                eprintln!(
                    "GPU source-pack type-check rejection: token={token} code={code:?} detail={detail}"
                );
            }
            if let Some((path, source, start, len)) = read_single_token_from_buffer(
                device,
                queue,
                &diagnostic_tokens.buffer,
                diagnostic_tokens.byte_size,
                token,
            )
            .ok()
            .and_then(|token_record| {
                source_pack_nearest_file_for_global_span(diagnostic_files, token_record.start).map(
                    |file| {
                        (
                            file.path.as_path(),
                            file.source.as_str(),
                            file.local_start_for_global(token_record.start),
                            token_record.len,
                        )
                    },
                )
            })
            .or_else(|| source_pack_fallback_type_check_span(diagnostic_files))
            {
                type_check_diagnostic_at_span(path, source, start, len, code, detail)
            } else {
                let (start, len) = first_nonempty_source_span("");
                type_check_diagnostic_at_span(Path::new("<source>"), "", start, len, code, detail)
            }
        }
        _ => type_check_execution_failed_for_source_pack(diagnostic_files, err),
    }
}

fn source_pack_fallback_type_check_span(
    diagnostic_files: &[DiagnosticSourceFile],
) -> Option<(&Path, &str, usize, usize)> {
    let file = diagnostic_files.first()?;
    let (start, len) = first_nonempty_source_span(&file.source);
    Some((&file.path, &file.source, start, len))
}

pub(in crate::compiler::gpu_compiler) fn type_check_execution_failed_for_source(
    diagnostic_path: &Path,
    source: &str,
    err: impl std::fmt::Display + std::fmt::Debug,
) -> CompileError {
    if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_some() {
        eprintln!("GPU type-check detail: {err:?}");
    }
    stage_execution_failed_for_source(type_check_execution_failure(), diagnostic_path, source, err)
}

pub(in crate::compiler::gpu_compiler) fn type_check_execution_failed_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
    err: impl std::fmt::Display + std::fmt::Debug,
) -> CompileError {
    if std::env::var_os("LANIUS_DEBUG_STAGE_ERRORS").is_some() {
        eprintln!("GPU type-check detail: {err:?}");
    }
    stage_execution_failed_for_source_pack(type_check_execution_failure(), diagnostic_files, err)
}

fn type_check_execution_failure() -> StageExecutionFailure<'static> {
    StageExecutionFailure {
        code: "LNC0047",
        message: "type-check execution failed",
        primary_label: "type checker failed before it could report a language error",
        source_help: "try reducing the source size; if this happens on a small file, report a compiler bug",
        source_pack_help: "try reducing the source pack; if this happens on a small package, report a compiler bug",
    }
}

pub(in crate::compiler::gpu_compiler) fn type_check_diagnostic_at_span(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    code: GpuTypeCheckCode,
    detail: u32,
) -> CompileError {
    match code {
        GpuTypeCheckCode::ImportCycle => import_cycle_diagnostic(path, source, start, len),
        GpuTypeCheckCode::UnresolvedImport => {
            unresolved_import_diagnostic(path, source, start, len)
        }
        GpuTypeCheckCode::UnsupportedImport => {
            unsupported_import_diagnostic(path, source, start, len)
        }
        GpuTypeCheckCode::DuplicateModule => duplicate_module_diagnostic(path, source, start, len),
        GpuTypeCheckCode::InvalidModulePath => {
            invalid_module_path_diagnostic(path, source, start, len)
        }
        GpuTypeCheckCode::BadHir => trait_impl_diagnostic(path, source, start, len, detail)
            .or_else(|| generic_param_diagnostic(path, source, start, len, detail))
            .unwrap_or_else(|| {
                syntax_error_to_compile_error_for_source_span(path, source, start, len)
            }),
        GpuTypeCheckCode::TraitBoundUnsatisfied | GpuTypeCheckCode::TraitBoundAmbiguous => {
            trait_bound_diagnostic(path, source, start, len, code, detail)
        }
        GpuTypeCheckCode::UnresolvedIdent => {
            unresolved_identifier_diagnostic(path, source, start, len, detail)
        }
        GpuTypeCheckCode::UnknownType => unknown_type_diagnostic(path, source, start, len, detail),
        GpuTypeCheckCode::AssignMismatch
            if assign_mismatch_looks_like_invalid_member_access(source, start, detail) =>
        {
            invalid_member_access_diagnostic(path, source, start, len, u32::MAX)
        }
        GpuTypeCheckCode::AssignMismatch => CompileError::Diagnostic(
            Diagnostic::error("LNC0006", "type mismatch")
                .with_primary_label(diagnostic_label_from_source_span(
                    path,
                    source,
                    start,
                    len,
                    type_mismatch_label(detail),
                ))
                .with_note(type_mismatch_note(detail)),
        ),
        GpuTypeCheckCode::ReturnMismatch => return_mismatch_diagnostic(path, source, start, len),
        GpuTypeCheckCode::ConditionType => condition_type_diagnostic(path, source, start, len),
        GpuTypeCheckCode::LoopControl => loop_control_diagnostic(path, source, start, len),
        GpuTypeCheckCode::InvalidMemberAccess => {
            invalid_member_access_diagnostic(path, source, start, len, detail)
        }
        GpuTypeCheckCode::InvalidArrayReturn => {
            invalid_array_return_diagnostic(path, source, start, len)
        }
        GpuTypeCheckCode::CallMismatch => {
            call_mismatch_diagnostic(path, source, start, len, detail)
        }
        GpuTypeCheckCode::NameLimit => name_limit_diagnostic(path, source, start, len, detail),
        GpuTypeCheckCode::Unknown(status_code) => {
            unclassified_type_check_diagnostic(path, source, start, len, status_code, detail)
        }
    }
}

fn assign_mismatch_looks_like_invalid_member_access(
    source: &str,
    start: usize,
    detail: u32,
) -> bool {
    const TY_VOID: u32 = 1;
    detail != 0 && detail % 256 == TY_VOID && span_is_dotted_member(source, start)
}

fn span_is_dotted_member(source: &str, start: usize) -> bool {
    source
        .get(..start)
        .and_then(|prefix| prefix.chars().rev().find(|ch| !ch.is_whitespace()))
        == Some('.')
}

fn return_mismatch_diagnostic(path: &Path, source: &str, start: usize, len: usize) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0006", "type mismatch")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "return value does not match the function return type",
            ))
            .with_note("change the returned expression or the function return type so they agree"),
    )
}

fn condition_type_diagnostic(path: &Path, source: &str, start: usize, len: usize) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0006", "type mismatch")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "this condition must have type bool",
            ))
            .with_note("use a boolean expression in conditions and with boolean-only operators"),
    )
}

fn loop_control_diagnostic(path: &Path, source: &str, start: usize, len: usize) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0041", "invalid loop control")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "loop control statement is outside a loop",
            ))
            .with_note("move this break or continue statement into a loop body, or remove it"),
    )
}

fn invalid_member_access_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> CompileError {
    let (label, note) = if span_is_dotted_member(source, start) {
        (
            "this value does not have the requested field",
            "field access is only valid for structs that declare a field with this name",
        )
    } else {
        match detail {
            0 => (
                "this field is not declared by the struct being initialized",
                "use one of the struct's declared field names or add the field to the struct declaration",
            ),
            1 => (
                "field name is already declared in this struct",
                "give each field in a struct declaration a unique name",
            ),
            _ => (
                "this value does not have the requested field",
                "field access is only valid for structs that declare a field with this name",
            ),
        }
    };

    CompileError::Diagnostic(
        Diagnostic::error("LNC0042", "invalid member access")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    )
}

fn invalid_array_return_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0043", "invalid array return")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "array return value is not valid in this context",
            ))
            .with_note(
                "return an array value that matches the function return type and is tracked by the current compiler array-return path",
            ),
    )
}

fn name_limit_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> CompileError {
    let (label, note) = if detail > 0 {
        (
            "name table or identifier length exceeds the current compiler limit".to_string(),
            format!(
                "the current compilation unit requires capacity {detail}; reduce identifier count or length until the compiler limit is raised"
            ),
        )
    } else {
        (
            "name table exceeds the current compiler limit".to_string(),
            "reduce identifier count or length until the compiler limit is raised".to_string(),
        )
    };

    CompileError::Diagnostic(
        Diagnostic::error("LNC0044", "compiler limit exceeded")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    )
}

fn unclassified_type_check_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    status_code: u32,
    detail: u32,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0045", "unclassified type-check rejection")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "the type checker rejected this source but did not classify the language error",
            ))
            .with_note(format!(
                "this is a compiler diagnostic mapping bug; internal status code {status_code}, detail {detail}"
            )),
    )
}

fn import_cycle_diagnostic(path: &Path, source: &str, start: usize, len: usize) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0002", "import cycle")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "import participates in a module cycle",
            ))
            .with_note(
                "remove the cycle or move shared declarations into a module that both sides can import without importing each other",
            ),
    )
}

fn unresolved_import_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0010", "unresolved import")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "imported module not found",
            ))
            .with_note(
                "the module resolver could not match this import path to a loaded module declaration",
            ),
    )
}

fn unsupported_import_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0011", "unsupported import form")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "only module-path imports are supported here",
            ))
            .with_note(
                "quoted imports are not loaded by the module resolver yet; use a module path such as import core::math",
            ),
    )
}

fn duplicate_module_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0013", "duplicate module declaration")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "this module path is already declared in the source pack",
            ))
            .with_note(
                "module identity comes from parsed module declarations; each loaded source pack must declare every module path at most once",
            ),
    )
}

fn invalid_module_path_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0015", "invalid module path")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "module declaration does not contain a valid module path",
            ))
            .with_note("module identity must come from a non-empty parsed module path declaration"),
    )
}

fn unresolved_identifier_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    _detail: u32,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0005", "unresolved identifier")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "not found in this scope",
            ))
            .with_note("declare the value before using it or import its defining module"),
    )
}

fn unknown_type_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    _detail: u32,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0007", "unknown type")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "type not found",
            ))
            .with_note("declare the type before using it or import its defining module"),
    )
}

fn trait_bound_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    code: GpuTypeCheckCode,
    detail: u32,
) -> CompileError {
    const PREDICATE_STATUS_INVALID_SUBJECT: u32 = 1;
    const PREDICATE_STATUS_BOUND_NOT_TRAIT: u32 = 2;
    const PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH: u32 = 11;
    const PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE: u32 = 12;
    const PREDICATE_STATUS_BOUND_ARITY_MISMATCH: u32 = 13;
    const PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND: u32 = 18;
    const PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW: u32 = 21;
    const PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION: u32 = 22;

    let (diagnostic_code, message, label, note) = match code {
        GpuTypeCheckCode::TraitBoundUnsatisfied if detail == PREDICATE_STATUS_INVALID_SUBJECT => (
            "LNC0008",
            "unsatisfied trait bound",
            "trait bound subject must be a type generic parameter",
            "use a declared type parameter as the bound subject; const generic parameters and undeclared names cannot carry trait bounds here",
        ),
        GpuTypeCheckCode::TraitBoundUnsatisfied if detail == PREDICATE_STATUS_BOUND_NOT_TRAIT => (
            "LNC0008",
            "unsatisfied trait bound",
            "trait bound target does not resolve to a trait",
            "name a trait in the bound before relying on trait solving",
        ),
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound exceeds the current trait argument limit",
                "this compiler currently supports at most two trait type arguments in a bound",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound argument shape is not supported here",
                "use scalar, generic, or concrete non-nested trait arguments here; nested generic arguments are rejected rather than matching only the outer type name",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_BOUND_ARITY_MISMATCH =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound uses the wrong number of trait arguments",
                "match the resolved trait declaration's generic parameter count before relying on the bound",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_NON_CALLABLE_BOUND =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bounds on this generic declaration are not enforced by the current trait solver",
                "move the bound to a called function before relying on declaration-level trait bounds",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait obligation exceeds the current trait-solver window",
                "reduce the number or width of generic call arguments so the trait obligation fits the current compiler limit",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound relation is not supported here",
                "this generic type pattern is not supported in this position yet; the compiler rejects it rather than matching only the visible top-level type",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied => (
            "LNC0008",
            "unsatisfied trait bound",
            "no matching impl satisfies this call",
            "the trait solver found no concrete impl for the call's inferred type arguments",
        ),
        GpuTypeCheckCode::TraitBoundAmbiguous => (
            "LNC0009",
            "ambiguous trait bound",
            "multiple matching impls satisfy this call",
            "remove overlapping impls or make the call's bound resolve to exactly one impl",
        ),
        _ => unreachable!("trait_bound_diagnostic called for non-trait-bound error"),
    };

    CompileError::Diagnostic(
        Diagnostic::error(diagnostic_code, message)
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    )
}

fn trait_impl_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> Option<CompileError> {
    let (label, note) = match detail {
        2 => (
            "trait impl header does not resolve to a trait",
            "name a trait in the impl header before providing trait methods",
        ),
        5 => (
            "trait impl target type does not resolve",
            "name a visible scalar, struct, enum, or supported alias as the impl target",
        ),
        6 => (
            "trait impl is missing a required method",
            "implement every method declared by the resolved trait",
        ),
        7 => (
            "trait impl method has the wrong number of parameters",
            "match each implemented method's parameter list to the trait declaration",
        ),
        8 => (
            "trait impl method signature does not match the trait declaration",
            "match each implemented method's parameter and return types to the resolved trait declaration; nested generic instance parameters are rejected for now rather than partially matched",
        ),
        11 => (
            "trait impl header exceeds the current trait argument limit",
            "this compiler currently supports at most two trait type arguments in a trait impl",
        ),
        12 => (
            "trait impl header uses an unsupported trait argument shape",
            "use scalar, generic, or concrete non-nested trait arguments here; nested generic arguments are rejected rather than matching only the outer type name",
        ),
        13 => (
            "trait impl header uses the wrong number of trait arguments",
            "match the resolved trait declaration's generic parameter count before implementing it",
        ),
        14 => (
            "trait impl target type is not supported here",
            "this compiler currently supports trait impls for scalar and non-generic nominal targets here; generic instance targets are rejected",
        ),
        15 => (
            "trait impl header contains an unknown trait argument type",
            "resolve every trait type argument to a scalar or nominal type before implementing the trait",
        ),
        16 => (
            "trait method-level generics are not supported here",
            "move the generic parameter to the trait or impl receiver type until method-level generic substitution is supported",
        ),
        17 => (
            "trait method where clauses are not supported here",
            "move the bound to the trait, impl, or caller-visible where clause until method-level predicate solving is supported",
        ),
        19 => (
            "trait impl overlaps an existing impl for the same trait and target",
            "make each supported trait impl key unique before relying on trait solving",
        ),
        20 => (
            "trait declares duplicate method contracts",
            "give each method in a trait a unique name until trait method overload resolution is supported",
        ),
        23 => (
            "trait impl declares a method not required by the trait",
            "remove extra impl methods or declare the method in the resolved trait contract",
        ),
        24 => (
            "trait impl declares duplicate methods for the same trait contract",
            "give each implemented trait method a unique name before trait contract validation",
        ),
        25 => (
            "trait impl visibility does not match the resolved trait contract",
            "public trait impls and public traits must agree in visibility",
        ),
        26 => (
            "trait impl method visibility does not match the trait declaration",
            "match each impl method's visibility to the resolved trait method contract",
        ),
        27 => (
            "trait impl method contract is not valid",
            "match every impl method to the resolved trait method declaration",
        ),
        28 => (
            "trait impl header uses generic trait arguments that are not supported here",
            "use concrete non-nested trait arguments in impl headers for now",
        ),
        29 => (
            "inherent impl target path is malformed",
            "name the target with a source-addressable type path",
        ),
        30 => (
            "inherent impl target declaration does not resolve",
            "name a visible struct, enum, scalar, or supported alias as the impl target",
        ),
        31 => (
            "inherent impl target declaration kind is unsupported",
            "inherent impls require a struct, enum, scalar, or supported alias target",
        ),
        32 => (
            "inherent impl target declaration identity is invalid",
            "the compiler could not map the resolved declaration to compact HIR",
        ),
        33 => (
            "inherent impl target has the wrong number of type arguments",
            "match the target declaration's generic parameter count",
        ),
        34 => (
            "inherent impl target contains an unsupported type argument",
            "use scalar, generic, or concrete non-nested target arguments here",
        ),
        _ => return None,
    };

    Some(CompileError::Diagnostic(
        Diagnostic::error("LNC0021", "invalid trait implementation")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    ))
}

fn generic_param_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> Option<CompileError> {
    let (label, note) = match detail {
        21 => (
            "generic parameter name is already declared in this parameter list",
            "give each type and const generic parameter in the declaration a unique name",
        ),
        _ => return None,
    };

    Some(CompileError::Diagnostic(
        Diagnostic::error("LNC0033", "invalid generic parameter list")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    ))
}

fn call_mismatch_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> CompileError {
    const CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF: u32 = 0xffffff01;
    const CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC: u32 = 0xffffff02;
    const CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE: u32 = 0xffffff03;
    const CALL_MISMATCH_GENERIC_CLAIM_CAPACITY: u32 = 0xffffff04;
    const CALL_MISMATCH_ARITY: u32 = 0xffffff05;
    let (label, note) = match detail {
        CALL_MISMATCH_UNSUPPORTED_METHOD_RETURN_REF => (
            "method return type is not supported for generic method dispatch here",
            "avoid generic method return types that depend on receiver type arguments for now",
        ),
        CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC => (
            "method-level generics are not supported for method dispatch here",
            "move the generic parameter to the trait, impl, or receiver type",
        ),
        CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE => (
            "method-level where clauses are not supported for method dispatch here",
            "move the bound to the trait, impl, or caller-visible where clause",
        ),
        CALL_MISMATCH_GENERIC_CLAIM_CAPACITY => (
            "generic call inference relation capacity was exhausted here",
            "reduce the number of repeated wide generic-instance call arguments until generic matching is made product-free",
        ),
        CALL_MISMATCH_ARITY => (
            "call has the wrong number of arguments",
            "match the argument list to the resolved function or method signature",
        ),
        _ => (
            "call does not match a resolved function or method",
            "no supported function or method signature matches this receiver and argument list",
        ),
    };

    CompileError::Diagnostic(
        Diagnostic::error("LNC0027", "call resolution failed")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    )
}

fn read_single_token_for_diagnostic(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    bufs: &crate::lexer::buffers::GpuBuffers,
    token_index: u32,
) -> Result<Token, String> {
    read_single_token_from_buffer(
        device,
        queue,
        &bufs.tokens_out.buffer,
        bufs.tokens_out.byte_size,
        token_index,
    )
}

fn read_single_token_from_buffer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    token_buffer_byte_size: usize,
    token_index: u32,
) -> Result<Token, String> {
    let token_stride = std::mem::size_of::<GpuToken>() as u64;
    let token_offset = u64::from(token_index)
        .checked_mul(token_stride)
        .ok_or_else(|| format!("token {token_index} byte offset overflow"))?;
    let token_end = token_offset
        .checked_add(token_stride)
        .ok_or_else(|| format!("token {token_index} byte end overflow"))?;
    if token_end > token_buffer_byte_size as u64 {
        return Err(format!(
            "token {token_index} byte range {token_offset}..{token_end} exceeds token buffer size {}",
            token_buffer_byte_size
        ));
    }

    let token_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.compiler.typecheck.diagnostic_token"),
        size: token_stride,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("compiler.typecheck.diagnostic-token-readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(token_buffer, token_offset, &token_readback, 0, token_stride);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "compiler.typecheck.diagnostic-token-readback",
        encoder.finish(),
    );

    let token_slice = token_readback.slice(0..token_stride);
    crate::gpu::passes_core::map_readback_blocking(
        device,
        &token_slice,
        "compiler.typecheck.diagnostic-token",
    )
    .map_err(|err| err.to_string())?;
    let mapped = token_slice.get_mapped_range();
    let mut tokens = read_tokens_from_mapped(&mapped, 1)?;
    drop(mapped);
    token_readback.unmap();
    tokens
        .pop()
        .ok_or_else(|| format!("token {token_index} readback returned no rows"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn qualified_path_relations_survive_unrelated_module_declarations() {
        let compiler = pollster::block_on(GpuCompiler::new()).expect("GPU compiler");
        let noise = (0..32)
            .map(|i| format!("pub fn noise_{i}() -> i32 {{ return {i}; }}\n"))
            .collect::<String>();
        let sources = [
            "module app::main;\nimport lib::target;\nimport lib::noise;\nfn main() -> i32 { return lib::target::answer(); }".to_owned(),
            "module lib::target;\npub fn answer() -> i32 { return 7; }".to_owned(),
            format!("module lib::noise;\n{noise}"),
        ];

        pollster::block_on(compiler.type_check_source_pack(&sources))
            .expect("qualified path remains resolvable when another module adds declarations");
    }

    #[test]
    fn type_check_execution_failure_for_source_is_structured_diagnostic() {
        let err = type_check_execution_failed_for_source(
            Path::new("app.lani"),
            "fn main() { return 0; }\n",
            "status readback failed",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0047");
                assert_eq!(diagnostic.message, "type-check execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("type-check execution diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("app.lani"));
                assert_eq!(
                    label.message,
                    "type checker failed before it could report a language error"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("error[LNC0047]: type-check execution failed"));
                assert!(rendered.contains("source input path: app.lani"));
                assert!(!rendered.contains("status readback failed"));
                assert!(!rendered.contains("type checker error:"));
                assert!(!rendered.contains("GpuTypeCheck"));
                assert!(!rendered.contains("type check error: type checker failed"));
            }
            other => panic!("expected structured type-check execution diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn type_check_execution_failure_for_source_pack_is_structured_diagnostic() {
        let paths = [Some(PathBuf::from("first.lani"))];
        let files = source_pack_diagnostic_files(&["module first;\n"], Some(&paths));

        let err = type_check_execution_failed_for_source_pack(&files, "status readback failed");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0047");
                assert_eq!(diagnostic.message, "type-check execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("type-check execution diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("first.lani"));
                assert_eq!(
                    label.message,
                    "type checker failed before it could report a language error"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("source file count: 1"));
                assert!(!rendered.contains("status readback failed"));
                assert!(!rendered.contains("type checker error:"));
                assert!(!rendered.contains("GpuTypeCheck"));
                assert!(!rendered.contains("type check error: type checker failed"));
            }
            other => panic!("expected structured source-pack diagnostic, got {other:?}"),
        }
    }
}
