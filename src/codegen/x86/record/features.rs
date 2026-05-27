use anyhow::Result;

use super::super::{
    GpuX86CodeGenerator,
    X86FeatureSummary,
    support::{
        dispatch_compute_pass,
        readback_u32s,
        reflected_bind_group,
        storage_u32_copy,
        uniform_u32_words,
        workgroup_grid_1d,
        zero_u32_words,
    },
};

impl GpuX86CodeGenerator {
    pub fn measure_features(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        token_capacity: u32,
        n_hir_nodes: u32,
        hir_status_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_stmt_record_buf: &wgpu::Buffer,
        hir_expr_record_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
    ) -> Result<X86FeatureSummary> {
        let params_buf = uniform_u32_words(
            device,
            "codegen.x86.feature_counts.params",
            &[token_capacity, 0, 0, n_hir_nodes],
        );
        let feature_record_buf = storage_u32_copy(device, "codegen.x86.feature_counts.record", 8);
        let readback_buf = readback_u32s(device, "codegen.x86.feature_counts.readback", 8);
        let bind_group = reflected_bind_group(
            device,
            Some("codegen.x86.feature_counts.bind_group"),
            &self.feature_counts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_stmt_record", hir_stmt_record_buf.as_entire_binding()),
                ("hir_expr_record", hir_expr_record_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("x86_feature_record", feature_record_buf.as_entire_binding()),
            ],
        )?;
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.feature_counts.encoder"),
        });
        zero_u32_words(queue, &mut encoder, &feature_record_buf, 8);
        let groups = workgroup_grid_1d(n_hir_nodes.div_ceil(256).max(1));
        dispatch_compute_pass(
            &mut encoder,
            "feature_counts",
            "codegen.x86.feature_counts",
            &self.feature_counts_pass,
            &bind_group,
            groups,
        );
        encoder.copy_buffer_to_buffer(&feature_record_buf, 0, &readback_buf, 0, 32);
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.feature-counts",
            encoder.finish(),
        );

        let readback_slice = readback_buf.slice(..);
        crate::gpu::passes_core::wait_for_readback_map(
            device,
            &readback_slice,
            "codegen.x86.feature_counts.readback",
            std::time::Duration::from_millis(crate::gpu::env::env_u64(
                "LANIUS_X86_READBACK_TIMEOUT_MS",
                3_000,
            )),
        )?;
        let words = {
            let data = readback_slice.get_mapped_range();
            let words = crate::gpu::readback::read_u32_words(&data, "x86 feature counts")?;
            drop(data);
            words
        };
        readback_buf.unmap();
        Ok(X86FeatureSummary::from_record_words(words))
    }
}
