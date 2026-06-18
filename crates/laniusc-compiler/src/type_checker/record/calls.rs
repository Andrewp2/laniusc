// src/type_checker/record/calls.rs

use super::*;

/// Records the primary call relation collection passes.
pub(in crate::type_checker) fn record_call_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    token_active_dispatch_args: &wgpu::Buffer,
    hir_active_dispatch_args: &wgpu::Buffer,
    _token_hir_active_dispatch_args: &wgpu::Buffer,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity
        .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
        .max(token_capacity.saturating_mul(2))
        .max(n_work);
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
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        groups.call_param_segment_scan_n_blocks,
        token_active_dispatch_args,
        &groups.call_param_segment_scan,
        "type_check.calls.call_param_segment_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_scatter_compact_hir_params,
        &groups.scatter_compact_hir_params,
        "type_check.calls.scatter_compact_hir_params",
        hir_active_dispatch_args,
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
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_mark_compact_hir_call_args,
        &groups.mark_compact_hir_call_args,
        "type_check.calls.mark_compact_hir_call_args",
        hir_active_dispatch_args,
    )?;
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        groups.compact_hir_call_arg_scan_n_blocks,
        hir_active_dispatch_args,
        &groups.compact_hir_call_arg_scan,
        "type_check.calls.compact_hir_call_arg_scan",
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_scatter_compact_hir_call_args,
        &groups.scatter_compact_hir_call_args,
        "type_check.calls.scatter_compact_hir_call_args",
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
        &passes.calls_erase_generic_params,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}

/// Records logarithmic argument-to-parameter row matching passes.
pub(in crate::type_checker) fn record_call_arg_param_matching_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_work: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.calls_match_arg_params_init,
        &groups.match_arg_params_init,
        "type_check.calls.match_arg_params_init",
        n_work,
    )?;

    for step in 0..groups.match_arg_param_steps {
        let (copy_group, step_group) = if step % 2 == 0 {
            (
                &groups.match_arg_params_copy_main_to_tmp,
                &groups.match_arg_params_step_main_to_tmp,
            )
        } else {
            (
                &groups.match_arg_params_copy_tmp_to_main,
                &groups.match_arg_params_step_tmp_to_main,
            )
        };
        record_compute(
            encoder,
            &passes.calls_match_arg_params_copy,
            copy_group,
            "type_check.calls.match_arg_params_copy",
            n_work,
        )?;
        record_compute(
            encoder,
            &passes.calls_match_arg_params_step,
            step_group,
            "type_check.calls.match_arg_params_step",
            n_work,
        )?;
    }

    Ok(())
}

/// Matches argument rows to parameter rows, then collects row-argument metadata.
pub(in crate::type_checker) fn record_call_arg_matching_and_collect_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    n_work: u32,
    groups: &CallBindGroups,
    collect_label: &'static str,
) -> Result<()> {
    record_call_arg_param_matching_with_passes(passes, encoder, n_work, groups)?;
    record_compute(
        encoder,
        &passes.calls_collect_row_args,
        &groups.collect_row_args,
        collect_label,
        n_work,
    )
}

/// Sorts and validates generic and const-generic claims emitted by call rows.
pub(in crate::type_checker) fn record_call_generic_claim_validation_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    hir_active_dispatch_args: &wgpu::Buffer,
    groups: &CallBindGroups,
) -> Result<()> {
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        groups.generic_claim_scan_n_blocks,
        hir_active_dispatch_args,
        &groups.generic_claim_scan,
        "type_check.calls.generic_claim_scan",
    )?;
    record_compute(
        encoder,
        &passes.calls_emit_generic_claims,
        &groups.emit_generic_claims,
        "type_check.calls.emit_generic_claims",
        groups.generic_claim_capacity.saturating_add(1),
    )?;
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &groups.generic_claim_radix_dispatch,
        "type_check.calls.generic_claim_radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.sort_generic_claim_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.calls_sort_generic_claims,
            &groups.sort_generic_claim_histogram[i],
            "type_check.calls.sort_generic_claims_histogram",
            &groups.generic_claim_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_generic_claim_bucket_prefix[i],
            "type_check.calls.sort_generic_claims_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_generic_claim_bucket_bases[i],
            "type_check.calls.sort_generic_claims_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.calls_sort_generic_claims_scatter,
            &groups.sort_generic_claim_scatter[i],
            "type_check.calls.sort_generic_claims_scatter",
            &groups.generic_claim_radix_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.calls_validate_generic_claims,
        &groups.validate_generic_claims,
        "type_check.calls.validate_generic_claims",
        &groups.generic_claim_radix_dispatch_args,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_mark_required_generics,
        &groups.mark_required_generics,
        "type_check.calls.mark_required_generics",
        hir_active_dispatch_args,
    )?;
    record_counted_u32_scan_bind_groups_with_passes(
        passes,
        encoder,
        groups.required_generic_scan_n_blocks,
        hir_active_dispatch_args,
        &groups.required_generic_scan,
        "type_check.calls.required_generic_scan",
    )?;
    record_compute(
        encoder,
        &passes.count_dispatch_args,
        &groups.required_generic_dispatch,
        "type_check.calls.required_generic_dispatch_args",
        1,
    )?;
    record_compute_indirect(
        encoder,
        &passes.calls_validate_required_generics,
        &groups.validate_required_generics,
        "type_check.calls.validate_required_generics",
        &groups.required_generic_dispatch_args,
    )?;
    record_compute(
        encoder,
        &passes.names_radix_dispatch_args,
        &groups.const_claim_radix_dispatch,
        "type_check.calls.const_claim_radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.sort_const_claim_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.calls_sort_generic_claims,
            &groups.sort_const_claim_histogram[i],
            "type_check.calls.sort_const_claims_histogram",
            &groups.const_claim_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_const_claim_bucket_prefix[i],
            "type_check.calls.sort_const_claims_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_const_claim_bucket_bases[i],
            "type_check.calls.sort_const_claims_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.calls_sort_generic_claims_scatter,
            &groups.sort_const_claim_scatter[i],
            "type_check.calls.sort_const_claims_scatter",
            &groups.const_claim_radix_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.calls_validate_const_claims,
        &groups.validate_const_claims,
        "type_check.calls.validate_const_claims",
        &groups.const_claim_radix_dispatch_args,
    )
}
