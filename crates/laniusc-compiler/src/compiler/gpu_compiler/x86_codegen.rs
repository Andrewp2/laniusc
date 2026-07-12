// src/compiler/gpu_compiler/x86_codegen.rs

use super::*;
use crate::{
    lexer::{GpuToken, Token, util::read_tokens_from_mapped},
    type_checker::GpuTypeCheckError,
};

enum RecordedSourcePackX86 {
    Fused {
        check: x86::RecordedX86Codegen,
        plan: SourcePackX86Plan,
    },
    Split {
        features: x86::RecordedX86FeatureMeasurement,
    },
}

impl<'gpu> GpuCompiler<'gpu> {
    /// Returns the initialized x86 code generator or its deferred initialization error.
    pub(super) fn x86_generator(&self) -> Result<&x86::GpuX86CodeGenerator, &str> {
        self.x86_generator.as_deref().map_err(String::as_str)
    }
    #[allow(clippy::too_many_arguments)]
    fn record_x86_from_parse_buffers_with_codegen(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_bytes_buf: &wgpu::Buffer,
        token_capacity: u32,
        x86_hir_node_count: u32,
        x86_inst_hir_node_count: u32,
        parse_bufs: &OwnedX86ParserBuffers,
        codegen: gpu_type_checker::GpuX86CodegenBuffers<'_>,
        feature_summary: x86::X86FeatureSummary,
        mut timer: Option<&mut GpuTimer>,
        map_backend_error: impl Fn(String) -> CompileError,
    ) -> Result<x86::RecordedX86Codegen, CompileError> {
        let hir_status = &parse_bufs.ll1_status;
        let external_scratch = Self::x86_external_scratch_from_frontend_buffers(
            parse_bufs,
            token_capacity,
            feature_summary,
        );
        self.x86_generator
            .as_deref()
            .map_err(|err| map_backend_error(format!("initialize x86 code generator: {err}")))?
            .record_elf_from_hir(
                device,
                queue,
                encoder,
                x86::RecordElfInputs {
                    source_len,
                    source_bytes_buf,
                    token_capacity,
                    n_hir_nodes: x86_hir_node_count,
                    inst_hir_node_count: x86_inst_hir_node_count,
                    hir_status_buf: hir_status,
                    active_hir_dispatch_args_buf: &parse_bufs.tree_active_dispatch_args,
                    hir_kind_buf: &parse_bufs.hir_kind,
                    hir_item_kind_buf: &parse_bufs.hir_item_kind,
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
                        method_decl_receiver_mode: codegen.method_decl_receiver_mode,
                        method_decl_receiver_ref_tag: codegen.method_decl_receiver_ref_tag,
                        method_decl_receiver_ref_payload: codegen.method_decl_receiver_ref_payload,
                    },
                    expr_metadata: x86::GpuX86ExprMetadataBuffers {
                        record: &parse_bufs.hir_expr_record,
                        expr_result_root_node: &parse_bufs.hir_expr_result_root_node,
                        int_value: &parse_bufs.hir_expr_int_value,
                        float_bits: &parse_bufs.hir_expr_float_bits,
                        string_start: &parse_bufs.hir_expr_string_start,
                        string_len: &parse_bufs.hir_expr_string_len,
                        string_data_offset: &parse_bufs.hir_string_data_offset,
                        string_decoded_len: &parse_bufs.hir_string_decoded_len,
                        string_data_words: &parse_bufs.hir_string_data_words,
                        string_node: &parse_bufs.hir_string_node,
                        string_count: &parse_bufs.hir_string_count,
                        stmt_record: &parse_bufs.hir_stmt_record,
                        type_form: &parse_bufs.hir_type_form,
                        type_len_value: &parse_bufs.hir_type_len_value,
                    },
                    call_metadata: x86::GpuX86CallMetadataBuffers {
                        name_id_by_token: codegen.name_id_by_token,
                        language_name_id: codegen.language_name_id,
                        path_count_out: codegen.path_count_out,
                        path_id_by_owner_hir: codegen.path_id_by_owner_hir,
                        resolved_value_decl: codegen.resolved_value_decl,
                        resolved_value_status: codegen.resolved_value_status,
                        decl_name_token: codegen.decl_name_token,
                        callee_node: &parse_bufs.hir_call_callee_node,
                        context_stmt_node: &parse_bufs.hir_call_context_stmt_node,
                        arg_start: &parse_bufs.hir_call_arg_start,
                        arg_end: &parse_bufs.hir_call_arg_end,
                        arg_count: &parse_bufs.hir_call_arg_count,
                        arg_parent_call: &parse_bufs.hir_call_arg_parent_call,
                        arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                        arg_row_node: codegen.call_arg_row_node,
                        arg_row_start: codegen.call_arg_row_start,
                        arg_row_count: codegen.call_arg_row_count,
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
                        nearest_element: &parse_bufs.hir_nearest_array_element_node,
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
                        struct_lit_head_node: &parse_bufs.hir_struct_lit_head_node,
                        struct_lit_context_stmt_node: &parse_bufs.hir_struct_lit_context_stmt_node,
                        struct_field_parent_struct: &parse_bufs.hir_struct_field_parent_struct,
                        struct_field_ordinal: &parse_bufs.hir_struct_field_ordinal,
                        struct_field_type_node: &parse_bufs.hir_struct_field_type_node,
                        struct_decl_field_start: &parse_bufs.hir_struct_decl_field_start,
                        struct_lit_field_parent_lit: &parse_bufs.hir_struct_lit_field_parent_lit,
                        struct_lit_field_start: &parse_bufs.hir_struct_lit_field_start,
                        struct_lit_field_count: &parse_bufs.hir_struct_lit_field_count,
                        struct_lit_field_value_node: &parse_bufs.hir_struct_lit_field_value_node,
                        struct_lit_field_next: &parse_bufs.hir_struct_lit_field_next,
                        member_result_field_ordinal: codegen.member_result_field_ordinal,
                        member_result_field_node: codegen.member_result_field_node,
                        struct_init_field_ordinal: codegen.struct_init_field_ordinal,
                        struct_init_field_ordinal_by_node: codegen
                            .struct_init_field_ordinal_by_node,
                        struct_init_field_decl_node_by_node: codegen
                            .struct_init_field_decl_node_by_node,
                    },
                    type_metadata: x86::GpuX86TypeMetadataBuffers {
                        type_value_node: &parse_bufs.hir_type_value_node,
                        type_path_leaf_node: &parse_bufs.hir_type_path_leaf_node,
                        decl_type_ref_tag: codegen.decl_type_ref_tag,
                        decl_type_ref_payload: codegen.decl_type_ref_payload,
                        type_expr_ref_tag: codegen.type_expr_ref_tag,
                        type_expr_ref_payload: codegen.type_expr_ref_payload,
                        module_type_path_type: codegen.module_type_path_type,
                        type_decl_hir_node_by_token: codegen.type_decl_hir_node_by_token,
                        visible_type: codegen.visible_type,
                        type_instance_kind: codegen.type_instance_kind,
                        type_instance_decl_token: codegen.type_instance_decl_token,
                        type_instance_elem_ref_tag: codegen.type_instance_elem_ref_tag,
                        type_instance_elem_ref_payload: codegen.type_instance_elem_ref_payload,
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
            .map_err(|err| map_backend_error(err.to_string()))
    }
    fn x86_external_scratch_from_frontend_buffers<'a>(
        parse_bufs: &'a OwnedX86ParserBuffers,
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
            expr_resolved_final: Some(&parse_bufs.hir_type_len_value),
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
            // x86 function discovery reads fn_entrypoint_tag as frontend
            // evidence; do not alias it into backend scratch that is cleared
            // before discovery runs.
            node_inst_count_info: None,
            node_inst_count_payload: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_range_start: Some(&parse_bufs.hir_type_path_leaf_link_a),
            node_inst_range_info: Some(&parse_bufs.hir_type_path_leaf_link_b),
            node_inst_subtree_bound_start: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_subtree_bound_end: Some(&parse_bufs.hir_array_element_previous),
            node_inst_gen_node_record: None,
            // Function discovery reads hir_item_kind before layout lowering.
            // The decl-layout scratch is initialized at backend start, so it
            // must not alias that live parser HIR input.
            decl_layout_record: None,
            const_value_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_namespace,
                token_words * 2,
            ),
            param_reg_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_visibility,
                token_words * 6,
            ),
            local_literal_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_path_start,
                token_words * 3,
            ),
        }
    }
    /// Compile one in-memory source string through the x86_64 backend using
    /// `<source>` as the diagnostic path.
    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    /// Read a source file from disk and compile it through the x86_64 backend
    /// with diagnostics labeled by that path.
    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    /// Compile an in-memory source pack through the x86_64 backend after
    /// bounded codegen-unit validation.
    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(sources, None)
            .await
    }

    async fn compile_source_pack_to_x86_64_with_paths<S: AsRef<str>>(
        &self,
        sources: &[S],
        source_paths: Option<&[Option<PathBuf>]>,
    ) -> Result<Vec<u8>, CompileError> {
        if sources.is_empty() {
            return Err(x86_empty_source_pack_compile_error());
        }
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to x86_64",
            sources,
        )?;
        let diagnostic_files = source_pack_diagnostic_files(sources, source_paths);
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.record");
                    let token_capacity = token_count.max(1);
                    let parser_capacity =
                        if let Some(cached) = self.cached_source_pack_parser_capacity(sources) {
                            host_timer.stamp("partial_parse_tree_capacity.cache_hit");
                            cached
                        } else {
                            let measured = self
                                .parser
                                .measure_resident_partial_parse_capacity(
                                    token_capacity,
                                    &bufs.tokens_out,
                                    &bufs.token_count,
                                    Some(&bufs.token_file_id),
                                    &self.parse_tables,
                                )
                                .map_err(|err| {
                                    parser_execution_failed_for_source_pack(
                                        &diagnostic_files,
                                        err,
                                    )
                                })?;
                            self.remember_source_pack_parser_capacity(sources, measured);
                            host_timer.stamp("partial_parse_tree_capacity.measured");
                            measured
                        };
                    let parser_tree_capacity = parser_capacity.tree_capacity;
                    let parser_feature_flags = parser_capacity.parser_feature_flags;
                    if crate::gpu::env::env_bool_truthy(
                        "LANIUS_GPU_COMPILE_HOST_TIMING",
                        false,
                    ) {
                        let conservative_tree_capacity = self
                            .parser
                            .partial_parse_resident_tree_capacity(
                                token_capacity,
                                &self.parse_tables,
                            );
                        eprintln!(
                            "[gpu_compile_host_timer] compiler.x86.source_pack.parser_capacity: exact={parser_tree_capacity} conservative={conservative_tree_capacity} tokens={token_capacity}"
                        );
                    }
                    let (parser_check, parser_metadata) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity_and_features(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            parser_feature_flags,
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                host_timer.stamp("parser_recorded");
                                let semantic_count = self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| {
                                        parser_execution_failed_for_source_pack(
                                            &diagnostic_files,
                                            err,
                                        )
                                    })?;
                                let module_record_capacity = self
                                    .type_checker
                                    .record_module_record_capacity_preflight(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        parse_bufs,
                                    )
                                    .map_err(|err| {
                                        type_check_execution_failed_for_source_pack(
                                            &diagnostic_files,
                                            gpu_type_checker::GpuTypeCheckError::Gpu(err),
                                        )
                                    })?;
                                Ok((semantic_count, module_record_capacity))
                            },
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source_pack(&diagnostic_files, err)
                        })?;
                    let (semantic_count, module_record_capacity) = parser_metadata?;
                    // Submit the parser boundary before allocating typecheck
                    // resident state. At large input sizes, exact emit and
                    // semantic counts save far more allocation time and memory
                    // than overlapping parser execution with conservative
                    // typecheck allocation.
                    let next_encoder = device.create_command_encoder(
                        &wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.source_pack.typecheck-x86.encoder"),
                        },
                    );
                    let parser_encoder = std::mem::replace(encoder, next_encoder);
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    host_timer.stamp("parser_submitted");
                    let preflight_capacities = self
                        .type_checker
                        .finish_module_record_capacity_preflight(device, &module_record_capacity)
                        .map_err(|err| {
                            type_check_execution_failed_for_source_pack(
                                &diagnostic_files,
                                gpu_type_checker::GpuTypeCheckError::Gpu(err),
                            )
                        })?;
                    if crate::gpu::env::env_bool_truthy(
                        "LANIUS_GPU_COMPILE_HOST_TIMING",
                        false,
                    ) {
                        eprintln!(
                            "[gpu_compile_host_timer] compiler.x86.source_pack.preflight_capacities: modules={} params={} args={} tree={parser_tree_capacity} tokens={token_capacity}",
                            preflight_capacities.module_records,
                            preflight_capacities.call_param_rows,
                            preflight_capacities.call_arg_rows,
                        );
                    }
                    host_timer.stamp("module_record_capacity_finished");
                    let early_parser_metadata = if exact_typecheck_capacity_boundary_required(
                        parser_tree_capacity,
                    ) {
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
                        let semantic_hir_count = self
                            .parser
                            .finish_recorded_hir_semantic_count(&semantic_count)
                            .map_err(|err| {
                                parser_execution_failed_for_source_pack(&diagnostic_files, err)
                            })?;
                        host_timer.stamp("parser_capacity_finished");
                        Some((ll1, semantic_hir_count))
                    } else {
                        None
                    };
                    let active_tree_capacity = early_parser_metadata
                        .as_ref()
                        .map(|(ll1, _semantic_hir_count)| {
                            hir_node_capacity_for_parser_emit(
                                parser_tree_capacity,
                                ll1.emit_len,
                            )
                        })
                        .unwrap_or(parser_tree_capacity);
                    let mut typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    typecheck_parse.module_record_capacity = preflight_capacities.module_records;
                    typecheck_parse.call_param_row_capacity = preflight_capacities.call_param_rows;
                    typecheck_parse.call_arg_row_capacity = preflight_capacities.call_arg_rows;
                    let x86_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedX86ParserBuffers::from_parser_buffers,
                        );
                    // Keep parser buffers resident across daemon jobs. The cloned
                    // handles below and the type-check bind groups refer to these
                    // same buffers, so releasing the parser cache here only forces
                    // identical jobs to recreate both parser and type-check state.
                    host_timer.stamp("parser_cache_retained");
                    let x86_diagnostics = OwnedX86DiagnosticBuffers::from_lexer_buffers(bufs);
                    let x86_source_bytes = bufs.in_bytes.clone();
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
                        |err| type_check_execution_failed_for_source_pack(&diagnostic_files, err),
                    )?;
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    if timer.is_none()
                        && !crate::gpu::passes_core::validation_scopes_enabled()
                        && typecheck_submission_overlap_enabled()
                    {
                        let next_encoder = device.create_command_encoder(
                            &wgpu::CommandEncoderDescriptor {
                                label: Some("compiler.x86.source_pack.x86.overlap.encoder"),
                            },
                        );
                        let typecheck_encoder = std::mem::replace(encoder, next_encoder);
                        crate::gpu::passes_core::submit_with_progress(
                            queue,
                            "compiler.x86.source_pack.typecheck.overlap",
                            typecheck_encoder.finish(),
                        );
                        host_timer.stamp("typecheck_submitted_overlap");
                    }
                    let x86_recorded = if let Some(plan) =
                        self.cached_source_pack_x86_plan(sources)
                    {
                        let codegen_buffers = self
                            .type_checker
                            .clone_x86_codegen_buffers()
                            .ok_or_else(|| {
                                x86_backend_execution_failed_for_source_pack(
                                    &diagnostic_files,
                                    "x86 type metadata buffers are unavailable",
                                )
                            })?;
                        let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                            device,
                            queue,
                            encoder,
                            x86_diagnostics.source_len,
                            &x86_source_bytes,
                            token_capacity,
                            plan.active_tree_capacity.max(1),
                            x86_inst_hir_node_count_for_backend_capacity(
                                plan.active_tree_capacity,
                                plan.semantic_hir_count,
                            ),
                            &x86_parse,
                            codegen_buffers.as_ref(),
                            plan.feature_summary,
                            None,
                            |err| {
                                x86_backend_execution_failed_for_source_pack(
                                    &diagnostic_files,
                                    err,
                                )
                            },
                        )?;
                        host_timer.stamp("x86_fused_recorded");
                        RecordedSourcePackX86::Fused {
                            check: x86_check,
                            plan,
                        }
                    } else {
                        let features = self
                            .x86_generator()
                            .map_err(|err| {
                                x86_backend_execution_failed_for_source_pack(
                                    &diagnostic_files,
                                    err,
                                )
                            })?
                            .record_feature_measurement(
                                device,
                                queue,
                                encoder,
                                token_capacity,
                                active_tree_capacity,
                                &x86_parse.ll1_status,
                                &x86_parse.hir_kind,
                                &x86_parse.hir_stmt_record,
                                &x86_parse.hir_expr_record,
                            )
                            .map_err(|err| {
                                x86_backend_execution_failed_for_source_pack(
                                    &diagnostic_files,
                                    err.to_string(),
                                )
                            })?;
                        host_timer.stamp("x86_features_recorded");
                        RecordedSourcePackX86::Split { features }
                    };
                    Ok((
                        type_check,
                        parser_check,
                        semantic_count,
                        early_parser_metadata,
                        token_count,
                        parser_tree_capacity,
                        x86_diagnostics,
                        x86_source_bytes,
                        x86_parse,
                        x86_recorded,
                    ))
                },
                |device,
                 queue,
                 (
                    type_check,
                    parser_check,
                    semantic_count,
                    early_parser_metadata,
                    token_count,
                    parser_tree_capacity,
                    x86_diagnostics,
                    x86_source_bytes,
                    x86_parse,
                    x86_recorded,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.finish");
                    self.x86_generator().map_err(|err| {
                        x86_backend_execution_failed_for_source_pack(&diagnostic_files, err)
                    })?;
                    host_timer.stamp("x86_generator_ready");
                    let (ll1, semantic_hir_count) = if let Some(metadata) = early_parser_metadata {
                        metadata
                    } else {
                        let ll1 = parser_check.read_status_result(device).map_err(|err| {
                            parser_execution_failed_for_source_pack(&diagnostic_files, err)
                        })?;
                        if !ll1.accepted {
                            let token_capacity = token_count.max(1);
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
                                &x86_diagnostics.tokens_out.buffer,
                                &diagnostic_files,
                                &parser_failure,
                            ));
                        }
                        let semantic_hir_count = self
                            .parser
                            .finish_recorded_hir_semantic_count(&semantic_count)
                            .map_err(|err| {
                                parser_execution_failed_for_source_pack(&diagnostic_files, err)
                            })?;
                        (ll1, semantic_hir_count)
                    };
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| {
                            type_check_error_to_compile_error_for_x86_source_pack(
                                device,
                                queue,
                                &x86_diagnostics,
                                &diagnostic_files,
                                err,
                            )
                        })?;
                    host_timer.stamp("typecheck_finish");
                    let x86_check = match x86_recorded {
                        RecordedSourcePackX86::Fused { check, plan } => {
                            if plan.active_tree_capacity != active_tree_capacity
                                || plan.semantic_hir_count != semantic_hir_count
                            {
                                return Err(x86_backend_execution_failed_for_source_pack(
                                    &diagnostic_files,
                                    format!(
                                        "cached x86 frontend plan drifted: active tree {} -> {}, semantic HIR {} -> {}",
                                        plan.active_tree_capacity,
                                        active_tree_capacity,
                                        plan.semantic_hir_count,
                                        semantic_hir_count,
                                    ),
                                ));
                            }
                            host_timer.stamp("x86_fused_ready");
                            check
                        }
                        RecordedSourcePackX86::Split { features } => {
                            let codegen_buffers = self
                                .type_checker
                                .clone_x86_codegen_buffers()
                                .ok_or_else(|| {
                                    x86_backend_execution_failed_for_source_pack(
                                        &diagnostic_files,
                                        "x86 type metadata buffers are unavailable",
                                    )
                                })?;
                            host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                            let feature_summary = self
                                .x86_generator()
                                .map_err(|err| {
                                    x86_backend_execution_failed_for_source_pack(
                                        &diagnostic_files,
                                        err,
                                    )
                                })?
                                .finish_feature_measurement(device, features)
                                .map_err(|err| {
                                    x86_backend_execution_failed_for_source_pack(
                                        &diagnostic_files,
                                        err.to_string(),
                                    )
                                })?;
                            host_timer.stamp("x86_features_finished");
                            let plan = SourcePackX86Plan {
                                feature_summary,
                                active_tree_capacity,
                                semantic_hir_count,
                            };
                            self.remember_source_pack_x86_plan(sources, plan);
                            let mut x86_encoder = device.create_command_encoder(
                                &wgpu::CommandEncoderDescriptor {
                                    label: Some("compiler.x86.source_pack.backend.encoder"),
                                },
                            );
                            let mut x86_timer = x86_gpu_timer(device, queue);
                            let check = self.record_x86_from_parse_buffers_with_codegen(
                                device,
                                queue,
                                &mut x86_encoder,
                                x86_diagnostics.source_len,
                                &x86_source_bytes,
                                token_count.max(1),
                                active_tree_capacity.max(1),
                                x86_inst_hir_node_count_for_backend_capacity(
                                    active_tree_capacity,
                                    semantic_hir_count,
                                ),
                                &x86_parse,
                                codegen_buffers.as_ref(),
                                feature_summary,
                                x86_timer.as_mut(),
                                |err| {
                                    if crate::gpu::env::env_bool_truthy(
                                        "LANIUS_GPU_COMPILE_HOST_TIMING",
                                        false,
                                    ) {
                                        eprintln!(
                                            "[gpu_compile_host_timer] compiler.x86.source_pack.backend_record_error: {err:#}"
                                        );
                                    }
                                    x86_backend_execution_failed_for_source_pack(
                                        &diagnostic_files,
                                        err,
                                    )
                                },
                            )?;
                            if let Some(timer) = x86_timer.as_ref() {
                                timer.resolve(&mut x86_encoder);
                            }
                            host_timer.stamp("x86_recorded");
                            crate::gpu::passes_core::submit_with_progress(
                                queue,
                                "compiler.x86.source_pack.backend",
                                x86_encoder.finish(),
                            );
                            host_timer.stamp("x86_submitted");
                            print_x86_gpu_timer(device, x86_timer.as_ref());
                            check
                        }
                    };
                    let result = x86_check.read_output(device, queue).map_err(|err| {
                        x86_codegen_error_to_compile_error_for_source_pack(
                            device,
                            queue,
                            &x86_diagnostics,
                            &x86_parse,
                            &diagnostic_files,
                            &err,
                        )
                    });
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| source_tokenization_failed_for_source_pack(&diagnostic_files, err))?
    }
    /// Compile an explicit in-memory source-pack manifest through the x86_64
    /// backend and preserve manifest source paths for diagnostics.
    pub async fn compile_source_pack_manifest_to_x86_64(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_x86_64_with_paths(
            &source_pack.sources,
            Some(&source_pack.source_paths),
        )
        .await
    }
    /// Compiles prepared source text to x86_64 output using a synthetic path.
    pub(in crate::compiler) async fn compile_expanded_source_to_x86_64(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_expanded_source_to_x86_64_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }

    async fn compile_expanded_source_to_x86_64_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.record");
                    let token_capacity = token_count.max(1);
                    let single_source = [src];
                    let parser_capacity =
                        if let Some(cached) = self.cached_source_pack_parser_capacity(&single_source)
                        {
                            cached
                        } else {
                            let measured = self
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
                            self.remember_source_pack_parser_capacity(&single_source, measured);
                            measured
                        };
                    let parser_tree_capacity = parser_capacity.tree_capacity;
                    let parser_feature_flags = parser_capacity.parser_feature_flags;
                    host_timer.stamp("partial_parse_tree_capacity");
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.parser-boundary.encoder"),
                        });
                    let mut parser_timer = parser_gpu_timer(device, queue);
                    let mut parser_timer_ref = parser_timer.as_mut();
                    let (parser_check, parser_metadata) = self
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
                            &mut parser_timer_ref,
                            |parse_bufs, encoder, timer| {
                                let semantic_count = self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| {
                                        parser_execution_failed_for_source(
                                            &diagnostic_path,
                                            src,
                                            err,
                                        )
                                    })?;
                                let module_record_capacity = self
                                    .type_checker
                                    .record_module_record_capacity_preflight(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        parse_bufs,
                                    )
                                    .map_err(|err| {
                                        type_check_execution_failed_for_source(
                                            &diagnostic_path,
                                            src,
                                            gpu_type_checker::GpuTypeCheckError::Gpu(err),
                                        )
                                    })?;
                                Ok((semantic_count, module_record_capacity))
                            },
                        )
                        .map_err(|err| {
                            parser_execution_failed_for_source(&diagnostic_path, src, err)
                        })?;
                    if let Some(timer) = parser_timer.as_ref() {
                        timer.resolve(&mut parser_encoder);
                    }
                    host_timer.stamp("parser_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.parser-boundary",
                        parser_encoder.finish(),
                    );
                    print_x86_gpu_timer(device, parser_timer.as_ref());
                    host_timer.stamp("parser_submitted");
                    let (semantic_count, module_record_capacity) = parser_metadata?;
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
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count)
                        .map_err(|err| {
                            parser_execution_failed_for_source(&diagnostic_path, src, err)
                        })?;
                    let preflight_capacities = self
                        .type_checker
                        .finish_module_record_capacity_preflight(device, &module_record_capacity)
                        .map_err(|err| {
                            type_check_execution_failed_for_source(
                                &diagnostic_path,
                                src,
                                gpu_type_checker::GpuTypeCheckError::Gpu(err),
                            )
                        })?;
                    if crate::gpu::env::env_bool_truthy(
                        "LANIUS_GPU_COMPILE_HOST_TIMING",
                        false,
                    ) {
                        eprintln!(
                            "[gpu_compile_host_timer] compiler.x86.preflight_capacities: modules={} params={} args={} tree={parser_tree_capacity} tokens={token_capacity}",
                            preflight_capacities.module_records,
                            preflight_capacities.call_param_rows,
                            preflight_capacities.call_arg_rows,
                        );
                    }
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
                    let mut typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    typecheck_parse.module_record_capacity = preflight_capacities.module_records;
                    typecheck_parse.call_param_row_capacity = preflight_capacities.call_param_rows;
                    typecheck_parse.call_arg_row_capacity = preflight_capacities.call_arg_rows;
                    let x86_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity_and_features(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            parser_feature_flags,
                            OwnedX86ParserBuffers::from_parser_buffers,
                        );
                    // See the source-pack path above: retaining the sequentially
                    // reused parser allocation also preserves type-check bind groups.
                    host_timer.stamp("parser_cache_retained");
                    let x86_diagnostics = OwnedX86DiagnosticBuffers::from_lexer_buffers(bufs);
                    let x86_source_bytes = bufs.in_bytes.clone();
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
                        |err| type_check_execution_failed_for_source(&diagnostic_path, src, err),
                    )?;
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    let x86_features = self
                        .x86_generator()
                        .map_err(|err| {
                            x86_backend_execution_failed_for_source(&diagnostic_path, src, err)
                        })?
                        .record_feature_measurement(
                            device,
                            queue,
                            encoder,
                            token_capacity,
                            active_tree_capacity,
                            &x86_parse.ll1_status,
                            &x86_parse.hir_kind,
                            &x86_parse.hir_stmt_record,
                            &x86_parse.hir_expr_record,
                        )
                        .map_err(|err| {
                            x86_backend_execution_failed_for_source(
                                &diagnostic_path,
                                src,
                                err.to_string(),
                            )
                        })?;
                    host_timer.stamp("x86_features_recorded");
                    Ok((
                        type_check,
                        token_count,
                        active_tree_capacity,
                        semantic_hir_count,
                        x86_diagnostics,
                        x86_source_bytes,
                        x86_parse,
                        x86_features,
                    ))
                },
                |device,
                 queue,
                 _lexer_bufs,
                 (
                    type_check,
                    token_count,
                    active_tree_capacity,
                    semantic_hir_count,
                    x86_diagnostics,
                    x86_source_bytes,
                    x86_parse,
                    x86_features,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.finish");
                    self.x86_generator().map_err(|err| {
                        x86_backend_execution_failed_for_source(&diagnostic_path, src, err)
                    })?;
                    host_timer.stamp("x86_generator_ready");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| {
                            type_check_error_to_compile_error_for_owned_source(
                                device,
                                queue,
                                &x86_diagnostics,
                                src,
                                &diagnostic_path,
                                err,
                            )
                        })?;
                    host_timer.stamp("typecheck_finish");
                    let codegen_buffers = self
                        .type_checker
                        .clone_x86_codegen_buffers()
                        .ok_or_else(|| {
                            x86_backend_execution_failed_for_source(
                                &diagnostic_path,
                                src,
                                "x86 type metadata buffers are unavailable",
                            )
                        })?;
                    host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                    let feature_summary = self
                        .x86_generator()
                        .map_err(|err| {
                            x86_backend_execution_failed_for_source(&diagnostic_path, src, err)
                        })?
                        .finish_feature_measurement(device, x86_features)
                        .map_err(|err| {
                            x86_backend_execution_failed_for_source(
                                &diagnostic_path,
                                src,
                                err.to_string(),
                            )
                        })?;
                    host_timer.stamp("x86_features_finished");
                    let token_capacity = token_count.max(1);
                    let x86_hir_node_count = active_tree_capacity.max(1);
                    let x86_inst_hir_node_count = x86_inst_hir_node_count_for_backend_capacity(
                        active_tree_capacity,
                        semantic_hir_count,
                    );
                    let mut x86_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.backend.encoder"),
                        });
                    let mut x86_timer = x86_gpu_timer(device, queue);
                    let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                        device,
                        queue,
                        &mut x86_encoder,
                        x86_diagnostics.source_len,
                        &x86_source_bytes,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        &x86_parse,
                        codegen_buffers.as_ref(),
                        feature_summary,
                        x86_timer.as_mut(),
                        |err| {
                            if crate::gpu::env::env_bool_truthy(
                                "LANIUS_GPU_COMPILE_HOST_TIMING",
                                false,
                            ) {
                                eprintln!(
                                    "[gpu_compile_host_timer] compiler.x86.record.error: {err}"
                                );
                            }
                            x86_backend_execution_failed_for_source(&diagnostic_path, src, err)
                        },
                    )?;
                    if let Some(timer) = x86_timer.as_ref() {
                        timer.resolve(&mut x86_encoder);
                    }
                    host_timer.stamp("x86_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.backend",
                        x86_encoder.finish(),
                    );
                    host_timer.stamp("x86_submitted");
                    print_x86_gpu_timer(device, x86_timer.as_ref());
                    let result = x86_check.read_output(device, queue).map_err(|err| {
                        x86_codegen_error_to_compile_error_for_source(
                            device,
                            queue,
                            &x86_diagnostics,
                            &x86_parse,
                            src,
                            &diagnostic_path,
                            &err,
                        )
                    });
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| source_tokenization_failed_for_source(&diagnostic_path, src, err))?
    }
}

