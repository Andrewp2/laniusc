// src/compiler/gpu_compiler/wasm_codegen.rs

use super::{typecheck::type_check_error_to_compile_error_for_source, *};
use crate::gpu::buffers::LaniusBuffer;

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu(src)?;
        self.compile_expanded_source_to_wasm_with_diagnostic_path(&src, PathBuf::from("<source>"))
            .await
    }
    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let path = path.as_ref();
        let src = prepare_source_for_gpu_from_path(path)?;
        self.compile_expanded_source_to_wasm_with_diagnostic_path(&src, path.to_path_buf())
            .await
    }
    pub async fn compile_source_pack_to_wasm<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        validate_in_memory_source_pack_fits_default_codegen_unit(
            "compile source pack to WASM",
            sources,
        )?;
        let diagnostic_files = source_pack_diagnostic_files(sources, None);
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("source_pack.compile.start");
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("source_pack.lex.recorded");
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("source_pack.parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_file_id: &parse_bufs.hir_type_file_id,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            bound_path_owner_by_leaf: &parse_bufs
                                                .hir_bound_path_owner_by_leaf,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            param_type_node: &parse_bufs.hir_param_type_node,
                                            method_owner_node: &parse_bufs.hir_method_owner_node,
                                            method_impl_node: &parse_bufs.hir_method_impl_node,
                                            method_name_token: &parse_bufs.hir_method_name_token,
                                            method_first_param_token: &parse_bufs
                                                .hir_method_first_param_token,
                                            method_receiver_mode: &parse_bufs
                                                .hir_method_receiver_mode,
                                            method_visibility: &parse_bufs.hir_method_visibility,
                                            method_signature_flags: &parse_bufs
                                                .hir_method_signature_flags,
                                            method_impl_receiver_type_node: &parse_bufs
                                                .hir_method_impl_receiver_type_node,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_result_node: &parse_bufs.hir_expr_result_node,
                                            expr_result_root_node: &parse_bufs
                                                .hir_expr_result_root_node,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            stmt_scope_end: &parse_bufs.hir_stmt_scope_end,
                                            nearest_stmt_node: &parse_bufs.hir_nearest_stmt_node,
                                            nearest_block_node: &parse_bufs.hir_nearest_block_node,
                                            nearest_loop_node: &parse_bufs.hir_nearest_loop_node,
                                            nearest_fn_node: &parse_bufs.hir_nearest_fn_node,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_lit_context_stmt_node: &parse_bufs
                                                .hir_array_lit_context_stmt_node,
                                            array_element_parent_lit: &parse_bufs
                                                .hir_array_element_parent_lit,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_context_stmt_node: &parse_bufs
                                                .hir_call_context_stmt_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            variant_payload_node: &parse_bufs
                                                .hir_variant_payload_node,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_context_stmt_node: &parse_bufs
                                                .hir_struct_lit_context_stmt_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("source_pack.typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                codegen.enclosing_fn,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                    member_name_token: &parse_bufs
                                                        .hir_member_name_token,
                                                    member_result_field_ordinal: codegen
                                                        .member_result_field_ordinal,
                                                    struct_init_field_ordinal_by_node: codegen
                                                        .struct_init_field_ordinal_by_node,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_next: &parse_bufs.hir_match_arm_next,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    context_stmt: &parse_bufs
                                                        .hir_call_context_stmt_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    result_root_node: &parse_bufs
                                                        .hir_expr_result_root_node,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                    nearest_stmt_node: &parse_bufs
                                                        .hir_nearest_stmt_node,
                                                    nearest_block_node: &parse_bufs
                                                        .hir_nearest_block_node,
                                                    nearest_enclosing_control_node: &parse_bufs
                                                        .hir_nearest_enclosing_control_node,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("source_pack.wasm.recorded");
                                let wasm_diagnostics = WasmDiagnosticBuffers {
                                    tokens_out: bufs.tokens_out.clone(),
                                };
                                Ok::<_, CompileError>((recorded, wasm_check, wasm_diagnostics))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.parser.typecheck.recorded");
                    let (type_check, wasm_check, wasm_diagnostics) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check, wasm_diagnostics))
                },
                |device, queue, (parser_check, type_check, wasm_check, wasm_diagnostics)| {
                    trace_wasm_compile("source_pack.finish.parser.start");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| {
                            wasm_codegen_error_to_compile_error_for_source_pack(
                                device,
                                queue,
                                &wasm_diagnostics.tokens_out,
                                &diagnostic_files,
                                &err,
                            )
                        })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }
    pub async fn compile_source_pack_manifest_to_wasm(
        &self,
        source_pack: &ExplicitSourcePack,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_source_pack_to_wasm(&source_pack.sources).await
    }
    pub(in crate::compiler) async fn compile_expanded_source_to_wasm(
        &self,
        src: &str,
    ) -> Result<Vec<u8>, CompileError> {
        self.compile_expanded_source_to_wasm_with_diagnostic_path(src, PathBuf::from("<source>"))
            .await
    }

    async fn compile_expanded_source_to_wasm_with_diagnostic_path(
        &self,
        src: &str,
        diagnostic_path: PathBuf,
    ) -> Result<Vec<u8>, CompileError> {
        // The current WASM recorder batches backend passes behind type checking.
        // Preflight keeps expected user type errors from executing backend codegen
        // until this path is split into staged GPU submissions like x86.
        self.type_check_expanded_source_with_diagnostic_path(src, diagnostic_path.clone())
            .await?;

        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("compile.start");
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("lex.recorded");
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
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_file_id: &parse_bufs.hir_type_file_id,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            bound_path_owner_by_leaf: &parse_bufs
                                                .hir_bound_path_owner_by_leaf,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            param_type_node: &parse_bufs.hir_param_type_node,
                                            method_owner_node: &parse_bufs.hir_method_owner_node,
                                            method_impl_node: &parse_bufs.hir_method_impl_node,
                                            method_name_token: &parse_bufs.hir_method_name_token,
                                            method_first_param_token: &parse_bufs
                                                .hir_method_first_param_token,
                                            method_receiver_mode: &parse_bufs
                                                .hir_method_receiver_mode,
                                            method_visibility: &parse_bufs.hir_method_visibility,
                                            method_signature_flags: &parse_bufs
                                                .hir_method_signature_flags,
                                            method_impl_receiver_type_node: &parse_bufs
                                                .hir_method_impl_receiver_type_node,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_result_node: &parse_bufs.hir_expr_result_node,
                                            expr_result_root_node: &parse_bufs
                                                .hir_expr_result_root_node,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            stmt_scope_end: &parse_bufs.hir_stmt_scope_end,
                                            nearest_stmt_node: &parse_bufs.hir_nearest_stmt_node,
                                            nearest_block_node: &parse_bufs.hir_nearest_block_node,
                                            nearest_loop_node: &parse_bufs.hir_nearest_loop_node,
                                            nearest_fn_node: &parse_bufs.hir_nearest_fn_node,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_lit_context_stmt_node: &parse_bufs
                                                .hir_array_lit_context_stmt_node,
                                            array_element_parent_lit: &parse_bufs
                                                .hir_array_element_parent_lit,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_context_stmt_node: &parse_bufs
                                                .hir_call_context_stmt_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            variant_payload_node: &parse_bufs
                                                .hir_variant_payload_node,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_context_stmt_node: &parse_bufs
                                                .hir_struct_lit_context_stmt_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                codegen.enclosing_fn,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                    member_name_token: &parse_bufs
                                                        .hir_member_name_token,
                                                    member_result_field_ordinal: codegen
                                                        .member_result_field_ordinal,
                                                    struct_init_field_ordinal_by_node: codegen
                                                        .struct_init_field_ordinal_by_node,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_next: &parse_bufs.hir_match_arm_next,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    context_stmt: &parse_bufs
                                                        .hir_call_context_stmt_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    result_root_node: &parse_bufs
                                                        .hir_expr_result_root_node,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                    nearest_stmt_node: &parse_bufs
                                                        .hir_nearest_stmt_node,
                                                    nearest_block_node: &parse_bufs
                                                        .hir_nearest_block_node,
                                                    nearest_enclosing_control_node: &parse_bufs
                                                        .hir_nearest_enclosing_control_node,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
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
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| {
                            type_check_error_to_compile_error_for_source(
                                device,
                                queue,
                                _bufs,
                                src,
                                &diagnostic_path,
                                err,
                            )
                        })?;
                    trace_wasm_compile("finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| {
                            wasm_codegen_error_to_compile_error_for_source(
                                device,
                                queue,
                                &_bufs.tokens_out.buffer,
                                src,
                                &diagnostic_path,
                                &err,
                            )
                        })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }
    pub(super) fn wasm_generator(&self) -> Result<&wasm::GpuWasmCodeGenerator, CompileError> {
        trace_wasm_compile("wasm.generator");
        self.wasm_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU WASM code generator: {err}"))
        })
    }
}

