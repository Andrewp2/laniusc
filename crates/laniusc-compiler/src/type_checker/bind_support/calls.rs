use super::{super::*, common::reflected_bind_group_from_resources};

/// Builds bind groups for call collection, argument matching, and claim validation.
pub(in crate::type_checker) fn create_call_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    hir_dispatch_args: &wgpu::Buffer,
    token_capacity: u32,
    hir_capacity: u32,
    call_param_capacity: u32,
    claim_capacity: u32,
    call_generic_claim_radix_dispatch_args: &LaniusBuffer<u32>,
    call_const_claim_radix_dispatch_args: &LaniusBuffer<u32>,
    call_required_generic_dispatch_args: &LaniusBuffer<u32>,
) -> Result<CallBindGroups> {
    let indirect = |spec, pass| {
        ComputeOperation::indirect_spec(device, graph, resources, spec, pass, hir_dispatch_args)
    };
    let direct = |spec, pass, workgroups| {
        ComputeOperation::direct_spec(device, graph, resources, spec, pass, workgroups)
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
    let prefix_scan_spec =
        |spec| PrefixScanOperation::from_spec(device, passes.into(), resources, spec);
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
    let required_generic_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.calls.required_generic_dispatch"),
        &passes.count_dispatch_args,
        0,
        &[
            (
                "gParams",
                required_generic_dispatch_params.as_entire_binding(),
            ),
            (
                "count_in",
                resources["call_required_generic_count_out"].clone(),
            ),
            (
                "dispatch_args",
                call_required_generic_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;
    let generic_claim_keys = CallClaimKeyPipeline::new(
        device,
        passes,
        CallClaimKeyBuild {
            kind: CallClaimKind::Generic,
            token_capacity,
            claim_capacity,
            dispatch_args: call_generic_claim_radix_dispatch_args,
            resources,
        },
    )?;
    let const_claim_keys = CallClaimKeyPipeline::new(
        device,
        passes,
        CallClaimKeyBuild {
            kind: CallClaimKind::Const,
            token_capacity,
            claim_capacity,
            dispatch_args: call_const_claim_radix_dispatch_args,
            resources,
        },
    )?;

    let argument_matching = CallArgumentMatchingOperation::new(
        direct(
            CALLS_ARGUMENT_MATCH_INITIALIZE,
            &passes.calls_match_arg_params_init,
            semantic_work,
        )?,
        direct(
            CALLS_ARGUMENT_MATCH_CONSUME,
            &passes.calls_collect_row_args,
            semantic_work,
        )?,
    );
    let generic_claim_validation =
        CallGenericClaimValidationOperation::new(CallGenericClaimValidationBuild {
            required_dispatch_pass: passes.count_dispatch_args.clone(),
            claim_scan: prefix_scan_spec(compiler_graph::GENERIC_CLAIM_SCAN)?,
            emit_claims: direct(
                CALLS_GENERIC_CLAIM_EMIT,
                &passes.calls_emit_generic_claims,
                claim_capacity.saturating_add(1),
            )?,
            validate_generic: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                CALLS_GENERIC_CLAIM_VALIDATE,
                &passes.calls_validate_generic_claims,
                generic_claim_keys.dispatch_args(),
            )?,
            generic_keys: generic_claim_keys,
            mark_required: indirect(
                CALLS_REQUIRED_GENERIC_MARK,
                &passes.calls_mark_required_generics,
            )?,
            required_scan: prefix_scan_spec(compiler_graph::REQUIRED_GENERIC_SCAN)?,
            required_dispatch: required_generic_dispatch,
            required_dispatch_params: required_generic_dispatch_params,
            validate_required: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                CALLS_REQUIRED_GENERIC_VALIDATE,
                &passes.calls_validate_required_generics,
                call_required_generic_dispatch_args,
            )?,
            validate_const: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                CALLS_CONST_CLAIM_VALIDATE,
                &passes.calls_validate_const_claims,
                const_claim_keys.dispatch_args(),
            )?,
            const_keys: const_claim_keys,
        });

    Ok(CallBindGroups {
        clear: direct(CALLS_CLEAR, &passes.calls_clear, lookup_work)?,
        clear_entrypoints: direct(
            CALLS_ENTRYPOINT_CLEAR,
            &passes.calls_clear_entrypoints,
            hir_capacity,
        )?,
        return_refs: indirect(CALLS_RETURN_REFS, &passes.calls_return_refs)?,
        entrypoints: indirect(CALLS_ENTRYPOINT_PROJECT, &passes.calls_entrypoints)?,
        functions: indirect(CALLS_FUNCTIONS, &passes.calls_functions)?,
        param_types: direct(
            CALLS_PARAM_TYPES,
            &passes.calls_param_types,
            call_param_capacity,
        )?,
        intrinsics: indirect(CALLS_INTRINSICS, &passes.calls_intrinsics)?,
        clear_hir_call_args: direct(
            CALLS_ARGUMENT_CLEAR,
            &passes.calls_clear_hir_call_args,
            call_arg_slot_work,
        )?,
        pack_hir_call_args: direct(
            CALLS_ARGUMENT_PACK,
            &passes.calls_pack_hir_call_args,
            hir_capacity,
        )?,
        mark_compact_hir_call_args: indirect(
            CALLS_ARGUMENT_MARK,
            &passes.calls_mark_compact_hir_call_args,
        )?,
        compact_hir_call_arg_scan: prefix_scan_spec(compiler_graph::CALL_ARG_ROW_SCAN)?,
        scatter_compact_hir_call_args: indirect(
            CALLS_ARGUMENT_SCATTER,
            &passes.calls_scatter_compact_hir_call_args,
        )?,
        call_param_segment_scan: prefix_scan_spec(compiler_graph::CALL_PARAM_ROW_SCAN)?,
        scatter_compact_hir_params: direct(
            CALLS_PARAM_SCATTER,
            &passes.calls_scatter_compact_hir_params,
            call_param_capacity,
        )?,
        resolve: indirect(CALLS_RESOLVE, &passes.calls_resolve)?,
        backend_targets: direct_name(
            compiler_graph::CALLS_BACKEND_TARGETS_PASS,
            &passes.calls_backend_targets,
            token_capacity,
        )?,
        argument_matching,
        generic_claim_validation,
        clear_generic_claim_type_args: indirect(
            CALLS_GENERIC_CLAIM_CLEAR,
            &passes.calls_clear_generic_claim_type_args,
        )?,
        apply_row_args: indirect(CALLS_APPLY_ARGUMENTS, &passes.calls_apply_row_args)?,
        infer_array_generics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_infer_array_generics",
            &passes.calls_infer_array_generics,
            resources,
        )?,
        validate_array_results: direct(
            CALLS_ARRAY_STATE_CONSUME,
            &passes.calls_validate_array_results,
            hir_capacity,
        )?,
        mark_array_args: indirect(CALLS_ARRAY_STATE_PUBLISH, &passes.calls_mark_array_args)?,
        project_result_instances: indirect(
            CALLS_RESULT_INSTANCE_PROJECT,
            &passes.calls_project_result_instances,
        )?,
        erase_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_erase_generic_params",
            &passes.calls_erase_generic_params,
            resources,
        )?,
    })
}