fn typecheck_submission_overlap_enabled() -> bool {
    match std::env::var("LANIUS_OVERLAP_TYPECHECK_SUBMISSION") {
        Ok(value) => !matches!(value.trim().to_ascii_lowercase().as_str(), "0" | "false"),
        Err(_) => true,
    }
}

fn x86_gpu_timer(device: &wgpu::Device, queue: &wgpu::Queue) -> Option<GpuTimer> {
    gpu_compile_timer(device, queue, 64)
}

fn parser_gpu_timer(device: &wgpu::Device, queue: &wgpu::Queue) -> Option<GpuTimer> {
    gpu_compile_timer(device, queue, 2048)
}

fn gpu_compile_timer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    query_capacity: u32,
) -> Option<GpuTimer> {
    let enabled = crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
        || crate::gpu::env::env_bool_truthy("LANIUS_GPU_TIMING", false)
        || crate::gpu::trace::enabled();
    (enabled && device.features().contains(wgpu::Features::TIMESTAMP_QUERY))
        .then(|| GpuTimer::new(device, queue, query_capacity))
}

fn print_x86_gpu_timer(device: &wgpu::Device, timer: Option<&GpuTimer>) {
    let Some(timer) = timer else {
        return;
    };
    let Some(values) = timer.try_read(device) else {
        return;
    };
    let Some((_, first)) = values.first() else {
        return;
    };
    let period_ns = timer.period_ns() as f64;
    let mut previous = *first;
    for (label, timestamp) in values {
        let elapsed_ms = ((timestamp - previous) as f64 * period_ns) / 1.0e6;
        eprintln!("[gpu_compile_timer] {label}: {elapsed_ms:.3}ms");
        previous = timestamp;
    }
}

