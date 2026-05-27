// src/compiler/gpu_compiler/typecheck.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.type_check_expanded_source(&src).await
    }
    pub async fn type_check_source_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_from_path(path)?;
        self.type_check_expanded_source(&src).await
    }
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
    pub async fn type_check_source_pack_manifest(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<(), CompileError> {
        self.type_check_source_pack(&source_pack.sources).await
    }
    pub(in crate::compiler) async fn type_check_expanded_source(
        &self,
        src: &str,
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
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
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
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok(type_check)
                },
                |device, _queue, _bufs, type_check| {
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }
    pub(super) async fn type_check_explicit_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
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
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
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
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok(type_check)
                },
                |device, _queue, type_check| {
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }
    #[allow(clippy::too_many_arguments)]
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
        timer: Option<&mut GpuTimer>,
    ) -> Result<gpu_type_checker::RecordedTypeCheck, CompileError> {
        // Typecheck metadata remains live across late module/generic/match
        // passes and is retained for x86 lowering. Keep it in typechecker-owned
        // rows instead of parser scratch so source-pack parser workspaces can
        // be replayed without corrupting semantic records.
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
            record_family_flag: &parse_bufs.hir_type_alias_owner_value_a,
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
