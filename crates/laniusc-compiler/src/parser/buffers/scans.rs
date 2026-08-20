use log::warn;

use super::{
    PackOffsetHierarchyStep,
    PackOffsetScanPlan,
    PackTotalReduceStep,
    TokenBlockScanHierarchyParams,
    TokenBlockScanPlan,
    TokenBlockScanStep,
    TreePrefixMaxBuildStep,
    TreePrefixScanStep,
};
use crate::gpu::{
    buffers::uniform_from_val,
    scan::{ScanFinalize, hierarchical_scan_levels, ping_pong_scan_steps},
};

pub(in crate::parser) fn pack_total_reduce_step_count(n_pairs: u32) -> u32 {
    let mut steps = 0;
    let mut item_count = n_pairs.div_ceil(256).max(1);
    while item_count > 1 {
        steps += 1;
        item_count = item_count.div_ceil(256).max(1);
    }
    steps
}

/// Creates the paired hierarchical scan for variable-length parser pack offsets.
pub(super) fn make_pack_offset_scan_plan(
    device: &wgpu::Device,
    n_pairs: u32,
) -> PackOffsetScanPlan {
    let n_blocks = n_pairs.div_ceil(256).max(1);
    let levels = hierarchical_scan_levels(n_blocks);
    let params = uniform_from_val(
        device,
        "pack.offset_scan.params",
        &super::super::passes::pack::offsets::Params { n_pairs, n_blocks },
    );
    let hierarchy_step =
        |direction: &str,
         index: usize,
         level: crate::gpu::scan::HierarchicalScanLevel,
         parent: Option<crate::gpu::scan::HierarchicalScanLevel>| {
            PackOffsetHierarchyStep {
                params: uniform_from_val(
                    device,
                    &format!("pack.offset_scan.{direction}.{index}.params"),
                    &super::super::passes::pack::offsets::HierarchyParams {
                        n_items: n_pairs,
                        n_blocks,
                        level_divisor: level.divisor,
                        level_offset: level.offset,
                        parent_divisor: parent.map_or(0, |value| value.divisor),
                        parent_offset: parent.map_or(0, |value| value.offset),
                    },
                ),
                work_items: level.count,
            }
        };
    let up = levels
        .iter()
        .copied()
        .enumerate()
        .map(|(index, level)| hierarchy_step("up", index, level, levels.get(index + 1).copied()))
        .collect();
    let down = (0..levels.len().saturating_sub(1))
        .rev()
        .map(|index| hierarchy_step("down", index, levels[index], Some(levels[index + 1])))
        .collect();
    PackOffsetScanPlan { params, up, down }
}

/// Creates reduction steps that collapse per-block pack totals to one total.
pub(super) fn make_pack_total_reduce_steps(
    device: &wgpu::Device,
    n_pairs: u32,
) -> Vec<PackTotalReduceStep> {
    let mut steps = Vec::with_capacity(pack_total_reduce_step_count(n_pairs) as usize);
    let mut item_count = n_pairs.div_ceil(256).max(1);
    let mut read_from_a = true;
    let mut write_to_a = false;
    while item_count > 1 {
        let label = "pack.total_reduce.params";
        steps.push(PackTotalReduceStep {
            params: uniform_from_val(
                device,
                label,
                &super::super::passes::pack::totals::reduce::Params { item_count },
            ),
            item_count,
            read_from_a,
            write_to_a,
        });
        item_count = item_count.div_ceil(256).max(1);
        read_from_a = write_to_a;
        write_to_a = !write_to_a;
    }
    steps
}