const EXACT_TYPECHECK_CAPACITY_MIN_HIR_NODES: u32 = 1 << 20;

fn exact_typecheck_capacity_boundary_required(parser_tree_capacity: u32) -> bool {
    parser_tree_capacity >= EXACT_TYPECHECK_CAPACITY_MIN_HIR_NODES
}

fn x86_codegen_error_to_compile_error_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    x86_parse: &OwnedX86ParserBuffers,
    src: &str,
    diagnostic_path: &Path,
    err: &anyhow::Error,
) -> CompileError {
    let Some(x86_err) = err.downcast_ref::<x86::X86OutputError>() else {
        return x86_backend_execution_failed_for_source(diagnostic_path, src, err);
    };

    let label = x86_diagnostic_label_for_source(
        device,
        queue,
        x86_parse,
        x86_diagnostics,
        x86_err,
        "compiler.x86.diagnostic-hir-token-pos",
        Some(0),
        src,
        diagnostic_path,
    );

    CompileError::Diagnostic(x86_backend_boundary_diagnostic(x86_err).with_primary_label(label))
}

fn x86_codegen_error_to_compile_error_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    x86_parse: &OwnedX86ParserBuffers,
    diagnostic_files: &[DiagnosticSourceFile],
    err: &anyhow::Error,
) -> CompileError {
    let Some(x86_err) = err.downcast_ref::<x86::X86OutputError>() else {
        return x86_backend_execution_failed_for_source_pack(diagnostic_files, err);
    };

    let label = x86_diagnostic_label_for_source_pack(
        device,
        queue,
        x86_parse,
        x86_diagnostics,
        diagnostic_files,
        x86_err,
        "compiler.x86.source-pack-diagnostic-hir-token-pos",
        Some(0),
    );

    CompileError::Diagnostic(x86_backend_boundary_diagnostic(x86_err).with_primary_label(label))
}

