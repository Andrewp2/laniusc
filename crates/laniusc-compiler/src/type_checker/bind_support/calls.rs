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
    dependency_bound_rows: u32,
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
    let status: LaniusBuffer<u32> = typed_buffer_from_resources(resources, "status")?;
    let status_prior: LaniusBuffer<u32> = typed_buffer_from_resources(resources, "status_prior")?;
    let type_row_args: LaniusBuffer<u32> = typed_buffer_from_resources(resources, "type_live_row_args")?;
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
    // The rounds' masked passes over HIR rows visit the listed active blocks.
    let listed_hir_args: LaniusBuffer<u32> =
        typed_buffer_from_resources(resources, "inference_hir_list_args")?;
    let listed_inference = |name, kernel| {
        ComputeOperation::indirect(
            device,
            graph,
            resources,
            name,
            &passes.kernel(kernel),
            &listed_hir_args,
        )
        .map(Some)
    };
    let listed_spec = |spec| {
        ComputeOperation::indirect_spec(device, graph, resources, passes, spec, &listed_hir_args)
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
    // Both claim scans' applies size the claim indexes from their totals.
    let claim_dispatch_params = uniform_from_val(
        device,
        "type_check.calls.claim_index_dispatch.params",
        &CountDispatchParams {
            capacity: claim_capacity,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let generic_claim_index = CallClaimIndexOperation::new(
        device,
        passes,
        CallClaimIndexBuild {
            kind: CallClaimKind::Generic,
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
            claim_scans: PrefixScanPairOperation::from_spec_with_total_dispatch(
                device,
                passes,
                resources,
                compiler_graph::CALL_CLAIM_SCAN,
                (&claim_dispatch_params).into(),
                [
                    "call_generic_claim_index_dispatch_args",
                    "call_const_claim_index_dispatch_args",
                ],
            )?,
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
            required_scan: PrefixScanOperation::from_spec_with_total_dispatch(
                device,
                passes,
                resources,
                compiler_graph::REQUIRED_GENERIC_SCAN,
                (&required_generic_dispatch_params).into(),
                "call_required_generic_dispatch_args",
            )?,
            dispatch_params: [claim_dispatch_params, required_generic_dispatch_params],
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
            &passes.kernel("type_checker/calls/project_backend_call_targets"),
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
            &listed_hir_args,
            &typed_buffer_from_resources(resources, "call_explicit_admission_args")?,
            struct_init_passes_required(parser_feature_flags),
        )?,
        contextual_result_requests: listed_spec(CALLS_CONTEXTUAL_RESULT_REQUESTS)?,
        contextual_results_final: indirect(CALLS_CONTEXTUAL_RESULTS_FINAL)?,
        clear_generic_claim_type_args: listed_spec(CALLS_GENERIC_CLAIM_CLEAR)?,
        apply_row_args: indirect(CALLS_APPLY_ARGUMENTS)?,
        apply_final_row_args: listed_spec(CALLS_APPLY_FINAL_ARGUMENTS)?,
        // Local generic functions infer from their own bounds, so every unit
        // records bound inference; only the dependency collector needs pages.
        bound_inference: Some(BoundInferenceOperations {
            clear: crate::gpu::operations::ClearBufferOperation::entire(
                graph,
                compiler_graph::CALLS_BOUND_TABLES_CLEAR_PASS,
                "bound_inference_counts",
                &typed_buffer_from_resources::<u32>(resources, "bound_inference_counts")?,
            )?,
            snapshot: crate::gpu::operations::CopyBufferOperation::new(
                graph,
                compiler_graph::CALLS_BOUND_TABLES_SNAPSHOT_PASS,
                "bound_inference_counts",
                &typed_buffer_from_resources::<u32>(resources, "bound_inference_counts")?,
                0,
                "bound_inference_local_counts",
                &typed_buffer_from_resources::<u32>(resources, "bound_inference_local_counts")?,
                0,
                compiler_graph::BOUND_INFERENCE_LOCAL_BYTES,
            )?,
            restore: crate::gpu::operations::CopyBufferOperation::new(
                graph,
                compiler_graph::CALLS_BOUND_TABLES_RESTORE_PASS,
                "bound_inference_local_counts",
                &typed_buffer_from_resources::<u32>(resources, "bound_inference_local_counts")?,
                0,
                "bound_inference_counts",
                &typed_buffer_from_resources::<u32>(resources, "bound_inference_counts")?,
                0,
                compiler_graph::BOUND_INFERENCE_LOCAL_BYTES,
            )?,
            // One lane per implementation or predicate row of the slot.
            collect_dependency: if has_dependency_interfaces {
                Some(direct(CALLS_BOUND_DEPENDENCY_COLLECT, dependency_bound_rows.max(1))?)
            } else {
                None
            },
            collect_local: indirect(CALLS_BOUND_LOCAL_COLLECT)?,
            infer: listed_spec(CALLS_BOUND_INFER)?,
        }),
        bind_method_receiver_environment: listed_inference(
            compiler_graph::CALLS_BIND_METHOD_RECEIVER_ENVIRONMENT_PASS,
            "type_checker/calls/claims/bind_method_receiver_environment",
        )?,
        materialize_return_types: listed_inference(
            compiler_graph::CALLS_MATERIALIZE_RETURN_TYPES_PASS,
            "type_checker/calls/results/materialize_return_types",
        )?,
        call_field_closure: substitution_passes::FieldClosureOperations::new(
            device,
            graph,
            resources,
            passes,
            &substitution_passes::CALL_FIELD_CLOSURE,
            &typed_buffer_from_resources(resources, "call_root_args")?,
        )?,
        project_argument_contexts: Some(substitution_passes::ArgumentContextOperations {
            call_envs: ComputeOperation::indirect(
                device,
                graph,
                resources,
                substitution_passes::SUBSTITUTION_CALL_ENVS_PASS,
                &passes.kernel(substitution_passes::SUBSTITUTION_CALL_ENVS_KERNEL),
                &listed_hir_args,
            )?,
            contexts: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::CALLS_PROJECT_ARGUMENT_CONTEXTS_PASS,
                &passes.kernel("type_checker/calls/arguments/project_argument_contexts"),
                hir_dispatch_args,
            )?,
        }),
        substitution: substitution_passes::SubstitutionOperations::new(
            device, graph, resources, passes,
        )?,
        return_type_index_clear: optional_generic(
            compiler_graph::CALLS_RETURN_TYPE_INDEX_CLEAR_PASS,
            "type_checker/types/instances/clear_type_application_index",
            &token_dispatch_args,
        )?,
        return_type_source_index: optional_generic(
            compiler_graph::CALLS_RETURN_TYPE_SOURCE_INDEX_PASS,
            "type_checker/types/instances/index_closed_applications",
            &token_dispatch_args,
        )?,
        call_roots: CallRootListOperations {
            clear_count: crate::gpu::operations::ClearBufferOperation::entire(
                graph,
                compiler_graph::CALLS_CALL_ROOTS_COUNT_CLEAR_PASS,
                "call_root_count",
                &typed_buffer_from_resources::<u32>(resources, "call_root_count")?,
            )?,
            clear_args: crate::gpu::operations::ClearBufferOperation::entire(
                graph,
                compiler_graph::CALLS_CALL_ROOTS_ARGS_CLEAR_PASS,
                "call_root_args",
                &typed_buffer_from_resources::<u32>(resources, "call_root_args")?,
            )?,
            list: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::CALLS_CALL_ROOTS_LIST_PASS,
                &passes.kernel(compiler_graph::CALLS_CALL_ROOTS_LIST_KERNEL),
                hir_dispatch_args,
            )?,
        },
        inference_blocks: InferenceBlockOperations {
            clear: crate::gpu::operations::ClearBufferOperation::entire(
                graph,
                compiler_graph::CALLS_INFERENCE_BLOCKS_CLEAR_PASS,
                "inference_block_tables",
                &typed_buffer_from_resources::<u32>(resources, "inference_block_tables")?,
            )?,
            ranges: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::CALLS_INFERENCE_RANGES_PASS,
                &passes.kernel(compiler_graph::CALLS_INFERENCE_RANGES_KERNEL),
                &typed_buffer_from_resources(resources, "token_hir_active_dispatch_args")?,
            )?,
            args: direct_name(
                compiler_graph::CALLS_INFERENCE_LIST_ARGS_PASS,
                &passes.kernel(compiler_graph::CALLS_INFERENCE_LIST_ARGS_KERNEL),
                1,
            )?,
            list: ComputeOperation::indirect(
                device,
                graph,
                resources,
                compiler_graph::CALLS_INFERENCE_BLOCK_LIST_PASS,
                &passes.kernel(compiler_graph::CALLS_INFERENCE_BLOCK_LIST_KERNEL),
                &typed_buffer_from_resources(resources, "inference_list_writer_args")?,
            )?,
        },
        type_row_list: if generic_param_record_passes_required(parser_feature_flags)
            || has_dependency_interfaces
        {
            Some(TypeRowListOperations {
                clear: crate::gpu::operations::ClearBufferOperation::entire(
                    graph,
                    compiler_graph::CALLS_TYPE_ROW_LIST_CLEAR_PASS,
                    "type_live_row_count",
                    &typed_buffer_from_resources::<u32>(resources, "type_live_row_count")?,
                )?,
                list: ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    compiler_graph::CALLS_TYPE_ROW_LIST_PASS,
                    &passes.kernel(compiler_graph::CALLS_TYPE_ROW_LIST_KERNEL),
                    &token_dispatch_args,
                )?,
                args: direct_name(
                    compiler_graph::CALLS_TYPE_ROW_LIST_ARGS_PASS,
                    &passes.kernel(compiler_graph::CALLS_TYPE_ROW_LIST_ARGS_KERNEL),
                    1,
                )?,
            })
        } else {
            None
        },
        return_type_index: if generic_param_record_passes_required(parser_feature_flags)
            || has_dependency_interfaces
        {
            Some(ComputeOperation::indirect_with_uniform(
                device,
                graph,
                resources,
                compiler_graph::CALLS_RETURN_TYPE_INDEX_PASS,
                &passes.kernel(compiler_graph::LISTED_APPLICATION_INDEX_KERNEL),
                &type_row_args,
                "gTypeRowList",
                &uniform_from_val(
                    device,
                    "type_check.calls.type_row_list.listed",
                    &TypeRowListParams { listed: 1, reserved0: 0, reserved1: 0, reserved2: 0 },
                ),
            )?)
        } else {
            None
        },
        return_imported_fields: optional_generic(
            compiler_graph::CALLS_RETURN_IMPORTED_FIELDS_PASS,
            compiler_graph::LISTED_IMPORTED_FIELDS_KERNEL,
            &type_row_args,
        )?,
        project_expression_types: listed_inference(
            compiler_graph::CALLS_PROJECT_EXPRESSION_TYPES_PASS,
            "type_checker/calls/results/project_expression_types",
        )?,
        record_literal_inference: if struct_init_passes_required(parser_feature_flags) {
            let listed = |name, kernel| {
                ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    name,
                    &passes.kernel(kernel),
                    &listed_hir_args,
                )
            };
            Some(RecordLiteralInferenceOperations {
                contexts: listed(
                    compiler_graph::CALLS_RECORD_CONTEXTS_PASS,
                    "type_checker/calls/results/project_record_contexts",
                )?,
                nested_contexts: listed(
                    compiler_graph::CALLS_RECORD_NESTED_CONTEXTS_PASS,
                    "type_checker/types/aggregates/propagate_nested_struct_contexts",
                )?,
                fields_and_references: ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    compiler_graph::CALLS_RECORD_FIELDS_AND_REFS_PASS,
                    &passes.kernel("type_checker/calls/results/project_record_field_expectations_and_references"),
                    &typed_buffer_from_resources(resources, "struct_literal_record_args")?,
                )?,
                rows_clear: crate::gpu::operations::ClearBufferOperation::entire(
                    graph,
                    compiler_graph::CALLS_STRUCT_LITERAL_ROWS_CLEAR_PASS,
                    "struct_literal_row_counts",
                    &typed_buffer_from_resources::<u32>(resources, "struct_literal_row_counts")?,
                )?,
                rows_list: ComputeOperation::indirect(
                    device,
                    graph,
                    resources,
                    compiler_graph::CALLS_STRUCT_LITERAL_ROWS_PASS,
                    &passes.kernel(compiler_graph::CALLS_STRUCT_LITERAL_ROWS_KERNEL),
                    &typed_buffer_from_resources(resources, "token_hir_active_dispatch_args")?,
                )?,
                rows_args: direct_name(
                    compiler_graph::CALLS_STRUCT_LITERAL_ROW_ARGS_PASS,
                    &passes.kernel(compiler_graph::CALLS_STRUCT_LITERAL_ROW_ARGS_KERNEL),
                    1,
                )?,
            })
        } else {
            None
        },
        field_expected_ids: crate::type_checker::struct_literal_field_types::FieldExpectedIdOperations::new(
            device,
            graph,
            resources,
            passes,
            struct_init_passes_required(parser_feature_flags),
        )?,
        validation_call_envs: crate::type_checker::struct_literal_field_types::ValidationCallEnvOperation::new(
            device,
            graph,
            resources,
            passes,
            hir_dispatch_args,
        )?,
        project_literal_contexts: listed_inference(
            compiler_graph::CALLS_PROJECT_LITERAL_CONTEXTS_PASS,
            "type_checker/calls/results/project_literal_contexts",
        )?,
        materialize_match_payloads: if match_passes_required(parser_feature_flags)
            && has_dependency_interfaces
        {
            inference(
                compiler_graph::CALLS_MATERIALIZE_MATCH_PAYLOADS_PASS,
                "type_checker/calls/results/materialize_match_payloads",
            )?
        } else {
            None
        },
        project_array_literal_elements: if array_passes_required(parser_feature_flags) {
            listed_inference(
                compiler_graph::CALLS_PROJECT_ARRAY_LITERAL_ELEMENTS_PASS,
                "type_checker/calls/results/project_array_literal_elements",
            )?
        } else {
            None
        },
        materialize_array_literals: if array_passes_required(parser_feature_flags) {
            listed_inference(
                compiler_graph::CALLS_MATERIALIZE_ARRAY_LITERALS_PASS,
                "type_checker/calls/results/materialize_array_literals",
            )?
        } else {
            None
        },
        validate_array_literals: if array_passes_required(parser_feature_flags) {
            inference(
                compiler_graph::CALLS_VALIDATE_ARRAY_LITERALS_PASS,
                "type_checker/calls/results/validate_array_literals",
            )?
        } else {
            None
        },
        infer_return_bindings: listed_inference(
            compiler_graph::CALLS_INFER_RETURN_BINDINGS_PASS,
            "type_checker/calls/inference/infer_return_bindings",
        )?,
        inference_round_reset: crate::gpu::operations::ClearBufferOperation::range(
            graph,
            compiler_graph::CALLS_INFERENCE_ROUND_RESET_PASS,
            "call_inference_state",
            &inference_state,
            4,
            4,
        )?,
        // Word r of the table is r; one word is copied per round.
        inference_round_number: crate::gpu::operations::CopyBufferOperation::new(
            graph,
            compiler_graph::CALLS_INFERENCE_ROUND_NUMBER_PASS,
            "call_inference_round_numbers",
            &typed_buffer_from_resources::<u32>(resources, "call_inference_round_numbers")?,
            0,
            "call_inference_round",
            &typed_buffer_from_resources::<u32>(resources, "call_inference_round")?,
            0,
            4,
        )?,
        inference_activity_clear: crate::gpu::operations::ClearBufferOperation::entire(
            graph,
            compiler_graph::CALLS_INFERENCE_ACTIVITY_CLEAR_PASS,
            "call_inference_fn_stamp",
            &typed_buffer_from_resources::<u32>(resources, "call_inference_fn_stamp")?,
        )?,
        inference_readback: (0..compiler_graph::CALL_INFERENCE_MAX_BATCH)
            .map(|slot| {
                crate::gpu::operations::CopyBufferOperation::new(
                    graph,
                    compiler_graph::CALLS_INFERENCE_READBACK_PASS,
                    "call_inference_state",
                    &inference_state,
                    0,
                    "call_inference_readback",
                    &inference_readback,
                    u64::from(slot) * compiler_graph::CALL_INFERENCE_READBACK_SLOT_BYTES,
                    8,
                )
            })
            .collect::<Result<_>>()?,
        inference_status_readback: (0..compiler_graph::CALL_INFERENCE_MAX_BATCH)
            .map(|slot| {
                crate::gpu::operations::CopyBufferOperation::new(
                    graph,
                    compiler_graph::CALLS_INFERENCE_STATUS_READBACK_PASS,
                    "status",
                    &status,
                    0,
                    "call_inference_readback",
                    &inference_readback,
                    u64::from(slot) * compiler_graph::CALL_INFERENCE_READBACK_SLOT_BYTES + 8,
                    16,
                )
            })
            .collect::<Result<_>>()?,
        status_prior: crate::gpu::operations::CopyBufferOperation::new(
            graph,
            compiler_graph::CALLS_STATUS_PRIOR_PASS,
            "status",
            &status,
            0,
            "status_prior",
            &status_prior,
            0,
            16,
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
