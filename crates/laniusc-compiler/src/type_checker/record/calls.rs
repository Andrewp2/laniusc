// src/type_checker/record/calls.rs

use super::*;

impl CallBindGroups {
    /// Records the primary call relation collection passes.
    pub(in crate::type_checker) fn record_primary(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        hir_active_dispatch_args: &wgpu::Buffer,
        dependency_params: Option<(
            &PassData,
            &wgpu::BindGroup,
            &PassData,
            &wgpu::BindGroup,
            &PassData,
            &wgpu::BindGroup,
        )>,
    ) -> Result<()> {
        self.clear.record(encoder)?;
        self.clear_entrypoints.record(encoder)?;
        self.return_refs.record(encoder)?;
        self.entrypoints.record(encoder)?;
        self.functions.record(encoder)?;
        self.param_types.record(encoder)?;
        if let Some((
            project_calls,
            project_calls_group,
            project_params,
            project_params_group,
            _,
            _,
        )) = dependency_params
        {
            record_compute_indirect(
                encoder,
                project_calls,
                project_calls_group,
                "type_check.dependencies.project_calls",
                hir_active_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                project_params,
                project_params_group,
                "type_check.dependencies.project_call_params",
                hir_active_dispatch_args,
            )?;
        }
        self.call_param_segment_scan.record(encoder)?;
        self.scatter_compact_hir_params.record(encoder)?;
        if let Some((_, _, _, _, scatter_params, scatter_group)) = dependency_params {
            record_compute_indirect(
                encoder,
                scatter_params,
                scatter_group,
                "type_check.dependencies.scatter_call_params",
                hir_active_dispatch_args,
            )?;
        }
        self.intrinsics.record(encoder)?;
        self.clear_hir_call_args.record(encoder)?;
        self.pack_hir_call_args.record(encoder)?;
        self.mark_compact_hir_call_args.record(encoder)?;
        self.compact_hir_call_arg_scan.record(encoder)?;
        self.scatter_compact_hir_call_args.record(encoder)
    }
}

/// Clears generic parameter cache rows before later call-resolution passes refill them.
pub(in crate::type_checker) fn record_call_erase_generic_params_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.kernel("type_checker/calls/04_erase_generic_params"),
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}
