use anyhow::Result;
use encase::ShaderType;

use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    passes_core::{BindGroupCache, CompilerGraphBuffers, PassData, make_pass_data_from_shader_key},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct InclusiveBlockScanParams {
    n_blocks: u32,
    _reserved0: u32,
    _reserved1: u32,
    _reserved2: u32,
}

/// Capacity-dependent parameters of an inclusive scan over precomputed
/// block sums. One workgroup scans every block (scan/blocks/inclusive).
pub struct InclusiveBlockScanPlan {
    params: LaniusBuffer<InclusiveBlockScanParams>,
}

impl InclusiveBlockScanPlan {
    pub(crate) fn new(device: &wgpu::Device, label: &str, n_blocks: u32) -> Self {
        Self {
            params: uniform_from_val(
                device,
                &format!("{label}.params"),
                &InclusiveBlockScanParams {
                    n_blocks: n_blocks.max(1),
                    _reserved0: 0,
                    _reserved1: 0,
                    _reserved2: 0,
                },
            ),
        }
    }
}

/// The shared pipeline of the one-workgroup inclusive scan over block sums.
pub(crate) struct InclusiveBlockScanKernels {
    scan: PassData,
}

impl InclusiveBlockScanKernels {
    pub(crate) fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            scan: make_pass_data_from_shader_key(
                device,
                "scan.blocks.inclusive",
                "main",
                "scan/blocks/inclusive",
            )?,
        })
    }

    /// Records the scan under the graph pass `label`: one dispatch of one
    /// workgroup.
    pub(crate) fn record_graph(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        cache: &mut BindGroupCache,
        graph_buffers: &impl CompilerGraphBuffers,
        label: &'static str,
        plan: &InclusiveBlockScanPlan,
        block_sum: &LaniusBuffer<u32>,
        block_prefix: &LaniusBuffer<u32>,
    ) -> Result<()> {
        let resources = std::collections::HashMap::from([
            ("gBlockScan".into(), plan.params.as_entire_binding()),
            ("block_sum".into(), block_sum.as_entire_binding()),
            ("block_prefix".into(), block_prefix.as_entire_binding()),
        ]);
        let group = cache
            .reflected_for_graph_invocation(
                device,
                label,
                label,
                &self.scan,
                graph_buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("inclusive block scan must have one bind group");
        super::record_direct(encoder, &self.scan, group.as_ref(), label, 1)
    }

    #[cfg(test)]
    fn record_for_test(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        label: &'static str,
        plan: &InclusiveBlockScanPlan,
        block_sum: &LaniusBuffer<u32>,
        block_prefix: &LaniusBuffer<u32>,
    ) -> Result<()> {
        use crate::gpu::passes_core::bind_group;
        let group = bind_group::create_bind_group_from_bindings(
            device,
            Some(label),
            &self.scan,
            0,
            &[
                ("gBlockScan", plan.params.as_entire_binding()),
                ("block_sum", block_sum.as_entire_binding()),
                ("block_prefix", block_prefix.as_entire_binding()),
            ],
        )?;
        super::record_direct(encoder, &self.scan, &group, label, 1)
    }

    pub(crate) fn graph_pass(&self) -> &PassData {
        &self.scan
    }
}

#[cfg(test)]
mod tests {
    use super::{InclusiveBlockScanKernels, InclusiveBlockScanPlan};
    use crate::gpu::{
        buffers::{
            readback_bytes,
            storage_ro_from_u32s,
            storage_rw_for_array,
            with_uniform_buffer_arena,
        },
        passes_core::map_readback_blocking,
    };

    #[test]
    fn physical_gpu_inclusive_block_scan_matches_cpu_prefix_sum() {
        let gpu = crate::gpu::device::global();
        // Spans many 2048-row chunks and ends in a partial one.
        let values = (0..65_537).map(|index| index % 7).collect::<Vec<u32>>();
        let block_sum = storage_ro_from_u32s(&gpu.device, "test.block_scan.input", &values);
        let block_prefix =
            storage_rw_for_array::<u32>(&gpu.device, "test.block_scan.output", values.len());
        let readback = readback_bytes(
            &gpu.device,
            "test.block_scan.readback",
            values.len() * 4,
            values.len() * 4,
        );
        let plan = with_uniform_buffer_arena(&gpu.device, "test.block_scan.uniforms", || {
            InclusiveBlockScanPlan::new(&gpu.device, "test.block_scan", values.len() as u32)
        });
        let kernels = InclusiveBlockScanKernels::new(&gpu.device).unwrap();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.block_scan.encoder"),
            });
        kernels
            .record_for_test(
                &gpu.device,
                &mut encoder,
                "test.block_scan",
                &plan,
                &block_sum,
                &block_prefix,
            )
            .unwrap();
        encoder.copy_buffer_to_buffer(
            &block_prefix.buffer,
            block_prefix.byte_offset,
            &readback.buffer,
            0,
            values.len() as u64 * 4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "test block scan readback").unwrap();
        let mapped = slice.get_mapped_range();
        let actual = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        let mut running = 0;
        let expected = values
            .iter()
            .map(|&value| {
                running += value;
                running
            })
            .collect::<Vec<_>>();
        assert_eq!(actual, expected);
    }
}
