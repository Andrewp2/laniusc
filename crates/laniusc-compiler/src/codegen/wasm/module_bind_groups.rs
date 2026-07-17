use super::*;

pub(super) struct WasmModuleBindGroups {
    pub hir_agg_body_bind_group: wgpu::BindGroup,
    pub hir_assert_module_bind_group: wgpu::BindGroup,
    pub module_type_dispatch_args_bind_group: wgpu::BindGroup,
    pub module_type_lengths_bind_group: wgpu::BindGroup,
    pub module_type_bytes_bind_group: wgpu::BindGroup,
    pub module_status_bind_group: wgpu::BindGroup,
    pub bind_group: wgpu::BindGroup,
    pub pack_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_module_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
    ) -> Result<WasmModuleBindGroups> {
        let GpuWasmCodegenInputs {
            calls: call_metadata,
            expressions: expr_metadata,
            call_return_type: call_return_type_buf,
            call_param_count: call_param_count_buf,
            call_param_type: call_param_type_buf,
            method_decl_receiver_mode: method_decl_receiver_mode_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            body_buf,
            body_plan_buf,
            body_status_buf,
            module_type_dispatch_buf,
            out_buf,
            packed_out_buf,
            params_buf,
            status_buf,
            wasm_func_flag_buf,
            wasm_func_scan_local_prefix_buf,
            wasm_func_token_by_slot_buf,
            func_scan_param_bufs,
            wasm_func_scan_prefix_a_buf,
            wasm_func_scan_prefix_b_buf,
            ..
        } = working;
        let final_func_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            wasm_func_scan_prefix_a_buf
        } else {
            wasm_func_scan_prefix_b_buf
        };
        let hir_agg_body_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_agg_body_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_agg_body"),
            &self.hir_agg_body_pass,
            0,
            &hir_agg_body_bindings,
        )?;

        let hir_assert_module_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_assert_module_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_assert_module"),
            &self.hir_assert_module_pass,
            0,
            &hir_assert_module_bindings,
        )?;

        let module_type_dispatch_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_dispatch_args"),
            &self.module_type_dispatch_args_pass,
            0,
            &[
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "module_type_dispatch_args",
                    module_type_dispatch_buf.as_entire_binding(),
                ),
            ],
        )?;

        let module_type_lengths_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_lengths"),
            &self.module_type_lengths_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
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
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
            ],
        )?;

        let module_type_bytes_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_bytes"),
            &self.module_type_bytes_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
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
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
            ],
        )?;

        let module_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_status"),
            &self.module_status_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "hir_string_pool_len",
                    expr_metadata.string_pool_len.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module"),
            &self.pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "hir_string_data_words",
                    expr_metadata.string_data_words.as_entire_binding(),
                ),
                (
                    "hir_string_pool_len",
                    expr_metadata.string_pool_len.as_entire_binding(),
                ),
                ("body_words", body_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
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
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("out_words", out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let pack_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_pack_output"),
            &self.pack_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("unpacked_words", out_buf.as_entire_binding()),
                ("packed_words", packed_out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        Ok(WasmModuleBindGroups {
            hir_agg_body_bind_group,
            hir_assert_module_bind_group,
            module_type_dispatch_args_bind_group,
            module_type_lengths_bind_group,
            module_type_bytes_bind_group,
            module_status_bind_group,
            bind_group,
            pack_bind_group,
        })
    }
}
