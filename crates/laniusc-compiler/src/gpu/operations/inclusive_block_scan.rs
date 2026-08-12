use anyhow::Result;
use encase::ShaderType;

use super::record_direct;
use crate::gpu::{
    buffers::{LaniusBuffer, uniform_from_val},
    passes_core::{PassData, bind_group, make_pass_data_from_shader_key},
    scan::{HierarchicalScanLevel, hierarchical_scan_levels},
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct InclusiveBlockScanParams {
    n_blocks: u32,
    level_divisor: u32,
    level_offset: u32,
    parent_divisor: u32,
    parent_offset: u32,
    _reserved0: u32,
    _reserved1: u32,
    _reserved2: u32,
}

struct InclusiveBlockScanStep {
    params: LaniusBuffer<InclusiveBlockScanParams>,
    work_items: u32,
}

/// Capacity-dependent schedule for an inclusive scan over precomputed block
/// sums. The hierarchy scratch occupies at most `n_blocks` u32 rows.
pub struct InclusiveBlockScanPlan {
    up: Vec<InclusiveBlockScanStep>,
    down: Vec<InclusiveBlockScanStep>,
}

impl InclusiveBlockScanPlan {
    pub(crate) fn new(device: &wgpu::Device, label: &str, n_blocks: u32) -> Self {
        let n_blocks = n_blocks.max(1);
        let levels = hierarchical_scan_levels(n_blocks);
        let step = |direction: &str,
                    index: usize,
                    level: HierarchicalScanLevel,
                    parent: Option<HierarchicalScanLevel>| {
            InclusiveBlockScanStep {
                params: uniform_from_val(
                    device,
                    &format!("{label}.{direction}.{index}.params"),
                    &InclusiveBlockScanParams {
                        n_blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |value| value.divisor),
                        parent_offset: parent.map_or(0, |value| value.offset),
                        _reserved0: 0,
                        _reserved1: 0,
                        _reserved2: 0,
                    },
                ),
                work_items: level.count,
            }
        };
        let up = levels
            .iter()
            .copied()
            .enumerate()
            .map(|(index, level)| step("up", index, level, levels.get(index + 1).copied()))
            .collect();
        let down = (0..levels.len().saturating_sub(1))
            .rev()
            .map(|index| step("down", index, levels[index], Some(levels[index + 1])))
            .collect();
        Self { up, down }
    }
}

/// Shared pipelines for an inclusive hierarchical scan over block sums.
pub(crate) struct InclusiveBlockScanKernels {
    up: PassData,
    down: PassData,
}

impl InclusiveBlockScanKernels {
    pub(crate) fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            up: make_pass_data_from_shader_key(
                device,
                "scan.blocks.inclusive.up",
                "main",
                "scan/blocks/inclusive_up",
            )?,
            down: make_pass_data_from_shader_key(
                device,
                "scan.blocks.inclusive.down",
                "main",
                "scan/blocks/inclusive_down",
            )?,
        })
    }

    pub(crate) fn record(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        label: &'static str,
        plan: &InclusiveBlockScanPlan,
        block_sum: &LaniusBuffer<u32>,
        block_prefix: &LaniusBuffer<u32>,
        hierarchy: &LaniusBuffer<u32>,
    ) -> Result<()> {
        for step in &plan.up {
            let group = bind_group::create_bind_group_from_bindings(
                device,
                Some(label),
                &self.up,
                0,
                &[
                    ("gBlockScan", step.params.as_entire_binding()),
                    ("block_sum", block_sum.as_entire_binding()),
                    ("block_prefix", block_prefix.as_entire_binding()),
                    ("block_hierarchy", hierarchy.as_entire_binding()),
                ],
            )?;
            record_direct(encoder, &self.up, &group, label, step.work_items)?;
        }
        for step in &plan.down {
            let group = bind_group::create_bind_group_from_bindings(
                device,
                Some(label),
                &self.down,
                0,
                &[
                    ("gBlockScan", step.params.as_entire_binding()),
                    ("block_prefix", block_prefix.as_entire_binding()),
                    ("block_hierarchy", hierarchy.as_entire_binding()),
                ],
            )?;
            record_direct(encoder, &self.down, &group, label, step.work_items)?;
        }
        Ok(())
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
        scan::hierarchical_scan_levels,
    };

    #[test]
    fn block_scan_pass_count_grows_by_hierarchy_depth_not_log_two_items() {
        for (blocks, expected) in [(1, 1), (256, 1), (257, 3), (65_536, 3), (65_537, 5)] {
            let levels = hierarchical_scan_levels(blocks).len();
            assert_eq!(levels * 2 - 1, expected);
        }
    }

    #[test]
    fn physical_gpu_inclusive_block_scan_matches_cpu_prefix_sum() {
        let gpu = crate::gpu::device::global();
        // Cross both hierarchy boundaries: 65,537 block sums require three
        // upsweep levels and two carry-propagation levels.
        let values = (0..65_537).map(|index| index % 7).collect::<Vec<u32>>();
        let block_sum = storage_ro_from_u32s(&gpu.device, "test.block_scan.input", &values);
        let block_prefix =
            storage_rw_for_array::<u32>(&gpu.device, "test.block_scan.output", values.len());
        let hierarchy =
            storage_rw_for_array::<u32>(&gpu.device, "test.block_scan.hierarchy", values.len());
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
            .record(
                &gpu.device,
                &mut encoder,
                "test.block_scan",
                &plan,
                &block_sum,
                &block_prefix,
                &hierarchy,
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
