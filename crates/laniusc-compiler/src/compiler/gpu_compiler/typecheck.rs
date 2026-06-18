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

impl<'gpu> GpuCompiler<'gpu> {
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
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "type check source pack",
            sources,
        )?;
        self.type_check_explicit_source_pack(sources).await
    }
    /// Type-check an explicit in-memory source-pack manifest and preserve any
    /// manifest source paths for diagnostics.
    pub async fn type_check_source_pack_manifest(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<(), CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "type check source pack",
            &source_pack.sources,
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
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = parser_check
                        .read_status_result(device)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    if !ll1.accepted {
                        return Err(parser_ll1_error_to_compile_error_for_source(
                            device,
                            queue,
                            &bufs.tokens_out.buffer,
                            src,
                            &diagnostic_path,
                            &ll1,
                        ));
                    }
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        parser_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
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
                        })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
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
        let diagnostic_files = source_pack_diagnostic_files(sources, source_paths);
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.source_pack.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = parser_check
                        .read_status_result(device)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    if !ll1.accepted {
                        return Err(parser_ll1_error_to_compile_error_for_source_pack(
                            device,
                            queue,
                            &bufs.tokens_out.buffer,
                            &diagnostic_files,
                            &ll1,
                        ));
                    }
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        parser_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok(RecordedTypeCheckWithDiagnosticBuffers {
                        type_check,
                        diagnostic_tokens: DiagnosticTokenBuffer::from_lexer_buffers(bufs),
                    })
                },
                |device, queue, recorded| {
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
                        })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
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
        parse_bufs: &OwnedTypecheckParserBuffers,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        timer: Option<&mut GpuTimer>,
    ) -> Result<gpu_type_checker::RecordedTypeCheck, CompileError> {
        // Typecheck metadata remains live across late module/generic/match
        // passes and is retained for x86 lowering. Keep it in typechecker-owned
        // rows so backend codegen can consume semantic records after the parser
        // resident cache has been released.
        self.type_checker
            .record_resident_token_buffer_with_hir_items_on_gpu(
                device,
                queue,
                encoder,
                source_len,
                source_file_capacity,
                token_capacity,
                &lexer_bufs.tokens_out,
                &lexer_bufs.token_count,
                &lexer_bufs.token_file_id,
                &lexer_bufs.in_bytes,
                hir_node_capacity,
                parser_hir_node_capacity,
                &parse_bufs.hir_kind,
                &parse_bufs.hir_token_pos,
                &parse_bufs.hir_token_end,
                &parse_bufs.hir_token_file_id,
                &parse_bufs.ll1_status,
                parse_bufs.hir_item_buffers(),
                timer,
            )
            .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
    }
    #[allow(dead_code)]
    fn typecheck_external_scratch_from_frontend_buffers<'a>(
        lexer_bufs: &'a LexerBuffers,
        parse_bufs: &'a OwnedTypecheckParserBuffers,
    ) -> gpu_type_checker::GpuTypeCheckExternalScratchBuffers<'a> {
        // Typecheck runs after lexing and parser HIR construction, but before
        // x86. Reuse frontend workspaces that are dead at this phase boundary;
        // do not borrow source/token buffers or parser HIR records that are
        // still read by typecheck or x86 lowering.
        gpu_type_checker::GpuTypeCheckExternalScratchBuffers {
            fn_entrypoint_tag: &parse_bufs.tree_prefix,
            // Path byte spans are consumed before type-instance metadata is
            // cleared and collected. Reuse their lexer-backed storage for the
            // type-expression ref rows instead of allocating two more
            // token-sized typecheck buffers.
            type_expr_ref_tag: &lexer_bufs.end_positions.buffer,
            type_expr_ref_payload: &lexer_bufs.types_compact.buffer,
            // Module-path key-radix scratch is consumed before type-instance
            // generic/const-param slot maps are cleared and populated.
            type_generic_param_slot_by_token: &parse_bufs.hir_list_rank_node,
            type_const_param_slot_by_token: &parse_bufs.hir_list_rank_local_prefix,
            record_family_flag: None,
            module_record_prefix: &parse_bufs.hir_type_alias_owner_value_b,
            record_scan_local_prefix: &parse_bufs.hir_type_alias_owner_link_a,
            module_path_key_radix_block_histogram: &parse_bufs.hir_list_rank_local_prefix,
            module_path_key_radix_block_bucket_prefix: &parse_bufs.hir_list_rank_node,
            path_id_by_owner_hir: &parse_bufs.hir_type_alias_owner_link_b,
            decl_module_file_id: &parse_bufs.token_brace_semantic_kind,
            decl_module_id: &parse_bufs.token_bracket_semantic_kind,
            decl_name_id: &parse_bufs.token_statement_context_kind,
            decl_namespace: &parse_bufs.token_brace_match_depth,
            decl_visibility: &parse_bufs.semantic_token_kinds,
            decl_token_start: &parse_bufs.token_depth_brace_inblock,
            decl_token_end: &parse_bufs.token_depth_bracket_inblock,
            decl_key_to_decl_id: &parse_bufs.hir_semantic_prefix_before_node,
            decl_key_order_tmp: &parse_bufs.hir_array_element_previous,
            decl_status: &parse_bufs.out_headers,
            call_param_count: &parse_bufs.hir_type_arg_rank_b,
            call_param_type: &parse_bufs.out_headers,
            call_arg_record: &parse_bufs.hir_match_rank_node,
            function_lookup_key: &parse_bufs.hir_match_rank_local_prefix,
            function_lookup_fn: &parse_bufs.hir_match_arm_previous,
            // Declaration generic-arity counts are live after module-path
            // status scratch is consumed and before method-name token scratch
            // is cleared/filled.
            type_decl_generic_param_count: &parse_bufs.out_headers,
            type_decl_generic_param_count_by_node: &parse_bufs.hir_type_path_leaf_value_a,
            type_instance_head_token: &parse_bufs.default_token_file_id,
            // Module declaration file/end rows are consumed by the upfront
            // module-path pipeline before type-instance argument spans are
            // cleared and collected.
            type_instance_arg_start: &parse_bufs.token_brace_semantic_kind,
            type_instance_arg_count: &parse_bufs.token_depth_bracket_inblock,
            type_instance_arg_ref_tag: &parse_bufs.hir_variant_rank_a,
            type_instance_arg_ref_payload: &parse_bufs.hir_variant_payload_link_a,
            type_instance_elem_ref_tag: &lexer_bufs.dfa_02_ping.buffer,
            type_instance_elem_ref_payload: &lexer_bufs.dfa_02_pong.buffer,
            // Declaration visibility and type-key tables are consumed by the
            // upfront module-path pipeline before type-instance length
            // metadata is cleared and later handed to x86.
            type_instance_len_kind: &parse_bufs.semantic_token_kinds,
            type_instance_len_payload: &lexer_bufs.dfa_chunk_summaries.buffer,
            // Module declaration ids are consumed by the upfront module-path
            // pipeline before the type-instance state row is cleared. The row
            // is typecheck-only and is not handed to x86.
            type_instance_state: &parse_bufs.token_bracket_semantic_kind,
            decl_type_key_to_decl_id: &lexer_bufs.dfa_chunk_summaries.buffer,
            decl_value_key_to_decl_id: &parse_bufs.hir_variant_payload_link_b,
            method_decl_module_id: &parse_bufs.hir_type_alias_owner_value_b,
            method_decl_impl_node: &parse_bufs.hir_type_alias_owner_link_a,
            method_decl_name_token: &parse_bufs.match_for_index,
            method_decl_name_id: &parse_bufs.hir_variant_payload_rank_a,
            method_decl_param_offset: &parse_bufs.hir_semantic_parent,
            method_decl_receiver_mode: &parse_bufs.hir_variant_payload_rank_b,
            method_decl_visibility: &parse_bufs.hir_variant_payload_owner_a,
            method_key_to_fn_token: &parse_bufs.hir_fn_signature_owner_link_b,
            method_key_status: &parse_bufs.hir_match_rank_node,
            method_key_radix_block_histogram: &parse_bufs.hir_fn_signature_function_owner_a,
            method_key_radix_block_bucket_prefix: &parse_bufs.hir_fn_signature_function_owner_b,
            method_call_receiver_ref_tag: &parse_bufs.hir_type_arg_previous,
            method_call_receiver_ref_payload: &parse_bufs.hir_match_rank_local_prefix,
            method_call_name_id: &parse_bufs.hir_variant_payload_owner_b,
            method_call_site_module_id: &parse_bufs.hir_variant_payload_link_b,
            import_visible_type_count: &parse_bufs.hir_variant_payload_rank_a,
            import_visible_value_count: &parse_bufs.hir_variant_payload_rank_b,
            import_visible_type_prefix: &parse_bufs.hir_variant_payload_owner_a,
            import_visible_value_prefix: &parse_bufs.hir_variant_payload_owner_b,
            resolved_type_decl: &lexer_bufs.tok_types.buffer,
            resolved_value_decl: &lexer_bufs.flags_packed.buffer,
            resolved_type_status: &lexer_bufs.s_all_final.buffer,
            resolved_value_status: &lexer_bufs.s_keep_final.buffer,
            // List-ranking workspaces are dead after parser HIR construction
            // and are not borrowed by x86. Use them for retained member/struct
            // type metadata produced after type-instance collection.
            member_result_ref_payload: &parse_bufs.hir_call_arg_owner_a,
            member_result_field_ordinal: &parse_bufs.hir_call_arg_owner_b,
            struct_init_field_expected_ref_tag: &parse_bufs.hir_call_arg_link_a,
            struct_init_field_expected_ref_payload: &parse_bufs.hir_call_arg_link_b,
            struct_init_field_context_instance: &parse_bufs.hir_call_arg_rank_a,
            struct_init_field_ordinal: &parse_bufs.hir_call_arg_rank_b,
            path_start: &lexer_bufs.end_positions.buffer,
            path_len: &lexer_bufs.types_compact.buffer,
            path_segment_count: &lexer_bufs.all_index_compact.buffer,
            path_segment_base: &parse_bufs.sc_offsets,
            path_segment_name_id: &parse_bufs.emit_offsets,
            path_segment_token: &parse_bufs.pack_sc_prefix_a,
            path_owner_hir: &parse_bufs.pack_sc_prefix_b,
            path_owner_token: &parse_bufs.pack_emit_prefix_a,
            path_owner_module_id: &parse_bufs.pack_emit_prefix_b,
            path_kind: &parse_bufs.hir_list_rank_flag,
        }
    }
}