fn x86_backend_boundary_diagnostic(x86_err: &x86::X86OutputError) -> Diagnostic {
    let diagnostic = Diagnostic::error("LNC0017", x86_err.public_message()).with_note(
        "this program reached a native x86 lowering path that is not supported yet; use `laniusc check` for diagnostics-only validation or emit WASM until this construct is covered",
    );
    if x86_err.error_code() == 9 {
        return diagnostic.with_note(
            "x86 call lowering currently supports direct Lanius function calls; runtime extern calls need an explicit host binding before they can emit native code",
        );
    }
    if x86_err.error_code() == x86::X86_ERR_UNSUPPORTED_LITERAL_EXPR {
        return diagnostic.with_note(
            "x86 string and char literals need a target data layout before they can lower to native code; the frontend HIR and types were accepted",
        );
    }
    diagnostic
}

fn x86_backend_execution_failed_for_source(
    diagnostic_path: &Path,
    src: &str,
    err: impl std::fmt::Display,
) -> CompileError {
    stage_execution_failed_for_source(x86_backend_execution_failure(), diagnostic_path, src, err)
}

fn x86_backend_execution_failed_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
    err: impl std::fmt::Display,
) -> CompileError {
    stage_execution_failed_for_source_pack(x86_backend_execution_failure(), diagnostic_files, err)
}

