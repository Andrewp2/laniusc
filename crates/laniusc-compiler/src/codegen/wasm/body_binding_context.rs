use super::*;

pub(super) struct WasmBodyBindingContext<'a> {
    pub inputs: GpuWasmCodegenInputs<'a>,
    expr_order: Option<&'a ResidentWasmExprOrder>,
    pub params_buf: &'a LaniusBuffer<WasmParams>,
    pub wasm_const_value_record_buf: &'a LaniusBuffer<u32>,
    pub body_let_init_expr_by_decl_token_buf: &'a LaniusBuffer<u32>,
    pub body_let_init_hir_by_decl_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_agg_local_width_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_agg_local_base_by_token_buf: &'a LaniusBuffer<u32>,
    pub struct_init_field_index_buf: &'a LaniusBuffer<u32>,
    pub member_result_field_index_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_flag_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_slot_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_param_ordinal_by_decl_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_body_len_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_local_max_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_return_count_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_invalid_count_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_return_token_by_token_buf: &'a LaniusBuffer<u32>,
    pub wasm_func_detail_by_token_buf: &'a LaniusBuffer<u32>,
    pub expr_subtree_total_buf: &'a LaniusBuffer<u32>,
    pub expr_subtree_features_buf: &'a LaniusBuffer<u32>,
}

