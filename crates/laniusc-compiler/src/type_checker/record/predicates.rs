use super::*;

/// Records predicate method-contract and method-parameter key tables.
pub(in crate::type_checker) fn record_predicate_method_contract_keys_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    predicate_active_dispatch_args: &wgpu::Buffer,
    groups: &PredicateBindGroups,
) -> Result<()> {
    groups.method_contract_keys.record(passes, encoder)?;
    groups.method_param_keys.record(passes, encoder)?;
    record_compute_indirect(
        encoder,
        &passes.kernel("type_checker/predicates/01e_build_method_owner_ranges"),
        &groups.build_method_contract_owner_ranges,
        "type_check.predicates.build_method_contract_owner_ranges",
        predicate_active_dispatch_args,
    )
}

/// Records predicate owner and implementation key tables.
pub(in crate::type_checker) fn record_predicate_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    groups: &PredicateBindGroups,
) -> Result<()> {
    groups.owner_keys.record(passes, encoder)?;
    groups.impl_keys.record(passes, encoder)
}
