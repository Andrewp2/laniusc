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
    _passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    visibility: &DependencyVisibilityState,
    _hir_active_dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    visibility.project_calls_group.record(encoder)?;
    visibility.project_call_params_group.record(encoder)
}

pub(in crate::type_checker) fn record_dependency_call_params(
    _passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    visibility: &DependencyVisibilityState,
    _hir_active_dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    visibility.scatter_call_params_group.record(encoder)
}

/// Clears generic parameter cache rows before later call-resolution passes refill them.
pub(in crate::type_checker) fn record_call_erase_generic_params_with_passes(
    encoder: &mut wgpu::CommandEncoder,
    groups: &CallBindGroups,
) -> Result<()> {
    groups.erase_generic_params.record(encoder)
}