struct RecordedTypeCheckWithDiagnosticBuffers {
    type_check: gpu_type_checker::RecordedTypeCheck,
    diagnostic_tokens: DiagnosticTokenBuffer,
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
    match &err {
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ImportCycle,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => {
                import_cycle_diagnostic(diagnostic_path, src, token_record.start, token_record.len)
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnresolvedImport,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => unresolved_import_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnsupportedImport,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => unsupported_import_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ImportPathTooDeep,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => import_path_too_deep_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::DuplicateModule,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => duplicate_module_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ModulePathTooDeep,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => module_path_too_deep_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::InvalidModulePath,
            ..
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => invalid_module_path_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::BadHir,
            detail,
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => {
                if let Some(diagnostic) = trait_impl_diagnostic(
                    diagnostic_path,
                    src,
                    token_record.start,
                    token_record.len,
                    *detail,
                ) {
                    diagnostic
                } else if let Some(diagnostic) = generic_param_diagnostic(
                    diagnostic_path,
                    src,
                    token_record.start,
                    token_record.len,
                    *detail,
                ) {
                    diagnostic
                } else {
                    syntax_error_to_compile_error_for_source_span(
                        diagnostic_path,
                        src,
                        token_record.start,
                        token_record.len,
                    )
                }
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code,
            detail,
        } if matches!(
            code,
            GpuTypeCheckCode::TraitBoundUnsatisfied | GpuTypeCheckCode::TraitBoundAmbiguous
        ) =>
        {
            match read_single_token_for_diagnostic(device, queue, bufs, *token) {
                Ok(token_record) => trait_bound_diagnostic(
                    diagnostic_path,
                    src,
                    token_record.start,
                    token_record.len,
                    *code,
                    *detail,
                ),
                Err(read_err) => CompileError::GpuTypeCheck(format!(
                    "{}; failed to read diagnostic token {}: {}",
                    err, token, read_err
                )),
            }
        }
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnresolvedIdent,
            detail,
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => unresolved_identifier_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
                *detail,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnknownType,
            detail,
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => unknown_type_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
                *detail,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::AssignMismatch,
            detail,
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => CompileError::Diagnostic(
                Diagnostic::error("LNC0006", "type mismatch")
                    .with_primary_label(diagnostic_label_from_source_span(
                        diagnostic_path,
                        src,
                        token_record.start,
                        token_record.len,
                        type_mismatch_label(*detail),
                    ))
                    .with_note(type_mismatch_note(*detail)),
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::CallMismatch,
            detail,
        } => match read_single_token_for_diagnostic(device, queue, bufs, *token) {
            Ok(token_record) => call_mismatch_diagnostic(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
                *detail,
            ),
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        _ => CompileError::GpuTypeCheck(err.to_string()),
    }
}

fn type_check_error_to_compile_error_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    diagnostic_tokens: &DiagnosticTokenBuffer,
    diagnostic_files: &[DiagnosticSourceFile],
    err: GpuTypeCheckError,
) -> CompileError {
    match &err {
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ImportCycle,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                import_cycle_diagnostic(&file.path, &file.source, local_start, token_record.len)
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnresolvedImport,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                unresolved_import_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnsupportedImport,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                unsupported_import_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ImportPathTooDeep,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                import_path_too_deep_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::DuplicateModule,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                duplicate_module_diagnostic(&file.path, &file.source, local_start, token_record.len)
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::ModulePathTooDeep,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                module_path_too_deep_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::InvalidModulePath,
            ..
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                invalid_module_path_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnresolvedIdent,
            detail,
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                unresolved_identifier_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                    *detail,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::UnknownType,
            detail,
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                unknown_type_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                    *detail,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::BadHir,
            detail,
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                if let Some(diagnostic) = trait_impl_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                    *detail,
                ) {
                    diagnostic
                } else if let Some(diagnostic) = generic_param_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                    *detail,
                ) {
                    diagnostic
                } else {
                    syntax_error_to_compile_error_for_source_span(
                        &file.path,
                        &file.source,
                        local_start,
                        token_record.len,
                    )
                }
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code,
            detail,
        } if matches!(
            code,
            GpuTypeCheckCode::TraitBoundUnsatisfied | GpuTypeCheckCode::TraitBoundAmbiguous
        ) =>
        {
            match read_single_token_from_buffer(
                device,
                queue,
                &diagnostic_tokens.buffer,
                diagnostic_tokens.byte_size,
                *token,
            ) {
                Ok(token_record) => {
                    let Some(file) =
                        source_pack_file_for_global_span(diagnostic_files, token_record.start)
                    else {
                        return CompileError::GpuTypeCheck(format!(
                            "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                            err, token, token_record.start
                        ));
                    };
                    let local_start = file.local_start_for_global(token_record.start);
                    trait_bound_diagnostic(
                        &file.path,
                        &file.source,
                        local_start,
                        token_record.len,
                        *code,
                        *detail,
                    )
                }
                Err(read_err) => CompileError::GpuTypeCheck(format!(
                    "{}; failed to read diagnostic token {}: {}",
                    err, token, read_err
                )),
            }
        }
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::AssignMismatch,
            detail,
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                CompileError::Diagnostic(
                    Diagnostic::error("LNC0006", "type mismatch")
                        .with_primary_label(diagnostic_label_from_source_span(
                            &file.path,
                            &file.source,
                            local_start,
                            token_record.len,
                            type_mismatch_label(*detail),
                        ))
                        .with_note(type_mismatch_note(*detail)),
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        GpuTypeCheckError::Rejected {
            token,
            code: GpuTypeCheckCode::CallMismatch,
            detail,
        } => match read_single_token_from_buffer(
            device,
            queue,
            &diagnostic_tokens.buffer,
            diagnostic_tokens.byte_size,
            *token,
        ) {
            Ok(token_record) => {
                let Some(file) =
                    source_pack_file_for_global_span(diagnostic_files, token_record.start)
                else {
                    return CompileError::GpuTypeCheck(format!(
                        "{}; failed to map diagnostic token {} at byte {} to a source-pack file",
                        err, token, token_record.start
                    ));
                };
                let local_start = file.local_start_for_global(token_record.start);
                call_mismatch_diagnostic(
                    &file.path,
                    &file.source,
                    local_start,
                    token_record.len,
                    *detail,
                )
            }
            Err(read_err) => CompileError::GpuTypeCheck(format!(
                "{}; failed to read diagnostic token {}: {}",
                err, token, read_err
            )),
        },
        _ => CompileError::GpuTypeCheck(err.to_string()),
    }
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
                "the GPU module resolver could not match this import path to a loaded module declaration",
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
                "quoted imports are not loaded by the GPU module resolver yet; use a module path such as import core::math",
            ),
    )
}

