use super::*;

impl GpuWasmCodeGenerator {
    /// Records WASM backend passes from resident frontend and type-check buffers.
    pub fn record_wasm_from_gpu_token_buffer(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        hir_node_capacity: u32,
        artifact_flags: u32,
        inputs: GpuWasmCodegenInputs<'_>,
    ) -> Result<RecordedWasmCodegen> {
        let GpuWasmCodegenInputs {
            token: token_buf,
            parent: parent_buf,
            first_child: first_child_buf,
            next_sibling: next_sibling_buf,
            hir_kind: hir_kind_buf,
            hir_token_pos: hir_token_pos_buf,
            hir_token_end: hir_token_end_buf,
            hir_status: hir_status_buf,
            parser_feature_flags: parser_feature_flags_buf,
            visible_decl: visible_decl_buf,
            visible_type: visible_type_buf,
            name_id_by_token: name_id_by_token_buf,
            language_name_id: language_name_id_buf,
            enclosing_fn: enclosing_fn_buf,
            structs: struct_metadata,
            calls: call_metadata,
            expressions: expr_metadata,
            arrays: array_metadata,
            paths: path_metadata,
            canonical_hir,
            path_id_by_owner_hir: path_id_by_owner_hir_buf,
            decl_type_ref_tag: decl_type_ref_tag_buf,
            decl_type_ref_payload: decl_type_ref_payload_buf,
            call_fn_index: call_fn_index_buf,
            call_intrinsic_tag: call_intrinsic_tag_buf,
            fn_entrypoint_tag: fn_entrypoint_tag_buf,
            call_return_type: call_return_type_buf,
            call_param_count: call_param_count_buf,
            call_param_type: call_param_type_buf,
            method_decl_param_offset: method_decl_param_offset_buf,
            method_decl_receiver_mode: method_decl_receiver_mode_buf,
            type_instance_decl_token: type_instance_decl_token_buf,
            type_decl_hir_node_by_token: type_decl_hir_node_by_token_buf,
            fn_return_ref_tag: fn_return_ref_tag_buf,
            fn_return_ref_payload: fn_return_ref_payload_buf,
            member_result_ref_tag: member_result_ref_tag_buf,
            member_result_ref_payload: member_result_ref_payload_buf,
            struct_init_field_expected_ref_tag: struct_init_field_expected_ref_tag_buf,
            struct_init_field_expected_ref_payload: struct_init_field_expected_ref_payload_buf,
            call_dependency_decl: _,
            ..
        } = inputs;
        trace_wasm_codegen("record.start");
        let output_capacity = estimate_wasm_output_capacity(source_len as usize, token_capacity);
        trace_wasm_codegen(&format!(
            "record.capacity output={output_capacity} tokens={token_capacity} hir_nodes={hir_node_capacity}"
        ));
        trace_wasm_codegen("record.fingerprint.start");
        let input_fingerprint = buffer_fingerprint(&[
            token_buf,
            parent_buf,
            first_child_buf,
            next_sibling_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            parser_feature_flags_buf,
            visible_decl_buf,
            visible_type_buf,
            name_id_by_token_buf,
            language_name_id_buf,
            enclosing_fn_buf,
            struct_metadata.lit_field_parent_lit,
            struct_metadata.member_name_token,
            struct_metadata.member_result_field_ordinal,
            struct_metadata.struct_init_field_ordinal_by_row,
            call_metadata.callee_node,
            call_metadata.context_stmt,
            call_metadata.arg_start,
            call_metadata.arg_parent_call,
            call_metadata.arg_count,
            call_metadata.arg_ordinal,
            call_metadata.arg_row_node,
            call_metadata.arg_row_start,
            call_metadata.arg_row_count,
            expr_metadata.record,
            expr_metadata.result_root_node,
            expr_metadata.parent_node,
            expr_metadata.forest_root_node,
            expr_metadata.int_value,
            expr_metadata.float_bits,
            expr_metadata.string_start,
            expr_metadata.string_len,
            expr_metadata.stmt_record,
            array_metadata.lit_first_element,
            array_metadata.lit_element_count,
            array_metadata.lit_context_stmt_node,
            array_metadata.element_parent_lit,
            array_metadata.element_ordinal,
            array_metadata.element_next,
            path_metadata.count_out,
            path_metadata.segment_count,
            path_metadata.segment_base,
            path_metadata.segment_token,
            path_metadata.id_by_owner_token,
            canonical_hir.count,
            canonical_hir.core,
            canonical_hir.links,
            canonical_hir.payload,
            canonical_hir.const_value,
            canonical_hir.expr_parent,
            canonical_hir.expr_root,
            canonical_hir.call_arg_count,
            canonical_hir.call_args,
            canonical_hir.param_count,
            canonical_hir.params,
            canonical_hir.field_count,
            canonical_hir.fields,
            canonical_hir.array_element_start,
            canonical_hir.array_element_count,
            canonical_hir.array_element_row_count,
            canonical_hir.array_elements,
            canonical_hir.string_count,
            canonical_hir.strings,
            canonical_hir.string_data_words,
            canonical_hir.string_pool_len,
            canonical_hir.path_count,
            canonical_hir.paths,
            canonical_hir.path_segment_count,
            canonical_hir.path_segments,
            path_id_by_owner_hir_buf,
            decl_type_ref_tag_buf,
            decl_type_ref_payload_buf,
            call_fn_index_buf,
            call_intrinsic_tag_buf,
            fn_entrypoint_tag_buf,
            call_return_type_buf,
            call_param_count_buf,
            call_param_type_buf,
            method_decl_param_offset_buf,
            method_decl_receiver_mode_buf,
            type_instance_decl_token_buf,
            type_decl_hir_node_by_token_buf,
            fn_return_ref_tag_buf,
            fn_return_ref_payload_buf,
            member_result_ref_tag_buf,
            member_result_ref_payload_buf,
            struct_init_field_expected_ref_tag_buf,
            struct_init_field_expected_ref_payload_buf,
        ]);
        trace_wasm_codegen("record.fingerprint.done");
        trace_wasm_codegen("record.lock.start");
        let mut guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        trace_wasm_codegen("record.lock.done");
        trace_wasm_codegen("record.resident.start");
        let bufs = match self.resident_buffers_for(
            &mut guard,
            device,
            input_fingerprint,
            output_capacity,
            token_capacity,
            hir_node_capacity,
            inputs,
        ) {
            Ok(bufs) => bufs,
            Err(err) => return Err(err),
        };
        trace_wasm_codegen("record.resident.done");

        let params = WasmParams {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes: hir_node_capacity,
            artifact_flags,
        };
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let (func_scan_local_groups_x, func_scan_local_groups_y) =
            workgroup_grid_1d(bufs.func_scan_blocks);
        let func_scan_block_groups = bufs.func_scan_blocks.div_ceil(256).max(1);
        let (func_scan_block_groups_x, func_scan_block_groups_y) =
            workgroup_grid_1d(func_scan_block_groups);
        let output_word_groups = (output_capacity as u32).div_ceil(4).div_ceil(256).max(1);
        let (output_word_groups_x, output_word_groups_y) = workgroup_grid_1d(output_word_groups);
        trace_wasm_codegen("record.write_params.start");
        queue.write_buffer(&bufs.params_buf, 0, &wasm_params_bytes(&params));
        for (scan_param_buf, scan_step) in bufs
            .body_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.body_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: token_capacity.saturating_mul(2),
                n_blocks: bufs.body_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        for (scan_param_buf, scan_step) in bufs
            .arg_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.arg_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: hir_node_capacity.saturating_mul(2).max(1),
                n_blocks: bufs.arg_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        for (scan_param_buf, scan_step) in bufs
            .func_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.func_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: token_capacity,
                n_blocks: bufs.func_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        queue.write_buffer(&bufs.body_status_buf, 0, &body_status_init_bytes());
        queue.write_buffer(&bufs.body_plan_buf, 0, &body_plan_init_bytes());
        queue.write_buffer(&bufs.status_buf, 0, &unsupported_shape_status_init_bytes());
        let const_value_clear = vec![0u8; bufs.token_capacity as usize * 2 * 4];
        queue.write_buffer(&bufs.wasm_const_value_record_buf, 0, &const_value_clear);
        queue.write_buffer(
            &bufs.body_dispatch_buf,
            0,
            &dispatch_args_bytes(output_word_groups_x, output_word_groups_y, 1),
        );
        trace_wasm_codegen("record.write_params.done");

        let agg_layout_groups = token_capacity.max(hir_node_capacity).div_ceil(256).max(1);
        let (agg_layout_groups_x, agg_layout_groups_y) = workgroup_grid_1d(agg_layout_groups);
        let hir_node_groups = hir_node_capacity.div_ceil(256).max(1);
        let (hir_node_groups_x, hir_node_groups_y) = workgroup_grid_1d(hir_node_groups);

        trace_wasm_codegen("record.dispatch.agg_layout_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.agg_layout_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.agg_layout_clear_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout_clear.done");

        trace_wasm_codegen("record.dispatch.agg_layout.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.agg_layout_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.agg_layout_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout.done");

        trace_wasm_codegen("record.dispatch.hir_agg_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_agg_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_agg_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_agg_scan_local.done");

        for (step_i, bind_group) in bufs.hir_agg_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_agg_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_agg_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_agg_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.const_values.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.const_values"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.wasm_const_values_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.wasm_const_values_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.const_values.done");