pub(super) fn make_token_block_scan_plan(
    device: &wgpu::Device,
    label: &str,
    n_blocks: u32,
) -> TokenBlockScanPlan {
    let n_blocks = n_blocks.max(1);
    let levels = hierarchical_scan_levels(n_blocks);
    let step = |direction: &str,
                index: usize,
                level: crate::gpu::scan::HierarchicalScanLevel,
                parent: Option<crate::gpu::scan::HierarchicalScanLevel>| {
        TokenBlockScanStep {
            params: uniform_from_val(
                device,
                &format!("{label}.{direction}.{index}.params"),
                &TokenBlockScanHierarchyParams {
                    n_blocks,
                    level_divisor: level.divisor,
                    level_offset: level.offset,
                    parent_divisor: parent.map_or(0, |value| value.divisor),
                    parent_offset: parent.map_or(0, |value| value.offset),
                    reserved0: 0,
                    reserved1: 0,
                    reserved2: 0,
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
    TokenBlockScanPlan { up, down }
}

/// Creates a hierarchical inclusive scan over semantic-HIR block sums.
pub(super) fn make_hir_prefix_scan_plan(
    device: &wgpu::Device,
    n_blocks: u32,
) -> crate::gpu::operations::InclusiveBlockScanPlan {
    crate::gpu::operations::InclusiveBlockScanPlan::new(
        device,
        "parser.hir_semantic_prefix",
        n_blocks,
    )
}

pub(super) fn make_tree_prefix_scan_steps(
    device: &wgpu::Device,
    base: super::super::passes::tree::prefix::local::Params,
    n_blocks: u32,
) -> Vec<TreePrefixScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::Always(n_blocks))
        .into_iter()
        .map(|plan| TreePrefixScanStep {
            params: uniform_from_val(
                device,
                "parser.tree_prefix_scan.legacy.params",
                &super::super::passes::tree::prefix::local::Params {
                    scan_step: plan.scan_step,
                    ..base
                },
            ),
            read_from_a: plan.read_from_a,
            write_to_a: plan.write_to_a,
        })
        .collect()
}

/// Creates the bottom-up max tree used to bound recovered tree prefix values.
pub(super) fn make_tree_prefix_max_build_steps(
    device: &wgpu::Device,
    n_blocks: u32,
    leaf_base: u32,
) -> Vec<TreePrefixMaxBuildStep> {
    let mut steps = Vec::new();
    steps.push(TreePrefixMaxBuildStep {
        params: uniform_from_val(
            device,
            "parser.tree_prefix_max.params.leaves",
            &super::super::passes::tree::prefix::build_max_tree::Params {
                n_blocks,
                leaf_base,
                start_node: 0,
                node_count: leaf_base,
                mode: 0,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0,
            },
        ),
        work_items: leaf_base,
    });

    let mut start_node = leaf_base / 2;
    while start_node > 0 {
        steps.push(TreePrefixMaxBuildStep {
            params: uniform_from_val(
                device,
                "parser.tree_prefix_max.params.combine",
                &super::super::passes::tree::prefix::build_max_tree::Params {
                    n_blocks,
                    leaf_base,
                    start_node,
                    node_count: start_node,
                    mode: 1,
                    _pad0: 0,
                    _pad1: 0,
                    _pad2: 0,
                },
            ),
            work_items: start_node,
        });

        if start_node == 1 {
            break;
        }
        start_node /= 2;
    }

    steps
}

/// Returns the next power of two, saturating at the largest supported tree base.
pub(super) fn next_power_of_two_u32(value: u32) -> u32 {
    value.checked_next_power_of_two().unwrap_or_else(|| {
        warn!(
            "value {value} overflows next_power_of_two_u32; using saturated value {}",
            1 << 31
        );
        1 << 31
    })
}

#[cfg(test)]
mod tests {
    use super::make_token_block_scan_plan;
    use crate::gpu::{
        buffers::{
            readback_bytes,
            storage_ro_from_bytes,
            storage_ro_from_u32s,
            storage_rw_for_array,
        },
        passes_core::{
            begin_counted_compute_pass,
            bind_group,
            make_pass_data_from_shader_key,
            map_readback_blocking,
        },
    };

    #[test]
    fn physical_gpu_statement_event_scan_crosses_workgroup_boundary() {
        let gpu = crate::gpu::device::global();
        let values = (0..257u32)
            .map(|index| (index.wrapping_mul(73) % 997) << 8)
            .collect::<Vec<_>>();
        let input = storage_ro_from_u32s(&gpu.device, "test.context_scan.input", &values);
        let output =
            storage_rw_for_array::<u32>(&gpu.device, "test.context_scan.output", values.len());
        let hierarchy =
            storage_rw_for_array::<u32>(&gpu.device, "test.context_scan.hierarchy", values.len());
        let readback = readback_bytes(
            &gpu.device,
            "test.context_scan.readback",
            values.len() * 4,
            values.len() * 4,
        );
        let plan =
            make_token_block_scan_plan(&gpu.device, "test.context_scan", values.len() as u32);
        let up = make_pass_data_from_shader_key(
            &gpu.device,
            "test.context_scan.up",
            "main",
            "parser/tokens/context/scan_up",
        )
        .unwrap();
        let down = make_pass_data_from_shader_key(
            &gpu.device,
            "test.context_scan.down",
            "main",
            "parser/tokens/context/scan_down",
        )
        .unwrap();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.context_scan.encoder"),
            });
        for step in &plan.up {
            let group = bind_group::create_bind_group_from_bindings(
                &gpu.device,
                Some("test.context_scan.up"),
                &up,
                0,
                &[
                    ("gContextScan", step.params.as_entire_binding()),
                    ("statement_event_block", input.as_entire_binding()),
                    ("statement_event_block_prefix", output.as_entire_binding()),
                    ("statement_event_hierarchy", hierarchy.as_entire_binding()),
                ],
            )
            .unwrap();
            let mut pass = begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some("test.context_scan.up"),
                    timestamp_writes: None,
                },
            );
            pass.set_pipeline(&up.pipeline);
            pass.set_bind_group(0, Some(&group), &[]);
            crate::gpu::passes_core::record_compute_dispatch();
            pass.dispatch_workgroups(step.work_items.div_ceil(256), 1, 1);
        }
        for step in &plan.down {
            let group = bind_group::create_bind_group_from_bindings(
                &gpu.device,
                Some("test.context_scan.down"),
                &down,
                0,
                &[
                    ("gContextScan", step.params.as_entire_binding()),
                    ("statement_event_block_prefix", output.as_entire_binding()),
                    ("statement_event_hierarchy", hierarchy.as_entire_binding()),
                ],
            )
            .unwrap();
            let mut pass = begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some("test.context_scan.down"),
                    timestamp_writes: None,
                },
            );
            pass.set_pipeline(&down.pipeline);
            pass.set_bind_group(0, Some(&group), &[]);
            crate::gpu::passes_core::record_compute_dispatch();
            pass.dispatch_workgroups(step.work_items.div_ceil(256), 1, 1);
        }
        encoder.copy_buffer_to_buffer(
            &output.buffer,
            output.byte_offset,
            &readback.buffer,
            0,
            values.len() as u64 * 4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "test context scan readback").unwrap();
        let mapped = slice.get_mapped_range();
        let actual = mapped
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        let mut maximum = 0;
        let expected = values
            .iter()
            .map(|&value| {
                let before = maximum;
                maximum = maximum.max(value);
                before
            })
            .collect::<Vec<_>>();
        assert_eq!(actual, expected);
    }

    #[test]
    fn physical_gpu_delimiter_scan_matches_add_and_max_prefixes() {
        let gpu = crate::gpu::device::global();
        let count = 4_097usize;
        let depths = (0..count)
            .map(|index| (index as i32 % 11) - 5)
            .collect::<Vec<_>>();
        let depth_bytes = depths
            .iter()
            .flat_map(|value| value.to_le_bytes())
            .collect::<Vec<_>>();
        let zeros_i32 = vec![0u8; count * 4];
        let events = (0..count as u32)
            .map(|index| (index.wrapping_mul(73) % 997) << 8)
            .collect::<Vec<_>>();

        let brace =
            storage_ro_from_bytes::<i32>(&gpu.device, "test.delimiter.brace", &depth_bytes, count);
        let bracket =
            storage_ro_from_bytes::<i32>(&gpu.device, "test.delimiter.bracket", &zeros_i32, count);
        let paren =
            storage_ro_from_bytes::<i32>(&gpu.device, "test.delimiter.paren", &zeros_i32, count);
        let angle =
            storage_ro_from_bytes::<i32>(&gpu.device, "test.delimiter.angle", &zeros_i32, count);
        let owner = storage_ro_from_u32s(&gpu.device, "test.delimiter.owner", &events);
        let event = storage_ro_from_u32s(&gpu.device, "test.delimiter.event", &events);

        let out_brace = storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.out.brace", count);
        let out_bracket =
            storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.out.bracket", count);
        let out_paren = storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.out.paren", count);
        let out_angle = storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.out.angle", count);
        let out_owner = storage_rw_for_array::<u32>(&gpu.device, "test.delimiter.out.owner", count);
        let out_event = storage_rw_for_array::<u32>(&gpu.device, "test.delimiter.out.event", count);
        let hierarchy_brace =
            storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.hierarchy.brace", count);
        let hierarchy_bracket =
            storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.hierarchy.bracket", count);
        let hierarchy_paren =
            storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.hierarchy.paren", count);
        let hierarchy_angle =
            storage_rw_for_array::<i32>(&gpu.device, "test.delimiter.hierarchy.angle", count);
        let hierarchy_owner =
            storage_rw_for_array::<u32>(&gpu.device, "test.delimiter.hierarchy.owner", count);
        let hierarchy_event =
            storage_rw_for_array::<u32>(&gpu.device, "test.delimiter.hierarchy.event", count);
        let readback = readback_bytes(&gpu.device, "test.delimiter.readback", count * 8, count * 8);
        let plan = make_token_block_scan_plan(&gpu.device, "test.delimiter", count as u32);
        let up = make_pass_data_from_shader_key(
            &gpu.device,
            "test.delimiter.up",
            "main",
            "parser/tokens/delimiters/02_scan_up",
        )
        .unwrap();
        let down = make_pass_data_from_shader_key(
            &gpu.device,
            "test.delimiter.down",
            "main",
            "parser/tokens/delimiters/02_scan_down",
        )
        .unwrap();
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.delimiter.encoder"),
            });
        for step in &plan.up {
            let group = bind_group::create_bind_group_from_bindings(
                &gpu.device,
                Some("test.delimiter.up"),
                &up,
                0,
                &[
                    ("gDelimiterScan", step.params.as_entire_binding()),
                    ("block_sum_brace", brace.as_entire_binding()),
                    ("block_sum_bracket", bracket.as_entire_binding()),
                    ("block_sum_paren", paren.as_entire_binding()),
                    ("block_sum_angle", angle.as_entire_binding()),
                    ("top_brace_owner_block", owner.as_entire_binding()),
                    ("statement_event_block", event.as_entire_binding()),
                    ("block_prefix_brace", out_brace.as_entire_binding()),
                    ("block_prefix_bracket", out_bracket.as_entire_binding()),
                    ("block_prefix_paren", out_paren.as_entire_binding()),
                    ("block_prefix_angle", out_angle.as_entire_binding()),
                    (
                        "top_brace_owner_block_prefix",
                        out_owner.as_entire_binding(),
                    ),
                    (
                        "statement_event_block_prefix",
                        out_event.as_entire_binding(),
                    ),
                    ("hierarchy_brace", hierarchy_brace.as_entire_binding()),
                    ("hierarchy_bracket", hierarchy_bracket.as_entire_binding()),
                    ("hierarchy_paren", hierarchy_paren.as_entire_binding()),
                    ("hierarchy_angle", hierarchy_angle.as_entire_binding()),
                    ("hierarchy_owner", hierarchy_owner.as_entire_binding()),
                    ("hierarchy_event", hierarchy_event.as_entire_binding()),
                ],
            )
            .unwrap();
            let mut pass = begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some("test.delimiter.up"),
                    timestamp_writes: None,
                },
            );
            pass.set_pipeline(&up.pipeline);
            pass.set_bind_group(0, Some(&group), &[]);
            crate::gpu::passes_core::record_compute_dispatch();
            pass.dispatch_workgroups(step.work_items.div_ceil(256), 1, 1);
        }
        for step in &plan.down {
            let group = bind_group::create_bind_group_from_bindings(
                &gpu.device,
                Some("test.delimiter.down"),
                &down,
                0,
                &[
                    ("gDelimiterScan", step.params.as_entire_binding()),
                    ("block_prefix_brace", out_brace.as_entire_binding()),
                    ("block_prefix_bracket", out_bracket.as_entire_binding()),
                    ("block_prefix_paren", out_paren.as_entire_binding()),
                    ("block_prefix_angle", out_angle.as_entire_binding()),
                    (
                        "top_brace_owner_block_prefix",
                        out_owner.as_entire_binding(),
                    ),
                    (
                        "statement_event_block_prefix",
                        out_event.as_entire_binding(),
                    ),
                    ("hierarchy_brace", hierarchy_brace.as_entire_binding()),
                    ("hierarchy_bracket", hierarchy_bracket.as_entire_binding()),
                    ("hierarchy_paren", hierarchy_paren.as_entire_binding()),
                    ("hierarchy_angle", hierarchy_angle.as_entire_binding()),
                    ("hierarchy_owner", hierarchy_owner.as_entire_binding()),
                    ("hierarchy_event", hierarchy_event.as_entire_binding()),
                ],
            )
            .unwrap();
            let mut pass = begin_counted_compute_pass(
                &mut encoder,
                &wgpu::ComputePassDescriptor {
                    label: Some("test.delimiter.down"),
                    timestamp_writes: None,
                },
            );
            pass.set_pipeline(&down.pipeline);
            pass.set_bind_group(0, Some(&group), &[]);
            crate::gpu::passes_core::record_compute_dispatch();
            pass.dispatch_workgroups(step.work_items.div_ceil(256), 1, 1);
        }
        encoder.copy_buffer_to_buffer(
            &out_brace.buffer,
            out_brace.byte_offset,
            &readback.buffer,
            0,
            count as u64 * 4,
        );
        encoder.copy_buffer_to_buffer(
            &out_event.buffer,
            out_event.byte_offset,
            &readback.buffer,
            count as u64 * 4,
            count as u64 * 4,
        );
        gpu.queue.submit(Some(encoder.finish()));

        let slice = readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "test delimiter scan readback").unwrap();
        let mapped = slice.get_mapped_range();
        let actual_depth = mapped[..count * 4]
            .chunks_exact(4)
            .map(|bytes| i32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        let actual_event = mapped[count * 4..]
            .chunks_exact(4)
            .map(|bytes| u32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        let mut sum = 0i32;
        let expected_depth = depths
            .iter()
            .map(|&value| {
                let before = sum;
                sum += value;
                before
            })
            .collect::<Vec<_>>();
        let mut maximum = 0u32;
        let expected_event = events
            .iter()
            .map(|&value| {
                let before = maximum;
                maximum = maximum.max(value);
                before
            })
            .collect::<Vec<_>>();
        assert_eq!(actual_depth, expected_depth);
        assert_eq!(actual_event, expected_event);
    }
}
