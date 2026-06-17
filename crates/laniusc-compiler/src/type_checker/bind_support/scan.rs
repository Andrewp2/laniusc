use super::super::*;

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
        &passes.counted_scan_blocks,
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

#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_counted_u32_scan_bind_groups_from_passes(
    counted_scan_local: &PassData,
    counted_scan_blocks: &PassData,
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

    let mut blocks = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            scan_prefix_a
        } else {
            scan_prefix_b
        };
        let prefix_out = if step.write_to_a {
            scan_prefix_a
        } else {
            scan_prefix_b
        };
        blocks.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.counted_scan_blocks")),
            counted_scan_blocks,
            0,
            &[
                ("gScan", step.params.as_entire_binding()),
                ("scan_count", scan_count.as_entire_binding()),
                ("scan_block_sum", scan_block_sum.as_entire_binding()),
                ("scan_block_prefix_in", prefix_in.as_entire_binding()),
                ("scan_block_prefix_out", prefix_out.as_entire_binding()),
            ],
        )?);
    }

    let final_prefix = if scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        scan_prefix_a
    } else {
        scan_prefix_b
    };
    let apply = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("{label}.counted_scan_apply")),
        counted_scan_apply,
        0,
        &[
            ("gScan", scan_steps[0].params.as_entire_binding()),
            ("scan_count", scan_count.as_entire_binding()),
            ("scan_local_prefix", scan_local_prefix.as_entire_binding()),
            ("scan_block_prefix", final_prefix.as_entire_binding()),
            ("scan_output_prefix", scan_output_prefix.as_entire_binding()),
            ("scan_total", scan_total.as_entire_binding()),
        ],
    )?;
    Ok(U32ScanBindGroups {
        local,
        blocks,
        apply,
    })
}

pub(in crate::type_checker) fn make_loop_depth_scan_steps(
    device: &wgpu::Device,
    base: LoopDepthParams,
) -> Vec<LoopDepthScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(
        base.n_blocks,
        crate::gpu::scan::ScanFinalize::Always(base.n_blocks),
    )
    .into_iter()
    .map(|plan| {
        let label = if plan.scan_step == 0 {
            "type_check.loop_depth.scan.params.init"
        } else if plan.scan_step == base.n_blocks {
            "type_check.loop_depth.scan.params.finalize"
        } else {
            "type_check.loop_depth.scan.params.step"
        };
        LoopDepthScanStep {
            params: uniform_from_val(
                device,
                label,
                &LoopDepthParams {
                    scan_step: plan.scan_step,
                    ..base
                },
            ),
            read_from_a: plan.read_from_a,
            write_to_a: plan.write_to_a,
        }
    })
    .collect()
}

pub(in crate::type_checker) fn make_name_scan_steps(
    device: &wgpu::Device,
    base: NameScanParams,
) -> Vec<NameScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(base.n_blocks, crate::gpu::scan::ScanFinalize::None)
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "type_check.names.scan.params.init"
            } else {
                "type_check.names.scan.params.step"
            };
            NameScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &NameScanParams {
                        scan_step: plan.scan_step,
                        ..base
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(in crate::type_checker) fn make_fn_context_scan_steps(
    device: &wgpu::Device,
    base: FnContextParams,
) -> Vec<FnContextScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(
        base.n_blocks,
        crate::gpu::scan::ScanFinalize::Always(base.n_blocks),
    )
    .into_iter()
    .map(|plan| {
        let label = if plan.scan_step == 0 {
            "type_check.fn_context.scan.params.init"
        } else if plan.scan_step == base.n_blocks {
            "type_check.fn_context.scan.params.finalize"
        } else {
            "type_check.fn_context.scan.params.step"
        };
        FnContextScanStep {
            params: uniform_from_val(
                device,
                label,
                &FnContextParams {
                    scan_step: plan.scan_step,
                    ..base
                },
            ),
            read_from_a: plan.read_from_a,
            write_to_a: plan.write_to_a,
        }
    })
    .collect()
}
