use super::super::*;

// Graph-driven control operations. The compiler graph owns every scan row;
// these names describe only the four generic aliases used by the shared
// hierarchy shaders.
#[derive(Clone, Copy)]
struct ControlScanResources {
    block_sum: &'static str,
    prefix: &'static str,
    hierarchy: &'static str,
    block_prefix: &'static str,
}

fn create_control_hierarchy(
    device: &wgpu::Device,
    label: &'static str,
    up_pass: &PassData,
    down_pass: &PassData,
    n_blocks: u32,
    resources: &ResourceMap<'_>,
    names: ControlScanResources,
) -> Result<(Vec<ScanHierarchyStep>, Vec<ScanHierarchyStep>)> {
    let levels = crate::gpu::scan::hierarchical_scan_levels(n_blocks);
    let bind = |suffix: &str,
                pass: &PassData,
                index: usize,
                level: crate::gpu::scan::HierarchicalScanLevel,
                parent: Option<crate::gpu::scan::HierarchicalScanLevel>| {
        let params = uniform_from_val(
            device,
            &format!("{label}.{suffix}.{index}.params"),
            &PrefixScanHierarchyParams {
                n_items: n_blocks.saturating_mul(256),
                n_blocks,
                level_divisor: level.divisor,
                level_offset: level.offset,
                parent_divisor: parent.map_or(0, |value| value.divisor),
                parent_offset: parent.map_or(0, |value| value.offset),
            },
        );
        let group = reflected_bind_group_with_overrides(
            device,
            &format!("{label}.{suffix}"),
            pass,
            resources,
            &[
                ("gHierarchy", params.as_entire_binding()),
                ("block_sum", resources[names.block_sum].clone()),
                ("scan_prefix", resources[names.prefix].clone()),
                ("scan_hierarchy", resources[names.hierarchy].clone()),
                ("block_prefix", resources[names.block_prefix].clone()),
            ],
        )?;
        Ok(ScanHierarchyStep {
            bind_group: group,
            work_items: level.count,
        })
    };
    let up = levels
        .iter()
        .copied()
        .enumerate()
        .map(|(index, level)| bind("up", up_pass, index, level, levels.get(index + 1).copied()))
        .collect::<Result<Vec<_>>>()?;
    let down = (0..levels.len().saturating_sub(1))
        .rev()
        .map(|index| {
            bind(
                "down",
                down_pass,
                index,
                levels[index],
                Some(levels[index + 1]),
            )
        })
        .collect::<Result<Vec<_>>>()?;
    Ok((up, down))
}

pub(in crate::type_checker) fn create_fn_context_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &ResourceMap<'_>,
    params: &LaniusBuffer<FnContextParams>,
    n_blocks: u32,
) -> Result<FnContextBindGroups> {
    let names = ControlScanResources {
        block_sum: "fn_block_sum",
        prefix: "fn_prefix_a",
        hierarchy: "fn_prefix_b",
        block_prefix: "fn_block_prefix",
    };
    let bind = |label, kernel, aliases: &[(&str, wgpu::BindingResource<'_>)]| {
        let mut overrides = vec![("gParams", params.as_entire_binding())];
        overrides.extend_from_slice(aliases);
        reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel(kernel),
            resources,
            &overrides,
        )
    };
    let block_sum = resources[names.block_sum].clone();
    let block_prefix = resources[names.block_prefix].clone();
    let clear = bind(
        "type_check_fn_context_01_clear",
        "type_checker/fn/context/01_clear",
        &[
            ("block_sum", block_sum.clone()),
            ("block_prefix", block_prefix.clone()),
        ],
    )?;
    let mark = bind(
        "type_check_fn_context_02_mark",
        "type_checker/fn/context/02_mark",
        &[],
    )?;
    let local = bind(
        "type_check_fn_context_03_local",
        "type_checker/fn/context/03_local",
        &[("block_sum", block_sum)],
    )?;
    let (hierarchy_up, hierarchy_down) = create_control_hierarchy(
        device,
        "type_check.fn_context",
        &passes.kernel("type_checker/fn/context/04_hierarchy_up"),
        &passes.kernel("type_checker/fn/context/04_hierarchy_down"),
        n_blocks,
        resources,
        names,
    )?;
    let apply = bind(
        "type_check_fn_context_05_apply",
        "type_checker/fn/context/05_apply",
        &[("block_prefix", block_prefix)],
    )?;
    Ok(FnContextBindGroups {
        clear,
        mark,
        local,
        hierarchy_up,
        hierarchy_down,
        apply,
    })
}

