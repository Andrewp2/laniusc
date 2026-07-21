use super::*;

pub(super) struct WasmBodyPlanBindGroups {
    pub hir_body_plan_collect_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_return_compact_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_compact_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_stmt_expr_compact_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_assign_compact_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_control_compact_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_return_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_return_agg_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_assign_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_control_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_agg_range_control_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_print_simple_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_host_void_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_host_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_host_env_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_host_io_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_host_string_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_return_host_io_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_return_host_string_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_direct_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_validate_let_call_status_bind_group: wgpu::BindGroup,
    pub hir_body_plan_agg_direct_call_bind_group: wgpu::BindGroup,
    pub hir_body_plan_agg_struct_bind_group: wgpu::BindGroup,
    pub hir_body_plan_arrays_bind_group: wgpu::BindGroup,
    pub hir_body_plan_functions_bind_group: wgpu::BindGroup,
    pub hir_body_plan_finalize_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_body_plan_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
        expr_order: &ResidentWasmExprOrder,
        compact_expr_order: &ResidentWasmExprOrder,
    ) -> Result<WasmBodyPlanBindGroups> {
        let GpuWasmCodegenInputs {
            parent: parent_buf,
            first_child: first_child_buf,
            hir_kind: hir_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            hir_status: hir_status_buf,
            parser_feature_flags: parser_feature_flags_buf,
            visible_decl: visible_decl_buf,
            visible_type: visible_type_buf,
            enclosing_fn: enclosing_fn_buf,
            if_depth: if_depth_buf,
            structs: struct_metadata,
            calls: call_metadata,
            expressions: expr_metadata,
            arrays: array_metadata,
            paths: path_metadata,
            call_fn_index: call_fn_index_buf,
            call_dependency_decl: call_dependency_decl_buf,
            call_intrinsic_tag: call_intrinsic_tag_buf,
            call_return_type: call_return_type_buf,
            call_param_count: call_param_count_buf,
            call_param_type: call_param_type_buf,
            method_decl_param_offset: method_decl_param_offset_buf,
            method_decl_receiver_mode: method_decl_receiver_mode_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            params_buf,
            body_fragment_aux_buf,
            body_fragment_len_buf,
            body_fragment_meta_buf,
            body_let_init_expr_by_decl_token_buf,
            body_plan_buf,
            body_status_buf,
            member_result_field_index_buf,
            status_buf,
            struct_init_field_index_buf,
            wasm_agg_local_base_by_token_buf,
            wasm_agg_local_width_by_token_buf,
            wasm_func_body_len_by_token_buf,
            wasm_func_detail_by_token_buf,
            wasm_func_flag_buf,
            wasm_func_invalid_count_by_token_buf,
            wasm_func_local_max_by_token_buf,
            wasm_func_param_ordinal_by_decl_token_buf,
            wasm_func_slot_by_token_buf,
            func_scan_param_bufs,
            wasm_agg_scan_prefix_a_buf,
            wasm_agg_scan_prefix_b_buf,
            ..
        } = working;
        let body_binding_context =
            WasmBodyBindingContext::new_with_expr_order(inputs, working, expr_order);
        let final_agg_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            wasm_agg_scan_prefix_a_buf
        } else {
            wasm_agg_scan_prefix_b_buf
        };
        let mut hir_body_plan_collect_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_plan_collect_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_plan_collect_bindings.extend([
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
        ]);
        let hir_body_plan_collect_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_collect"),
            &self.hir_body_plan_collect_pass,
            0,
            &hir_body_plan_collect_bindings,
        )?;

        let mut hir_body_plan_validate_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_plan_validate_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_plan_validate_bindings.extend([
            ("expr_root_total", expr_order.root_total.as_entire_binding()),
            (
                "parser_feature_flags",
                parser_feature_flags_buf.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node",
                struct_metadata.lit_context_stmt_node.as_entire_binding(),
            ),
        ]);
        let hir_body_plan_validate_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate"),
            &self.hir_body_plan_validate_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let compact_body_binding_context = WasmBodyBindingContext::new_with_compact_expr_order(
            inputs,
            working,
            compact_expr_order,
        );
        let mut hir_body_plan_validate_return_compact_bindings = Vec::new();
        compact_body_binding_context.extend(
            &mut hir_body_plan_validate_return_compact_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_plan_validate_return_compact_bindings.extend([
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
        ]);
        let hir_body_plan_validate_return_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_compact"),
            &self.hir_body_plan_validate_return_compact_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        let hir_body_plan_validate_let_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_compact"),
            &self.hir_body_plan_validate_let_compact_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        let hir_body_plan_validate_stmt_expr_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_stmt_expr_compact"),
            &self.hir_body_plan_validate_stmt_expr_compact_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        let hir_body_plan_validate_assign_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_assign_compact"),
            &self.hir_body_plan_validate_assign_compact_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        let hir_body_plan_validate_print_simple_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_print_simple"),
            &self.hir_body_plan_validate_print_simple_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        hir_body_plan_validate_return_compact_bindings.extend([
            (
                "compact_hir_nearest_loop",
                inputs.canonical_hir.nearest_loop.as_entire_binding(),
            ),
            ("if_depth", if_depth_buf.as_entire_binding()),
        ]);
        let hir_body_plan_validate_control_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_control_compact"),
            &self.hir_body_plan_validate_control_compact_pass,
            0,
            &hir_body_plan_validate_return_compact_bindings,
        )?;
        let hir_body_plan_validate_return_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_call"),
            &self.hir_body_plan_validate_return_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_agg_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_agg_call"),
            &self.hir_body_plan_validate_return_agg_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_assign_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_assign"),
            &self.hir_body_plan_validate_assign_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_control_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_control"),
            &self.hir_body_plan_validate_control_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_agg_range_control_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_agg_range_control"),
            &self.hir_body_plan_validate_agg_range_control_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_call"),
            &self.hir_body_plan_validate_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_host_void_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_host_void_call"),
            &self.hir_body_plan_validate_host_void_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host"),
            &self.hir_body_plan_validate_let_host_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_env_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_env"),
            &self.hir_body_plan_validate_let_host_env_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_io_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_io"),
            &self.hir_body_plan_validate_let_host_io_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_string_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_string"),
            &self.hir_body_plan_validate_let_host_string_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_host_io_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_host_io"),
            &self.hir_body_plan_validate_return_host_io_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_host_string_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_host_string"),
            &self.hir_body_plan_validate_return_host_string_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_direct_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_direct_call"),
            &self.hir_body_plan_validate_let_direct_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_call"),
            &self.hir_body_plan_validate_let_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_call_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_call_status"),
            &self.hir_body_plan_validate_let_call_status_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_agg_direct_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_agg_direct_call"),
            &self.hir_body_plan_agg_direct_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_agg_struct_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_agg_struct"),
            &self.hir_body_plan_agg_struct_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;

        let hir_body_plan_arrays_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_arrays"),
            &self.hir_body_plan_arrays_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "parser_feature_flags",
                    parser_feature_flags_buf.as_entire_binding(),
                ),
                ("parent", parent_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                ("visible_type", visible_type_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_result_root_node",
                    expr_metadata.result_root_node.as_entire_binding(),
                ),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                (
                    "expr_subtree_total",
                    body_binding_context
                        .expr_subtree_total_buf
                        .as_entire_binding(),
                ),
                (
                    "expr_subtree_features",
                    body_binding_context
                        .expr_subtree_features_buf
                        .as_entire_binding(),
                ),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
                (
                    "hir_array_lit_context_stmt_node",
                    array_metadata.lit_context_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_array_element_parent_lit",
                    array_metadata.element_parent_lit.as_entire_binding(),
                ),
                (
                    "hir_array_element_ordinal",
                    array_metadata.element_ordinal.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_field_parent_lit",
                    struct_metadata.lit_field_parent_lit.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_context_stmt_node",
                    struct_metadata.lit_context_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_field_value_node",
                    struct_metadata.lit_field_value_node.as_entire_binding(),
                ),
                (
                    "hir_member_receiver_node",
                    struct_metadata.member_receiver_node.as_entire_binding(),
                ),
                (
                    "hir_member_name_token",
                    struct_metadata.member_name_token.as_entire_binding(),
                ),
                (
                    "member_result_field_index",
                    member_result_field_index_buf.as_entire_binding(),
                ),
                (
                    "struct_init_field_index",
                    struct_init_field_index_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_width_by_token",
                    wasm_agg_local_width_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_base_by_token",
                    wasm_agg_local_base_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_block_prefix",
                    final_agg_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "path_count_out",
                    path_metadata.count_out.as_entire_binding(),
                ),
                (
                    "path_segment_count",
                    path_metadata.segment_count.as_entire_binding(),
                ),
                (
                    "path_segment_base",
                    path_metadata.segment_base.as_entire_binding(),
                ),
                (
                    "path_segment_token",
                    path_metadata.segment_token.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_token",
                    path_metadata.id_by_owner_token.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "call_arg_row_node",
                    call_metadata.arg_row_node.as_entire_binding(),
                ),
                (
                    "call_arg_row_start",
                    call_metadata.arg_row_start.as_entire_binding(),
                ),
                (
                    "call_arg_row_count",
                    call_metadata.arg_row_count.as_entire_binding(),
                ),
                ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                (
                    "call_dependency_decl",
                    call_dependency_decl_buf.as_entire_binding(),
                ),
                (
                    "call_intrinsic_tag",
                    call_intrinsic_tag_buf.as_entire_binding(),
                ),
                (
                    "method_decl_param_offset",
                    method_decl_param_offset_buf.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_type", call_param_type_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_body_len_by_token",
                    wasm_func_body_len_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_local_max_by_token",
                    wasm_func_local_max_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_invalid_count_by_token",
                    wasm_func_invalid_count_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_detail_by_token",
                    wasm_func_detail_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                ("body_plan", body_plan_buf.as_entire_binding()),
            ],
        )?;

        let mut hir_body_plan_functions_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_plan_functions_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_plan_functions_bindings.extend([
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
        ]);
        let hir_body_plan_functions_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_functions"),
            &self.hir_body_plan_functions_pass,
            0,
            &hir_body_plan_functions_bindings,
        )?;

        let mut hir_body_plan_finalize_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_plan_finalize_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_plan_finalize_bindings.extend([
            ("body_plan", body_plan_buf.as_entire_binding()),
            ("body_status", body_status_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ]);
        let hir_body_plan_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_finalize"),
            &self.hir_body_plan_finalize_pass,
            0,
            &hir_body_plan_finalize_bindings,
        )?;

        Ok(WasmBodyPlanBindGroups {
            hir_body_plan_collect_bind_group,
            hir_body_plan_validate_bind_group,
            hir_body_plan_validate_return_compact_bind_group,
            hir_body_plan_validate_let_compact_bind_group,
            hir_body_plan_validate_stmt_expr_compact_bind_group,
            hir_body_plan_validate_assign_compact_bind_group,
            hir_body_plan_validate_control_compact_bind_group,
            hir_body_plan_validate_return_call_bind_group,
            hir_body_plan_validate_return_agg_call_bind_group,
            hir_body_plan_validate_assign_bind_group,
            hir_body_plan_validate_control_bind_group,
            hir_body_plan_validate_agg_range_control_bind_group,
            hir_body_plan_validate_print_simple_bind_group,
            hir_body_plan_validate_call_bind_group,
            hir_body_plan_validate_host_void_call_bind_group,
            hir_body_plan_validate_let_host_bind_group,
            hir_body_plan_validate_let_host_env_bind_group,
            hir_body_plan_validate_let_host_io_bind_group,
            hir_body_plan_validate_let_host_string_bind_group,
            hir_body_plan_validate_return_host_io_bind_group,
            hir_body_plan_validate_return_host_string_bind_group,
            hir_body_plan_validate_let_direct_call_bind_group,
            hir_body_plan_validate_let_call_bind_group,
            hir_body_plan_validate_let_call_status_bind_group,
            hir_body_plan_agg_direct_call_bind_group,
            hir_body_plan_agg_struct_bind_group,
            hir_body_plan_arrays_bind_group,
            hir_body_plan_functions_bind_group,
            hir_body_plan_finalize_bind_group,
        })
    }
}
