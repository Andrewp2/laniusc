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

    /// Type-checks one bounded library against already-materialized dependency
    /// semantic interfaces.
    pub async fn type_check_source_pack_with_dependencies<S: AsRef<str>>(
        &self,
        library_id: u32,
        sources: &[S],
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
    ) -> Result<(), CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "type check source pack with dependencies",
            sources,
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            0,
            dependency_interfaces,
            false,
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
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "semantic interface source pack",
            sources,
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            0,
            &[],
            true,
        )
        .await?
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
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "semantic interface source pack with dependencies",
            sources,
        )?;
        self.type_check_explicit_source_pack_with_paths_and_interface(
            sources,
            None,
            Some(library_id),
            unit_id,
            dependency_interfaces,
            true,
        )
        .await?
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
                    let parser_capacity = self
                        .parser
                        .measure_resident_partial_parse_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source(&diagnostic_path, src, err)
                        })?;
                    let parser_tree_capacity = parser_capacity.tree_capacity;
                    let parser_feature_flags = parser_capacity.parser_feature_flags;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            parser_feature_flags,
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source(&diagnostic_path, src, err)
                        })?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = parser_check.read_status_result(device).map_err(|err| {
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
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
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
                        None,
                        timer.as_deref_mut(),
                        |err| type_check_execution_failed_for_source(&diagnostic_path, src, err),
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
            &[],
            false,
        )
        .await
        .map(|_| ())
    }

    async fn type_check_explicit_source_pack_with_paths_and_interface<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
        library_id: Option<u32>,
        unit_id: u32,
        dependency_interfaces: &[crate::compiler::GpuSemanticInterfaceArtifact],
        emit_semantic_interface: bool,
    ) -> Result<Option<crate::compiler::GpuSemanticInterfaceArtifact>, CompileError> {
        let diagnostic_files = source_pack_diagnostic_files(sources, source_paths);
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        let dependency_state = match library_id {
            Some(_) if dependency_interfaces.is_empty() => None,
            Some(library_id) => Some(
                gpu_type_checker::GpuDependencyInterfaceState::new(
                    &self.gpu.device,
                    library_id,
                    unit_id,
                    dependency_interfaces,
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
                    let token_capacity = token_count.max(1);
                    let parser_capacity = self
                        .parser
                        .measure_resident_partial_parse_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source_pack(&diagnostic_files, err)
                        })?;
                    let parser_tree_capacity = parser_capacity.tree_capacity;
                    let parser_feature_flags = parser_capacity.parser_feature_flags;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.source_pack.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            parser_feature_flags,
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source_pack(&diagnostic_files, err)
                        })?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = parser_check.read_status_result(device).map_err(|err| {
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
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
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
                        dependency_state.as_ref(),
                        timer.as_deref_mut(),
                        |err| type_check_execution_failed_for_source_pack(&diagnostic_files, err),
                    )?;
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
                                    encoder,
                                    library_id,
                                    unit_id,
                                    bufs.n,
                                    &bufs.in_bytes,
                                    typecheck_parse.semantic_interface_hir_buffers(),
                                )
                                .map_err(|err| {
                                    CompileError::GpuFrontend(format!(
                                        "semantic-interface identity recording failed: {err}"
                                    ))
                                })
                        })
                        .transpose()?;
                    Ok(RecordedTypeCheckWithDiagnosticBuffers {
                        type_check,
                        diagnostic_tokens: DiagnosticTokenBuffer::from_lexer_buffers(bufs),
                        semantic_interface,
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
                        })?;
                    recorded
                        .semantic_interface
                        .as_ref()
                        .map(|identity| {
                            self.type_checker
                                .finish_semantic_interface(device, identity)
                                .map_err(|err| {
                                    CompileError::GpuFrontend(format!(
                                        "semantic-interface readback failed: {err}"
                                    ))
                                })
                        })
                        .transpose()
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
        parse_bufs: &OwnedTypecheckParserBuffers,
        hir_node_capacity: u32,
        parser_hir_node_capacity: u32,
        dependency_interfaces: Option<&gpu_type_checker::GpuDependencyInterfaceState>,
        timer: Option<&mut GpuTimer>,
        map_execution_error: impl FnOnce(GpuTypeCheckError) -> CompileError,
    ) -> Result<gpu_type_checker::RecordedTypeCheck, CompileError> {
        let module_path_scratch =
            Self::typecheck_external_scratch_from_frontend_buffers(lexer_bufs, parse_bufs);
        self.type_checker
            .record_resident_token_buffer_with_hir_items_and_scratch_on_gpu(
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
                module_path_scratch,
                dependency_interfaces,
                timer,
            )
            .map_err(map_execution_error)
    }

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
            record_family_flag: Some(&parse_bufs.hir_list_rank_flag),
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
            path_kind: &parse_bufs.hir_match_arm_owner_a,
        }
    }
}

struct RecordedTypeCheckWithDiagnosticBuffers {
    type_check: gpu_type_checker::RecordedTypeCheck,
    diagnostic_tokens: DiagnosticTokenBuffer,
    semantic_interface: Option<gpu_type_checker::RecordedSemanticInterface>,
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

pub(super) fn type_check_error_to_compile_error_for_source_pack_tokens(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &LaniusBuffer<crate::lexer::GpuToken>,
    diagnostic_files: &[DiagnosticSourceFile],
    err: GpuTypeCheckError,
) -> CompileError {
    let diagnostic_tokens = DiagnosticTokenBuffer {
        buffer: token_buffer.clone(),
        byte_size: token_buffer.byte_size,
    };
    type_check_error_to_compile_error_for_source_pack(
        device,
        queue,
        &diagnostic_tokens,
        diagnostic_files,
        err,
    )
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
    err: impl std::fmt::Display,
) -> CompileError {
    stage_execution_failed_for_source(type_check_execution_failure(), diagnostic_path, source, err)
}

pub(in crate::compiler::gpu_compiler) fn type_check_execution_failed_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
    err: impl std::fmt::Display,
) -> CompileError {
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
        GpuTypeCheckCode::ImportPathTooDeep => {
            import_path_too_deep_diagnostic(path, source, start, len)
        }
        GpuTypeCheckCode::DuplicateModule => duplicate_module_diagnostic(path, source, start, len),
        GpuTypeCheckCode::ModulePathTooDeep => {
            module_path_too_deep_diagnostic(path, source, start, len)
        }
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
                "this compiler currently supports at most eight module path segments in an import",
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
                "this compiler currently supports at most eight module path segments in a module declaration",
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
    detail: u32,
) -> CompileError {
    const TYPECHECK_DETAIL_PATH_TOO_DEEP: u32 = 0xffffff05;
    let (label, note) = if detail == TYPECHECK_DETAIL_PATH_TOO_DEEP {
        (
            "value path exceeds the current resolver depth limit",
            "this compiler currently supports at most eight module path segments before the leaf value",
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
            "this compiler currently supports at most eight module path segments before the leaf type",
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
        GpuTypeCheckCode::TraitBoundUnsatisfied
            if detail == PREDICATE_STATUS_BOUND_PATH_TOO_DEEP =>
        {
            (
                "LNC0008",
                "unsatisfied trait bound",
                "trait bound path exceeds the current trait path limit",
                "this compiler currently resolves at most eight module path segments before the trait or bound-argument leaf",
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
            "trait impl header path exceeds the current trait path limit",
            "this compiler currently resolves at most eight module path segments before the trait or argument leaf",
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
