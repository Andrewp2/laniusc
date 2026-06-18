use super::*;

/// Records predicate method-contract and method-parameter key tables.
pub(in crate::type_checker) fn record_predicate_method_contract_keys_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    predicate_active_dispatch_args: &wgpu::Buffer,
    groups: &PredicateBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.predicates_seed_key_order,
        &groups.seed_method_contract_key_order,
        "type_check.predicates.seed_method_contract_key_order",
        predicate_active_dispatch_args,
    )?;
    for i in 0..groups.sort_method_contract_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys,
            &groups.sort_method_contract_key_histogram[i],
            "type_check.predicates.sort_method_contract_keys_histogram",
            predicate_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_method_contract_key_bucket_prefix[i],
            "type_check.predicates.sort_method_contract_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_method_contract_key_bucket_bases[i],
            "type_check.predicates.sort_method_contract_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys_scatter,
            &groups.sort_method_contract_key_scatter[i],
            "type_check.predicates.sort_method_contract_keys_scatter",
            predicate_active_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.predicates_seed_key_order,
        &groups.seed_method_param_key_order,
        "type_check.predicates.seed_method_param_key_order",
        predicate_active_dispatch_args,
    )?;
    for i in 0..groups.sort_method_param_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys,
            &groups.sort_method_param_key_histogram[i],
            "type_check.predicates.sort_method_param_keys_histogram",
            predicate_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_method_param_key_bucket_prefix[i],
            "type_check.predicates.sort_method_param_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_method_param_key_bucket_bases[i],
            "type_check.predicates.sort_method_param_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys_scatter,
            &groups.sort_method_param_key_scatter[i],
            "type_check.predicates.sort_method_param_keys_scatter",
            predicate_active_dispatch_args,
        )?;
    }
    record_compute_indirect(
        encoder,
        &passes.predicates_build_method_owner_ranges,
        &groups.build_method_contract_owner_ranges,
        "type_check.predicates.build_method_contract_owner_ranges",
        predicate_active_dispatch_args,
    )?;

    Ok(())
}

/// Records predicate owner, impl, obligation, and validation passes.
pub(in crate::type_checker) fn record_predicate_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    predicate_active_dispatch_args: &wgpu::Buffer,
    groups: &PredicateBindGroups,
) -> Result<()> {
    record_compute_indirect(
        encoder,
        &passes.predicates_seed_key_order,
        &groups.seed_owner_key_order,
        "type_check.predicates.seed_owner_key_order",
        predicate_active_dispatch_args,
    )?;
    for i in 0..groups.sort_owner_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys,
            &groups.sort_owner_key_histogram[i],
            "type_check.predicates.sort_owner_keys_histogram",
            predicate_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_owner_key_bucket_prefix[i],
            "type_check.predicates.sort_owner_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_owner_key_bucket_bases[i],
            "type_check.predicates.sort_owner_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys_scatter,
            &groups.sort_owner_key_scatter[i],
            "type_check.predicates.sort_owner_keys_scatter",
            predicate_active_dispatch_args,
        )?;
    }

    record_compute_indirect(
        encoder,
        &passes.predicates_seed_key_order,
        &groups.seed_impl_key_order,
        "type_check.predicates.seed_impl_key_order",
        predicate_active_dispatch_args,
    )?;
    for i in 0..groups.sort_impl_key_scatter.len() {
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys,
            &groups.sort_impl_key_histogram[i],
            "type_check.predicates.sort_impl_keys_histogram",
            predicate_active_dispatch_args,
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_prefix,
            &groups.sort_impl_key_bucket_prefix[i],
            "type_check.predicates.sort_impl_keys_bucket_prefix",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            &passes.names_radix_bucket_bases,
            &groups.sort_impl_key_bucket_bases[i],
            "type_check.predicates.sort_impl_keys_bucket_bases",
            256,
        )?;
        record_compute_indirect(
            encoder,
            &passes.predicates_sort_keys_scatter,
            &groups.sort_impl_key_scatter[i],
            "type_check.predicates.sort_impl_keys_scatter",
            predicate_active_dispatch_args,
        )?;
    }

    Ok(())
}
