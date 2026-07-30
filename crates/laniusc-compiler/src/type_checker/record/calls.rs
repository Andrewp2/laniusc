// src/type_checker/record/calls.rs

use super::*;

impl CallBindGroups {
    pub(in crate::type_checker) fn record_primary_prefix(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.clear.record(encoder)?;
        self.clear_entrypoints.record(encoder)?;
        self.return_refs.record(encoder)?;
        self.entrypoints.record(encoder)?;
        self.functions.record(encoder)?;
        self.param_types.record(encoder)
    }

    pub(in crate::type_checker) fn record_primary_scan(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.call_param_segment_scan.record(encoder)?;
        self.scatter_compact_hir_params.record(encoder)
    }

    pub(in crate::type_checker) fn record_primary_suffix(
        &self,
        encoder: &mut wgpu::CommandEncoder,
    ) -> Result<()> {
        self.intrinsics.record(encoder)?;
        self.clear_hir_call_args.record(encoder)?;
        self.pack_hir_call_args.record(encoder)?;
        self.compact_hir_call_args.record(encoder)
    }
}

pub(in crate::type_checker) fn record_dependency_call_counts(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    visibility: &DependencyVisibilityState,
    hir_active_dispatch_args: &wgpu::Buffer,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/07_project_calls"),
        &visibility.project_calls_group,
        "type_check.dependencies.project_calls",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/07a_project_call_params"),
        &visibility.project_call_params_group,
        "type_check.dependencies.project_call_params",
        hir_active_dispatch_args,
    )
}

pub(in crate::type_checker) fn record_dependency_call_params(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    visibility: &DependencyVisibilityState,
    hir_active_dispatch_args: &wgpu::Buffer,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/dependencies/07b_scatter_call_params"),
        &visibility.scatter_call_params_group,
        "type_check.dependencies.scatter_call_params",
        hir_active_dispatch_args,
    )
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
