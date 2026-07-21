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
            visible_type: visible_type_buf,
            structs: struct_metadata,
            canonical_hir,
            type_decl_hir_node_by_token: type_decl_hir_node_by_token_buf,
            call_return_type: call_return_type_buf,
            decl_type_ref_tag: decl_type_ref_tag_buf,
            decl_type_ref_payload: decl_type_ref_payload_buf,
            type_instance_decl_token: type_instance_decl_token_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            params_buf,
            wasm_const_value_record_buf,
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
                ("compact_hir_count", canonical_hir.count.as_entire_binding()),
                ("compact_hir_core", canonical_hir.core.as_entire_binding()),
                (
                    "compact_hir_payload",
                    canonical_hir.payload.as_entire_binding(),
                ),
                (
                    "compact_const_value",
                    canonical_hir.const_value.as_entire_binding(),
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
            ("compact_hir_count", canonical_hir.count.as_entire_binding()),
            ("compact_hir_core", canonical_hir.core.as_entire_binding()),
            (
                "compact_hir_payload",
                canonical_hir.payload.as_entire_binding(),
            ),
            (
                "compact_field_count",
                canonical_hir.field_count.as_entire_binding(),
            ),
            ("compact_fields", canonical_hir.fields.as_entire_binding()),
            (
                "decl_type_ref_tag",
                decl_type_ref_tag_buf.as_entire_binding(),
            ),
            (
                "decl_type_ref_payload",
                decl_type_ref_payload_buf.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_instance_decl_token_buf.as_entire_binding(),
            ),
            (
                "struct_init_field_ordinal_by_row",
                struct_metadata
                    .struct_init_field_ordinal_by_row
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