fn x86_backend_execution_failure() -> StageExecutionFailure<'static> {
    StageExecutionFailure {
        code: "LNC0017",
        message: "x86 backend execution failed",
        primary_label: "native x86 backend failed before it could classify this source",
        source_help: "use `laniusc check` to validate frontend diagnostics; if this happens on a small supported program, report a compiler bug",
        source_pack_help: "use `laniusc check` to validate frontend diagnostics; if this happens on a small supported source pack, report a compiler bug",
    }
}

fn x86_empty_source_pack_compile_error() -> CompileError {
    CompileError::Diagnostic(
        Diagnostic::error("LNC0017", "missing main entrypoint")
            .with_primary_label(x86_fallback_label_for_source_pack(&[]))
            .with_note("x86 source packs must contain at least one source file before native entry selection can run"),
    )
}

fn x86_diagnostic_label_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_parse: &OwnedX86ParserBuffers,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    x86_err: &x86::X86OutputError,
    hir_token_pos_readback_label: &'static str,
    invalid_select_anchor_token: Option<u32>,
    src: &str,
    diagnostic_path: &Path,
) -> DiagnosticLabel {
    let token = x86_diagnostic_token_for_error(
        device,
        queue,
        x86_parse,
        x86_err,
        hir_token_pos_readback_label,
        invalid_select_anchor_token,
    );
    if let Ok(token_index) = token {
        if let Ok(token_record) =
            read_single_owned_token_for_diagnostic(device, queue, x86_diagnostics, token_index)
        {
            return diagnostic_label_from_source_span(
                diagnostic_path,
                src,
                token_record.start,
                token_record.len,
                "not supported by the native x86 backend yet",
            );
        }
    }

    x86_fallback_label_for_source(diagnostic_path, src)
}