        trace_wasm_codegen("record.dispatch.hir_functions_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_clear_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_clear.done");

        trace_wasm_codegen("record.dispatch.hir_functions_mark.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_mark"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_mark_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_mark_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_mark.done");

        for iteration in 0..WASM_FUNCTION_REACHABILITY_ITERATIONS {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_functions_reach.{iteration}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_functions_reach"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_functions_reach_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_functions_reach_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_functions_reach.{iteration}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.hir_functions_count.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_count"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_count_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_count_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_count.done");

        trace_wasm_codegen("record.dispatch.hir_func_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_func_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_func_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_func_scan_local.done");

        for (step_i, bind_group) in bufs.hir_func_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_func_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_func_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_func_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.hir_functions_scatter.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_scatter"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_scatter_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_scatter_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_scatter.done");

        trace_wasm_codegen("record.dispatch.hir_body_let_init_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_let_init_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_let_init_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_let_init_clear_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_let_init_clear.done");

        trace_wasm_codegen("record.dispatch.hir_body_let_init.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_let_init"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_let_init_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_let_init_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_let_init.done");

        trace_wasm_codegen("record.dispatch.hir_expr_order.start");
        self.record_wasm_expr_order(encoder, &bufs.expr_order)?;
        trace_wasm_codegen("record.dispatch.hir_expr_order.done");

        trace_wasm_codegen("record.dispatch.hir_expr_contributions.start");
        self.record_wasm_expr_contributions(encoder, &bufs.expr_order)?;
        trace_wasm_codegen("record.dispatch.hir_expr_contributions.done");

        trace_wasm_codegen("record.dispatch.compact_hir_expr_order.start");
        self.record_wasm_expr_order(encoder, &bufs.compact_expr_order)?;
        trace_wasm_codegen("record.dispatch.compact_hir_expr_order.done");
        trace_wasm_codegen("record.dispatch.compact_hir_expr_contributions.start");
        self.record_wasm_expr_contributions(encoder, &bufs.compact_expr_order)?;
        trace_wasm_codegen("record.dispatch.compact_hir_expr_contributions.done");

        trace_wasm_codegen("record.dispatch.hir_body_plan_collect.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_collect"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_collect_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_collect_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_plan_collect.done");

        trace_wasm_codegen("record.early_features.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        encoder.copy_buffer_to_buffer(
            &bufs.body_plan_buf,
            0,
            &bufs.body_plan_readback,
            0,
            (WASM_BODY_PLAN_WORDS * 4) as u64,
        );
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_invalid_count_by_token_buf,
                0,
                &bufs.wasm_func_invalid_count_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_detail_by_token_buf,
                0,
                &bufs.wasm_func_detail_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
        }
        trace_wasm_codegen("record.early_features.copy_status.done");

        Ok(RecordedWasmCodegen {
            output_capacity,
            token_capacity,
        })
    }
}