struct WasmDiagnosticBuffers {
    tokens_out: LaniusBuffer<crate::lexer::GpuToken>,
}

fn wasm_codegen_error_to_compile_error_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    src: &str,
    diagnostic_path: &Path,
    err: &anyhow::Error,
) -> CompileError {
    let Some(wasm_err) = err.downcast_ref::<wasm::WasmOutputError>() else {
        return CompileError::GpuCodegen(err.to_string());
    };

    let label =
        wasm_error_label_for_source(device, queue, token_buffer, src, diagnostic_path, wasm_err);
    CompileError::Diagnostic(wasm_backend_boundary_diagnostic(wasm_err).with_primary_label(label))
}

fn wasm_error_label_for_source(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    src: &str,
    diagnostic_path: &Path,
    wasm_err: &wasm::WasmOutputError,
) -> DiagnosticLabel {
    if wasm_err.detail_is_token() {
        if let Ok(token) =
            read_single_token_from_buffer(device, queue, token_buffer, wasm_err.error_detail())
        {
            return diagnostic_label_from_source_span(
                diagnostic_path,
                src,
                token.start,
                token.len,
                "not supported by the WASM backend yet",
            );
        }
    }

    diagnostic_label_from_source_span(
        diagnostic_path,
        src,
        first_nonempty_label_start(src),
        first_label_len(src),
        "not supported by the WASM backend yet",
    )
}

