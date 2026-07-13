// src/type_checker/record/control_flow.rs

use super::*;

/// Records the resident loop-depth passes from the cached type-check state.
pub(in crate::type_checker) fn record_loop_depth_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    state: &ResidentTypeCheckState,
) -> Result<()> {
    record_loop_depth_bind_groups_with_passes(
        passes,
        encoder,
        state.cache_key.token_capacity,
        &state.hir_active_dispatch_args,
        state.loop_n_blocks,
        &state.loop_bind_groups,
    )
}

/// Records enclosing-function context clear, mark, scan, and apply passes.
pub(in crate::type_checker) fn record_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
    n_blocks: u32,
    groups: &FnContextBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.fn_context_clear,
        &groups.clear,
        "type_check.fn_context.clear",
        token_capacity.max(n_blocks).max(1),
    )?;
    record_compute_indirect(
        encoder,
        &passes.fn_context_mark,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.fn_context_local,
        &groups.local,
        "type_check.fn_context.local",
        token_capacity.max(1),
    )?;
    for step in &groups.hierarchy_up {
        record_compute(
            encoder,
            &passes.fn_context_hierarchy_up,
            &step.bind_group,
            "type_check.fn_context.hierarchy_up",
            step.work_items,
        )?;
    }
    for step in &groups.hierarchy_down {
        record_compute(
            encoder,
            &passes.fn_context_hierarchy_down,
            &step.bind_group,
            "type_check.fn_context.hierarchy_down",
            step.work_items,
        )?;
    }
    record_compute(
        encoder,
        &passes.fn_context_apply,
        &groups.apply,
        "type_check.fn_context.apply",
        token_capacity.max(1),
    )
}

/// Records loop-depth clear, mark, scan, and apply passes.
pub(in crate::type_checker) fn record_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
    n_blocks: u32,
    groups: &LoopDepthBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.loop_depth_clear,
        &groups.clear,
        "type_check.loop_depth.clear",
        token_capacity.saturating_add(1),
    )?;
    record_compute_indirect(
        encoder,
        &passes.loop_depth_mark,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.loop_depth_local,
        &groups.local,
        "type_check.loop_depth.local",
        n_blocks.saturating_mul(256),
    )?;
    for step in &groups.hierarchy_up {
        record_compute(
            encoder,
            &passes.loop_depth_hierarchy_up,
            &step.bind_group,
            "type_check.loop_depth.hierarchy_up",
            step.work_items,
        )?;
    }
    for step in &groups.hierarchy_down {
        record_compute(
            encoder,
            &passes.loop_depth_hierarchy_down,
            &step.bind_group,
            "type_check.loop_depth.hierarchy_down",
            step.work_items,
        )?;
    }
    record_compute(
        encoder,
        &passes.loop_depth_apply,
        &groups.apply,
        "type_check.loop_depth.apply",
        token_capacity.max(1),
    )
}
