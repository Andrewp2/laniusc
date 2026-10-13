use super::{super::*, buffers::Buffers, inputs::CreateInputs, layout::Layout};

pub(in crate::type_checker) struct DependencyTypeIndexInvocations {
    initialize: ComputeInvocation,
    jumps: Box<[ComputeInvocation]>,
    clear_generic_arity: ComputeInvocation,
    count_generic_arity: ComputeInvocation,
}

pub(in crate::type_checker) struct DependencyTypeIndexOperations {
    initialize: ComputeOperation,
    jump_a_to_b: Option<ComputeOperation>,
    jump_b_to_a: Option<ComputeOperation>,
    clear_generic_arity: ComputeOperation,
    count_generic_arity: ComputeOperation,
}

impl DependencyTypeIndexOperations {
    fn invocations(
        &self,
        graph: &compiler_graph::TypeCheckCompilerGraph,
        names: DependencyTypeIndexPassNames,
        jump_rounds: u32,
    ) -> Result<DependencyTypeIndexInvocations> {
        let initialize = self.initialize.invocation(graph, names.initialize)?;
        let mut jumps = Vec::with_capacity(jump_rounds as usize);
        for round in 0..jump_rounds {
            let operation = if round % 2 == 0 {
                self.jump_a_to_b
                    .as_ref()
                    .expect("an even canonical-type jump requires A-to-B storage")
            } else {
                self.jump_b_to_a
                    .as_ref()
                    .expect("an odd canonical-type jump requires B-to-A storage")
            };
            let name = if round % 2 == 0 && round + 1 == jump_rounds {
                names.jump_final_a_to_b
            } else if round % 2 == 0 {
                names.jump_a_to_b
            } else {
                names.jump_b_to_a
            };
            jumps.push(operation.invocation(graph, name)?);
        }
        Ok(DependencyTypeIndexInvocations {
            initialize,
            jumps: jumps.into_boxed_slice(),
            clear_generic_arity: self
                .clear_generic_arity
                .invocation(graph, names.clear_generic_arity)?,
            count_generic_arity: self
                .count_generic_arity
                .invocation(graph, names.count_generic_arity)?,
        })
    }

    pub(in crate::type_checker) fn record(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        invocations: &DependencyTypeIndexInvocations,
    ) -> Result<()> {
        self.initialize
            .record_invocation(encoder, &invocations.initialize)?;
        for (round, invocation) in invocations.jumps.iter().enumerate() {
            let operation = if round % 2 == 0 {
                self.jump_a_to_b
                    .as_ref()
                    .expect("an even canonical-type jump requires A-to-B storage")
            } else {
                self.jump_b_to_a
                    .as_ref()
                    .expect("an odd canonical-type jump requires B-to-A storage")
            };
            operation.record_invocation(encoder, invocation)?;
        }
        self.clear_generic_arity
            .record_invocation(encoder, &invocations.clear_generic_arity)?;
        self.count_generic_arity
            .record_invocation(encoder, &invocations.count_generic_arity)
    }
}

