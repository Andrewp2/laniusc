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
use crate::gpu::buffers::LaniusBuffer;

/// Feature-count resources retained until the enclosing frontend submission
/// has completed and its summary can be consumed by backend recording.
pub struct RecordedX86FeatureMeasurement {
    _params_buf: LaniusBuffer<u32>,
    _feature_record_buf: LaniusBuffer<u32>,
    _bind_group: wgpu::BindGroup,
    readback_buf: wgpu::Buffer,
}

impl GpuX86CodeGenerator {
    /// Records feature counting and readback into an existing command encoder.
    ///
    /// This lets the compiler append the summary to its frontend submission,
    /// avoiding a separate queue submission and GPU synchronization boundary.
    pub fn record_feature_measurement(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        n_hir_nodes: u32,
        hir_status_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_stmt_record_buf: &wgpu::Buffer,
        hir_expr_record_buf: &wgpu::Buffer,
    ) -> Result<RecordedX86FeatureMeasurement> {
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
                ("x86_feature_record", feature_record_buf.as_entire_binding()),
            ],
        )?;
        zero_u32_words(queue, encoder, &feature_record_buf, 8);
        let groups = workgroup_grid_1d(n_hir_nodes.div_ceil(256).max(1));
        dispatch_compute_pass(
            encoder,
            "feature_counts",
            "codegen.x86.feature_counts",
            &self.feature_counts_pass,
            &bind_group,
            groups,
        );
        encoder.copy_buffer_to_buffer(&feature_record_buf, 0, &readback_buf, 0, 32);
        Ok(RecordedX86FeatureMeasurement {
            _params_buf: params_buf,
            _feature_record_buf: feature_record_buf,
            _bind_group: bind_group,
            readback_buf,
        })
    }

    /// Consumes a feature summary whose enclosing command buffer has already
    /// been submitted. The map normally completes immediately after the
    /// frontend status wait that precedes this call.
    pub fn finish_feature_measurement(
        &self,
        device: &wgpu::Device,
        recorded: RecordedX86FeatureMeasurement,
    ) -> Result<X86FeatureSummary> {
        let readback_slice = recorded.readback_buf.slice(..);
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
        recorded.readback_buf.unmap();
        Ok(X86FeatureSummary::from_record_words(words))
    }

    /// Counts HIR features that control x86 buffer sizing and optional pass execution.
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
    ) -> Result<X86FeatureSummary> {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.x86.feature_counts.encoder"),
        });
        let recorded = self.record_feature_measurement(
            device,
            queue,
            &mut encoder,
            token_capacity,
            n_hir_nodes,
            hir_status_buf,
            hir_kind_buf,
            hir_stmt_record_buf,
            hir_expr_record_buf,
        )?;
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.x86.feature-counts",
            encoder.finish(),
        );

        self.finish_feature_measurement(device, recorded)
    }
}
