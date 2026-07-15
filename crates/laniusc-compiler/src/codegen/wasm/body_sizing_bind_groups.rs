use super::*;

pub(super) struct WasmBodySizingBindGroups {
    pub hir_body_clear_bind_group: wgpu::BindGroup,
    pub hir_body_counts_bind_group: wgpu::BindGroup,
    pub hir_body_scan_local_bind_group: wgpu::BindGroup,
    pub hir_body_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub hir_body_agg_call_arg_counts_bind_group: wgpu::BindGroup,
    pub hir_body_agg_call_arg_count_scan_local_bind_group: wgpu::BindGroup,
    pub hir_body_agg_call_arg_count_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub hir_body_agg_call_arg_records_bind_group: wgpu::BindGroup,
    pub hir_body_direct_call_arg_records_bind_group: wgpu::BindGroup,
    pub hir_body_agg_call_arg_byte_scan_local_bind_group: wgpu::BindGroup,
    pub hir_body_agg_call_arg_byte_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    pub hir_body_agg_call_finalize_bind_group: wgpu::BindGroup,
    pub hir_body_direct_call_finalize_bind_group: wgpu::BindGroup,
    pub hir_body_status_bind_group: wgpu::BindGroup,
}

impl GpuWasmCodeGenerator {
    pub(super) fn create_wasm_body_sizing_bind_groups(
        &self,
        device: &wgpu::Device,
        inputs: GpuWasmCodegenInputs<'_>,
        working: &WasmWorkingBuffers,
        expr_order: &ResidentWasmExprOrder,
    ) -> Result<WasmBodySizingBindGroups> {
        let GpuWasmCodegenInputs {
            call_return_type: call_return_type_buf,
            ..
        } = inputs;
        let WasmWorkingBuffers {
            arg_scan_param_bufs,
            body_buf,
            body_fragment_aux_buf,
            body_fragment_len_buf,
            body_fragment_meta_buf,
            body_plan_buf,
            body_scan_block_sum_buf,
            body_scan_local_prefix_buf,
            body_scan_param_bufs,
            body_scan_prefix_a_buf,
            body_scan_prefix_b_buf,
            body_status_buf,
            params_buf,
            status_buf,
            wasm_agg_call_arg_aux_buf,
            wasm_agg_call_arg_byte_block_sum_buf,
            wasm_agg_call_arg_byte_local_prefix_buf,
            wasm_agg_call_arg_byte_prefix_a_buf,
            wasm_agg_call_arg_byte_prefix_b_buf,
            wasm_agg_call_arg_count_block_sum_buf,
            wasm_agg_call_arg_count_by_fragment_buf,
            wasm_agg_call_arg_count_local_prefix_buf,
            wasm_agg_call_arg_count_prefix_a_buf,
            wasm_agg_call_arg_count_prefix_b_buf,
            wasm_agg_call_arg_len_buf,
            wasm_agg_call_arg_meta_buf,
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
        let hir_body_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_clear"),
            &self.hir_body_clear_pass,
            0,
            &[
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
                ("body_plan", body_plan_buf.as_entire_binding()),
            ],
        )?;

        let mut hir_body_counts_bindings = Vec::new();
        body_binding_context.extend(&mut hir_body_counts_bindings, final_agg_scan_block_prefix);
        hir_body_counts_bindings.extend([
            ("body_plan", body_plan_buf.as_entire_binding()),
            ("call_return_type", call_return_type_buf.as_entire_binding()),
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
            ("status", status_buf.as_entire_binding()),
        ]);
        let hir_body_counts_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_counts"),
            &self.hir_body_counts_pass,
            0,
            &hir_body_counts_bindings,
        )?;

        let hir_body_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    body_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_body_scan_block_bind_groups = (0..body_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &body_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &body_scan_prefix_a_buf
                } else {
                    &body_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &body_scan_prefix_a_buf
                } else {
                    &body_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", body_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            body_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let final_body_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            &body_scan_prefix_a_buf
        } else {
            &body_scan_prefix_b_buf
        };
        let hir_body_agg_call_arg_counts_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_counts"),
            &self.hir_body_agg_call_arg_counts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_call_arg_count_by_fragment",
                    wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_count_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_count_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_call_arg_count_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_count_scan_block_bind_groups = (0..body_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_call_arg_count_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_call_arg_count_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_count_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_call_arg_count_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_count_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_agg_call_arg_count_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", body_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_call_arg_count_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_arg_count_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_agg_call_arg_count_prefix_a_buf
        } else {
            &wasm_agg_call_arg_count_prefix_b_buf
        };

        let mut hir_body_agg_call_arg_records_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_agg_call_arg_records_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_agg_call_arg_records_bindings.extend([
            ("gScan", body_scan_param_bufs[0].as_entire_binding()),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
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
        ]);
        let hir_body_agg_call_arg_records_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_records"),
            &self.hir_body_agg_call_arg_records_pass,
            0,
            &hir_body_agg_call_arg_records_bindings,
        )?;
        let hir_body_direct_call_arg_records_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_direct_call_arg_records"),
            &self.hir_body_direct_call_arg_records_pass,
            0,
            &hir_body_agg_call_arg_records_bindings,
        )?;

        let hir_body_agg_call_arg_byte_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_byte_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", arg_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_call_arg_len_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_call_arg_byte_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_byte_scan_block_bind_groups = (0..arg_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_call_arg_byte_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_call_arg_byte_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_byte_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_call_arg_byte_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_byte_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_agg_call_arg_byte_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", arg_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_call_arg_byte_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_arg_byte_scan_block_prefix = if (arg_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_agg_call_arg_byte_prefix_a_buf
        } else {
            &wasm_agg_call_arg_byte_prefix_b_buf
        };
        let mut hir_body_agg_call_finalize_bindings = Vec::new();
        body_binding_context.extend(
            &mut hir_body_agg_call_finalize_bindings,
            final_agg_scan_block_prefix,
        );
        hir_body_agg_call_finalize_bindings.extend([
            ("gScan", body_scan_param_bufs[0].as_entire_binding()),
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
        let hir_body_agg_call_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_finalize"),
            &self.hir_body_agg_call_finalize_pass,
            0,
            &hir_body_agg_call_finalize_bindings,
        )?;
        let hir_body_direct_call_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_direct_call_finalize"),
            &self.hir_body_direct_call_finalize_pass,
            0,
            &hir_body_agg_call_finalize_bindings,
        )?;
        let hir_body_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_status"),
            &self.hir_body_status_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("body_status", body_status_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        Ok(WasmBodySizingBindGroups {
            hir_body_clear_bind_group,
            hir_body_counts_bind_group,
            hir_body_scan_local_bind_group,
            hir_body_scan_block_bind_groups,
            hir_body_agg_call_arg_counts_bind_group,
            hir_body_agg_call_arg_count_scan_local_bind_group,
            hir_body_agg_call_arg_count_scan_block_bind_groups,
            hir_body_agg_call_arg_records_bind_group,
            hir_body_direct_call_arg_records_bind_group,
            hir_body_agg_call_arg_byte_scan_local_bind_group,
            hir_body_agg_call_arg_byte_scan_block_bind_groups,
            hir_body_agg_call_finalize_bind_group,
            hir_body_direct_call_finalize_bind_group,
            hir_body_status_bind_group,
        })
    }
}