/// Per-unit projection of immutable dependency declarations into the local
/// import graph. Local and dependency declaration identities intentionally use
/// separate outputs so downstream passes cannot interpret a persisted identity
/// as a local HIR row.
pub(in crate::type_checker) struct DependencyVisibilityState {
    /// Stable dependency identity for each resolved type path. These rows
    /// remain valid after dependency pages are replaced, unlike page-local
    /// declaration indices.
    pub(in crate::type_checker) resolved_dependency_library_id: LaniusBuffer<u32>,
    pub(in crate::type_checker) resolved_dependency_unit_id: LaniusBuffer<u32>,
    pub(in crate::type_checker) resolved_dependency_local_index: LaniusBuffer<u32>,
    /// Value bindings are independent when the same path also names a type.
    pub(in crate::type_checker) resolved_dependency_value_library_id: LaniusBuffer<u32>,
    pub(in crate::type_checker) resolved_dependency_value_unit_id: LaniusBuffer<u32>,
    pub(in crate::type_checker) resolved_dependency_value_local_index: LaniusBuffer<u32>,
    pub(in crate::type_checker) declaration_field_count: LaniusBuffer<u32>,
    _retained_buffers: Box<[LaniusBuffer<u32>]>,
    pub(in crate::type_checker) scan: PrefixScanOperation,
    pub(in crate::type_checker) count_group: ComputeOperation,
    pub(in crate::type_checker) clear_workspace_group: ComputeOperation,
    pub(in crate::type_checker) scatter_group: ComputeOperation,
    pub(in crate::type_checker) clear_lookup_group: ComputeOperation,
    pub(in crate::type_checker) build_lookup_group: ComputeOperation,
    pub(in crate::type_checker) resolve_type_group: ComputeOperation,
    pub(in crate::type_checker) resolve_value_group: ComputeOperation,
    pub(in crate::type_checker) project_types_group: ComputeOperation,
    pub(in crate::type_checker) count_call_collection: ComputeInvocation,
    pub(in crate::type_checker) scatter_call_collection: ComputeInvocation,
    pub(in crate::type_checker) clear_lookup_call_collection: ComputeInvocation,
    pub(in crate::type_checker) build_lookup_call_collection: ComputeInvocation,
    pub(in crate::type_checker) resolve_type_call_collection: ComputeInvocation,
    pub(in crate::type_checker) resolve_value_call_collection: ComputeInvocation,
    pub(in crate::type_checker) project_types_after_clear: ComputeInvocation,
    pub(in crate::type_checker) project_calls_group: ComputeOperation,
    pub(in crate::type_checker) clear_normalized_member_lookup: ComputeInvocation,
    pub(in crate::type_checker) build_normalized_member_lookup: ComputeOperation,
    pub(in crate::type_checker) resolve_normalized_members: ComputeOperation,
    pub(in crate::type_checker) project_normalized_values: ComputeOperation,
    pub(in crate::type_checker) project_call_params_group: ComputeOperation,
    pub(in crate::type_checker) scatter_call_params_group: ComputeOperation,
    pub(in crate::type_checker) validate_call_arity_group: ComputeOperation,
    pub(in crate::type_checker) validate_call_args_group: ComputeOperation,
    pub(in crate::type_checker) validate_call_results_group: ComputeOperation,
    pub(in crate::type_checker) validate_call_results_validate: ComputeInvocation,
    pub(in crate::type_checker) generic_call_results_resolve: ComputeInvocation,
    pub(in crate::type_checker) type_index: DependencyTypeIndexOperations,
    pub(in crate::type_checker) type_index_module_paths: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_call_collection: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_after_type_clear: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_type_instance_projection: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_alias_targets: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_call_param_scatter: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_method_projection: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_method_lookup: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_return_materialization: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_call_validation: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) type_index_trait_contracts: DependencyTypeIndexInvocations,
    pub(in crate::type_checker) project_type_instances_group: ComputeOperation,
    pub(in crate::type_checker) materialize_alias_targets_group: ComputeOperation,
    pub(in crate::type_checker) collect_methods_group: ComputeOperation,
    pub(in crate::type_checker) project_methods_group: ComputeOperation,
    pub(in crate::type_checker) project_struct_literals_group: ComputeOperation,
    pub(in crate::type_checker) _params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _type_params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _value_params: LaniusBuffer<DependencyInterfaceVisibilityParams>,
    pub(in crate::type_checker) _canonical_type_params: LaniusBuffer<DependencyCanonicalTypeParams>,
}

