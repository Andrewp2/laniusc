use super::super::*;

/// Builds method declaration and method-call resolution bind groups.
pub(in crate::type_checker) fn create_method_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    keys: MethodIndex,
    token_args: &LaniusBuffer<u32>,
    method_token_args: &LaniusBuffer<u32>,
    method_compact_args: &LaniusBuffer<u32>,
    method_hir_args: &LaniusBuffer<u32>,
    method_token_hir_args: &LaniusBuffer<u32>,
    lookup_args: &LaniusBuffer<u32>,
) -> Result<MethodBindGroups> {
    let indirect =
        |spec, args| ComputeOperation::indirect_spec(device, graph, resources, passes, spec, args);
    let lookup = |spec, offset| {
        ComputeOperation::indirect_spec_at(device, graph, resources, passes, spec, lookup_args, offset)
    };
    let single = |spec| ComputeOperation::direct_spec(device, graph, resources, passes, spec, 1);
    // The ordinary operations are built for the direct transaction and also
    // record its inference invocations; the lookup sweeps have their own.
    Ok(MethodBindGroups {
        clear: indirect(METHODS_CLEAR, token_args)?,
        collect: indirect(METHODS_COLLECT, method_compact_args)?,
        attach_metadata: indirect(METHODS_ATTACH_METADATA, method_compact_args)?,
        bind_self_receivers: indirect(METHODS_BIND_SELF_RECEIVERS, method_hir_args)?,
        keys,
        mark_call_keys: indirect(METHODS_MARK_CALL_KEYS, method_token_hir_args)?,
        mark_call_return_keys: indirect(METHODS_MARK_CALL_RETURN_KEYS_DIRECT, method_hir_args)?,
        reset_candidates: indirect(METHODS_RESET_CANDIDATES_DIRECT, method_token_args)?,
        resolve_table: indirect(METHODS_RESOLVE_TABLE_DIRECT, method_token_args)?,
        offer_bound_members: indirect(METHODS_OFFER_BOUND_MEMBERS_DIRECT, method_token_args)?,
        finalize_candidates: indirect(METHODS_FINALIZE_CANDIDATES_DIRECT, method_token_args)?,
        resolve: indirect(METHODS_RESOLVE, method_token_hir_args)?,
        lookup: MethodLookupSweeps {
            arm: single(METHODS_ARM_LOOKUP_SWEEPS)?,
            mark_call_keys: lookup(METHODS_MARK_CALL_KEYS_LOOKUP, METHOD_LOOKUP_TOKEN_HIR_ARGS_OFFSET)?,
            mark_call_return_keys: lookup(METHODS_MARK_CALL_RETURN_KEYS, METHOD_LOOKUP_HIR_ARGS_OFFSET)?,
            reset_candidates: lookup(METHODS_RESET_CANDIDATES, METHOD_LOOKUP_TOKEN_ARGS_OFFSET)?,
            resolve_table: lookup(METHODS_RESOLVE_TABLE, METHOD_LOOKUP_TOKEN_ARGS_OFFSET)?,
            offer_bound_members: lookup(METHODS_OFFER_BOUND_MEMBERS, METHOD_LOOKUP_TOKEN_ARGS_OFFSET)?,
            finalize_candidates: lookup(METHODS_FINALIZE_CANDIDATES, METHOD_LOOKUP_TOKEN_ARGS_OFFSET)?,
            gate: single(METHODS_GATE_LOOKUP_SWEEP)?,
        },
    })
}
