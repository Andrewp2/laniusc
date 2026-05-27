// src/compiler/gpu_compiler/x86_codegen.rs

use super::*;

impl<'gpu> GpuCompiler<'gpu> {
    pub(super) fn x86_generator(&self) -> Result<&x86::GpuX86CodeGenerator, CompileError> {
        self.x86_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU x86 code generator: {err}"))
        })
    }
    #[allow(clippy::too_many_arguments)]
    fn record_x86_from_parse_buffers_with_codegen(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        x86_hir_node_count: u32,
        x86_inst_hir_node_count: u32,
        parse_bufs: &OwnedX86ParserBuffers,
        codegen: gpu_type_checker::GpuX86CodegenBuffers<'_>,
        feature_summary: x86::X86FeatureSummary,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<x86::RecordedX86Codegen, CompileError> {
        let hir_status = &parse_bufs.ll1_status;
        let external_scratch = Self::x86_external_scratch_from_frontend_and_codegen_buffers(
            parse_bufs,
            codegen,
            token_capacity,
            feature_summary,
        );
        self.x86_generator()?
            .record_elf_from_hir(
                device,
                queue,
                encoder,
                x86::RecordElfInputs {
                    source_len,
                    token_capacity,
                    n_hir_nodes: x86_hir_node_count,
                    inst_hir_node_count: x86_inst_hir_node_count,
                    hir_status_buf: hir_status,
                    active_hir_dispatch_args_buf: &parse_bufs.tree_active_dispatch_args,
                    hir_kind_buf: &parse_bufs.hir_kind,
                    parent_buf: &parse_bufs.parent,
                    subtree_end_buf: &parse_bufs.subtree_end,
                    function_metadata: x86::GpuX86FunctionMetadataBuffers {
                        node_decl_token: &parse_bufs.hir_item_decl_token,
                        node_name_token: &parse_bufs.hir_item_name_token,
                        hir_token_pos: &parse_bufs.hir_token_pos,
                        fn_return_type_node: &parse_bufs.hir_fn_return_type_node,
                        param_record: &parse_bufs.hir_param_record,
                        enclosing_fn: codegen.enclosing_fn,
                        method_decl_param_offset: codegen.method_decl_param_offset,
                        method_decl_receiver_ref_tag: codegen.method_decl_receiver_ref_tag,
                        method_decl_receiver_ref_payload: codegen.method_decl_receiver_ref_payload,
                    },
                    expr_metadata: x86::GpuX86ExprMetadataBuffers {
                        record: &parse_bufs.hir_expr_record,
                        int_value: &parse_bufs.hir_expr_int_value,
                        stmt_record: &parse_bufs.hir_stmt_record,
                        type_form: &parse_bufs.hir_type_form,
                        type_len_value: &parse_bufs.hir_type_len_value,
                    },
                    call_metadata: x86::GpuX86CallMetadataBuffers {
                        callee_node: &parse_bufs.hir_call_callee_node,
                        arg_start: &parse_bufs.hir_call_arg_start,
                        arg_end: &parse_bufs.hir_call_arg_end,
                        arg_count: &parse_bufs.hir_call_arg_count,
                        arg_parent_call: &parse_bufs.hir_call_arg_parent_call,
                        arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                        member_receiver_node: &parse_bufs.hir_member_receiver_node,
                        member_name_token: &parse_bufs.hir_member_name_token,
                        call_fn_index: codegen.call_fn_index,
                        call_intrinsic_tag: codegen.call_intrinsic_tag,
                        call_return_type: codegen.call_return_type,
                        call_return_type_token: codegen.call_return_type_token,
                        call_param_type: codegen.call_param_type,
                    },
                    array_metadata: x86::GpuX86ArrayMetadataBuffers {
                        lit_first_element: &parse_bufs.hir_array_lit_first_element,
                        lit_element_count: &parse_bufs.hir_array_lit_element_count,
                        element_parent_lit: &parse_bufs.hir_array_element_parent_lit,
                        element_ordinal: &parse_bufs.hir_array_element_ordinal,
                        element_next: &parse_bufs.hir_array_element_next,
                    },
                    enum_metadata: x86::GpuX86EnumMetadataBuffers {
                        item_decl_token: &parse_bufs.hir_item_decl_token,
                        variant_parent_enum: &parse_bufs.hir_variant_parent_enum,
                        variant_ordinal: &parse_bufs.hir_variant_ordinal,
                        variant_payload_count: &parse_bufs.hir_variant_payload_count,
                        match_scrutinee_node: &parse_bufs.hir_match_scrutinee_node,
                        match_arm_start: &parse_bufs.hir_match_arm_start,
                        match_arm_count: &parse_bufs.hir_match_arm_count,
                        match_arm_next: &parse_bufs.hir_match_arm_next,
                        match_arm_pattern_node: &parse_bufs.hir_match_arm_pattern_node,
                        match_arm_payload_start: &parse_bufs.hir_match_arm_payload_start,
                        match_arm_payload_count: &parse_bufs.hir_match_arm_payload_count,
                        match_arm_result_node: &parse_bufs.hir_match_arm_result_node,
                        hir_token_pos: &parse_bufs.hir_token_pos,
                        path_count_out: codegen.path_count_out,
                        path_id_by_owner_hir: codegen.path_id_by_owner_hir,
                        resolved_value_decl: codegen.resolved_value_decl,
                        resolved_value_status: codegen.resolved_value_status,
                        decl_count_out: codegen.decl_count_out,
                        decl_kind: codegen.decl_kind,
                        decl_name_token: codegen.decl_name_token,
                        decl_id_by_name_token: codegen.decl_id_by_name_token,
                        decl_hir_node: codegen.decl_hir_node,
                        decl_parent_type_decl: codegen.decl_parent_type_decl,
                    },
                    struct_metadata: x86::GpuX86StructMetadataBuffers {
                        item_name_token: &parse_bufs.hir_item_name_token,
                        decl_hir_node: codegen.decl_hir_node,
                        struct_decl_field_count: &parse_bufs.hir_struct_decl_field_count,
                        struct_lit_field_parent_lit: &parse_bufs.hir_struct_lit_field_parent_lit,
                        struct_lit_field_start: &parse_bufs.hir_struct_lit_field_start,
                        struct_lit_field_count: &parse_bufs.hir_struct_lit_field_count,
                        struct_lit_field_value_node: &parse_bufs.hir_struct_lit_field_value_node,
                        struct_lit_field_next: &parse_bufs.hir_struct_lit_field_next,
                        member_result_field_ordinal: codegen.member_result_field_ordinal,
                        struct_init_field_ordinal: codegen.struct_init_field_ordinal,
                        struct_init_field_ordinal_by_node: codegen
                            .struct_init_field_ordinal_by_node,
                    },
                    type_metadata: x86::GpuX86TypeMetadataBuffers {
                        decl_type_ref_tag: codegen.decl_type_ref_tag,
                        decl_type_ref_payload: codegen.decl_type_ref_payload,
                        visible_type: codegen.visible_type,
                        type_instance_kind: codegen.type_instance_kind,
                        type_instance_decl_token: codegen.type_instance_decl_token,
                        type_instance_len_kind: codegen.type_instance_len_kind,
                        type_instance_len_payload: codegen.type_instance_len_payload,
                    },
                    visible_decl_buf: codegen.visible_decl,
                    fn_entrypoint_tag_buf: codegen.fn_entrypoint_tag,
                    feature_summary,
                    external_scratch,
                    timer: timer.as_deref_mut(),
                },
            )
            .map_err(|err| CompileError::GpuCodegen(err.to_string()))
    }
    fn x86_external_scratch_from_frontend_and_codegen_buffers<'a>(
        parse_bufs: &'a OwnedX86ParserBuffers,
        codegen: gpu_type_checker::GpuX86CodegenBuffers<'a>,
        token_capacity: u32,
        feature_summary: x86::X86FeatureSummary,
    ) -> x86::GpuX86ExternalScratchBuffers<'a> {
        // x86 backend recording starts only after typecheck has finished and
        // taken ownership of its codegen metadata. These parser HIR/type
        // workspace rows are not read by the backend input surface; borrowing
        // them here is the explicit arena-lifetime boundary between frontend
        // and backend.
        let token_words = token_capacity.max(1) as usize;
        x86::GpuX86ExternalScratchBuffers {
            expr_resolved_final: None,
            node_func: Some(&parse_bufs.hir_type_value_node),
            func_owner_scan_local_prefix: None,
            func_slot_by_node: Some(&parse_bufs.hir_type_len_token),
            match_pattern_owner: Some(&parse_bufs.hir_type_path_leaf_node),
            match_pattern_node_owner: Some(&parse_bufs.hir_type_arg_start),
            match_pattern_node_variant: Some(&parse_bufs.hir_type_arg_count),
            match_pattern_node_payload_decl: Some(&parse_bufs.hir_type_arg_next),
            match_pattern_first_use_node: Some(&parse_bufs.hir_type_alias_target_node),
            enclosing_let_node_a: None,
            enclosing_let_node_b: Some(&parse_bufs.hir_semantic_dense_node),
            node_inst_same_end_link_a: Some(&parse_bufs.hir_variant_payload_owner_a),
            node_inst_same_end_link_b: Some(&parse_bufs.hir_variant_payload_owner_b),
            node_inst_scan_local_prefix: None,
            call_record: if !feature_summary.has_call() && !feature_summary.has_param() {
                Some(&parse_bufs.hir_param_record)
            } else {
                None
            },
            call_type_record: None,
            node_inst_count_info: Some(codegen.fn_entrypoint_tag),
            node_inst_count_payload: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_range_start: Some(&parse_bufs.hir_type_path_leaf_link_a),
            node_inst_range_info: Some(&parse_bufs.hir_type_path_leaf_link_b),
            node_inst_subtree_bound_start: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_subtree_bound_end: Some(&parse_bufs.hir_array_element_previous),
            node_inst_gen_node_record: None,
            decl_layout_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_kind,
                token_words * 4,
            ),
            const_value_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_namespace,
                token_words * 2,
            ),
            param_reg_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_visibility,
                token_words * 5,
            ),
            local_literal_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_path_start,
                token_words * 3,
            ),
        }
    }
    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }
    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }
    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to x86_64",
            sources,
        )?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.record");
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
                    host_timer.stamp("projected_tree_capacity");
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.source_pack.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, semantic_count) = self
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
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                host_timer.stamp("parser_recorded");
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    host_timer.stamp("parser_submitted");
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count?)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
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
                    host_timer.stamp("parser_cache_released");
                    let lexer_parse_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(bufs);
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
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok((
                        type_check,
                        token_count,
                        active_tree_capacity,
                        semantic_hir_count,
                        parser_tree_capacity,
                        lexer_parse_inputs,
                    ))
                },
                |device,
                 queue,
                 (
                    type_check,
                    token_count,
                    active_tree_capacity,
                    semantic_hir_count,
                    parser_tree_capacity,
                    lexer_parse_inputs,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let mut codegen_buffers =
                        self.type_checker
                            .take_x86_codegen_buffers()
                            .ok_or_else(|| {
                                CompileError::GpuCodegen(
                                    "GPU x86 type metadata buffers missing".into(),
                                )
                            })?;
                    host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                    let token_capacity = token_count.max(1);
                    let x86_hir_node_count = active_tree_capacity.max(1);
                    let x86_inst_hir_node_count = x86_inst_hir_node_count_for_backend_capacity(
                        active_tree_capacity,
                        semantic_hir_count,
                    );
                    codegen_buffers.copy_backend_metadata_before_parser_replay(
                        device,
                        queue,
                        token_capacity.max(x86_hir_node_count),
                    );
                    let mut x86_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.source_pack.backend.encoder"),
                        });
                    let (x86_parse, reparsed_active_tree_capacity, reparsed_semantic_hir_count) =
                        self.reparse_x86_parser_buffers_from_lexer_inputs(
                            device,
                            queue,
                            &lexer_parse_inputs,
                            token_capacity,
                            parser_tree_capacity,
                        )?;
                    if reparsed_active_tree_capacity != active_tree_capacity
                        || reparsed_semantic_hir_count != semantic_hir_count
                    {
                        return Err(CompileError::GpuSyntax(format!(
                            "source-pack backend parser replay changed HIR capacity/count: initial=({active_tree_capacity}, {semantic_hir_count}) replay=({reparsed_active_tree_capacity}, {reparsed_semantic_hir_count})"
                        )));
                    }
                    let feature_summary = self
                        .x86_generator()?
                        .measure_features(
                            device,
                            queue,
                            token_capacity,
                            x86_hir_node_count,
                            &x86_parse.ll1_status,
                            &x86_parse.hir_kind,
                            &x86_parse.hir_stmt_record,
                            &x86_parse.hir_expr_record,
                            &x86_parse.hir_token_pos,
                            &x86_parse.parent,
                            &x86_parse.first_child,
                            codegen_buffers.as_ref().enclosing_fn,
                        )
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                        device,
                        queue,
                        &mut x86_encoder,
                        lexer_parse_inputs.source_len,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        &x86_parse,
                        codegen_buffers.as_ref(),
                        feature_summary,
                        None,
                    )?;
                    host_timer.stamp("x86_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.source_pack.backend",
                        x86_encoder.finish(),
                    );
                    host_timer.stamp("x86_submitted");
                    let result = x86_check
                        .read_output(device, queue)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }
    pub async fn compile_source_pack_manifest_to_x86_64(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64(&source_pack.sources)
            .await
    }
    fn reparse_x86_parser_buffers_from_lexer_inputs(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        lexer_inputs: &OwnedLexerParserInputBuffers,
        token_capacity: u32,
        parser_tree_capacity: u32,
    ) -> Result<(OwnedX86ParserBuffers, u32, u32), CompileError> {
        let mut parser_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("compiler.x86.backend-parser-boundary.encoder"),
        });
        let mut parser_timer: Option<&mut GpuTimer> = None;
        let (parser_check, semantic_count) = self
            .parser
            .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                &mut parser_encoder,
                token_capacity,
                &lexer_inputs.tokens_out,
                &lexer_inputs.token_count,
                Some(&lexer_inputs.token_file_id),
                lexer_inputs.source_len,
                &lexer_inputs.in_bytes,
                &self.parse_tables,
                Some(parser_tree_capacity),
                &mut parser_timer,
                |parse_bufs, encoder, timer| {
                    self.parser
                        .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                },
            )
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "compiler.x86.backend-parser-boundary",
            parser_encoder.finish(),
        );
        let ll1 = self
            .parser
            .finish_recorded_resident_ll1_hir_check_result(&parser_check)
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        let semantic_hir_count = self
            .parser
            .finish_recorded_hir_semantic_count(&semantic_count?)
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        let active_tree_capacity =
            hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
        let x86_parse = self
            .parser
            .with_current_resident_buffers_with_tree_capacity(
                token_capacity,
                &self.parse_tables,
                parser_tree_capacity,
                OwnedX86ParserBuffers::from_parser_buffers,
            );
        self.parser.release_current_resident_buffers();
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        Ok((x86_parse, active_tree_capacity, semantic_hir_count))
    }
    pub(in crate::compiler) async fn compile_expanded_source_to_x86_64(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count_releasing_lexer(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.record");
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
                    host_timer.stamp("projected_tree_capacity");
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, semantic_count) = self
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
                            |parse_bufs, encoder, timer| {
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.parser-boundary",
                        parser_encoder.finish(),
                    );
                    host_timer.stamp("parser_submitted");
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count?)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
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
                    host_timer.stamp("parser_cache_released");
                    let lexer_parse_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(bufs);
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
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok((
                        type_check,
                        token_count,
                        active_tree_capacity,
                        semantic_hir_count,
                        bufs.n,
                        parser_tree_capacity,
                        lexer_parse_inputs,
                    ))
                },
                |device,
                 queue,
                 (
                    type_check,
                    token_count,
                    active_tree_capacity,
                    semantic_hir_count,
                    source_len,
                    parser_tree_capacity,
                    lexer_parse_inputs,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let mut codegen_buffers = self
                        .type_checker
                        .take_x86_codegen_buffers()
                        .ok_or_else(|| {
                            CompileError::GpuCodegen("GPU x86 type metadata buffers missing".into())
                        })?;
                    host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                    let token_capacity = token_count.max(1);
                    let x86_hir_node_count = active_tree_capacity.max(1);
                    let x86_inst_hir_node_count = x86_inst_hir_node_count_for_backend_capacity(
                        active_tree_capacity,
                        semantic_hir_count,
                    );
                    codegen_buffers.copy_backend_metadata_before_parser_replay(
                        device,
                        queue,
                        token_capacity.max(x86_hir_node_count),
                    );
                    let (x86_parse, reparsed_active_tree_capacity, reparsed_semantic_hir_count) =
                        self.reparse_x86_parser_buffers_from_lexer_inputs(
                            device,
                            queue,
                            &lexer_parse_inputs,
                            token_capacity,
                            parser_tree_capacity,
                        )?;
                    if reparsed_active_tree_capacity != active_tree_capacity
                        || reparsed_semantic_hir_count != semantic_hir_count
                    {
                        return Err(CompileError::GpuSyntax(format!(
                            "backend parser replay changed HIR capacity/count: initial=({active_tree_capacity}, {semantic_hir_count}) replay=({reparsed_active_tree_capacity}, {reparsed_semantic_hir_count})"
                        )));
                    }
                    let mut x86_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.backend.encoder"),
                        });
                    let feature_summary = self
                        .x86_generator()?
                        .measure_features(
                            device,
                            queue,
                            token_capacity,
                            x86_hir_node_count,
                            &x86_parse.ll1_status,
                            &x86_parse.hir_kind,
                            &x86_parse.hir_stmt_record,
                            &x86_parse.hir_expr_record,
                            &x86_parse.hir_token_pos,
                            &x86_parse.parent,
                            &x86_parse.first_child,
                            codegen_buffers.as_ref().enclosing_fn,
                        )
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                        device,
                        queue,
                        &mut x86_encoder,
                        source_len,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        &x86_parse,
                        codegen_buffers.as_ref(),
                        feature_summary,
                        None,
                    )?;
                    host_timer.stamp("x86_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.backend",
                        x86_encoder.finish(),
                    );
                    host_timer.stamp("x86_submitted");
                    let result = x86_check
                        .read_output(device, queue)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }
}
