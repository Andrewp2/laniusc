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
    _call_arg_capacity: u32,
    claim_capacity: u32,
    parser_feature_flags: u32,
    has_dependency_interfaces: bool,
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
    let token_dispatch_args = typed_buffer_from_resources(resources, "token_active_dispatch_args")?;
    let inference_state: LaniusBuffer<u32> =
        typed_buffer_from_resources(resources, "call_inference_state")?;
    let inference_readback: LaniusBuffer<u32> =
        typed_buffer_from_resources(resources, "call_inference_readback")?;
    let optional_generic = |name, kernel, dispatch| {
        if generic_param_record_passes_required(parser_feature_flags) || has_dependency_interfaces {
            ComputeOperation::indirect(
                device,
                graph,
                resources,
                name,
                &passes.kernel(kernel),
                dispatch,
            )
            .map(Some)
        } else {
            Ok(None)
        }
    };
    // Ordinary unannotated calls also need accepted expression/return facts.
    // Only type application indexing and generic environments are optional.
    let inference = |name, kernel| {
        ComputeOperation::indirect(
            device,
            graph,
            resources,
            name,
            &passes.kernel(kernel),
            hir_dispatch_args,
        )
        .map(Some)
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
            claim_capacity,
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
            const_scan: prefix_scan_spec(compiler_graph::CONST_CLAIM_SCAN)?,
            emit_claims: indirect(CALLS_GENERIC_CLAIM_EMIT)?,
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
            publish_const_environment: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                passes,
                CALLS_CONST_ENVIRONMENT_PUBLISH,
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
        explicit_application_binding: ComputeOperation::indirect_spec(
            device, graph, resources, passes, CALLS_EXPLICIT_APPLICATIONS_BIND,
            &typed_buffer_from_resources(resources, "explicit_application_dispatch_args")?,
        )?,
        explicit_application_validation: ComputeOperation::indirect_spec(
            device, graph, resources, passes, CALLS_EXPLICIT_APPLICATIONS_VALIDATE,
            &typed_buffer_from_resources(resources, "explicit_application_dispatch_args")?,
        )?,
        backend_targets: direct_name(
            compiler_graph::CALLS_BACKEND_TARGETS_PASS,
            &passes.kernel("type_checker/calls/04_backend_targets"),
            token_capacity,
        )?,
        argument_matching,
        generic_claim_validation,
        environment_admission: CallEnvironmentAdmission::new(
            device,
            graph,
            passes,
            resources,
            hir_dispatch_args,
            &token_dispatch_args,
            struct_init_passes_required(parser_feature_flags),
        )?,
        contextual_result_requests: indirect(CALLS_CONTEXTUAL_RESULT_REQUESTS)?,
        clear_generic_claim_type_args: indirect(CALLS_GENERIC_CLAIM_CLEAR)?,
        apply_row_args: indirect(CALLS_APPLY_ARGUMENTS)?,
        bind_method_receiver_environment: inference(
            compiler_graph::CALLS_BIND_METHOD_RECEIVER_ENVIRONMENT_PASS,
            "type_checker/calls/03d_bind_method_receiver_environment",
        )?,
        materialize_return_types: inference(
            compiler_graph::CALLS_MATERIALIZE_RETURN_TYPES_PASS,
            "type_checker/calls/03e_materialize_return_types",
        )?,
        call_field_closure: substitution_passes::FieldClosureOperations::new(
            device,
            graph,
            resources,
            passes,
            &substitution_passes::CALL_FIELD_CLOSURE,
            hir_dispatch_args,
        )?,
        project_argument_contexts: Some(substitution_passes::ArgumentContextOperations {
            call_envs: ComputeOperation::indirect(
                device,
                graph,
                resources,
                substitution_passes::SUBSTITUTION_CALL_ENVS_PASS,
                &passes.kernel(substitution_passes::SUBSTITUTION_CALL_ENVS_KERNEL),
                hir_dispatch_args,
            )?,
            contexts: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::CALLS_PROJECT_ARGUMENT_CONTEXTS_PASS,
                &passes.kernel("type_checker/calls/03k_project_argument_contexts"),
                hir_dispatch_args,
            )?,
        }),
        substitution: substitution_passes::SubstitutionOperations::new(
            device, graph, resources, passes,
        )?,
        return_type_index_clear: optional_generic(
            compiler_graph::CALLS_RETURN_TYPE_INDEX_CLEAR_PASS,
            "type_checker/type/instances/02b_clear_application_index",
            &token_dispatch_args,
        )?,
        return_type_source_index: optional_generic(
            compiler_graph::CALLS_RETURN_TYPE_SOURCE_INDEX_PASS,
            "type_checker/type/instances/02c_index_closed_applications",
            &token_dispatch_args,
        )?,
        return_type_index: optional_generic(
            compiler_graph::CALLS_RETURN_TYPE_INDEX_PASS,
            "type_checker/type/instances/02c_index_closed_applications",
            &token_dispatch_args,
        )?,
        return_imported_fields: optional_generic(
            compiler_graph::CALLS_RETURN_IMPORTED_FIELDS_PASS,
            compiler_graph::IMPORTED_FIELDS_KERNEL,
            &token_dispatch_args,
        )?,
        project_expression_types: inference(
            compiler_graph::CALLS_PROJECT_EXPRESSION_TYPES_PASS,
            "type_checker/calls/03g_project_expression_types",
        )?,
        record_literal_inference: if struct_init_passes_required(parser_feature_flags) {
            let operation = |name, kernel| {
                ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    name,
                    &passes.kernel(kernel),
                    hir_dispatch_args,
                )
            };
            Some(RecordLiteralInferenceOperations {
                contexts: operation(
                    compiler_graph::CALLS_RECORD_CONTEXTS_PASS,
                    "type_checker/calls/03k3_project_record_contexts",
                )?,
                nested_contexts: operation(
                    compiler_graph::CALLS_RECORD_NESTED_CONTEXTS_PASS,
                    "type_checker/type/instances/04a3_nested_struct_contexts",
                )?,
                fields: operation(
                    compiler_graph::CALLS_RECORD_FIELDS_PASS,
                    "type_checker/type/instances/04_struct_init_fields",
                )?,
                references: operation(
                    compiler_graph::CALLS_RECORD_REFS_PASS,
                    "type_checker/semantic/artifact/01a_struct_literal_refs",
                )?,
            })
        } else {
            None
        },
        project_literal_contexts: inference(
            compiler_graph::CALLS_PROJECT_LITERAL_CONTEXTS_PASS,
            "type_checker/calls/03k1_project_literal_contexts",
        )?,
        materialize_match_payloads: if match_passes_required(parser_feature_flags)
            && has_dependency_interfaces
        {
            inference(
                compiler_graph::CALLS_MATERIALIZE_MATCH_PAYLOADS_PASS,
                "type_checker/calls/03k2_materialize_match_payloads",
            )?
        } else {
            None
        },
        project_array_literal_elements: if array_passes_required(parser_feature_flags) {
            inference(
                compiler_graph::CALLS_PROJECT_ARRAY_LITERAL_ELEMENTS_PASS,
                "type_checker/calls/03h_project_array_literal_elements",
            )?
        } else {
            None
        },
        materialize_array_literals: if array_passes_required(parser_feature_flags) {
            inference(
                compiler_graph::CALLS_MATERIALIZE_ARRAY_LITERALS_PASS,
                "type_checker/calls/03i_materialize_array_literals",
            )?
        } else {
            None
        },
        validate_array_literals: if array_passes_required(parser_feature_flags) {
            inference(
                compiler_graph::CALLS_VALIDATE_ARRAY_LITERALS_PASS,
                "type_checker/calls/03j_validate_array_literals",
            )?
        } else {
            None
        },
        infer_return_bindings: inference(
            compiler_graph::CALLS_INFER_RETURN_BINDINGS_PASS,
            "type_checker/calls/03f_infer_return_bindings",
        )?,
        inference_readback: crate::gpu::operations::CopyBufferOperation::new(
            graph,
            compiler_graph::CALLS_INFERENCE_READBACK_PASS,
            "call_inference_state",
            &inference_state,
            0,
            "call_inference_readback",
            &inference_readback,
            0,
            8,
        )?,
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