impl WasmBodyBindingContext<'_> {
    pub(super) fn new<'a>(
        inputs: GpuWasmCodegenInputs<'a>,
        working: &'a WasmWorkingBuffers,
    ) -> WasmBodyBindingContext<'a> {
        WasmBodyBindingContext {
            inputs,
            expr_order: None,
            params_buf: &working.params_buf,
            wasm_const_value_record_buf: &working.wasm_const_value_record_buf,
            body_let_init_expr_by_decl_token_buf: &working.body_let_init_expr_by_decl_token_buf,
            body_let_init_hir_by_decl_token_buf: &working.body_let_init_hir_by_decl_token_buf,
            wasm_agg_local_width_by_token_buf: &working.wasm_agg_local_width_by_token_buf,
            wasm_agg_local_base_by_token_buf: &working.wasm_agg_local_base_by_token_buf,
            struct_init_field_index_buf: &working.struct_init_field_index_buf,
            member_result_field_index_buf: &working.member_result_field_index_buf,
            wasm_func_flag_buf: &working.wasm_func_flag_buf,
            wasm_func_slot_by_token_buf: &working.wasm_func_slot_by_token_buf,
            wasm_func_param_ordinal_by_decl_token_buf: &working
                .wasm_func_param_ordinal_by_decl_token_buf,
            wasm_func_body_len_by_token_buf: &working.wasm_func_body_len_by_token_buf,
            wasm_func_local_max_by_token_buf: &working.wasm_func_local_max_by_token_buf,
            wasm_func_return_count_by_token_buf: &working.wasm_func_return_count_by_token_buf,
            wasm_func_invalid_count_by_token_buf: &working.wasm_func_invalid_count_by_token_buf,
            wasm_func_return_token_by_token_buf: &working.wasm_func_return_token_by_token_buf,
            wasm_func_detail_by_token_buf: &working.wasm_func_detail_by_token_buf,
            expr_subtree_total_buf: &working.expr_subtree_total_buf,
            expr_subtree_features_buf: &working.expr_subtree_features_buf,
        }
    }

    pub(super) fn new_with_expr_order<'a>(
        inputs: GpuWasmCodegenInputs<'a>,
        working: &'a WasmWorkingBuffers,
        expr_order: &'a ResidentWasmExprOrder,
    ) -> WasmBodyBindingContext<'a> {
        let mut context = Self::new(inputs, working);
        context.expr_order = Some(expr_order);
        context
    }

    pub(super) fn new_with_compact_expr_order<'a>(
        inputs: GpuWasmCodegenInputs<'a>,
        working: &'a WasmWorkingBuffers,
        expr_order: &'a ResidentWasmExprOrder,
    ) -> WasmBodyBindingContext<'a> {
        let mut context = Self::new_with_expr_order(inputs, working, expr_order);
        context.expr_subtree_total_buf = &working.compact_expr_subtree_total_buf;
        context.expr_subtree_features_buf = &working.compact_expr_subtree_features_buf;
        context
    }

    pub(super) fn extend<'a>(
        &'a self,
        bindings: &mut Vec<(&'static str, wgpu::BindingResource<'a>)>,
        agg_scan_block_prefix: &'a LaniusBuffer<u32>,
    ) {
        let GpuWasmCodegenInputs {
            parent: parent_buf,
            first_child: first_child_buf,
            hir_kind: hir_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            hir_token_end: hir_token_end_buf,
            hir_status: hir_status_buf,
            visible_decl: visible_decl_buf,
            visible_type: visible_type_buf,
            compact_expr_scalar_type,
            name_id_by_token: name_id_by_token_buf,
            language_name_id: language_name_id_buf,
            enclosing_fn: enclosing_fn_buf,
            structs: struct_metadata,
            calls: call_metadata,
            expressions: expr_metadata,
            arrays: array_metadata,
            paths: path_metadata,
            canonical_hir,
            path_id_by_owner_hir,
            call_fn_index: call_fn_index_buf,
            call_dependency_decl: call_dependency_decl_buf,
            call_intrinsic_tag: call_intrinsic_tag_buf,
            fn_entrypoint_tag: fn_entrypoint_tag_buf,
            call_return_type: call_return_type_buf,
            call_param_count: call_param_count_buf,
            call_param_type: call_param_type_buf,
            method_decl_param_offset: method_decl_param_offset_buf,
            method_decl_receiver_mode: method_decl_receiver_mode_buf,
            ..
        } = self.inputs;
        let params_buf = self.params_buf;
        let wasm_const_value_record_buf = self.wasm_const_value_record_buf;
        let body_let_init_expr_by_decl_token_buf = self.body_let_init_expr_by_decl_token_buf;
        let body_let_init_hir_by_decl_token_buf = self.body_let_init_hir_by_decl_token_buf;
        let wasm_agg_local_width_by_token_buf = self.wasm_agg_local_width_by_token_buf;
        let wasm_agg_local_base_by_token_buf = self.wasm_agg_local_base_by_token_buf;
        let struct_init_field_index_buf = self.struct_init_field_index_buf;
        let member_result_field_index_buf = self.member_result_field_index_buf;
        let wasm_func_flag_buf = self.wasm_func_flag_buf;
        let wasm_func_slot_by_token_buf = self.wasm_func_slot_by_token_buf;
        let wasm_func_param_ordinal_by_decl_token_buf =
            self.wasm_func_param_ordinal_by_decl_token_buf;
        let wasm_func_body_len_by_token_buf = self.wasm_func_body_len_by_token_buf;
        let wasm_func_local_max_by_token_buf = self.wasm_func_local_max_by_token_buf;
        let wasm_func_return_count_by_token_buf = self.wasm_func_return_count_by_token_buf;
        let wasm_func_invalid_count_by_token_buf = self.wasm_func_invalid_count_by_token_buf;
        let wasm_func_return_token_by_token_buf = self.wasm_func_return_token_by_token_buf;
        let wasm_func_detail_by_token_buf = self.wasm_func_detail_by_token_buf;
        let expr_subtree_total_buf = self.expr_subtree_total_buf;
        let expr_subtree_features_buf = self.expr_subtree_features_buf;
        bindings.extend([
            ("gParams", params_buf.as_entire_binding()),
            ("compact_hir_count", canonical_hir.count.as_entire_binding()),
            ("compact_hir_core", canonical_hir.core.as_entire_binding()),
            ("compact_hir_links", canonical_hir.links.as_entire_binding()),
            (
                "compact_hir_payload",
                canonical_hir.payload.as_entire_binding(),
            ),
            (
                "compact_const_value",
                canonical_hir.const_value.as_entire_binding(),
            ),
            (
                "compact_expr_parent",
                canonical_hir.expr_parent.as_entire_binding(),
            ),
            (
                "compact_expr_root",
                canonical_hir.expr_root.as_entire_binding(),
            ),
            (
                "compact_call_arg_count",
                canonical_hir.call_arg_count.as_entire_binding(),
            ),
            (
                "compact_call_args",
                canonical_hir.call_args.as_entire_binding(),
            ),
            (
                "compact_field_count",
                canonical_hir.field_count.as_entire_binding(),
            ),
            ("compact_fields", canonical_hir.fields.as_entire_binding()),
            (
                "compact_array_element_start",
                canonical_hir.array_element_start.as_entire_binding(),
            ),
            (
                "compact_array_element_count",
                canonical_hir.array_element_count.as_entire_binding(),
            ),
            (
                "compact_array_element_row_count",
                canonical_hir.array_element_row_count.as_entire_binding(),
            ),
            (
                "compact_array_elements",
                canonical_hir.array_elements.as_entire_binding(),
            ),
            (
                "compact_string_count",
                canonical_hir.string_count.as_entire_binding(),
            ),
            ("compact_strings", canonical_hir.strings.as_entire_binding()),
            (
                "compact_string_data_words",
                canonical_hir.string_data_words.as_entire_binding(),
            ),
            (
                "compact_string_pool_len",
                canonical_hir.string_pool_len.as_entire_binding(),
            ),
            (
                "compact_path_count",
                canonical_hir.path_count.as_entire_binding(),
            ),
            ("compact_paths", canonical_hir.paths.as_entire_binding()),
            (
                "compact_path_segment_count",
                canonical_hir.path_segment_count.as_entire_binding(),
            ),
            (
                "compact_path_segments",
                canonical_hir.path_segments.as_entire_binding(),
            ),
            (
                "path_id_by_owner_hir",
                path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "expr_subtree_total",
                expr_subtree_total_buf.as_entire_binding(),
            ),
            (
                "expr_subtree_features",
                expr_subtree_features_buf.as_entire_binding(),
            ),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("parent", parent_buf.as_entire_binding()),
            ("first_child", first_child_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            ("call_fn_index", call_fn_index_buf.as_entire_binding()),
            (
                "call_dependency_decl",
                call_dependency_decl_buf.as_entire_binding(),
            ),
            ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
            ("language_name_id", language_name_id_buf.as_entire_binding()),
            (
                "fn_entrypoint_tag",
                fn_entrypoint_tag_buf.as_entire_binding(),
            ),
            ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
            ("visible_decl", visible_decl_buf.as_entire_binding()),
            ("visible_type", visible_type_buf.as_entire_binding()),
            (
                "compact_expr_scalar_type",
                compact_expr_scalar_type.as_entire_binding(),
            ),
            (
                "wasm_const_value_record",
                wasm_const_value_record_buf.as_entire_binding(),
            ),
            (
                "body_let_init_expr_by_decl_token",
                body_let_init_expr_by_decl_token_buf.as_entire_binding(),
            ),
            (
                "body_let_init_hir_by_decl_token",
                body_let_init_hir_by_decl_token_buf.as_entire_binding(),
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
                agg_scan_block_prefix.as_entire_binding(),
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
            (
                "hir_array_lit_first_element",
                array_metadata.lit_first_element.as_entire_binding(),
            ),
            (
                "hir_array_lit_element_count",
                array_metadata.lit_element_count.as_entire_binding(),
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
                "hir_array_element_next",
                array_metadata.element_next.as_entire_binding(),
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
                "hir_struct_lit_field_parent_lit",
                struct_metadata.lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_value_node",
                struct_metadata.lit_field_value_node.as_entire_binding(),
            ),
            (
                "struct_init_field_index",
                struct_init_field_index_buf.as_entire_binding(),
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
                "hir_call_context_stmt_node",
                call_metadata.context_stmt.as_entire_binding(),
            ),
            (
                "hir_nearest_stmt_node",
                expr_metadata.nearest_stmt_node.as_entire_binding(),
            ),
            (
                "hir_nearest_block_node",
                expr_metadata.nearest_block_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_start",
                call_metadata.arg_start.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call",
                call_metadata.arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_count",
                call_metadata.arg_count.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal",
                call_metadata.arg_ordinal.as_entire_binding(),
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
            ("call_param_count", call_param_count_buf.as_entire_binding()),
            ("call_param_type", call_param_type_buf.as_entire_binding()),
            ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
            (
                "wasm_func_slot_by_token",
                wasm_func_slot_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_param_ordinal_by_decl_token",
                wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_body_len_by_token",
                wasm_func_body_len_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_local_max_by_token",
                wasm_func_local_max_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_return_count_by_token",
                wasm_func_return_count_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_invalid_count_by_token",
                wasm_func_invalid_count_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_return_token_by_token",
                wasm_func_return_token_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_func_detail_by_token",
                wasm_func_detail_by_token_buf.as_entire_binding(),
            ),
        ]);
        if let Some(expr_order) = self.expr_order {
            bindings.extend([
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
            ]);
        }
    }
}