fn x86_diagnostic_label_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_parse: &OwnedX86ParserBuffers,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    diagnostic_files: &[DiagnosticSourceFile],
    x86_err: &x86::X86OutputError,
    hir_token_pos_readback_label: &'static str,
    invalid_select_anchor_token: Option<u32>,
) -> DiagnosticLabel {
    let token = x86_diagnostic_token_for_error(
        device,
        queue,
        x86_parse,
        x86_err,
        hir_token_pos_readback_label,
        invalid_select_anchor_token,
    );
    if let Ok(token_index) = token {
        if let Ok(token_record) =
            read_single_owned_token_for_diagnostic(device, queue, x86_diagnostics, token_index)
        {
            if let Some(file) =
                source_pack_nearest_file_for_global_span(diagnostic_files, token_record.start)
            {
                return diagnostic_label_from_source_span(
                    &file.path,
                    &file.source,
                    file.local_start_for_global(token_record.start),
                    token_record.len,
                    "not supported by the native x86 backend yet",
                );
            }
        }
    }

    x86_fallback_label_for_source_pack(diagnostic_files)
}

fn x86_fallback_label_for_source(diagnostic_path: &Path, src: &str) -> DiagnosticLabel {
    let (start, len) = first_nonempty_source_span(src);
    diagnostic_label_from_source_span(
        diagnostic_path,
        src,
        start,
        len,
        "not supported by the native x86 backend yet",
    )
}

