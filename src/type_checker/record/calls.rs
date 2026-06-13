// src/type_checker/record/calls.rs

use super::*;

pub(in crate::type_checker) fn record_call_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    hir_active_dispatch_args: &wgpu::Buffer,
    _token_hir_active_dispatch_args: &wgpu::Buffer,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    let call_arg_slot_work = n_work
        .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
        .max(token_capacity)
        .max(1);
    record_compute(
        encoder,
        &passes.calls_clear,
        &groups.clear,
        "type_check.calls.clear",
        lookup_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_return_refs,
        &groups.return_refs,
        "type_check.calls.return_refs",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_entrypoints,
        &groups.entrypoints,
        "type_check.calls.entrypoints",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_functions,
        &groups.functions,
        "type_check.calls.functions",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.calls_param_types,
        &groups.param_types,
        "type_check.calls.param_types",
        n_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_intrinsics,
        &groups.intrinsics,
        "type_check.calls.intrinsics",
        hir_active_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.calls_clear_hir_call_args,
        &groups.clear_hir_call_args,
        "type_check.calls.clear_hir_call_args",
        call_arg_slot_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_pack_hir_call_args,
        &groups.pack_hir_call_args,
        "type_check.calls.pack_hir_call_args",
        n_work,
    )
}

pub(in crate::type_checker) fn record_call_erase_generic_params_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.calls_erase_generic_params,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}
