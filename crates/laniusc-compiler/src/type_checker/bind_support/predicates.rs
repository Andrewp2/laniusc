use super::super::*;

/// Builds the reflected predicate schedule. Buffer ownership and shader
/// bindings come from the compiler graph; this function supplies only dynamic
/// capacities and the one operation-local dispatch uniform.
pub(in crate::type_checker) fn create_predicate_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
) -> Result<PredicateBindGroups> {
    let token_dispatch_args = typed_buffer_from_resources(resources, "token_active_dispatch_args")?;
    let hir_dispatch_args = typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
    let predicate_dispatch_args =
        typed_buffer_from_resources(resources, "predicate_hir_dispatch_args")?;
    let predicate_single_dispatch_args =
        typed_buffer_from_resources(resources, "predicate_single_dispatch_args")?;
    let obligation_dispatch_args =
        typed_buffer_from_resources(resources, "predicate_obligation_pair_dispatch_args")?;
    let indirect = |name, kernel, dispatch_args| {
        ComputeOperation::indirect(
            device,
            graph,
            resources,
            name,
            &passes.kernel(kernel),
            dispatch_args,
        )
    };

    let clear_syntax_tokens = indirect(
        compiler_graph::PREDICATES_CLEAR_SYNTAX_TOKENS_PASS,
        "type_checker/predicates/00a_clear_syntax_tokens",
        &token_dispatch_args,
    )?;
    let clear_bound_arg_facts = indirect(
        compiler_graph::PREDICATES_CLEAR_BOUND_ARG_FACTS_PASS,
        "type_checker/predicates/00_clear_bound_arg_facts",
        &hir_dispatch_args,
    )?;
    let collect_bound_arg_facts = indirect(
        compiler_graph::PREDICATES_COLLECT_BOUND_ARG_FACTS_PASS,
        "type_checker/predicates/00b_collect_bound_arg_facts",
        &predicate_dispatch_args,
    )?;
    let collect_method_contracts = indirect(
        compiler_graph::PREDICATES_COLLECT_METHOD_CONTRACTS_PASS,
        "type_checker/predicates/00c_collect_method_contracts",
        &predicate_dispatch_args,
    )?;
    let collect = indirect(
        compiler_graph::PREDICATES_COLLECT_PASS,
        "type_checker/predicates/01_collect",
        &predicate_dispatch_args,
    )?;
    let validate_bound_args = indirect(
        compiler_graph::PREDICATES_VALIDATE_BOUND_ARGS_PASS,
        "type_checker/predicates/01a_validate_bound_args",
        &predicate_dispatch_args,
    )?;
    let collect_impls = indirect(
        compiler_graph::PREDICATES_COLLECT_IMPLS_PASS,
        "type_checker/predicates/01_collect_impls",
        &predicate_dispatch_args,
    )?;

    let emit_method_validation_rows = indirect(
        compiler_graph::PREDICATES_EMIT_METHOD_VALIDATION_ROWS_PASS,
        "type_checker/predicates/01f_emit_method_validation_rows",
        &predicate_dispatch_args,
    )?;
    let emit_method_param_validation_rows = indirect(
        compiler_graph::PREDICATES_EMIT_METHOD_PARAM_VALIDATION_ROWS_PASS,
        "type_checker/predicates/01f1_emit_method_param_validation_rows",
        &predicate_dispatch_args,
    )?;
    let validate_method_type_arg_rows = indirect(
        compiler_graph::PREDICATES_VALIDATE_METHOD_TYPE_ARG_ROWS_PASS,
        "type_checker/predicates/01f2_validate_method_type_arg_rows",
        &predicate_dispatch_args,
    )?;
    let reduce_method_validation_errors = indirect(
        compiler_graph::PREDICATES_REDUCE_METHOD_VALIDATION_ERRORS_PASS,
        "type_checker/predicates/01g_reduce_method_validation_errors",
        &predicate_dispatch_args,
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
    let count_obligation_pairs = indirect(
        compiler_graph::PREDICATES_COUNT_OBLIGATION_PAIRS_PASS,
        "type_checker/predicates/02a_count_obligations",
        &predicate_dispatch_args,
    )?;
    let mut obligation_dispatch_resources = resources.clone();
    obligation_dispatch_resources.buffer("gParams", &obligation_pair_dispatch_params);
    let obligation_pair_dispatch = ComputeOperation::indirect(
        device,
        graph,
        &obligation_dispatch_resources,
        compiler_graph::PREDICATES_OBLIGATION_PAIR_DISPATCH_PASS,
        &passes.kernel("type_checker/count/dispatch_args"),
        &predicate_single_dispatch_args,
    )?;
    let obligation_pair_dispatch_clear = crate::gpu::operations::ClearBufferOperation::entire(
        graph,
        compiler_graph::PREDICATES_OBLIGATION_PAIR_DISPATCH_CLEAR_PASS,
        "predicate_obligation_pair_dispatch_args",
        &obligation_dispatch_args,
    )?;
    let validate_obligation_pairs = indirect(
        compiler_graph::PREDICATES_VALIDATE_OBLIGATION_PAIRS_PASS,
        "type_checker/predicates/02b_validate_obligations",
        &obligation_dispatch_args,
    )?;

    Ok(PredicateBindGroups {
        clear_syntax_tokens,
        clear_bound_arg_facts,
        collect_bound_arg_facts,
        collect_method_contracts,
        collect,
        validate_bound_args,
        collect_impls,
        emit_method_validation_rows,
        emit_method_param_validation_rows,
        validate_method_type_arg_rows,
        reduce_method_validation_errors,
        _obligation_pair_dispatch_params: obligation_pair_dispatch_params,
        count_obligation_pairs,
        obligation_pair_scan,
        obligation_pair_dispatch_clear,
        obligation_pair_dispatch,
        validate_obligation_pairs,
    })
}
