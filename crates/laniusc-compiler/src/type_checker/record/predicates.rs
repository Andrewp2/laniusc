use super::*;

/// Records predicate method-contract and method-parameter key tables.
pub(in crate::type_checker) fn record_predicate_method_contract_keys_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    predicate_active_dispatch_args: &wgpu::Buffer,
    predicate_radix_prefix_dispatch_args: &wgpu::Buffer,
    predicate_radix_bases_dispatch_args: &wgpu::Buffer,
    groups: &PredicateBindGroups,
) -> Result<()> {
    if let Some(sort_keys_small) = &groups.sort_method_contract_keys_small {
        record_compute_indirect(
            encoder,
            passes
                .predicates_sort_keys_small
                .as_ref()
                .expect("small predicate bind group requires its pass"),
            sort_keys_small,
            "type_check.predicates.sort_method_contract_keys_small",
            predicate_active_dispatch_args,
        )?;
    } else {
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
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_prefix,
                &groups.sort_method_contract_key_bucket_prefix[i],
                "type_check.predicates.sort_method_contract_keys_bucket_prefix",
                predicate_radix_prefix_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_bases,
                &groups.sort_method_contract_key_bucket_bases[i],
                "type_check.predicates.sort_method_contract_keys_bucket_bases",
                predicate_radix_bases_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.predicates_sort_keys_scatter,
                &groups.sort_method_contract_key_scatter[i],
                "type_check.predicates.sort_method_contract_keys_scatter",
                predicate_active_dispatch_args,
            )?;
        }
    }
    if let Some(sort_keys_small) = &groups.sort_method_param_keys_small {
        record_compute_indirect(
            encoder,
            passes
                .predicates_sort_keys_small
                .as_ref()
                .expect("small predicate bind group requires its pass"),
            sort_keys_small,
            "type_check.predicates.sort_method_param_keys_small",
            predicate_active_dispatch_args,
        )?;
    } else {
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
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_prefix,
                &groups.sort_method_param_key_bucket_prefix[i],
                "type_check.predicates.sort_method_param_keys_bucket_prefix",
                predicate_radix_prefix_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_bases,
                &groups.sort_method_param_key_bucket_bases[i],
                "type_check.predicates.sort_method_param_keys_bucket_bases",
                predicate_radix_bases_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.predicates_sort_keys_scatter,
                &groups.sort_method_param_key_scatter[i],
                "type_check.predicates.sort_method_param_keys_scatter",
                predicate_active_dispatch_args,
            )?;
        }
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
    predicate_radix_prefix_dispatch_args: &wgpu::Buffer,
    predicate_radix_bases_dispatch_args: &wgpu::Buffer,
    groups: &PredicateBindGroups,
) -> Result<()> {
    if let Some(sort_keys_small) = &groups.sort_owner_keys_small {
        record_compute_indirect(
            encoder,
            passes
                .predicates_sort_keys_small
                .as_ref()
                .expect("small predicate bind group requires its pass"),
            sort_keys_small,
            "type_check.predicates.sort_owner_keys_small",
            predicate_active_dispatch_args,
        )?;
    } else {
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
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_prefix,
                &groups.sort_owner_key_bucket_prefix[i],
                "type_check.predicates.sort_owner_keys_bucket_prefix",
                predicate_radix_prefix_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_bases,
                &groups.sort_owner_key_bucket_bases[i],
                "type_check.predicates.sort_owner_keys_bucket_bases",
                predicate_radix_bases_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.predicates_sort_keys_scatter,
                &groups.sort_owner_key_scatter[i],
                "type_check.predicates.sort_owner_keys_scatter",
                predicate_active_dispatch_args,
            )?;
        }
    }

    if let Some(sort_keys_small) = &groups.sort_impl_keys_small {
        record_compute_indirect(
            encoder,
            passes
                .predicates_sort_keys_small
                .as_ref()
                .expect("small predicate bind group requires its pass"),
            sort_keys_small,
            "type_check.predicates.sort_impl_keys_small",
            predicate_active_dispatch_args,
        )?;
    } else {
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
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_prefix,
                &groups.sort_impl_key_bucket_prefix[i],
                "type_check.predicates.sort_impl_keys_bucket_prefix",
                predicate_radix_prefix_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.names_radix_bucket_bases,
                &groups.sort_impl_key_bucket_bases[i],
                "type_check.predicates.sort_impl_keys_bucket_bases",
                predicate_radix_bases_dispatch_args,
            )?;
            record_compute_indirect(
                encoder,
                &passes.predicates_sort_keys_scatter,
                &groups.sort_impl_key_scatter[i],
                "type_check.predicates.sort_impl_keys_scatter",
                predicate_active_dispatch_args,
            )?;
        }
    }

    Ok(())
}