pub(in crate::type_checker) fn create_if_depth_bind_groups(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &ResourceMap<'_>,
    params: &LaniusBuffer<IfDepthParams>,
    n_blocks: u32,
) -> Result<IfDepthBindGroups> {
    let names = ControlScanResources {
        block_sum: "if_block_sum",
        prefix: "if_prefix_a",
        hierarchy: "if_prefix_b",
        block_prefix: "if_block_prefix",
    };
    let bind = |label, kernel, aliases: &[(&str, wgpu::BindingResource<'_>)]| {
        let mut overrides = vec![("gParams", params.as_entire_binding())];
        overrides.extend_from_slice(aliases);
        reflected_bind_group_with_overrides(
            device,
            label,
            &passes.kernel(kernel),
            resources,
            &overrides,
        )
    };
    let block_sum = resources[names.block_sum].clone();
    let block_prefix = resources[names.block_prefix].clone();
    let clear = bind(
        "type_check_if_depth_01_clear",
        "type_checker/loop/depth/01_clear",
        &[],
    )?;
    let mark = bind(
        "type_check_if_depth_02_mark",
        "type_checker/loop/depth/02_mark",
        &[],
    )?;
    let local = bind(
        "type_check_if_depth_03_local",
        "type_checker/loop/depth/03_local",
        &[("block_sum", block_sum)],
    )?;
    let (hierarchy_up, hierarchy_down) = create_control_hierarchy(
        device,
        "type_check.if_depth",
        &passes.kernel("type_checker/loop/depth/04_hierarchy_up"),
        &passes.kernel("type_checker/loop/depth/04_hierarchy_down"),
        n_blocks,
        resources,
        names,
    )?;
    let apply = bind(
        "type_check_if_depth_05_apply",
        "type_checker/loop/depth/05_apply",
        &[("block_prefix", block_prefix)],
    )?;
    Ok(IfDepthBindGroups {
        clear,
        mark,
        local,
        hierarchy_up,
        hierarchy_down,
        apply,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::{
        gpu::{
            buffers::{readback_bytes, storage_ro_from_bytes, storage_ro_from_u32s},
            device,
            passes_core::{bind_group, make_pass_data_from_shader_key, map_readback_blocking},
        },
        parser::buffers::HirCore,
    };

    fn words<const N: usize>(records: &[[u32; N]]) -> Vec<u8> {
        records
            .iter()
            .flat_map(|record| record.iter())
            .flat_map(|word| word.to_le_bytes())
            .collect()
    }

    #[test]
    fn physical_gpu_marks_compact_hir_if_spans() {
        let gpu = device::global();
        let mark_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.if_depth.mark",
            "main",
            "type_checker/loop/depth/02_mark",
        )
        .unwrap();
        let local_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.if_depth.local",
            "main",
            "type_checker/loop/depth/03_local",
        )
        .unwrap();
        let apply_pass = make_pass_data_from_shader_key(
            &gpu.device,
            "test.if_depth.apply",
            "main",
            "type_checker/loop/depth/05_apply",
        )
        .unwrap();
        let params = uniform_from_val(
            &gpu.device,
            "test.if_depth.params",
            &IfDepthParams {
                n_tokens: 64,
                n_hir_nodes: 3,
                n_blocks: 1,
                scan_step: 0,
            },
        );
        let count = storage_ro_from_u32s(&gpu.device, "test.if_depth.count", &[3]);
        let core = storage_ro_from_bytes::<HirCore>(
            &gpu.device,
            "test.if_depth.core",
            &words(&[[11, u32::MAX, 4, 60], [10, 0, 16, 40], [13, 1, 24, 25]]),
            3,
        );
        let delta = crate::gpu::buffers::storage_rw_for_array::<i32>(
            &gpu.device,
            "test.if_depth.delta",
            64,
        );
        gpu.queue.write_buffer(&delta.buffer, 0, &vec![0u8; 64 * 4]);
        let inblock = crate::gpu::buffers::storage_rw_for_array::<i32>(
            &gpu.device,
            "test.if_depth.inblock",
            64,
        );
        let block_sum = crate::gpu::buffers::storage_rw_for_array::<i32>(
            &gpu.device,
            "test.if_depth.block_sum",
            1,
        );
        let block_prefix = crate::gpu::buffers::storage_rw_for_array::<i32>(
            &gpu.device,
            "test.if_depth.block_prefix",
            1,
        );
        let depth = crate::gpu::buffers::storage_rw_for_array::<i32>(
            &gpu.device,
            "test.if_depth.depth",
            64,
        );
        for buffer in [&inblock, &block_sum, &block_prefix, &depth] {
            gpu.queue
                .write_buffer(&buffer.buffer, 0, &vec![0u8; buffer.byte_size as usize]);
        }
        let mark_group = bind_group::create_bind_group_from_bindings(
            &gpu.device,
            Some("test.if_depth.mark"),
            &mark_pass,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                ("compact_hir_count", count.as_entire_binding()),
                ("compact_hir_core", core.as_entire_binding()),
                ("if_delta", delta.as_entire_binding()),
            ],
        )
        .unwrap();
        let local_group = bind_group::create_bind_group_from_bindings(
            &gpu.device,
            Some("test.if_depth.local"),
            &local_pass,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                ("if_delta", delta.as_entire_binding()),
                ("if_depth_inblock", inblock.as_entire_binding()),
                ("block_sum", block_sum.as_entire_binding()),
            ],
        )
        .unwrap();
        let apply_group = bind_group::create_bind_group_from_bindings(
            &gpu.device,
            Some("test.if_depth.apply"),
            &apply_pass,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                ("if_depth_inblock", inblock.as_entire_binding()),
                ("block_prefix", block_prefix.as_entire_binding()),
                ("if_depth", depth.as_entire_binding()),
            ],
        )
        .unwrap();
        let delta_readback = readback_bytes(&gpu.device, "test.if_depth.delta.rb", 64 * 4, 64);
        let depth_readback = readback_bytes(&gpu.device, "test.if_depth.depth.rb", 64 * 4, 64);
        let mut encoder = gpu
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("test.if_depth.encoder"),
            });
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.if_depth.mark"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&mark_pass.pipeline);
            compute.set_bind_group(0, Some(&mark_group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&delta.buffer, 0, &delta_readback.buffer, 0, 64 * 4);
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.if_depth.local"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&local_pass.pipeline);
            compute.set_bind_group(0, Some(&local_group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("test.if_depth.apply"),
                timestamp_writes: None,
            });
            compute.set_pipeline(&apply_pass.pipeline);
            compute.set_bind_group(0, Some(&apply_group), &[]);
            compute.dispatch_workgroups(1, 1, 1);
        }
        encoder.copy_buffer_to_buffer(&depth.buffer, 0, &depth_readback.buffer, 0, 64 * 4);
        gpu.queue.submit(Some(encoder.finish()));
        let slice = delta_readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "compact HIR if-depth mark").unwrap();
        let mapped = slice.get_mapped_range();
        let actual = mapped
            .chunks_exact(4)
            .map(|bytes| i32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        assert_eq!(actual[16], 1);
        assert_eq!(actual[40], -1);
        drop(mapped);
        delta_readback.unmap();

        let slice = depth_readback.slice(..);
        map_readback_blocking(&gpu.device, &slice, "compact HIR if-depth apply").unwrap();
        let mapped = slice.get_mapped_range();
        let actual = mapped
            .chunks_exact(4)
            .map(|bytes| i32::from_le_bytes(bytes.try_into().unwrap()))
            .collect::<Vec<_>>();
        assert_eq!(actual[15], 0);
        assert_eq!(actual[16], 1);
        assert_eq!(actual[39], 1);
        assert_eq!(actual[40], 0);
    }
}
