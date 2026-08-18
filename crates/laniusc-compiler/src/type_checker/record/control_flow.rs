// src/type_checker/record/control_flow.rs

use super::*;
/// Records the resident enclosing-`if` depth passes from cached type-check state.
pub(in crate::type_checker) fn record_if_depth_passes_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    state: &ResidentTypeCheckWorkspace,
) -> Result<()> {
    let groups = &state.if_depth_bind_groups;
    groups.clear.record(encoder)?;
    groups.mark.record(encoder)?;
    groups.local.record(encoder)?;
    for step in &groups.hierarchy_up {
        step.operation.record(encoder)?;
    }
    for step in &groups.hierarchy_down {
        step.operation.record(encoder)?;
    }
    groups.apply.record(encoder)
}

/// Records enclosing-function context clear, mark, scan, and apply passes.
pub(in crate::type_checker) fn record_fn_context_bind_groups_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &FnContextBindGroups,
) -> Result<()> {
    groups.clear.record(encoder)?;
    groups.mark.record(encoder)?;
    groups.local.record(encoder)?;
    for step in &groups.hierarchy_up {
        step.operation.record(encoder)?;
    }
    for step in &groups.hierarchy_down {
        step.operation.record(encoder)?;
    }
    groups.apply.record(encoder)
}
