use super::*;

pub(super) struct WasmBodyScatterBindGroups {
    pub hir_body_scatter_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_frame_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_return_scalar_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_return_expr_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_return_expr_compact_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_control_compact_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_range_compact_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_print_compact_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_conversion_expr_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_let_const_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_expr_control_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_agg_range_control_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_let_direct_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_direct_nested_call_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_host_io_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_host_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_stored_expr_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_agg_copy_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_member_assign_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_array_lean_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_return_member_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_agg_call_args_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_nested_call_args_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_agg_direct_call_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_return_agg_direct_call_bind_group: wgpu::BindGroup,
    pub hir_body_scatter_binary_direct_call_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_body_scatter_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
        expr_order: &ResidentWasmExprOrder,
        compact_expr_order: &ResidentWasmExprOrder,
    ) -> Result<WasmBodyScatterBindGroups> {
        let GpuWasmCodegenInputs {
            first_child: first_child_buf,
            hir_kind: hir_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            hir_token_end: hir_token_end_buf,
            hir_status: hir_status_buf,
            visible_decl: visible_decl_buf,
            visible_type: visible_type_buf,
            name_id_by_token: name_id_by_token_buf,
            language_name_id: language_name_id_buf,
            enclosing_fn: enclosing_fn_buf,
            structs: struct_metadata,
            calls: call_metadata,
            expressions: expr_metadata,
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
            arg_scan_param_bufs,
            body_buf,
            body_fragment_aux_buf,
            body_fragment_len_buf,
            body_fragment_meta_buf,
            body_let_init_expr_by_decl_token_buf,
            expr_subtree_total_buf,
            body_scan_local_prefix_buf,
            body_scan_param_bufs,
            member_result_field_index_buf,
            params_buf,
            status_buf,
            wasm_agg_call_arg_aux_buf,
            wasm_agg_call_arg_byte_local_prefix_buf,
            wasm_agg_call_arg_count_by_fragment_buf,
            wasm_agg_call_arg_count_local_prefix_buf,
            wasm_agg_call_arg_len_buf,
            wasm_agg_call_arg_meta_buf,
            wasm_agg_local_base_by_token_buf,
            wasm_agg_local_width_by_token_buf,
            wasm_const_value_record_buf,
            wasm_func_flag_buf,
            wasm_func_local_max_by_token_buf,
            wasm_func_param_ordinal_by_decl_token_buf,
            wasm_func_slot_by_token_buf,
            func_scan_param_bufs,
            wasm_agg_scan_prefix_a_buf,
            wasm_agg_scan_prefix_b_buf,
            body_scan_prefix_a_buf,
            body_scan_prefix_b_buf,
            wasm_agg_call_arg_count_prefix_a_buf,
            wasm_agg_call_arg_count_prefix_b_buf,
            wasm_agg_call_arg_byte_prefix_a_buf,
            wasm_agg_call_arg_byte_prefix_b_buf,
            ..
        } = working;
        let body_binding_context =
            WasmBodyBindingContext::new_with_expr_order(inputs, working, expr_order);
        let final_agg_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            wasm_agg_scan_prefix_a_buf
        } else {
            wasm_agg_scan_prefix_b_buf
        };
        let final_body_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            body_scan_prefix_a_buf
        } else {
            body_scan_prefix_b_buf
        };
        let final_arg_count_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            wasm_agg_call_arg_count_prefix_a_buf
        } else {
            wasm_agg_call_arg_count_prefix_b_buf
        };
        let final_arg_byte_scan_block_prefix = if (arg_scan_param_bufs.len() - 1) % 2 == 0 {
            wasm_agg_call_arg_byte_prefix_a_buf
        } else {
            wasm_agg_call_arg_byte_prefix_b_buf
        };
        let create_hir_body_scatter_bind_group = |label: &'static str, pass: &LazyWasmPass| {
            create_wasm_bind_group(
                device,
                Some(label),
                pass,
                0,
                &[
                    ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                    ("gParams", params_buf.as_entire_binding()),
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
                        "body_scan_local_prefix",
                        body_scan_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "body_scan_block_prefix",
                        final_body_scan_block_prefix.as_entire_binding(),
                    ),
                    ("status", status_buf.as_entire_binding()),
                    ("hir_status", hir_status_buf.as_entire_binding()),
                    ("first_child", first_child_buf.as_entire_binding()),
                    ("hir_kind", hir_kind_buf.as_entire_binding()),
                    ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                    ("hir_token_end", hir_token_end_buf.as_entire_binding()),
                    ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
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
                        "hir_expr_forest_root_node",
                        expr_metadata.forest_root_node.as_entire_binding(),
                    ),
                    ("expr_order", expr_order.order_a.as_entire_binding()),
                    (
                        "expr_root_order_range",
                        expr_order.root_order_range.as_entire_binding(),
                    ),
                    ("expr_node_span", expr_order.node_span.as_entire_binding()),
                    (
                        "expr_node_emission",
                        expr_order.node_emission.as_entire_binding(),
                    ),
                    (
                        "expr_subtree_total",
                        expr_subtree_total_buf.as_entire_binding(),
                    ),
                    (
                        "hir_expr_int_value",
                        expr_metadata.int_value.as_entire_binding(),
                    ),
                    (
                        "hir_expr_float_bits",
                        expr_metadata.float_bits.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_start",
                        expr_metadata.string_start.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_len",
                        expr_metadata.string_len.as_entire_binding(),
                    ),
                    ("visible_type", visible_type_buf.as_entire_binding()),
                    ("visible_decl", visible_decl_buf.as_entire_binding()),
                    (
                        "wasm_const_value_record",
                        wasm_const_value_record_buf.as_entire_binding(),
                    ),
                    ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                    ("language_name_id", language_name_id_buf.as_entire_binding()),
                    (
                        "body_let_init_expr_by_decl_token",
                        body_let_init_expr_by_decl_token_buf.as_entire_binding(),
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
                        "hir_member_receiver_node",
                        struct_metadata.member_receiver_node.as_entire_binding(),
                    ),
                    (
                        "hir_member_name_token",
                        struct_metadata.member_name_token.as_entire_binding(),
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
                    ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                    (
                        "call_dependency_decl",
                        call_dependency_decl_buf.as_entire_binding(),
                    ),
                    (
                        "call_intrinsic_tag",
                        call_intrinsic_tag_buf.as_entire_binding(),
                    ),
                    ("call_return_type", call_return_type_buf.as_entire_binding()),
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
                    (
                        "member_result_field_index",
                        member_result_field_index_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_field_node",
                        struct_metadata.member_result_field_node.as_entire_binding(),
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
                        "method_decl_param_offset",
                        method_decl_param_offset_buf.as_entire_binding(),
                    ),
                    (
                        "method_decl_receiver_mode",
                        method_decl_receiver_mode_buf.as_entire_binding(),
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
                    (
                        "wasm_agg_call_arg_count_by_fragment",
                        wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_count_local_prefix",
                        wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_count_block_prefix",
                        final_arg_count_scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_len",
                        wasm_agg_call_arg_len_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_byte_local_prefix",
                        wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_byte_block_prefix",
                        final_arg_byte_scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "wasm_func_param_ordinal_by_decl_token",
                        wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                    ),
                    ("call_param_count", call_param_count_buf.as_entire_binding()),
                    ("call_param_type", call_param_type_buf.as_entire_binding()),
                    ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                    (
                        "wasm_func_slot_by_token",
                        wasm_func_slot_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_local_max_by_token",
                        wasm_func_local_max_by_token_buf.as_entire_binding(),
                    ),
                    ("body_words", body_buf.as_entire_binding()),
                ],
            )
        };
        let hir_body_scatter_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter",
            &self.hir_body_scatter_pass,
        )?;
        let hir_body_scatter_frame_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_frame"),
            &self.hir_body_scatter_frame_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_return_scalar_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_return_scalar"),
            &self.hir_body_scatter_return_scalar_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_return_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_return_expr",
            &self.hir_body_scatter_return_expr_pass,
        )?;
        let compact_body_binding_context = WasmBodyBindingContext::new_with_compact_expr_order(
            inputs,
            working,
            compact_expr_order,
        );
        let mut compact_return_expr_bindings = Vec::new();
        compact_body_binding_context.extend(
            &mut compact_return_expr_bindings,
            final_agg_scan_block_prefix,
        );
        compact_return_expr_bindings.extend([
            ("gScan", body_scan_param_bufs[0].as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_scan_local_prefix",
                body_scan_local_prefix_buf.as_entire_binding(),
            ),
            (
                "body_scan_block_prefix",
                final_body_scan_block_prefix.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
            ("body_words", body_buf.as_entire_binding()),
        ]);
        let hir_body_scatter_return_expr_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_return_expr_compact"),
            &self.hir_body_scatter_return_expr_compact_pass,
            0,
            &compact_return_expr_bindings,
        )?;
        let hir_body_scatter_control_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_control_compact"),
            &self.hir_body_scatter_control_compact_pass,
            0,
            &compact_return_expr_bindings,
        )?;
        let hir_body_scatter_range_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_range_compact"),
            &self.hir_body_scatter_range_compact_pass,
            0,
            &compact_return_expr_bindings,
        )?;
        let hir_body_scatter_print_compact_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_print_compact"),
            &self.hir_body_scatter_print_compact_pass,
            0,
            &compact_return_expr_bindings,
        )?;
        let hir_body_scatter_conversion_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_conversion_expr",
            &self.hir_body_scatter_conversion_expr_pass,
        )?;
        let hir_body_scatter_let_const_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_let_const"),
            &self.hir_body_scatter_let_const_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_expr_control_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_expr_control",
            &self.hir_body_scatter_expr_control_pass,
        )?;
        let hir_body_scatter_agg_range_control_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_range_control",
            &self.hir_body_scatter_agg_range_control_pass,
        )?;
        let hir_body_scatter_let_direct_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_let_direct",
            &self.hir_body_scatter_let_direct_pass,
        )?;
        let hir_body_scatter_direct_nested_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_direct_nested_call",
            &self.hir_body_scatter_direct_nested_call_pass,
        )?;
        let hir_body_scatter_host_io_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_host_io",
            &self.hir_body_scatter_host_io_pass,
        )?;
        let hir_body_scatter_host_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_host",
            &self.hir_body_scatter_host_pass,
        )?;
        let hir_body_scatter_stored_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_stored_expr",
            &self.hir_body_scatter_stored_expr_pass,
        )?;
        let hir_body_scatter_agg_copy_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_copy",
            &self.hir_body_scatter_agg_copy_pass,
        )?;
        let hir_body_scatter_member_assign_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_member_assign",
            &self.hir_body_scatter_member_assign_pass,
        )?;
        let hir_body_scatter_array_lean_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_array_lean",
            &self.hir_body_scatter_array_lean_pass,
        )?;
        let hir_body_scatter_return_member_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_return_member",
            &self.hir_body_scatter_return_member_pass,
        )?;
        let mut hir_body_scatter_agg_call_args_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_scatter_agg_call_args_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_scatter_agg_call_args_bindings.extend([
            ("gBodyScan", body_scan_param_bufs[0].as_entire_binding()),
            ("gArgScan", arg_scan_param_bufs[0].as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
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
                "body_scan_local_prefix",
                body_scan_local_prefix_buf.as_entire_binding(),
            ),
            (
                "body_scan_block_prefix",
                final_body_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_by_fragment",
                wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_local_prefix",
                wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_block_prefix",
                final_arg_count_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_len",
                wasm_agg_call_arg_len_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_meta",
                wasm_agg_call_arg_meta_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_aux",
                wasm_agg_call_arg_aux_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_local_prefix",
                wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_block_prefix",
                final_arg_byte_scan_block_prefix.as_entire_binding(),
            ),
            ("body_words", body_buf.as_entire_binding()),
        ]);
        let hir_body_scatter_agg_call_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_agg_call_args"),
            &self.hir_body_scatter_agg_call_args_pass,
            0,
            &hir_body_scatter_agg_call_args_bindings,
        )?;
        let hir_body_scatter_nested_call_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_nested_call_args"),
            &self.hir_body_scatter_nested_call_args_pass,
            0,
            &hir_body_scatter_agg_call_args_bindings,
        )?;
        let hir_body_scatter_agg_direct_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_direct_call",
            &self.hir_body_scatter_agg_direct_call_pass,
        )?;
        let hir_body_scatter_return_agg_direct_call_bind_group =
            create_hir_body_scatter_bind_group(
                "codegen_wasm_hir_body_scatter_return_agg_direct_call",
                &self.hir_body_scatter_return_agg_direct_call_pass,
            )?;
        let hir_body_scatter_binary_direct_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_binary_direct_call",
            &self.hir_body_scatter_binary_direct_call_pass,
        )?;

        Ok(WasmBodyScatterBindGroups {
            hir_body_scatter_bind_group,
            hir_body_scatter_frame_bind_group,
            hir_body_scatter_return_scalar_bind_group,
            hir_body_scatter_return_expr_bind_group,
            hir_body_scatter_return_expr_compact_bind_group,
            hir_body_scatter_control_compact_bind_group,
            hir_body_scatter_range_compact_bind_group,
            hir_body_scatter_print_compact_bind_group,
            hir_body_scatter_conversion_expr_bind_group,
            hir_body_scatter_let_const_bind_group,
            hir_body_scatter_expr_control_bind_group,
            hir_body_scatter_agg_range_control_bind_group,
            hir_body_scatter_let_direct_bind_group,
            hir_body_scatter_direct_nested_call_bind_group,
            hir_body_scatter_host_io_bind_group,
            hir_body_scatter_host_bind_group,
            hir_body_scatter_stored_expr_bind_group,
            hir_body_scatter_agg_copy_bind_group,
            hir_body_scatter_member_assign_bind_group,
            hir_body_scatter_array_lean_bind_group,
            hir_body_scatter_return_member_bind_group,
            hir_body_scatter_agg_call_args_bind_group,
            hir_body_scatter_nested_call_args_bind_group,
            hir_body_scatter_agg_direct_call_bind_group,
            hir_body_scatter_return_agg_direct_call_bind_group,
            hir_body_scatter_binary_direct_call_bind_group,
        })
    }
}
