use super::*;

impl GpuWasmCodeGenerator {
    pub(super) fn record_wasm_scatter_and_pack(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
        features: WasmBodyFeatures,
        body_len: u32,
    ) -> Result<()> {
        let output_capacity = recorded.output_capacity;
        let token_capacity = recorded.token_capacity;
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let (func_scan_local_groups_x, func_scan_local_groups_y) =
            workgroup_grid_1d(bufs.func_scan_blocks);
        let func_scan_block_groups = bufs.func_scan_blocks.div_ceil(256).max(1);
        let (func_scan_block_groups_x, func_scan_block_groups_y) =
            workgroup_grid_1d(func_scan_block_groups);
        let body_scatter_items = output_capacity as u32;
        let body_scatter_groups = body_scatter_items.div_ceil(256).max(1);
        let (body_scatter_groups_x, body_scatter_groups_y) = workgroup_grid_1d(body_scatter_groups);
        let wasm_assert_output_groups = ((output_capacity as u32)
            .min(WASM_ASSERT_OUTPUT_TARGET_LIMIT))
        .div_ceil(256)
        .max(1);
        let (wasm_assert_output_groups_x, wasm_assert_output_groups_y) =
            workgroup_grid_1d(wasm_assert_output_groups);
        let has_direct_arg_scatter = features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT);
        let has_agg_or_binary_arg_scatter = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let expr_control_has_full_only_shape = features.has(WASM_BODY_FEATURE_ASSIGN)
            || features.has(WASM_BODY_FEATURE_CONTROL)
            || features.has(WASM_BODY_FEATURE_STMT_CALL)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT);
        let needs_expr_control_scatter = features.has(WASM_BODY_FEATURE_EXPR_CONTROL);
        let needs_full_body_scatter = expr_control_has_full_only_shape;
        let body_scatter_stage = if needs_full_body_scatter {
            "hir_body_scatter"
        } else {
            "hir_body_scatter_frame"
        };
        trace_wasm_codegen(&format!(
            "record.phase2.dispatch.{body_scatter_stage}.start"
        ));
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(if needs_full_body_scatter {
                "codegen.wasm.hir_body_scatter"
            } else {
                "codegen.wasm.hir_body_scatter_frame"
            }),
            timestamp_writes: None,
        });
        if needs_full_body_scatter {
            compute.set_pipeline(self.hir_body_scatter_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_bind_group), &[]);
        } else {
            compute.set_pipeline(self.hir_body_scatter_frame_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_frame_bind_group), &[]);
        }
        compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
        drop(compute);
        trace_wasm_codegen(&format!("record.phase2.dispatch.{body_scatter_stage}.done"));

        if features.has(WASM_BODY_FEATURE_RETURN_SCALAR) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_scalar.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_scalar"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_scalar_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_scalar_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_scalar.done");
        }

        if features.has(WASM_BODY_FEATURE_LET_CONST) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_const.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_let_const"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_let_const_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_let_const_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_const.done");
        }

        if needs_expr_control_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_expr_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_expr_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_expr_control_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_expr_control_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_expr_control.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_range_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_range_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_range_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_range_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_range_control.done");
        }

        // The generic expression-control pass also recognizes return-expression
        // fragments, but it does not implement the full aggregate-member atom
        // surface. Let the dedicated return-expression emitter own those bytes.
        if features.has(WASM_BODY_FEATURE_RETURN_EXPR) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_return_expr_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_return_expr_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr.done");
        }
        if features.has(WASM_BODY_FEATURE_RETURN_EXPR)
            || features.has(WASM_BODY_FEATURE_EXPR_CONTROL)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr_compact.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_expr_compact"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_expr_compact_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_expr_compact_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr_compact.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_control_compact.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_control_compact"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_control_compact_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_control_compact_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_control_compact.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_range_compact.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_range_compact"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_range_compact_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_range_compact_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_range_compact.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_print_compact.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_print_compact"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_print_compact_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_print_compact_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_print_compact.done");
        }

        if features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_direct.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_let_direct"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_let_direct_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_let_direct_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_direct.done");
        }
        if features.has(WASM_BODY_FEATURE_HOST_IO) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host_io.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_host_io_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_host_io_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host_io.done");
        }

        if features.has(WASM_BODY_FEATURE_HOST_BASIC)
            || features.has(WASM_BODY_FEATURE_HOST_ENV)
            || features.has(WASM_BODY_FEATURE_HOST_VOID)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_host"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_host_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_host_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host.done");
        }

        if features.has(WASM_BODY_FEATURE_ARRAYS) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_stored_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_stored_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_stored_expr_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_stored_expr_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_stored_expr.done");
        }

        if features.has(WASM_BODY_FEATURE_ARRAY_ALLOC) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_array_lean.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_array_lean"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_array_lean_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_array_lean_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_array_lean.done");
        }

        if features.has(WASM_BODY_FEATURE_AGG_COPY) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_copy.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_copy"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_agg_copy_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_agg_copy_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_copy.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_member_assign.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_member_assign"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_member_assign_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_member_assign_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_member_assign.done");
        }

        // Specialized expression bytes must win over generic, host, and array
        // emitters that recognize the same broad fragment families.
        if features.has(WASM_BODY_FEATURE_MEMBER_EXPR_SCATTER) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_conversion_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_conversion_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_conversion_expr_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_conversion_expr_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_conversion_expr.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_NESTED_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_direct_nested_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_direct_nested_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_direct_nested_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_direct_nested_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_direct_nested_call.done");
        }

        if has_direct_arg_scatter || has_agg_or_binary_arg_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_call_args.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_call_args"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_call_args_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_call_args_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_call_args.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_nested_call_args.start");
            let (nested_arg_groups_x, nested_arg_groups_y) =
                workgroup_grid_1d(bufs.arg_scan_blocks);
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_nested_call_args"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_nested_call_args_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_nested_call_args_bind_group),
                &[],
            );
            compute.dispatch_workgroups(nested_arg_groups_x, nested_arg_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_nested_call_args.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT) {
            trace_wasm_codegen(
                "record.phase2.dispatch.hir_body_scatter_return_agg_direct_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_agg_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_agg_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.phase2.dispatch.hir_body_scatter_return_agg_direct_call.done",
            );
        }

        if features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_direct_call.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_MEMBER_EXPR) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_member.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_member"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_member_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_member_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_member.done");
        }

        if features.has(WASM_BODY_FEATURE_BINARY_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_binary_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_binary_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_binary_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_binary_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_binary_direct_call.done");
        }

        trace_wasm_codegen("record.phase2.dispatch.hir_agg_body.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_agg_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_agg_body_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_agg_body_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.hir_agg_body.done");

        trace_wasm_codegen("record.phase2.dispatch.call_relocations.start");
        self.record_wasm_call_relocations(encoder, &bufs.call_relocations, body_len)?;
        trace_wasm_codegen("record.phase2.dispatch.call_relocations.done");

        trace_wasm_codegen("record.phase2.dispatch.module_type_lengths.start");
        // This buffer held sparse token-indexed reachability flags in phase
        // one and is reused below as a dense slot-indexed type-length array.
        // The length pass dispatches only live function slots, so clear stale
        // token rows before the subsequent full-capacity prefix scan.
        encoder.clear_buffer(&bufs._wasm_func_flag_buf, 0, None);
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_dispatch_args"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_dispatch_args_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_dispatch_args_bind_group), &[]);
        compute.dispatch_workgroups(1, 1, 1);
        drop(compute);
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_lengths"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_lengths_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_lengths_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs._module_type_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_type_lengths.done");

        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_func_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        for bind_group in &bufs.hir_func_scan_block_bind_groups {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.module_type_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
        }

        trace_wasm_codegen("record.phase2.dispatch.module_status.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_status"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_status_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_status_bind_group), &[]);
        compute.dispatch_workgroups(WASM_MODULE_STATUS_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_status.done");

        trace_wasm_codegen("record.phase2.dispatch.module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module.done");

        trace_wasm_codegen("record.phase2.dispatch.module_type_bytes.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_bytes"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_bytes_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_bytes_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs._module_type_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_type_bytes.done");

        trace_wasm_codegen("record.phase2.dispatch.hir_assert_module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_assert_module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_assert_module_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_assert_module_bind_group), &[]);
        compute.dispatch_workgroups(wasm_assert_output_groups_x, wasm_assert_output_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.hir_assert_module.done");

        trace_wasm_codegen("record.phase2.dispatch.pack_output.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.pack_output"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.pack_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.pack_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.pack_output.done");

        trace_wasm_codegen("record.phase2.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        encoder.copy_buffer_to_buffer(
            &bufs.call_relocations.status_buf,
            0,
            &bufs.status_readback,
            16,
            16,
        );
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &bufs.body_plan_buf,
                0,
                &bufs.body_plan_readback,
                0,
                (WASM_BODY_PLAN_WORDS * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_len_buf,
                0,
                &bufs.body_fragment_len_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 4) as u64,
            );
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
        trace_wasm_codegen("record.phase2.copy_status.done");
        Ok(())
    }
}
