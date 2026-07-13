use super::super::*;

/// Builds counted `u32` scan bind groups using the standard type-check passes.
pub(in crate::type_checker) fn create_counted_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    label: &'static str,
    scan_steps: &[NameScanStep],
    scan_count: &wgpu::Buffer,
    scan_input: &wgpu::Buffer,
    scan_output_prefix: &wgpu::Buffer,
    scan_total: &wgpu::Buffer,
    scan_local_prefix: &wgpu::Buffer,
    scan_block_sum: &wgpu::Buffer,
    scan_prefix_a: &wgpu::Buffer,
    scan_prefix_b: &wgpu::Buffer,
) -> Result<U32ScanBindGroups> {
    create_counted_u32_scan_bind_groups_from_passes(
        &passes.counted_scan_local,
        &passes.counted_scan_hierarchy_up,
        &passes.counted_scan_hierarchy_down,
        &passes.counted_scan_apply,
        device,
        label,
        scan_steps,
        scan_count,
        scan_input,
        scan_output_prefix,
        scan_total,
        scan_local_prefix,
        scan_block_sum,
        scan_prefix_a,
        scan_prefix_b,
    )
}

/// Builds counted `u32` scan bind groups from explicitly supplied passes.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_counted_u32_scan_bind_groups_from_passes(
    counted_scan_local: &PassData,
    counted_scan_hierarchy_up: &PassData,
    counted_scan_hierarchy_down: &PassData,
    counted_scan_apply: &PassData,
    device: &wgpu::Device,
    label: &'static str,
    scan_steps: &[NameScanStep],
    scan_count: &wgpu::Buffer,
    scan_input: &wgpu::Buffer,
    scan_output_prefix: &wgpu::Buffer,
    scan_total: &wgpu::Buffer,
    scan_local_prefix: &wgpu::Buffer,
    scan_block_sum: &wgpu::Buffer,
    scan_prefix_a: &wgpu::Buffer,
    scan_prefix_b: &wgpu::Buffer,
) -> Result<U32ScanBindGroups> {
    let local = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("{label}.counted_scan_local")),
        counted_scan_local,
        0,
        &[
            ("gScan", scan_steps[0].params.as_entire_binding()),
            ("scan_count", scan_count.as_entire_binding()),
            ("scan_input", scan_input.as_entire_binding()),
            ("scan_local_prefix", scan_local_prefix.as_entire_binding()),
            ("scan_block_sum", scan_block_sum.as_entire_binding()),
        ],
    )?;

    let n_items = (scan_local_prefix.size() / 4).min(u32::MAX as u64) as u32;
    let n_blocks = (scan_block_sum.size() / 4).min(u32::MAX as u64) as u32;
    let levels = crate::gpu::scan::hierarchical_scan_levels(n_blocks);

    let mut hierarchy_up = Vec::with_capacity(levels.len());
    for (index, level) in levels.iter().copied().enumerate() {
        let parent = levels.get(index + 1).copied();
        let params = uniform_from_val(
            device,
            &format!("{label}.counted_scan_hierarchy_up.{index}"),
            &CountedScanHierarchyParams {
                n_items,
                n_blocks,
                level_divisor: level.divisor,
                level_offset: level.offset,
                parent_divisor: parent.map_or(0, |parent| parent.divisor),
                parent_offset: parent.map_or(0, |parent| parent.offset),
            },
        );
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.counted_scan_hierarchy_up")),
            counted_scan_hierarchy_up,
            0,
            &[
                ("gHierarchy", params.as_entire_binding()),
                ("scan_count", scan_count.as_entire_binding()),
                ("scan_block_sum", scan_block_sum.as_entire_binding()),
                ("scan_block_prefix", scan_prefix_a.as_entire_binding()),
                ("scan_hierarchy", scan_prefix_b.as_entire_binding()),
            ],
        )?;
        hierarchy_up.push(ScanHierarchyStep {
            bind_group,
            work_items: level.count,
        });
    }

    let mut hierarchy_down = Vec::with_capacity(levels.len().saturating_sub(1));
    for child_index in (0..levels.len().saturating_sub(1)).rev() {
        let child = levels[child_index];
        let parent = levels[child_index + 1];
        let params = uniform_from_val(
            device,
            &format!("{label}.counted_scan_hierarchy_down.{child_index}"),
            &CountedScanHierarchyParams {
                n_items,
                n_blocks,
                level_divisor: child.divisor,
                level_offset: child.offset,
                parent_divisor: parent.divisor,
                parent_offset: parent.offset,
            },
        );
        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.counted_scan_hierarchy_down")),
            counted_scan_hierarchy_down,
            0,
            &[
                ("gHierarchy", params.as_entire_binding()),
                ("scan_count", scan_count.as_entire_binding()),
                ("scan_block_prefix", scan_prefix_a.as_entire_binding()),
                ("scan_hierarchy", scan_prefix_b.as_entire_binding()),
            ],
        )?;
        hierarchy_down.push(ScanHierarchyStep {
            bind_group,
            work_items: child.count,
        });
    }

    let apply = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("{label}.counted_scan_apply")),
        counted_scan_apply,
        0,
        &[
            ("gScan", scan_steps[0].params.as_entire_binding()),
            ("scan_count", scan_count.as_entire_binding()),
            ("scan_local_prefix", scan_local_prefix.as_entire_binding()),
            ("scan_block_prefix", scan_prefix_a.as_entire_binding()),
            ("scan_output_prefix", scan_output_prefix.as_entire_binding()),
            ("scan_total", scan_total.as_entire_binding()),
        ],
    )?;
    Ok(U32ScanBindGroups {
        local,
        hierarchy_up,
        hierarchy_down,
        apply,
    })
}

/// Creates the shared base parameter packet for hierarchical counted scans.
pub(in crate::type_checker) fn make_name_scan_steps(
    device: &wgpu::Device,
    base: NameScanParams,
) -> Vec<NameScanStep> {
    vec![NameScanStep {
        params: uniform_from_val(device, "type_check.names.scan.params", &base),
    }]
}
