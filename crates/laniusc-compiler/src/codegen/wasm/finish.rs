use super::*;

impl GpuWasmCodeGenerator {
    /// Completes the body-planning and scatter phases shared by executable and
    /// relocatable-object output.
    pub(super) fn complete_recorded_wasm(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedWasmCodegen,
    ) -> Result<()> {
        let mut host_timer = WasmFinishHostTimer::new();
        let guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("WASM code generation buffers missing"))?;
        host_timer.stamp("lock_buffers");
        let early_prefix =
            read_wasm_prefix_plan(device, &bufs.status_readback, &bufs.body_plan_readback)?;
        host_timer.stamp("read_early_prefix");
        if early_prefix.status[2] != 0 && early_prefix.status[2] != ERR_UNSUPPORTED_SOURCE_SHAPE {
            return Err(wasm_output_error_from_status(
                early_prefix.status[2],
                early_prefix.status[3],
            )
            .into());
        }
        let early_features = WasmBodyFeatures::from_body_plan(&early_prefix.body_plan);
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] body_plan.features mask=0x{:08x}",
                early_features.mask()
            );
            eprintln!("[laniusc][wasm-codegen] readback.early_func_invalid");
            trace_func_invalid_readback(
                device,
                &bufs.wasm_func_invalid_count_readback,
                &bufs.wasm_func_detail_readback,
            )?;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.body_plan.encoder"),
        });
        host_timer.stamp("body_plan.create_encoder");
        self.record_wasm_body_plan_and_status(&mut encoder, bufs, recorded, early_features)?;
        host_timer.stamp("body_plan.record");
        self.persist_pipeline_cache_if_dirty(device);
        host_timer.stamp("body_plan.persist_pipeline_cache");
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.body_plan",
            encoder.finish(),
        );
        host_timer.stamp("body_plan.submit");

        let prefix =
            read_wasm_prefix_plan(device, &bufs.status_readback, &bufs.body_plan_readback)?;
        host_timer.stamp("body_plan.read_prefix");
        if prefix.status[2] != 0 {
            if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
                trace_body_fragment_len_readback(
                    device,
                    &bufs.body_fragment_len_readback,
                    recorded.token_capacity,
                )?;
                trace_body_fragment_aux_readback(
                    device,
                    &bufs.body_fragment_aux_readback,
                    recorded.token_capacity,
                )?;
                trace_body_fragment_meta_readback(
                    device,
                    &bufs.body_fragment_meta_readback,
                    recorded.token_capacity,
                )?;
                trace_func_invalid_readback(
                    device,
                    &bufs.wasm_func_invalid_count_readback,
                    &bufs.wasm_func_detail_readback,
                )?;
            }
            return Err(wasm_output_error_from_status(prefix.status[2], prefix.status[3]).into());
        }
        let features = WasmBodyFeatures::from_body_plan(&prefix.body_plan);
        let body_len = prefix.body_plan[3];
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] phase2.features mask=0x{:08x}",
                features.mask()
            );
            trace_body_fragment_aux_readback(
                device,
                &bufs.body_fragment_aux_readback,
                recorded.token_capacity,
            )?;
            trace_body_fragment_meta_readback(
                device,
                &bufs.body_fragment_meta_readback,
                recorded.token_capacity,
            )?;
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.phase2.encoder"),
        });
        host_timer.stamp("phase2.create_encoder");
        self.prepare_wasm_call_relocations(queue, &bufs.call_relocations, body_len)?;
        self.record_wasm_scatter_and_pack(&mut encoder, bufs, recorded, features, body_len)?;
        host_timer.stamp("phase2.record");
        // Generator initialization persists too early to capture demand-created
        // pipelines. Persist here only when phase-2 recording created one.
        self.persist_pipeline_cache_if_dirty(device);
        host_timer.stamp("phase2.persist_pipeline_cache");
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.phase2",
            encoder.finish(),
        );
        host_timer.stamp("phase2.submit");
        Ok(())
    }

    /// Reads and validates the output bytes produced by a recorded WASM backend run.
    pub fn finish_recorded_wasm(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedWasmCodegen,
    ) -> Result<Vec<u8>> {
        self.complete_recorded_wasm(device, queue, recorded)?;
        let mut host_timer = WasmFinishHostTimer::new();
        let guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("WASM code generation buffers missing"))?;
        let output = read_wasm_output(
            device,
            queue,
            &bufs.out_buf,
            &bufs.packed_out_buf,
            &bufs.status_readback,
            &bufs.body_plan_readback,
            &bufs.body_fragment_len_readback,
            &bufs.wasm_func_invalid_count_readback,
            &bufs.wasm_func_detail_readback,
            &bufs.out_readback,
            recorded.output_capacity,
            recorded.token_capacity,
        )?;
        host_timer.stamp("read_output");
        Ok(output)
    }
}
