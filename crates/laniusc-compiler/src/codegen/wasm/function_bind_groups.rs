use super::*;

pub(super) struct WasmFunctionBindGroups {
    pub hir_body_let_init_clear_bind_group: wgpu::BindGroup,
    pub hir_body_let_init_bind_group: wgpu::BindGroup,
    pub hir_functions_clear_bind_group: wgpu::BindGroup,
    pub hir_functions_mark_bind_group: wgpu::BindGroup,
    pub hir_functions_reach_bind_group: wgpu::BindGroup,
    pub hir_functions_count_bind_group: wgpu::BindGroup,
    pub hir_func_scan_local_bind_group: wgpu::BindGroup,
    pub hir_func_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub hir_agg_scan_local_bind_group: wgpu::BindGroup,
    pub hir_agg_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub hir_functions_scatter_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_function_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
    ) -> Result<WasmFunctionBindGroups> {
        let GpuWasmCodegenInputs {
            first_child: first_child_buf,
            hir_kind: hir_kind_buf,
            hir_item_kind: hir_item_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            hir_token_end: hir_token_end_buf,
            hir_status: hir_status_buf,
            name_id_by_token: name_id_by_token_buf,
            language_name_id: language_name_id_buf,
            enclosing_fn: enclosing_fn_buf,
            structs: struct_metadata,
            calls: call_metadata,
            expressions: expr_metadata,
            paths: path_metadata,
            hir_param_record: hir_param_record_buf,
            call_fn_index: call_fn_index_buf,
            call_intrinsic_tag: call_intrinsic_tag_buf,
            fn_entrypoint_tag: fn_entrypoint_tag_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            params_buf,
            body_plan_buf,
            func_scan_param_bufs,
            body_let_init_expr_by_decl_token_buf,
            wasm_agg_local_width_by_token_buf,
            wasm_agg_local_base_by_token_buf,
            wasm_agg_scan_block_sum_buf,
            wasm_agg_scan_prefix_a_buf,
            wasm_agg_scan_prefix_b_buf,
            wasm_func_body_len_by_token_buf,
            wasm_func_decl_flag_buf,
            wasm_func_detail_by_token_buf,
            wasm_func_flag_buf,
            wasm_func_invalid_count_by_token_buf,
            wasm_func_local_max_by_token_buf,
            wasm_func_param_ordinal_by_decl_token_buf,
            wasm_func_return_count_by_token_buf,
            wasm_func_return_token_by_token_buf,
            wasm_func_scan_block_sum_buf,
            wasm_func_scan_local_prefix_buf,
            wasm_func_scan_prefix_a_buf,
            wasm_func_scan_prefix_b_buf,
            wasm_func_slot_by_token_buf,
            wasm_func_token_by_slot_buf,
            ..
        } = working;
        let hir_body_let_init_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_let_init_clear"),
            &self.hir_body_let_init_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_body_let_init_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_let_init"),
            &self.hir_body_let_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("hir_token_end", hir_token_end_buf.as_entire_binding()),
                (
                    "hir_expr_result_root_node",
                    expr_metadata.result_root_node.as_entire_binding(),
                ),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_local_max_by_token",
                    wasm_func_local_max_by_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_functions_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_clear"),
            &self.hir_functions_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
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
            ],
        )?;

        let hir_functions_mark_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_mark"),
            &self.hir_functions_mark_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_item_kind", hir_item_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                (
                    "fn_entrypoint_tag",
                    fn_entrypoint_tag_buf.as_entire_binding(),
                ),
                ("hir_param_record", hir_param_record_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_functions_reach_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_reach"),
            &self.hir_functions_reach_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
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
                    "hir_member_name_token",
                    struct_metadata.member_name_token.as_entire_binding(),
                ),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                (
                    "call_intrinsic_tag",
                    call_intrinsic_tag_buf.as_entire_binding(),
                ),
                ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                ("language_name_id", language_name_id_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
            ],
        )?;

        let hir_functions_count_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_count"),
            &self.hir_functions_count_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
            ],
        )?;

        let hir_func_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_func_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", func_scan_param_bufs[0].as_entire_binding()),
                ("body_fragment_len", wasm_func_flag_buf.as_entire_binding()),
                (
                    "body_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_func_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_func_scan_block_bind_groups = (0..func_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_func_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_func_scan_prefix_a_buf
                } else {
                    &wasm_func_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_func_scan_prefix_a_buf
                } else {
                    &wasm_func_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_hir_func_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", func_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_func_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let hir_agg_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_agg_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", func_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_local_width_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_local_base_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_agg_scan_block_bind_groups = (0..func_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_scan_prefix_a_buf
                } else {
                    &wasm_agg_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_scan_prefix_a_buf
                } else {
                    &wasm_agg_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_hir_agg_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", func_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let final_func_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_func_scan_prefix_a_buf
        } else {
            &wasm_func_scan_prefix_b_buf
        };

        let hir_functions_scatter_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_scatter"),
            &self.hir_functions_scatter_pass,
            0,
            &[
                (
                    "gScan",
                    func_scan_param_bufs
                        .last()
                        .expect("function scan has at least one parameter buffer")
                        .as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
            ],
        )?;

        Ok(WasmFunctionBindGroups {
            hir_body_let_init_clear_bind_group,
            hir_body_let_init_bind_group,
            hir_functions_clear_bind_group,
            hir_functions_mark_bind_group,
            hir_functions_reach_bind_group,
            hir_functions_count_bind_group,
            hir_func_scan_local_bind_group,
            hir_func_scan_block_bind_groups,
            hir_agg_scan_local_bind_group,
            hir_agg_scan_block_bind_groups,
            hir_functions_scatter_bind_group,
        })
    }
}
