// src/type_checker/record/methods.rs

use super::*;

const METHOD_CALL_RESULT_RECEIVER_PASSES: usize = 8;

/// Clears token-indexed method declaration and call metadata.
pub(in crate::type_checker) fn record_method_clear_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_active_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_clear,
        &groups.clear,
        "type_check.methods.clear",
        token_active_dispatch_args,
    )
}

/// Records method declaration collection and receiver metadata binding after clearing.
pub(in crate::type_checker) fn record_method_declaration_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    method_token_dispatch_args: &wgpu::Buffer,
    method_compact_dispatch_args: &wgpu::Buffer,
    method_hir_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_collect,
        &groups.collect,
        "type_check.methods.collect",
        method_compact_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_attach_metadata,
        &groups.attach_metadata,
        "type_check.methods.attach_metadata",
        method_token_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.methods_bind_self_receivers,
        &groups.bind_self_receivers,
        "type_check.methods.bind_self_receivers",
        method_hir_dispatch_args,
    )
}

/// Records method key-table seeding, sorting, scattering, and validation.
pub(in crate::type_checker) fn record_method_key_table_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    method_token_dispatch_args: &wgpu::Buffer,
    method_radix_prefix_dispatch_args: &wgpu::Buffer,
    method_radix_bases_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_seed_key_order,
        &groups.keys.seed_key_order,
        "type_check.methods.seed_key_order",
        method_token_dispatch_args,
    )?;
    if let Some(sort_key_small) = &groups.keys.sort_key_small {
        record_compute_indirect(
            encoder,
            &passes.methods_sort_keys_small,
            sort_key_small,
            "type_check.methods.sort_keys_small",
            method_radix_bases_dispatch_args,
        )?;
    } else {
        for i in 0..groups.keys.sort_key_scatter.len() {
            record_compute_indirect(
                encoder,
                &passes.methods_sort_keys,
                &groups.keys.sort_key_histogram[i],
                "type_check.methods.sort_keys_histogram",
                method_token_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_prefix,
                &groups.keys.sort_key_bucket_prefix[i],
                "type_check.methods.sort_keys_bucket_prefix",
                method_radix_prefix_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_bases,
                &groups.keys.sort_key_bucket_bases[i],
                "type_check.methods.sort_keys_bucket_bases",
                method_radix_bases_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.methods_sort_keys_scatter,
                &groups.keys.sort_key_scatter[i],
                "type_check.methods.sort_keys_scatter",
                method_token_dispatch_args,
            )?;
        }
    }
    record_compute_indirect(
        encoder,
        &passes.methods_validate_keys,
        &groups.keys.validate_keys,
        "type_check.methods.validate_keys",
        method_token_dispatch_args,
    )?;
    Ok(())
}

/// Records method-call key marking and fixed-point-like table resolution passes.
pub(in crate::type_checker) fn record_method_call_resolution_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    method_token_dispatch_args: &wgpu::Buffer,
    method_token_hir_dispatch_args: &wgpu::Buffer,
    method_hir_dispatch_args: &wgpu::Buffer,
    groups: &MethodBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.methods_mark_call_keys,
        &groups.mark_call_keys,
        "type_check.methods.mark_call_keys",
        method_token_hir_dispatch_args,
    )?;
    for _ in 0..METHOD_CALL_RESULT_RECEIVER_PASSES {
        record_compute_indirect(
            encoder,
            &passes.methods_mark_call_return_keys,
            &groups.mark_call_return_keys,
            "type_check.methods.mark_call_return_keys",
            method_hir_dispatch_args,
        )?;
        record_compute_indirect(
            encoder,
            &passes.methods_resolve_table,
            &groups.resolve_table,
            "type_check.methods.resolve_table",
            method_token_dispatch_args,
        )?;
    }
    Ok(())
}
