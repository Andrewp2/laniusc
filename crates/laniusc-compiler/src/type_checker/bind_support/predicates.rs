use super::super::*;

/// Builds the reflected predicate schedule. Buffer ownership and shader
/// bindings come from the compiler graph; this function supplies only dynamic
/// capacities and the one operation-local dispatch uniform.
pub(in crate::type_checker) fn create_predicate_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    token_capacity: u32,
    predicate_capacity: u32,
    predicate_blocks: u32,
    resources: &ResourceMap<'_>,
) -> Result<PredicateBindGroups> {
    let reflected = |label, kernel| {
        reflected_bind_group_from_resources(device, label, &passes.kernel(kernel), resources)
    };

    let clear_syntax_tokens = reflected(
        "type_check_resident_predicates_clear_syntax_tokens",
        "type_checker/predicates/00a_clear_syntax_tokens",
    )?;
    let clear_bound_arg_facts = reflected(
        "type_check_resident_predicates_clear_bound_arg_facts",
        "type_checker/predicates/00_clear_bound_arg_facts",
    )?;
    let collect_bound_arg_facts = reflected(
        "type_check_resident_predicates_collect_bound_arg_facts",
        "type_checker/predicates/00b_collect_bound_arg_facts",
    )?;
    let collect_method_contracts = reflected(
        "type_check_resident_predicates_collect_method_contracts",
        "type_checker/predicates/00c_collect_method_contracts",
    )?;
    let collect = reflected(
        "type_check_resident_predicates_collect",
        "type_checker/predicates/01_collect",
    )?;
    let validate_bound_args = reflected(
        "type_check_resident_predicates_validate_bound_args",
        "type_checker/predicates/01a_validate_bound_args",
    )?;
    let collect_impls = reflected(
        "type_check_resident_predicates_collect_impls",
        "type_checker/predicates/01_collect_impls",
    )?;

    let build_keys = |kind| {
        PredicateKeyPipeline::new(
            device,
            passes,
            PredicateKeyBuild {
                kind,
                token_capacity,
                predicate_capacity,
                predicate_blocks,
                resources,
            },
        )
    };
    let method_contract_keys = build_keys(PredicateKeyKind::MethodContract)?;
    let method_param_keys = build_keys(PredicateKeyKind::MethodParam)?;
    let owner_keys = build_keys(PredicateKeyKind::Owner)?;
    let impl_keys = build_keys(PredicateKeyKind::Impl)?;

    let build_method_contract_owner_ranges = reflected(
        "type_check_resident_predicates_build_method_contract_owner_ranges",
        "type_checker/predicates/01e_build_method_owner_ranges",
    )?;
    let emit_method_validation_rows = reflected(
        "type_check_resident_predicates_emit_method_validation_rows",
        "type_checker/predicates/01f_emit_method_validation_rows",
    )?;
    let emit_method_param_validation_rows = reflected(
        "type_check_resident_predicates_emit_method_param_validation_rows",
        "type_checker/predicates/01f1_emit_method_param_validation_rows",
    )?;
    let validate_method_type_arg_rows = reflected(
        "type_check_resident_predicates_validate_method_type_arg_rows",
        "type_checker/predicates/01f2_validate_method_type_arg_rows",
    )?;
    let reduce_method_validation_errors = reflected(
        "type_check_resident_predicates_reduce_method_validation_errors",
        "type_checker/predicates/01g_reduce_method_validation_errors",
    )?;

    let obligation_pair_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        resources,
        compiler_graph::PREDICATES_OBLIGATION_PAIR_SCAN,
    )?;
    let obligation_pair_dispatch_params = uniform_from_val(
        device,
        "type_check.predicates.obligation_pair_dispatch.params",
        &CountDispatchParams {
            capacity: u32::MAX,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let count_obligation_pairs = reflected(
        "type_check_resident_predicates_count_obligation_pairs",
        "type_checker/predicates/02a_count_obligations",
    )?;
    let pair_total = resources["predicate_obligation_pair_total"].clone();
    let pair_dispatch_args = resources["predicate_obligation_pair_dispatch_args"].clone();
    let obligation_pair_dispatch = reflected_bind_group_with_overrides(
        device,
        "type_check.predicates.obligation_pair_dispatch",
        &passes.kernel("type_checker/count/dispatch_args"),
        resources,
        &[
            (
                "gParams",
                obligation_pair_dispatch_params.as_entire_binding(),
            ),
            ("count_in", pair_total),
            ("dispatch_args", pair_dispatch_args),
        ],
    )?;
    let validate_obligation_pairs = reflected(
        "type_check_resident_predicates_validate_obligation_pairs",
        "type_checker/predicates/02b_validate_obligations",
    )?;

    Ok(PredicateBindGroups {
        clear_syntax_tokens,
        clear_bound_arg_facts,
        collect_bound_arg_facts,
        collect_method_contracts,
        collect,
        validate_bound_args,
        collect_impls,
        method_contract_keys,
        method_param_keys,
        build_method_contract_owner_ranges,
        emit_method_validation_rows,
        emit_method_param_validation_rows,
        validate_method_type_arg_rows,
        reduce_method_validation_errors,
        owner_keys,
        impl_keys,
        _obligation_pair_dispatch_params: obligation_pair_dispatch_params,
        count_obligation_pairs,
        obligation_pair_scan,
        obligation_pair_dispatch,
        obligation_pair_dispatch_args: typed_alias_storage_u32(
            &typed_buffer_from_resources::<u32>(
                resources,
                "predicate_obligation_pair_dispatch_args",
            )?,
            3,
        ),
        validate_obligation_pairs,
    })
}
