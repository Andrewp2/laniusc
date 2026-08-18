use super::super::*;

/// Builds bind groups for collecting, sorting, and projecting type instances.
pub(in crate::type_checker) fn create_type_instance_bind_groups(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    token_capacity: u32,
    hir_capacity: u32,
    parser_feature_flags: u32,
) -> Result<TypeInstanceBindGroups> {
    let struct_field_index =
        StructFieldIndex::new(device, graph, passes, resources, token_capacity.max(1))?;

    let type_instance_arg_row_scan = PrefixScanOperation::from_spec(
        device,
        passes,
        resources,
        compiler_graph::TYPE_INSTANCE_ARG_ROW_SCAN,
    )?;
    let hir_dispatch_args = typed_buffer_from_resources(resources, "hir_active_dispatch_args")?;
    let token_dispatch_args = typed_buffer_from_resources(resources, "token_active_dispatch_args")?;
    let indirect_hir = |name, kernel| {
        ComputeOperation::indirect(
            device,
            graph,
            resources,
            name,
            &passes.kernel(kernel),
            &hir_dispatch_args,
        )
    };
    let indirect_token = |name, kernel| {
        ComputeOperation::indirect(
            device,
            graph,
            resources,
            name,
            &passes.kernel(kernel),
            &token_dispatch_args,
        )
    };
    let generic_parameters = if generic_param_record_passes_required(parser_feature_flags) {
        GenericParameterRecordOperation::present(
            indirect_hir(
                compiler_graph::TYPE_INSTANCES_MARK_GENERIC_PARAM_RECORDS_PASS,
                "type_checker/type/instances/00a_mark_generic_param_records",
            )?,
            indirect_hir(
                compiler_graph::TYPE_INSTANCES_DECL_GENERIC_PARAMS_PASS,
                "type_checker/type/instances/00b_decl_generic_params",
            )?,
            GenericParameterIndex::new(device, graph, passes, resources, token_capacity.max(1))?,
            indirect_hir(
                compiler_graph::TYPE_INSTANCES_GENERIC_PARAM_USE_SLOTS_PASS,
                "type_checker/type/instances/00e_generic_param_use_slots",
            )?,
        )
    } else {
        GenericParameterRecordOperation::empty(graph, resources)?
    };
    let collection_scalar = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_COLLECT_INITIAL,
        &hir_dispatch_args,
    )?;
    let collection_named = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_COLLECT_INITIAL_NAMED,
        &hir_dispatch_args,
    )?;
    let collection_aggregate_refs = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_REFS,
        &hir_dispatch_args,
    )?;
    let collection_aggregate_details = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_COLLECT_INITIAL_AGGREGATE_DETAILS,
        &hir_dispatch_args,
    )?;
    let collection = TypeInstanceCollectionOperations {
        projected_scalar: collection_scalar
            .invocation(graph, TYPE_INSTANCES_COLLECT_PROJECTED.name)?,
        projected_named: collection_named
            .invocation(graph, TYPE_INSTANCES_COLLECT_PROJECTED_NAMED.name)?,
        projected_aggregate_refs: collection_aggregate_refs
            .invocation(graph, TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_REFS.name)?,
        projected_aggregate_details: collection_aggregate_details.invocation(
            graph,
            TYPE_INSTANCES_COLLECT_PROJECTED_AGGREGATE_DETAILS.name,
        )?,
        scalar: collection_scalar,
        named: collection_named,
        aggregate_refs: collection_aggregate_refs,
        aggregate_details: collection_aggregate_details,
    };
    let decl_refs = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        TYPE_INSTANCES_DECL_REFS,
        &hir_dispatch_args,
    )?;
    let decl_refs_for_bindings =
        decl_refs.invocation(graph, TYPE_INSTANCES_DECL_REFS_FOR_BINDINGS.name)?;
    let member_receivers = indirect_hir(
        compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_PASS,
        "type_checker/type/instances/03a_member_receivers",
    )?;
    let member_receivers_after_array = member_receivers.invocation(
        graph,
        compiler_graph::TYPE_INSTANCES_MEMBER_RECEIVERS_AFTER_ARRAY_PASS,
    )?;
    let member_results = indirect_hir(
        compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_PASS,
        "type_checker/type/instances/03_member_results",
    )?;
    let member_results_after_array = member_results.invocation(
        graph,
        compiler_graph::TYPE_INSTANCES_MEMBER_RESULTS_AFTER_ARRAY_PASS,
    )?;
    let member_substitute = indirect_token(
        compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_PASS,
        "type_checker/type/instances/03b_member_substitute",
    )?;
    let member_substitute_after_array = member_substitute.invocation(
        graph,
        compiler_graph::TYPE_INSTANCES_MEMBER_SUBSTITUTE_AFTER_ARRAY_PASS,
    )?;
    // These scans are recorded before aggregate comparison begins, so the
    // aggregate scan workspace can safely serve both relations without
    // increasing resident scratch memory.
    Ok(TypeInstanceBindGroups {
        clear: ComputeOperation::direct_spec(
            device,
            graph,
            resources,
            passes,
            TYPE_INSTANCES_CLEAR,
            token_capacity.max(hir_capacity),
        )?,
        type_instance_arg_row_scan,
        generic_parameters,
        struct_field_index,
        collection,
        collect_named_arg_refs: ComputeOperation::indirect_spec(
            device,
            graph,
            resources,
            passes,
            TYPE_INSTANCES_COLLECT_NAMED_ARG_REFS,
            &hir_dispatch_args,
        )?,
        hash_arg_rows: indirect_token(
            compiler_graph::TYPE_INSTANCE_ARG_HASH_ROWS_PASS,
            "type_checker/type/instances/01g_hash_arg_rows",
        )?,
        clear_semantic_type_rows: Box::new(ComputeOperation::direct(
            device,
            graph,
            resources,
            compiler_graph::TYPE_SEMANTIC_CLEAR_PASS,
            &passes.kernel("type_checker/type/instances/01h_clear_semantic_type_rows"),
            token_capacity
                .saturating_add(LANGUAGE_SYMBOL_COUNT)
                .max(hir_capacity),
        )?),
        semantic_type_rows: Box::new(CompactionOperation::indirect(
            device,
            graph,
            resources,
            passes,
            TYPE_SEMANTIC_COMPACTION,
            &typed_buffer_from_resources(resources, "hir_active_dispatch_args")?,
        )?),
        decl_refs,
        decl_refs_for_bindings,
        member_receivers,
        member_receivers_after_array,
        member_results,
        member_results_after_array,
        member_substitute,
        member_substitute_after_array,
        struct_init_clear: ComputeOperation::direct(
            device,
            graph,
            resources,
            compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CLEAR_PASS,
            &passes.kernel("type_checker/type/instances/04a_struct_init_clear"),
            token_capacity.max(hir_capacity),
        )?,
        struct_init_contexts: indirect_hir(
            compiler_graph::TYPE_INSTANCES_STRUCT_INIT_CONTEXTS_PASS,
            "type_checker/type/instances/04a2_struct_init_contexts",
        )?,
        struct_init_fields: indirect_hir(
            compiler_graph::TYPE_INSTANCES_STRUCT_INIT_FIELDS_PASS,
            "type_checker/type/instances/04_struct_init_fields",
        )?,
        struct_init_substitute: indirect_token(
            compiler_graph::TYPE_INSTANCES_STRUCT_INIT_SUBSTITUTE_PASS,
            "type_checker/type/instances/04b_struct_init_substitute",
        )?,
        array_return_refs: ComputeOperation::indirect_spec(
            device,
            graph,
            resources,
            passes,
            TYPE_INSTANCES_ARRAY_RETURN_REFS,
            &hir_dispatch_args,
        )?,
        array_literal_return_refs: ComputeOperation::indirect_spec(
            device,
            graph,
            resources,
            passes,
            TYPE_INSTANCES_ARRAY_LITERAL_RETURN_REFS,
            &hir_dispatch_args,
        )?,
        validate_aggregate_access: indirect_hir(
            compiler_graph::TYPE_INSTANCES_VALIDATE_AGGREGATE_ACCESS_PASS,
            "type_checker/type/instances/08_validate_aggregate_access",
        )?,
    })
}
