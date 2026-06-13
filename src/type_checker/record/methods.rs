// src/type_checker/record/methods.rs

use super::*;

pub(in crate::type_checker) fn record_method_declaration_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    token_active_dispatch_args: &wgpu::Buffer,
    hir_active_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.max(1);
    record_compute(
        encoder,
        &passes.methods_clear,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_collect,
        &groups.collect,
        "type_check.methods.collect",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_attach_metadata,
        &groups.attach_metadata,
        "type_check.methods.attach_metadata",
        token_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_bind_self_receivers,
        &groups.bind_self_receivers,
        "type_check.methods.bind_self_receivers",
        hir_active_dispatch_args,
    )
}

pub(in crate::type_checker) fn record_method_key_table_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_active_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_seed_key_order,
        &groups.keys.seed_key_order,
        "type_check.methods.seed_key_order",
        token_active_dispatch_args,
    )?;
    for i in 0..groups.keys.sort_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.methods_sort_keys,
            &groups.keys.sort_key_histogram[i],
            "type_check.methods.sort_keys_histogram",
            token_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.keys.sort_key_bucket_prefix[i],
            "type_check.methods.sort_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.keys.sort_key_bucket_bases[i],
            "type_check.methods.sort_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.methods_sort_keys_scatter,
            &groups.keys.sort_key_scatter[i],
            "type_check.methods.sort_keys_scatter",
            token_active_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.methods_validate_keys,
        &groups.keys.validate_keys,
        "type_check.methods.validate_keys",
        token_active_dispatch_args,
    )?;
    Ok(())
}

pub(in crate::type_checker) fn record_method_call_resolution_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_active_dispatch_args: &wgpu::Buffer,
    hir_active_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_mark_call_keys,
        &groups.mark_call_keys,
        "type_check.methods.mark_call_keys",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_mark_call_return_keys,
        &groups.mark_call_return_keys,
        "type_check.methods.mark_call_return_keys",
        hir_active_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_resolve_table,
        &groups.resolve_table,
        "type_check.methods.resolve_table",
        token_active_dispatch_args,
    )
}