fn import_path_too_deep_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0012", "import path too deep")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "import path exceeds the current resolver depth limit",
            ))
            .with_note(
                "this compiler slice supports at most eight module path segments in an import",
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
                "module identity comes from GPU-parsed module declarations; each loaded source pack must declare every module path at most once",
            ),
    )
}

fn module_path_too_deep_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
) -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0014", "module path too deep")
            .with_primary_label(diagnostic_label_from_source_span(
                path,
                source,
                start,
                len,
                "module path exceeds the current resolver depth limit",
            ))
            .with_note(
                "this compiler slice supports at most eight module path segments in a module declaration",
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
            .with_note(
                "module identity must come from a non-empty GPU-parsed module path declaration",
            ),
    )
}

fn unresolved_identifier_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> CompileError {
    const TYPECHECK_DETAIL_PATH_TOO_DEEP: u32 = 0xffffff05;
    let (label, note) = if detail == TYPECHECK_DETAIL_PATH_TOO_DEEP {
        (
            "value path exceeds the current resolver depth limit",
            "this compiler slice supports at most eight module path segments before the leaf value",
        )
    } else {
        (
            "not found in this scope",
            "declare the value before using it or import its defining module",
        )
    };

    CompileError::Diagnostic(
        Diagnostic::error("LNC0005", "unresolved identifier")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
    )
}