fn x86_fallback_label_for_source_pack(
    diagnostic_files: &[DiagnosticSourceFile],
) -> DiagnosticLabel {
    if let Some(file) = diagnostic_files.first() {
        let (start, len) = first_nonempty_source_span(&file.source);
        return diagnostic_label_from_source_span(
            &file.path,
            &file.source,
            start,
            len,
            "not supported by the native x86 backend yet",
        );
    }

    diagnostic_label_from_source_span(
        PathBuf::from("<source pack>"),
        "",
        0,
        1,
        "not supported by the native x86 backend yet",
    )
}

fn x86_diagnostic_token_for_error(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_parse: &OwnedX86ParserBuffers,
    x86_err: &x86::X86OutputError,
    hir_token_pos_readback_label: &'static str,
    invalid_select_anchor_token: Option<u32>,
) -> Result<u32, String> {
    if x86_err.error_code() == 2
        || (x86_err.error_code() == 17 && x86_err.error_detail() == u32::MAX)
    {
        if let Some(token) = invalid_select_anchor_token {
            return Ok(token);
        }
    }
    if x86_err.error_code() == 48 {
        return read_u32_from_buffer_for_diagnostic(
            device,
            queue,
            &x86_parse.hir_token_pos,
            x86_err.error_detail(),
            hir_token_pos_readback_label,
        );
    }
    if x86_err.detail_is_token() {
        return Ok(x86_err.error_detail());
    }
    if x86_err.detail_is_hir_node() {
        return read_u32_from_buffer_for_diagnostic(
            device,
            queue,
            &x86_parse.hir_token_pos,
            x86_err.error_detail(),
            hir_token_pos_readback_label,
        );
    }
    Err(format!(
        "x86 error code {} detail {} is not source-addressable",
        x86_err.error_code(),
        x86_err.error_detail()
    ))
}

fn type_check_error_to_compile_error_for_owned_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
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
            let (start, len) =
                read_single_owned_token_for_diagnostic(device, queue, x86_diagnostics, token)
                    .map(|token_record| (token_record.start, token_record.len))
                    .unwrap_or_else(|_| first_nonempty_source_span(src));
            type_check_diagnostic_at_span(diagnostic_path, src, start, len, code, detail)
        }
        _ => type_check_execution_failed_for_source(diagnostic_path, src, err),
    }
}

