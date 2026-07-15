use super::*;

impl GpuWasmCodeGenerator {
    pub(super) fn record_wasm_body_plan_and_status(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
        features: WasmBodyFeatures,
    ) -> Result<()> {
        let token_capacity = recorded.token_capacity;
        let body_item_capacity = token_capacity.saturating_mul(2);
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let body_item_groups = body_item_capacity.div_ceil(256).max(1);
        let (body_item_groups_x, body_item_groups_y) = workgroup_grid_1d(body_item_groups);
        let arg_record_capacity = bufs.hir_node_capacity.saturating_mul(2).max(1);
        let arg_record_groups = arg_record_capacity.div_ceil(256).max(1);
        let (arg_record_groups_x, arg_record_groups_y) = workgroup_grid_1d(arg_record_groups);
        let hir_node_groups = bufs.hir_node_capacity.div_ceil(256).max(1);
        let (hir_node_groups_x, hir_node_groups_y) = workgroup_grid_1d(hir_node_groups);
        let (body_scan_local_groups_x, body_scan_local_groups_y) =
            workgroup_grid_1d(bufs.body_scan_blocks);
        let body_scan_block_groups = bufs.body_scan_blocks.div_ceil(256).max(1);
        let (body_scan_block_groups_x, body_scan_block_groups_y) =
            workgroup_grid_1d(body_scan_block_groups);
        let (arg_scan_local_groups_x, arg_scan_local_groups_y) =
            workgroup_grid_1d(bufs.arg_scan_blocks);
        let arg_scan_block_groups = bufs.arg_scan_blocks.div_ceil(256).max(1);
        let (arg_scan_block_groups_x, arg_scan_block_groups_y) =
            workgroup_grid_1d(arg_scan_block_groups);
        let has_stmt_print_direct = features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT);
        let has_direct_call = features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || has_stmt_print_direct;
        let has_plain_let_direct = features.has(WASM_BODY_FEATURE_LET_DIRECT);
        let has_binary_direct = features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_scalar_return_direct = features.has(WASM_BODY_FEATURE_RETURN_DIRECT);
        let has_return_agg_direct = features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT);
        let has_return_call_planning =
            has_scalar_return_direct || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_assign = features.has(WASM_BODY_FEATURE_ASSIGN);
        let has_control = features.has(WASM_BODY_FEATURE_CONTROL);
        let has_stmt_print = features.has(WASM_BODY_FEATURE_STMT_PRINT);
        let has_stmt_host_void = features.has(WASM_BODY_FEATURE_STMT_HOST_VOID)
            || (features.has(WASM_BODY_FEATURE_STMT_CALL)
                && features.has(WASM_BODY_FEATURE_HOST_VOID));
        let has_host = features.has(WASM_BODY_FEATURE_HOST);
        let has_host_basic = has_host || features.has(WASM_BODY_FEATURE_HOST_BASIC);
        let has_host_env = has_host || features.has(WASM_BODY_FEATURE_HOST_ENV);
        let has_host_io_bare = features.has(WASM_BODY_FEATURE_HOST_IO)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_I32)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_STRING)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_RETURN);
        let has_host_io_i32 =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_I32) || has_host_io_bare;
        let has_host_io_string =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_STRING) || has_host_io_bare;
        let has_host_io_return =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_RETURN) || has_host_io_bare;
        let has_host_io_return_string_only =
            has_host_io_return && has_host_io_string && !has_host_io_i32 && !has_host;
        let has_host_io_return_combined = has_host_io_return && !has_host_io_return_string_only;
        let has_agg_direct_call = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_AGG_COPY);
        let has_agg_or_binary_call_arg_records = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_direct_call_arg_records = has_direct_call || has_agg_or_binary_call_arg_records;
        let use_direct_call_arg_record_shaders =
            has_direct_call_arg_records && !has_agg_or_binary_call_arg_records;
        let has_agg_struct = features.has(WASM_BODY_FEATURE_ARRAY_ALLOC)
            || features.has(WASM_BODY_FEATURE_MEMBER_EXPR);
        let has_array_like =
            features.has(WASM_BODY_FEATURE_ARRAYS) || features.has(WASM_BODY_FEATURE_ARRAY_ALLOC);

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_clear_bind_group), &[]);
        compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_clear.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_validate"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_validate_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_validate_return"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_validate_return_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_return_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return.done");

        if has_return_call_planning {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return_call.done");
        }

        if has_return_agg_direct {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_agg_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_agg_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_agg_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_agg_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_agg_call.done",
            );
        }

        if has_assign {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_assign.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_assign"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_validate_assign_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_assign_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_assign.done");
        }

        if has_control {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_control.done");

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_agg_range_control.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_agg_range_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_agg_range_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_agg_range_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_agg_range_control.done",
            );
        }

        if has_stmt_print {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_print_simple.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_print_simple"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_print_simple_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_print_simple_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_print_simple.done",
            );
        }

        if has_stmt_print_direct || features.has(WASM_BODY_FEATURE_DIRECT) {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_validate_call_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_call_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_call.done");
        }

        if has_stmt_host_void {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_host_void_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_host_void_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_host_void_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_host_void_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_host_void_call.done",
            );
        }

        if has_host_basic {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host.done");
        }

        if has_host_env {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_env.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_env"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_env_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_env_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_env.done",
            );
        }

        if has_host_io_i32 {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_io.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_io_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_io_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host_io.done");
        }

        if has_host_io_string {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_string.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_string"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_string_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_string_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_string.done",
            );
        }

        if has_host_io_return_string_only {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_string.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_host_string"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_host_string_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_host_string_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_string.done",
            );
        }

        if has_host_io_return_combined {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_io.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_host_io_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_host_io_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_io.done",
            );
        }

        if has_plain_let_direct {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_direct_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_direct_call.done",
            );
        }

        if has_binary_direct {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_call.done");
        }

        if has_agg_direct_call {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_agg_direct_call_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_agg_direct_call_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_direct_call.done");
        }

        if has_agg_struct {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_struct.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_agg_struct"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_agg_struct_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_agg_struct_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_struct.done");
        }

        if has_array_like {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_arrays.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_arrays"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_arrays_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_arrays_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_arrays.done");
        }

        if has_direct_call_arg_records {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_agg_call_arg_counts.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_counts"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_agg_call_arg_counts_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_agg_call_arg_counts_bind_group), &[]);
            compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_agg_call_arg_counts.done");

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_local.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_count_scan_local"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_agg_call_arg_count_scan_local_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scan_local_groups_x, body_scan_local_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_local.done",
            );

            for (step_i, bind_group) in bufs
                .hir_body_agg_call_arg_count_scan_block_bind_groups
                .iter()
                .enumerate()
            {
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_blocks.{step_i}.start"
                ));
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("codegen.wasm.hir_body_agg_call_arg_count_scan_blocks"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(bind_group), &[]);
                compute.dispatch_workgroups(body_scan_block_groups_x, body_scan_block_groups_y, 1);
                drop(compute);
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_blocks.{step_i}.done"
                ));
            }

            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_arg_records.start"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_arg_records.start"
            });
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(if use_direct_call_arg_record_shaders {
                    "codegen.wasm.hir_body_direct_call_arg_records"
                } else {
                    "codegen.wasm.hir_body_agg_call_arg_records"
                }),
                timestamp_writes: None,
            });
            if use_direct_call_arg_record_shaders {
                compute.set_pipeline(
                    self.hir_body_direct_call_arg_records_pass
                        .pipeline()?
                        .as_ref(),
                );
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_direct_call_arg_records_bind_group),
                    &[],
                );
            } else {
                compute.set_pipeline(self.hir_body_agg_call_arg_records_pass.pipeline()?.as_ref());
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_agg_call_arg_records_bind_group),
                    &[],
                );
            }
            compute.dispatch_workgroups(arg_record_groups_x, arg_record_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_arg_records.done"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_arg_records.done"
            });

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_local.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_byte_scan_local"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_agg_call_arg_byte_scan_local_bind_group),
                &[],
            );
            compute.dispatch_workgroups(arg_scan_local_groups_x, arg_scan_local_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_local.done",
            );

            for (step_i, bind_group) in bufs
                .hir_body_agg_call_arg_byte_scan_block_bind_groups
                .iter()
                .enumerate()
            {
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_blocks.{step_i}.start"
                ));
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("codegen.wasm.hir_body_agg_call_arg_byte_scan_blocks"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(bind_group), &[]);
                compute.dispatch_workgroups(arg_scan_block_groups_x, arg_scan_block_groups_y, 1);
                drop(compute);
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_blocks.{step_i}.done"
                ));
            }

            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_finalize.start"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_finalize.start"
            });
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(if use_direct_call_arg_record_shaders {
                    "codegen.wasm.hir_body_direct_call_finalize"
                } else {
                    "codegen.wasm.hir_body_agg_call_finalize"
                }),
                timestamp_writes: None,
            });
            if use_direct_call_arg_record_shaders {
                compute.set_pipeline(self.hir_body_direct_call_finalize_pass.pipeline()?.as_ref());
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_direct_call_finalize_bind_group),
                    &[],
                );
            } else {
                compute.set_pipeline(self.hir_body_agg_call_finalize_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(&bufs.hir_body_agg_call_finalize_bind_group), &[]);
            }
            compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_finalize.done"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_finalize.done"
            });
        }

        let skip_non_essential_validations = crate::gpu::env::env_bool_truthy(
            "LANIUS_SHADER_DISABLE_NON_ESSENTIAL_VALIDATIONS",
            true,
        );
        if !skip_non_essential_validations && has_direct_call {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_call_status.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_call_status"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_call_status_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_call_status_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_call_status.done",
            );
        }

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_functions.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_functions"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_functions_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_functions_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_functions.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_finalize.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_finalize"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_finalize_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_finalize_bind_group), &[]);
        compute.dispatch_workgroups(WASM_BODY_PLAN_FINALIZE_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_finalize.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_counts.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_counts"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_counts_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_counts_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_counts.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(body_scan_local_groups_x, body_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_scan_local.done");

        for (step_i, bind_group) in bufs.hir_body_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.body_plan.dispatch.hir_body_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(body_scan_block_groups_x, body_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.body_plan.dispatch.hir_body_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_status.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_status"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_status_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_status_bind_group), &[]);
        compute.dispatch_workgroups(WASM_BODY_STATUS_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_status.done");

        trace_wasm_codegen("record.body_plan.copy_status.start");
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
                &bufs._body_fragment_len_buf,
                0,
                &bufs.body_fragment_len_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_aux_buf,
                0,
                &bufs.body_fragment_aux_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 16) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_meta_buf,
                0,
                &bufs.body_fragment_meta_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 16) as u64,
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
        trace_wasm_codegen("record.body_plan.copy_status.done");

        Ok(())
    }
}