fn unknown_type_diagnostic(
    path: &Path,
    source: &str,
    start: usize,
    len: usize,
    detail: u32,
) -> CompileError {
    const TYPECHECK_DETAIL_PATH_TOO_DEEP: u32 = 0xffffff05;
    let (label, note) = if detail == TYPECHECK_DETAIL_PATH_TOO_DEEP {
        (
            "type path exceeds the current resolver depth limit",
            "this compiler slice supports at most eight module path segments before the leaf type",
        )
    } else {
        (
            "type not found",
            "declare the type before using it or import its defining module",
        )
    };

    CompileError::Diagnostic(
        Diagnostic::error("LNC0007", "unknown type")
            .with_primary_label(diagnostic_label_from_source_span(
                path, source, start, len, label,
            ))
            .with_note(note),
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
    const PREDICATE_STATUS_BOUND_PATH_TOO_DEEP: u32 = 29;

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
            "name a trait in the bound before relying on GPU predicate solving",
        ),
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_WIDTH =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound exceeds the current GPU predicate argument limit",
                "this compiler slice records at most two trait type arguments per predicate row",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_ARG_SHAPE =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound argument shape is not supported by the current GPU predicate row",
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
                "trait bounds on this generic declaration are not enforced by the current GPU predicate solver",
                "move the bound to a called function or add GPU instantiation obligation rows before relying on declaration-level trait bounds",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_OBLIGATION_WINDOW =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait obligation exceeds the current GPU predicate solver window",
                "this compiler slice matches call obligations only when call argument metadata and predicate-owner ranges fit in the bounded GPU records",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_UNSUPPORTED_BOUND_ARG_RELATION =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound relation is outside the current GPU predicate row shape",
                "this generic type pattern is not supported in this position yet; the compiler rejects it rather than matching only the visible top-level type",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_BOUND_PATH_TOO_DEEP =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound path exceeds the current GPU predicate path limit",
                "this compiler slice resolves at most eight module path segments before the trait or bound-argument leaf",
            )
        }
        GpuTypeCheckCode::TraitBoundUnsatisfied => (
            "LNC0008",
            "unsatisfied trait bound",
            "no matching impl satisfies this call",
            "the GPU predicate solver found no concrete impl for the call's inferred type arguments",
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
            "trait impl header exceeds the current GPU predicate argument limit",
            "this compiler slice records at most two trait type arguments per trait impl row",
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
            "trait impl target type is outside the current GPU predicate row shape",
            "trait impl predicate rows currently match only scalar and non-generic nominal targets; add target type-argument rows before implementing traits for generic instances",
        ),
        15 => (
            "trait impl header contains an unknown trait argument type",
            "resolve every recorded trait type argument to a scalar or nominal type before implementing the trait",
        ),
        16 => (
            "trait method-level generics are outside the current GPU trait contract records",
            "move the generic parameter to the trait or impl receiver type until method-level generic substitution is implemented on GPU",
        ),
        17 => (
            "trait method where clauses are outside the current GPU trait contract records",
            "move the bound to the trait, impl, or caller-visible where clause until method-level predicate solving is implemented on GPU",
        ),
        19 => (
            "trait impl overlaps an existing impl for the same trait and target",
            "make each supported trait impl key unique before relying on GPU trait solving",
        ),
        20 => (
            "trait declares duplicate method contracts",
            "give each method in a trait a unique name until GPU trait method overload resolution is implemented",
        ),
        23 => (
            "trait impl declares a method not required by the trait",
            "remove extra impl methods or declare the method in the resolved trait contract",
        ),
        24 => (
            "trait impl declares duplicate methods for the same trait contract",
            "give each implemented trait method a unique name before GPU trait contract validation",
        ),
        25 => (
            "trait impl visibility does not match the resolved trait contract",
            "public trait impls and public traits must agree until GPU obligation matching carries module-scoped impl visibility rows",
        ),
        26 => (
            "trait impl method visibility does not match the trait declaration",
            "match each impl method's visibility to the resolved trait method contract",
        ),
        27 => (
            "trait impl method contract rows are not valid for GPU validation",
            "rebuild compact trait-method validation rows before accepting this trait impl",
        ),
        28 => (
            "trait impl header uses generic trait arguments outside the current GPU predicate row shape",
            "publish trait impl argument rows that carry generic-parameter references before accepting generic impl headers",
        ),
        29 => (
            "trait impl header path exceeds the current GPU predicate path limit",
            "this compiler slice resolves at most eight module path segments before the trait or argument leaf",
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
            "method return type is outside the current GPU substitution records",
            "publish method return substitution rows keyed by receiver type-instance arguments before accepting generic method returns",
        ),
        CALL_MISMATCH_UNSUPPORTED_METHOD_GENERIC => (
            "method-level generics are outside the current GPU method-call records",
            "publish explicit method-level generic substitution rows before accepting generic method dispatch",
        ),
        CALL_MISMATCH_UNSUPPORTED_METHOD_WHERE => (
            "method-level where clauses are outside the current GPU method-call records",
            "publish method predicate obligation rows before accepting method-level where clauses",
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