fn type_check_error_to_compile_error_for_x86_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    diagnostic_files: &[DiagnosticSourceFile],
    err: GpuTypeCheckError,
) -> CompileError {
    match err {
        GpuTypeCheckError::Rejected {
            token,
            code,
            detail,
        } => {
            if let Some((path, source, start, len)) =
                read_single_owned_token_for_diagnostic(device, queue, x86_diagnostics, token)
                    .ok()
                    .and_then(|token_record| {
                        source_pack_nearest_file_for_global_span(
                            diagnostic_files,
                            token_record.start,
                        )
                        .map(|file| {
                            (
                                file.path.as_path(),
                                file.source.as_str(),
                                file.local_start_for_global(token_record.start),
                                token_record.len,
                            )
                        })
                    })
                    .or_else(|| x86_source_pack_fallback_type_check_span(diagnostic_files))
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

fn x86_source_pack_fallback_type_check_span(
    diagnostic_files: &[DiagnosticSourceFile],
) -> Option<(&Path, &str, usize, usize)> {
    let file = diagnostic_files.first()?;
    let (start, len) = first_nonempty_source_span(&file.source);
    Some((&file.path, &file.source, start, len))
}

fn read_u32_from_buffer_for_diagnostic(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    buffer: &wgpu::Buffer,
    index: u32,
    label: &'static str,
) -> Result<u32, String> {
    let offset = u64::from(index)
        .checked_mul(4)
        .ok_or_else(|| format!("u32 index {index} byte offset overflow"))?;
    let end = offset
        .checked_add(4)
        .ok_or_else(|| format!("u32 index {index} byte end overflow"))?;
    if end > buffer.size() {
        return Err(format!(
            "u32 index {index} byte range {offset}..{end} exceeds buffer size {}",
            buffer.size()
        ));
    }

    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: 4,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("compiler.x86.diagnostic-u32-readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(buffer, offset, &readback, 0, 4);
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "compiler.x86.diagnostic-u32-readback",
        encoder.finish(),
    );

    let slice = readback.slice(0..4);
    crate::gpu::passes_core::map_readback_blocking(device, &slice, label)
        .map_err(|err| err.to_string())?;
    let mapped = slice.get_mapped_range();
    let word = u32::from_le_bytes(mapped[0..4].try_into().expect("u32 diagnostic word"));
    drop(mapped);
    readback.unmap();
    Ok(word)
}

fn read_single_owned_token_for_diagnostic(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    x86_diagnostics: &OwnedX86DiagnosticBuffers,
    token_index: u32,
) -> Result<Token, String> {
    let token_stride = std::mem::size_of::<GpuToken>() as u64;
    let token_offset = u64::from(token_index)
        .checked_mul(token_stride)
        .ok_or_else(|| format!("token {token_index} byte offset overflow"))?;
    let token_end = token_offset
        .checked_add(token_stride)
        .ok_or_else(|| format!("token {token_index} byte end overflow"))?;
    if token_end > x86_diagnostics.tokens_out.size() {
        return Err(format!(
            "token {token_index} byte range {token_offset}..{token_end} exceeds token buffer size {}",
            x86_diagnostics.tokens_out.size()
        ));
    }

    let token_readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.compiler.x86.diagnostic_token"),
        size: token_stride,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("compiler.x86.diagnostic-token-readback.encoder"),
    });
    encoder.copy_buffer_to_buffer(
        &x86_diagnostics.tokens_out,
        token_offset,
        &token_readback,
        0,
        token_stride,
    );
    crate::gpu::passes_core::submit_with_progress(
        queue,
        "compiler.x86.diagnostic-token-readback",
        encoder.finish(),
    );

    let token_slice = token_readback.slice(0..token_stride);
    crate::gpu::passes_core::map_readback_blocking(
        device,
        &token_slice,
        "compiler.x86.diagnostic-token",
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
    fn exact_typecheck_capacity_boundary_is_reserved_for_large_hir() {
        assert!(!exact_typecheck_capacity_boundary_required(
            EXACT_TYPECHECK_CAPACITY_MIN_HIR_NODES - 1
        ));
        assert!(exact_typecheck_capacity_boundary_required(
            EXACT_TYPECHECK_CAPACITY_MIN_HIR_NODES
        ));
    }

    #[test]
    fn x86_backend_execution_failure_for_source_is_structured_diagnostic() {
        let err = x86_backend_execution_failed_for_source(
            Path::new("app.lani"),
            "fn main() { return 0; }\n",
            "finish readback failed",
        );

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0017");
                assert_eq!(diagnostic.message, "x86 backend execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 backend diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("app.lani"));
                assert_eq!(
                    label.message,
                    "native x86 backend failed before it could classify this source"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("error[LNC0017]: x86 backend execution failed"));
                assert!(!rendered.contains("finish readback failed"));
                assert!(!rendered.contains("x86 backend error:"));
                assert!(!rendered.contains("GpuCodegen"));
                assert!(!rendered.contains("code generation error:"));
            }
            other => panic!("expected structured x86 backend diagnostic, got {other:?}"),
        }
    }

    #[test]
    fn x86_backend_execution_failure_for_source_pack_is_structured_diagnostic() {
        let paths = [Some(PathBuf::from("first.lani"))];
        let files = source_pack_diagnostic_files(&["module first;\n"], Some(&paths));

        let err = x86_backend_execution_failed_for_source_pack(&files, "finish readback failed");

        match err {
            CompileError::Diagnostic(diagnostic) => {
                assert_eq!(diagnostic.code, "LNC0017");
                assert_eq!(diagnostic.message, "x86 backend execution failed");
                let label = diagnostic
                    .primary_label
                    .as_ref()
                    .expect("x86 backend diagnostic should carry a label");
                assert_eq!(label.path, PathBuf::from("first.lani"));
                assert_eq!(
                    label.message,
                    "native x86 backend failed before it could classify this source"
                );
                let rendered = diagnostic.render();
                assert!(rendered.contains("source file count: 1"));
                assert!(!rendered.contains("finish readback failed"));
                assert!(!rendered.contains("x86 backend error:"));
                assert!(!rendered.contains("GpuCodegen"));
                assert!(!rendered.contains("code generation error:"));
            }
            other => panic!("expected structured x86 source-pack diagnostic, got {other:?}"),
        }
    }
}
