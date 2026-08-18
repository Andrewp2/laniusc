use super::super::*;

/// Builds bind groups for call collection, argument matching, and claim validation.
pub(in crate::type_checker) fn create_call_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    hir_dispatch_args: &LaniusBuffer<u32>,
    token_capacity: u32,
    hir_capacity: u32,
    call_param_capacity: u32,
    call_arg_capacity: u32,
    claim_capacity: u32,
) -> Result<CallBindGroups> {
    let indirect = |spec| {
        ComputeOperation::indirect_spec(device, graph, resources, passes, spec, hir_dispatch_args)
    };
    let direct = |spec, workgroups| {
        ComputeOperation::direct_spec(device, graph, resources, passes, spec, workgroups)
    };
    let direct_name = |name, pass, workgroups| {
        ComputeOperation::direct(device, graph, resources, name, pass, workgroups)
    };
    let lookup_work = token_capacity
        .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
        .max(token_capacity.saturating_mul(2))
        .max(hir_capacity);
    let call_arg_slot_work = hir_capacity
        .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
        .max(token_capacity)
        .max(1);
    let semantic_work = token_capacity.max(hir_capacity).max(512);
    let call_generic_claim_index_dispatch_args =
        typed_buffer_from_resources(resources, "call_generic_claim_index_dispatch_args")?;
    let call_const_claim_index_dispatch_args =
        typed_buffer_from_resources(resources, "call_const_claim_index_dispatch_args")?;
    let call_required_generic_dispatch_args =
        typed_buffer_from_resources(resources, "call_required_generic_dispatch_args")?;
    let prefix_scan_spec = |spec| PrefixScanOperation::from_spec(device, passes, resources, spec);
    let required_generic_dispatch_params = uniform_from_val(
        device,
        "type_check.calls.required_generic_dispatch.params",
        &CountDispatchParams {
            capacity: u32::MAX,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let required_generic_dispatch = ComputeOperation::direct_with_uniform(
        device,
        graph,
        resources,
        compiler_graph::REQUIRED_GENERIC_DISPATCH_PASS,
        &passes.kernel("type_checker/count/dispatch_args"),
        &required_generic_dispatch_params,
        1,
    )?;
    let generic_claim_index = CallClaimIndexOperation::new(
        device,
        passes,
        CallClaimIndexBuild {
            kind: CallClaimKind::Generic,
            claim_capacity,
            dispatch_args: &call_generic_claim_index_dispatch_args,
            graph,
            resources,
        },
    )?;
    let const_claim_index = CallClaimIndexOperation::new(
        device,
        passes,
        CallClaimIndexBuild {
            kind: CallClaimKind::Const,
            claim_capacity: call_arg_capacity,
            dispatch_args: &call_const_claim_index_dispatch_args,
            graph,
            resources,
        },
    )?;

    let argument_matching = CallArgumentMatchingOperation::new(
        direct(CALLS_ARGUMENT_MATCH_INITIALIZE, semantic_work)?,
        direct(CALLS_ARGUMENT_MATCH_CONSUME, semantic_work)?,
    );
    let generic_claim_validation =
        CallGenericClaimValidationOperation::new(CallGenericClaimValidationBuild {
            claim_scan: prefix_scan_spec(compiler_graph::GENERIC_CLAIM_SCAN)?,
            emit_claims: direct(CALLS_GENERIC_CLAIM_EMIT, claim_capacity.saturating_add(1))?,
            validate_generic: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_GENERIC_CLAIM_VALIDATE,
                generic_claim_index.dispatch_args(),
            )?,
            generic_index: generic_claim_index,
            mark_required: indirect(CALLS_REQUIRED_GENERIC_MARK)?,
            required_scan: prefix_scan_spec(compiler_graph::REQUIRED_GENERIC_SCAN)?,
            required_dispatch: required_generic_dispatch,
            required_dispatch_params: required_generic_dispatch_params,
            validate_required: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_REQUIRED_GENERIC_VALIDATE,
                &call_required_generic_dispatch_args,
            )?,
            validate_const: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_CONST_CLAIM_VALIDATE,
                const_claim_index.dispatch_args(),
            )?,
            const_index: const_claim_index,
        });

    Ok(CallBindGroups {
        clear: direct(CALLS_CLEAR, lookup_work)?,
        clear_entrypoints: direct(CALLS_ENTRYPOINT_CLEAR, hir_capacity)?,
        return_refs: indirect(CALLS_RETURN_REFS)?,
        entrypoints: indirect(CALLS_ENTRYPOINT_PROJECT)?,
        functions: indirect(CALLS_FUNCTIONS)?,
        param_types: direct(CALLS_PARAM_TYPES, call_param_capacity)?,
        intrinsics: indirect(CALLS_INTRINSICS)?,
        clear_hir_call_args: direct(CALLS_ARGUMENT_CLEAR, call_arg_slot_work)?,
        pack_hir_call_args: direct(CALLS_ARGUMENT_PACK, hir_capacity)?,
        compact_hir_call_args: CompactionOperation::indirect(
            device,
            graph,
            resources,
            passes,
            CALL_ARGUMENT_COMPACTION,
            hir_dispatch_args,
        )?,
        call_param_segment_scan: prefix_scan_spec(compiler_graph::CALL_PARAM_ROW_SCAN)?,
        scatter_compact_hir_params: direct(CALLS_PARAM_SCATTER, call_param_capacity)?,
        resolve: indirect(CALLS_RESOLVE)?,
        backend_targets: direct_name(
            compiler_graph::CALLS_BACKEND_TARGETS_PASS,
            &passes.kernel("type_checker/calls/04_backend_targets"),
            token_capacity,
        )?,
        argument_matching,
        generic_claim_validation,
        contextual_result_requests: indirect(CALLS_CONTEXTUAL_RESULT_REQUESTS)?,
        clear_generic_claim_type_args: indirect(CALLS_GENERIC_CLAIM_CLEAR)?,
        apply_row_args: indirect(CALLS_APPLY_ARGUMENTS)?,
        infer_array_generics: ComputeOperation::direct_spec(
            device,
            graph,
            resources,
            passes,
            CALLS_INFER_ARRAY_GENERICS,
            semantic_work,
        )?,
        validate_array_results: direct(CALLS_ARRAY_STATE_CONSUME, hir_capacity)?,
        mark_array_args: indirect(CALLS_ARRAY_STATE_PUBLISH)?,
        project_result_instances: indirect(CALLS_RESULT_INSTANCE_PROJECT)?,
        erase_generic_params: ComputeOperation::direct_spec(
            device,
            graph,
            resources,
            passes,
            CALLS_GENERIC_PARAMS_ERASE,
            token_capacity
                .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
                .max(1),
        )?,
    })
}