pub(in crate::type_checker) fn create(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<Option<Box<DependencyVisibilityState>>> {
    let Some(dependencies) = inputs.dependency_interfaces else {
        return Ok(None);
    };
    let import_capacity = layout.import_record_capacity_u32.max(1);
    // Imported public declarations are not bounded by the importing unit's
    // token count. A small entry module can import a large persisted interface,
    // so retain enough rows for every declaration in the dependency batch.
    let visible_capacity = inputs
        .token_capacity
        .max(dependencies.declaration_count)
        .max(1);
    let lookup_capacity = visible_capacity
        .checked_mul(2)
        .and_then(u32::checked_next_power_of_two)
        .ok_or_else(|| anyhow::anyhow!("dependency visibility lookup capacity exceeds u32"))?;
    let path_capacity = layout.record_capacity_u32.max(1);

    let params_value = DependencyInterfaceVisibilityParams {
        declaration_count: dependencies.declaration_count,
        import_capacity,
        visible_capacity,
        lookup_capacity,
        source_len: inputs.source_len,
        path_capacity,
        namespace: 0,
        hir_capacity: inputs.hir_node_capacity.max(1),
    };
    let params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.params",
        &params_value,
    );
    let type_params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.type_params",
        &DependencyInterfaceVisibilityParams {
            namespace: 3,
            ..params_value
        },
    );
    let value_params = uniform_from_val(
        device,
        "type_check.dependencies.visibility.value_params",
        &DependencyInterfaceVisibilityParams {
            namespace: 2,
            ..params_value
        },
    );
    let canonical_type_params = uniform_from_val(
        device,
        "type_check.dependencies.canonical_type.params",
        &DependencyCanonicalTypeParams {
            type_count: dependencies.type_count,
            declaration_count: dependencies.declaration_count,
            member_count: dependencies.member_count,
            path_capacity,
            token_capacity: inputs.token_capacity.max(1),
        },
    );

    let count = graph.u32_buffer("dependency_visible_count")?;
    let prefix = graph.u32_buffer("dependency_visible_prefix")?;
    let total = graph.u32_buffer("dependency_visible_total")?;
    let owner_module = graph.u32_buffer("dependency_visible_owner_module")?;
    let declaration = graph.u32_buffer("dependency_visible_decl")?;
    let lookup = graph.u32_buffer("dependency_visible_lookup")?;
    let resolved_dependency_library_id = graph.u32_buffer("resolved_dependency_library_id")?;
    let resolved_dependency_unit_id = graph.u32_buffer("resolved_dependency_unit_id")?;
    let resolved_dependency_local_index = graph.u32_buffer("resolved_dependency_local_index")?;
    let resolved_dependency_value_library_id =
        graph.u32_buffer("resolved_dependency_value_library_id")?;
    let resolved_dependency_value_unit_id = graph.u32_buffer("resolved_dependency_value_unit_id")?;
    let resolved_dependency_value_local_index =
        graph.u32_buffer("resolved_dependency_value_local_index")?;
    let mut scan_resources = resources.clone();
    scan_resources.buffers([
        ("import_record_count_out", &buffers.import_count_out),
        ("import_dispatch_args", &buffers.import_dispatch_args),
        ("dependency_visible_count", &count),
        ("dependency_visible_prefix", &prefix),
        ("dependency_visible_total", &total),
    ]);
    scan_resources.buffers([
        (
            "module_record_scan_local_prefix",
            inputs.module_record_scan_workspace.local_prefix,
        ),
        (
            "module_record_scan_block_sum",
            inputs.module_record_scan_workspace.block_sum,
        ),
        (
            "module_record_scan_prefix_a",
            inputs.module_record_scan_workspace.block_prefix,
        ),
    ]);
    let scan = PrefixScanOperation::from_spec(
        device,
        passes,
        &scan_resources,
        compiler_graph::DEPENDENCY_VISIBLE_SCAN,
    )?;
    let canonical_type_roots_a = graph.u32_buffer("dependency_canonical_type_roots_a")?;
    let canonical_type_roots_b = graph.u32_buffer("dependency_canonical_type_roots_b")?;
    let declaration_generic_arity = graph.u32_buffer("dependency_declaration_generic_arity")?;
    let declaration_field_count = graph.u32_buffer("dependency_declaration_field_count")?;
    let mut canonical_type_jump_rounds = 0u32;
    let mut canonical_type_jump_reach = 1u32;
    while canonical_type_jump_reach < dependencies.type_count.max(1) {
        canonical_type_jump_reach = canonical_type_jump_reach.saturating_mul(16);
        canonical_type_jump_rounds += 1;
    }
    let clear_capacity = import_capacity
        .max(visible_capacity)
        .max(lookup_capacity)
        .max(path_capacity)
        .max(inputs.hir_node_capacity.max(1));
    let mut visibility_resources = resources.clone();
    visibility_resources.buffer("gParams", &params);
    let clear_workspace_group = ComputeOperation::direct_spec(
        device,
        graph,
        &visibility_resources,
        passes,
        DEPENDENCY_WORKSPACE_CLEAR,
        clear_capacity,
    )?;
    let count_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &visibility_resources,
        passes,
        DEPENDENCY_IMPORT_VISIBILITY_COUNT,
        &buffers.import_dispatch_args,
    )?;
    let scatter_group = ComputeOperation::direct_spec(
        device,
        graph,
        &visibility_resources,
        passes,
        DEPENDENCY_IMPORT_VISIBILITY_SCATTER,
        visible_capacity,
    )?;
    let clear_lookup_group = ComputeOperation::direct_spec(
        device,
        graph,
        &visibility_resources,
        passes,
        DEPENDENCY_VISIBLE_LOOKUP_CLEAR,
        lookup_capacity,
    )?;
    let build_lookup_group = ComputeOperation::direct_spec(
        device,
        graph,
        &visibility_resources,
        passes,
        DEPENDENCY_VISIBLE_LOOKUP_BUILD,
        visible_capacity,
    )?;

    let mut type_path_resources = resources.clone();
    type_path_resources.buffer("gParams", &type_params);
    let resolve_type_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &type_path_resources,
        passes,
        DEPENDENCY_TYPE_PATHS_RESOLVE,
        &buffers.path_dispatch_args,
    )?;
    let mut value_path_resources = resources.clone();
    value_path_resources.buffer("gParams", &value_params);
    let resolve_value_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_VALUE_PATHS_RESOLVE,
        &buffers.path_dispatch_args,
    )?;
    let mut canonical_type_resources = resources.clone();
    canonical_type_resources.buffer("gParams", &canonical_type_params);
    let type_index_names = DEPENDENCY_TYPE_INDEX_MODULE_PATHS;
    let initialize_type_index = ComputeOperation::direct(
        device,
        graph,
        &canonical_type_resources,
        type_index_names.initialize,
        &passes.kernel("type_checker/dependencies/09_init_canonical_type_roots"),
        dependencies.type_count.max(1),
    )?;
    let jump_a_to_b = if canonical_type_jump_rounds == 0 {
        None
    } else {
        let name = if canonical_type_jump_rounds == 1 {
            type_index_names.jump_final_a_to_b
        } else {
            type_index_names.jump_a_to_b
        };
        Some(ComputeOperation::direct(
            device,
            graph,
            &canonical_type_resources,
            name,
            &passes.kernel("type_checker/dependencies/10_jump_canonical_type_roots"),
            dependencies.type_count.max(1),
        )?)
    };
    let jump_b_to_a = if canonical_type_jump_rounds >= 2 {
        Some(ComputeOperation::direct(
            device,
            graph,
            &canonical_type_resources,
            type_index_names.jump_b_to_a,
            &passes.kernel("type_checker/dependencies/10_jump_canonical_type_roots"),
            dependencies.type_count.max(1),
        )?)
    } else {
        None
    };
    let clear_generic_arity = ComputeOperation::direct(
        device,
        graph,
        &canonical_type_resources,
        type_index_names.clear_generic_arity,
        &passes.kernel("type_checker/dependencies/12_clear_declaration_generic_arity"),
        dependencies.declaration_count.max(1),
    )?;
    let count_generic_arity = ComputeOperation::direct(
        device,
        graph,
        &canonical_type_resources,
        type_index_names.count_generic_arity,
        &passes.kernel("type_checker/dependencies/13_count_declaration_generic_arity"),
        dependencies.member_count.max(1),
    )?;
    let type_index = DependencyTypeIndexOperations {
        initialize: initialize_type_index,
        jump_a_to_b,
        jump_b_to_a,
        clear_generic_arity,
        count_generic_arity,
    };
    let project_types_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &canonical_type_resources,
        passes,
        DEPENDENCY_TYPES_PROJECT,
        &buffers.path_dispatch_args,
    )?;
    let project_type_instances_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &canonical_type_resources,
        passes,
        DEPENDENCY_TYPE_INSTANCES_PROJECT,
        &buffers.path_dispatch_args,
    )?;
    let mut alias_resources = canonical_type_resources.clone();
    alias_resources.buffer("gParams", inputs.params);
    let materialize_alias_targets_group = ComputeOperation::indirect_spec(
        device, graph, &alias_resources, passes, DEPENDENCY_ALIAS_TARGETS_MATERIALIZE,
        &buffers.path_dispatch_args,
    )?;
    let collect_methods_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_METHODS_COLLECT,
        inputs.hir_active_dispatch_args,
    )?;
    let project_methods_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_METHODS_PROJECT,
        inputs.hir_active_dispatch_args,
    )?;
    let project_struct_literals_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &canonical_type_resources,
        passes,
        DEPENDENCY_STRUCT_LITERALS_PROJECT,
        inputs.hir_active_dispatch_args,
    )?;
    let clear_normalized_member_lookup = clear_lookup_group.invocation(
        graph, DEPENDENCY_NORMALIZED_MEMBER_LOOKUP_CLEAR.name)?;
    let build_normalized_member_lookup = ComputeOperation::direct_spec(
        device, graph, &visibility_resources, passes,
        DEPENDENCY_NORMALIZED_MEMBER_LOOKUP_BUILD, visible_capacity)?;
    let resolve_normalized_members = ComputeOperation::indirect_spec(
        device, graph, &visibility_resources, passes,
        DEPENDENCY_NORMALIZED_MEMBERS_RESOLVE, &buffers.path_dispatch_args)?;
    let project_normalized_values = ComputeOperation::indirect_spec(
        device, graph, &canonical_type_resources, passes,
        DEPENDENCY_NORMALIZED_VALUES_PROJECT, &buffers.path_dispatch_args)?;
    let project_calls_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALLS_PROJECT,
        inputs.hir_active_dispatch_args,
    )?;
    let project_call_params_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALL_PARAMS_PROJECT,
        inputs.hir_active_dispatch_args,
    )?;
    let scatter_call_params_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALL_PARAMS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;
    let validate_call_args_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALL_ARGS_VALIDATE,
        inputs.hir_active_dispatch_args,
    )?;
    let validate_call_arity_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALL_ARITY_VALIDATE,
        inputs.hir_active_dispatch_args,
    )?;
    let validate_call_results_group = ComputeOperation::indirect_spec(
        device,
        graph,
        &value_path_resources,
        passes,
        DEPENDENCY_CALL_RESULTS_SUBSTITUTE,
        inputs.hir_active_dispatch_args,
    )?;
    let replay = DEPENDENCY_PAGE_CALL_COLLECTION;
    let count_call_collection = count_group.invocation(graph, replay.count_import_visibility)?;
    let scatter_call_collection =
        scatter_group.invocation(graph, replay.scatter_import_visibility)?;
    let clear_lookup_call_collection =
        clear_lookup_group.invocation(graph, replay.clear_visible_lookup)?;
    let build_lookup_call_collection =
        build_lookup_group.invocation(graph, replay.build_visible_lookup)?;
    let resolve_type_call_collection =
        resolve_type_group.invocation(graph, replay.resolve_type_paths)?;
    let resolve_value_call_collection =
        resolve_value_group.invocation(graph, replay.resolve_value_paths)?;
    let project_types_after_clear =
        project_types_group.invocation(graph, DEPENDENCY_TYPES_PROJECT_AFTER_CLEAR.name)?;
    let validate_call_results_validate =
        validate_call_results_group.invocation(graph, DEPENDENCY_CALL_RESULTS_VALIDATE.name)?;
    let generic_call_results_resolve = validate_call_results_group
        .invocation(graph, DEPENDENCY_GENERIC_CALL_RESULTS_RESOLVE.name)?;
    let type_index_module_paths = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_MODULE_PATHS,
        canonical_type_jump_rounds,
    )?;
    let type_index_call_collection = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_CALL_COLLECTION,
        canonical_type_jump_rounds,
    )?;
    let type_index_after_type_clear = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_AFTER_TYPE_CLEAR,
        canonical_type_jump_rounds,
    )?;
    let type_index_type_instance_projection = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_TYPE_INSTANCE_PROJECTION,
        canonical_type_jump_rounds,
    )?;
    let type_index_alias_targets = type_index.invocations(
        graph, DEPENDENCY_TYPE_INDEX_ALIAS_TARGETS, canonical_type_jump_rounds,
    )?;
    let type_index_call_param_scatter = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_CALL_PARAM_SCATTER,
        canonical_type_jump_rounds,
    )?;
    let type_index_method_projection = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_METHOD_PROJECTION,
        canonical_type_jump_rounds,
    )?;
    let type_index_method_lookup = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_METHOD_LOOKUP,
        canonical_type_jump_rounds,
    )?;
    let type_index_call_validation = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_CALL_VALIDATION,
        canonical_type_jump_rounds,
    )?;
    let type_index_return_materialization = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_RETURN_MATERIALIZATION,
        canonical_type_jump_rounds,
    )?;
    let type_index_trait_contracts = type_index.invocations(
        graph,
        DEPENDENCY_TYPE_INDEX_TRAIT_CONTRACTS,
        canonical_type_jump_rounds,
    )?;

    Ok(Some(Box::new(DependencyVisibilityState {
        resolved_dependency_library_id,
        resolved_dependency_unit_id,
        resolved_dependency_local_index,
        resolved_dependency_value_library_id,
        resolved_dependency_value_unit_id,
        resolved_dependency_value_local_index,
        declaration_field_count: declaration_field_count.clone(),
        _retained_buffers: Box::new([
            count,
            prefix,
            total,
            owner_module,
            declaration,
            lookup,
            canonical_type_roots_a,
            canonical_type_roots_b,
            declaration_generic_arity,
            declaration_field_count,
        ]),
        scan,
        count_group,
        clear_workspace_group,
        scatter_group,
        clear_lookup_group,
        build_lookup_group,
        resolve_type_group,
        resolve_value_group,
        project_types_group,
        count_call_collection,
        scatter_call_collection,
        clear_lookup_call_collection,
        build_lookup_call_collection,
        resolve_type_call_collection,
        resolve_value_call_collection,
        project_types_after_clear,
        project_calls_group,
        clear_normalized_member_lookup,
        build_normalized_member_lookup,
        resolve_normalized_members,
        project_normalized_values,
        project_call_params_group,
        scatter_call_params_group,
        validate_call_arity_group,
        validate_call_args_group,
        validate_call_results_group,
        validate_call_results_validate,
        generic_call_results_resolve,
        type_index,
        type_index_module_paths,
        type_index_call_collection,
        type_index_after_type_clear,
        type_index_type_instance_projection,
        type_index_alias_targets,
        type_index_call_param_scatter,
        type_index_method_projection,
        type_index_method_lookup,
        type_index_return_materialization,
        type_index_call_validation,
        type_index_trait_contracts,
        project_type_instances_group,
        materialize_alias_targets_group,
        collect_methods_group,
        project_methods_group,
        project_struct_literals_group,
        _params: params,
        _type_params: type_params,
        _value_params: value_params,
        _canonical_type_params: canonical_type_params,
    })))
}
