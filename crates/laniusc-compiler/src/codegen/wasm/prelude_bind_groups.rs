use super::*;

pub(super) struct WasmPreludeBindGroups {
    pub wasm_const_values_bind_group: wgpu::BindGroup,
    pub agg_layout_clear_bind_group: wgpu::BindGroup,
    pub agg_layout_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_prelude_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
    ) -> Result<WasmPreludeBindGroups> {
        let GpuWasmCodegenInputs {
            hir_status: hir_status_buf,
            hir_kind: hir_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            visible_type: visible_type_buf,
            structs: struct_metadata,
            expressions: expr_metadata,
            type_decl_hir_node_by_token: type_decl_hir_node_by_token_buf,
            call_return_type: call_return_type_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            params_buf,
            wasm_const_value_record_buf,
            struct_field_count_by_decl_token_buf,
            struct_field_index_by_token_buf,
            struct_field_decl_by_token_buf,
            struct_field_name_id_buf,
            struct_field_ref_tag_buf,
            struct_field_ref_payload_buf,
            struct_field_scalar_offset_buf,
            struct_field_scalar_width_buf,
            struct_init_field_index_buf,
            member_result_field_index_buf,
            wasm_agg_local_width_by_token_buf,
            wasm_agg_local_base_by_token_buf,
            ..
        } = working;

        let wasm_const_values_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_const_values"),
            &self.wasm_const_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
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
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "wasm_const_value_record",
                    wasm_const_value_record_buf.as_entire_binding(),
                ),
            ],
        )?;

        let mut agg_layout_clear_bindings = vec![("gParams", params_buf.as_entire_binding())];
        agg_layout_clear_bindings.extend([
            (
                "struct_field_count_by_decl_token",
                struct_field_count_by_decl_token_buf.as_entire_binding(),
            ),
            (
                "struct_field_index_by_token",
                struct_field_index_by_token_buf.as_entire_binding(),
            ),
            (
                "struct_field_decl_by_token",
                struct_field_decl_by_token_buf.as_entire_binding(),
            ),
            (
                "struct_field_name_id",
                struct_field_name_id_buf.as_entire_binding(),
            ),
            (
                "struct_field_ref_tag",
                struct_field_ref_tag_buf.as_entire_binding(),
            ),
            (
                "struct_field_ref_payload",
                struct_field_ref_payload_buf.as_entire_binding(),
            ),
            (
                "struct_field_scalar_offset",
                struct_field_scalar_offset_buf.as_entire_binding(),
            ),
            (
                "struct_field_scalar_width",
                struct_field_scalar_width_buf.as_entire_binding(),
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
                "wasm_agg_local_width_by_token",
                wasm_agg_local_width_by_token_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_local_base_by_token",
                wasm_agg_local_base_by_token_buf.as_entire_binding(),
            ),
        ]);
        let agg_layout_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_agg_layout_clear"),
            &self.agg_layout_clear_pass,
            0,
            &agg_layout_clear_bindings,
        )?;

        let agg_layout_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node",
                expr_metadata.result_root_node.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_count",
                struct_metadata.struct_decl_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node",
                struct_metadata.lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_count",
                struct_metadata.lit_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                struct_metadata.lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                struct_metadata.member_name_token.as_entire_binding(),
            ),
            (
                "member_result_field_ordinal",
                struct_metadata
                    .member_result_field_ordinal
                    .as_entire_binding(),
            ),
            (
                "type_decl_hir_node_by_token",
                type_decl_hir_node_by_token_buf.as_entire_binding(),
            ),
            ("visible_type", visible_type_buf.as_entire_binding()),
            ("call_return_type", call_return_type_buf.as_entire_binding()),
            (
                "struct_init_field_ordinal_by_node",
                struct_metadata
                    .struct_init_field_ordinal_by_node
                    .as_entire_binding(),
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
                "wasm_agg_local_width_by_token",
                wasm_agg_local_width_by_token_buf.as_entire_binding(),
            ),
        ];
        let agg_layout_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_agg_layout"),
            &self.agg_layout_pass,
            0,
            &agg_layout_bindings,
        )?;

        Ok(WasmPreludeBindGroups {
            wasm_const_values_bind_group,
            agg_layout_clear_bind_group,
            agg_layout_bind_group,
        })
    }
}