fn wasm_codegen_error_to_compile_error_for_source_pack(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_buffer: &wgpu::Buffer,
    diagnostic_files: &[DiagnosticSourceFile],
    err: &anyhow::Error,
) -> CompileError {
    let Some(wasm_err) = err.downcast_ref::<wasm::WasmOutputError>() else {
        return CompileError::GpuCodegen(err.to_string());
    };
    let Some(file) = diagnostic_files.first() else {
        return CompileError::GpuCodegen(err.to_string());
    };

    let label = if wasm_err.detail_is_token() {
        read_single_token_from_buffer(device, queue, token_buffer, wasm_err.error_detail())
            .ok()
            .and_then(|token| {
                source_pack_file_for_global_span(diagnostic_files, token.start).map(|file| {
                    diagnostic_label_from_source_span(
                        &file.path,
                        &file.source,
                        file.local_start_for_global(token.start),
                        token.len,
                        "not supported by the WASM backend yet",
                    )
                })
            })
            .unwrap_or_else(|| {
                diagnostic_label_from_source_span(
                    &file.path,
                    &file.source,
                    first_nonempty_label_start(&file.source),
                    first_label_len(&file.source),
                    "not supported by the WASM backend yet",
                )
            })
    } else {
        diagnostic_label_from_source_span(
            &file.path,
            &file.source,
            first_nonempty_label_start(&file.source),
            first_label_len(&file.source),
            "not supported by the WASM backend yet",
        )
    };

    CompileError::Diagnostic(wasm_backend_boundary_diagnostic(wasm_err).with_primary_label(label))
}

fn wasm_backend_boundary_diagnostic(wasm_err: &wasm::WasmOutputError) -> Diagnostic {
    Diagnostic::error("LNC0036", wasm_err.error_name()).with_note(format!(
        "WASM backend error code {} detail {}",
        wasm_err.error_code(),
        wasm_err.error_detail()
    ))
}

fn first_label_len(source: &str) -> usize {
    source[first_nonempty_label_start(source)..]
        .chars()
        .next()
        .map(char::len_utf8)
        .unwrap_or(0)
}

fn first_nonempty_label_start(source: &str) -> usize {
    source
        .char_indices()
        .find(|(_, ch)| !ch.is_whitespace())
        .map(|(index, _)| index)
        .unwrap_or(0)
}
