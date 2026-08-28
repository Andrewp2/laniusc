use super::{super::*, buffers::Buffers, inputs::CreateInputs, layout::Layout};

/// Bind groups for module identity, import resolution, and import-cycle checks.
///
/// The module index maps canonical module keys, resolves imports into module ids, and
/// validates the import graph before declaration lookup consumes it.
pub(in crate::type_checker) struct ModuleIndex {
    pub(in crate::type_checker) scatter_module_records: ComputeOperation,
    pub(in crate::type_checker) module_record_params: LaniusBuffer<ModuleRecordScatterParams>,
    pub(in crate::type_checker) clear_module_lookup: ComputeOperation,
    pub(in crate::type_checker) build_module_keys: ComputeOperation,
    pub(in crate::type_checker) module_dispatch_params: LaniusBuffer<CountDispatchParams>,
    pub(in crate::type_checker) module_dispatch: ComputeOperation,
    pub(in crate::type_checker) validate_modules: ComputeOperation,
    pub(in crate::type_checker) clear_dependency_module_lookup: Option<ComputeOperation>,
    pub(in crate::type_checker) build_dependency_module_lookup: Option<ComputeOperation>,
    pub(in crate::type_checker) resolve_dependency_imports: Option<ComputeOperation>,
    pub(in crate::type_checker) clear_dependency_module_lookup_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) build_dependency_module_lookup_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) resolve_dependency_imports_call_collection:
        Option<ComputeInvocation>,
    pub(in crate::type_checker) scatter_import_records: ComputeOperation,
    pub(in crate::type_checker) resolve_imports: ComputeOperation,
    pub(in crate::type_checker) clear_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) build_import_edge_set: ComputeOperation,
    pub(in crate::type_checker) validate_import_cycles: ComputeOperation,
    pub(in crate::type_checker) module_lookup_params: LaniusBuffer<ModuleLookupParams>,
    pub(in crate::type_checker) import_resolve_params: LaniusBuffer<ImportResolveParams>,
    pub(in crate::type_checker) retained_params: Vec<LaniusBuffer<ModuleKeyRadixParams>>,
}

/// Creates bind groups for module indexing and import-edge validation.
pub(in crate::type_checker) fn create_module_index(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    layout: Layout,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<ModuleIndex> {
    let module_record_params = uniform_from_val(
        device,
        "type_check.modules.module_records.params",
        &ModuleRecordScatterParams {
            hir_node_capacity: inputs.hir_node_capacity,
            token_capacity: inputs.token_capacity,
            module_capacity: layout.module_capacity_u32,
            reserved: 0,
        },
    );
    let mut module_record_resources = resources.clone();
    module_record_resources.buffer("gParams", &module_record_params);
    // Module rows are a compaction scatter over the active dense-HIR domain.
    // Dispatching over the capacity here would reinterpret stale flag/prefix
    // rows beyond the current compact HIR as live records on daemon reuse.
    let scatter_module_records = ComputeOperation::indirect_spec(
        device,
        graph,
        &module_record_resources,
        passes,
        MODULE_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let module_lookup_params = uniform_from_val(
        device,
        "type_check.modules.module_lookup.params",
        &ModuleLookupParams {
            path_capacity: layout.record_capacity_u32,
            path_segment_capacity: inputs.token_capacity,
            module_capacity: layout.module_capacity_u32,
            reserved: 0,
        },
    );
    let mut module_lookup_resources = resources.clone();
    module_lookup_resources.buffer("gParams", &module_lookup_params);
    let clear_module_lookup = ComputeOperation::direct_spec(
        device,
        graph,
        &module_lookup_resources,
        passes,
        MODULE_LOOKUP_CLEAR,
        inputs.token_capacity.saturating_mul(2).max(1),
    )?;
    let build_module_keys = ComputeOperation::direct_spec(
        device,
        graph,
        &module_lookup_resources,
        passes,
        MODULE_KEYS_BUILD,
        layout.module_n_blocks.saturating_mul(256).max(1),
    )?;

    let module_dispatch_params = uniform_from_val(
        device,
        "type_check.modules.module_dispatch.params",
        &CountDispatchParams {
            capacity: layout.module_capacity_u32,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let mut module_dispatch_resources = resources.clone();
    module_dispatch_resources.buffer("gParams", &module_dispatch_params);
    let module_dispatch = ComputeOperation::direct_spec(
        device,
        graph,
        &module_dispatch_resources,
        passes,
        MODULE_DISPATCH,
        1,
    )?;

    let retained_params = Vec::with_capacity(5);

    let validate_modules = ComputeOperation::indirect_spec(
        device,
        graph,
        &module_lookup_resources,
        passes,
        MODULES_VALIDATE,
        &buffers.module_dispatch_args,
    )?;

    let scatter_import_records = ComputeOperation::indirect_spec(
        device,
        graph,
        resources,
        passes,
        IMPORT_RECORDS_SCATTER,
        inputs.hir_active_dispatch_args,
    )?;

    let resolve_import_params = uniform_from_val(
        device,
        "type_check.modules.resolve_imports.params",
        &ImportResolveParams {
            import_capacity: layout.import_record_capacity_u32,
            path_capacity: layout.record_capacity_u32,
            path_segment_capacity: inputs.token_capacity,
            module_capacity: layout.module_capacity_u32,
            dependency_interfaces_present: u32::from(inputs.dependency_interfaces.is_some()),
            reserved0: 0,
            reserved1: 0,
            reserved2: 0,
        },
    );
    let mut resolve_resources = resources.clone();
    resolve_resources.buffer("gParams", &resolve_import_params);
    resolve_resources.alias("path_prefix_id", "path_prefix_id_a")?;
    let resolve_imports = ComputeOperation::indirect_spec(
        device,
        graph,
        &resolve_resources,
        passes,
        RESOLVE_IMPORTS,
        &buffers.import_dispatch_args,
    )?;

    let dependency_module_params = inputs.dependency_interfaces.map(|dependencies| {
        uniform_from_val(
            device,
            "type_check.dependencies.module_params",
            &DependencyInterfaceModuleParams {
                module_count: dependencies.module_count,
                lookup_capacity: dependencies.module_lookup_capacity,
                import_capacity: layout.import_record_capacity_u32,
                source_len: inputs.source_len,
            },
        )
    });
    let dependency_operation_resources = dependency_module_params.as_ref().map(|params| {
        let mut resources = resources.clone();
        resources.buffer("gParams", params);
        resources
    });
    let build_dependency_module_lookup = match (
        inputs.dependency_interfaces,
        dependency_operation_resources.as_ref(),
    ) {
        (Some(dependencies), Some(resources)) => Some(ComputeOperation::direct_spec(
            device,
            graph,
            resources,
            passes,
            DEPENDENCY_MODULE_LOOKUP_BUILD,
            dependencies.module_count.max(1),
        )?),
        _ => None,
    };
    let clear_dependency_module_lookup = match (
        inputs.dependency_interfaces,
        dependency_operation_resources.as_ref(),
    ) {
        (Some(dependencies), Some(resources)) => Some(ComputeOperation::direct_spec(
            device,
            graph,
            resources,
            passes,
            DEPENDENCY_MODULE_LOOKUP_CLEAR,
            dependencies.module_lookup_capacity.max(1),
        )?),
        _ => None,
    };
    let resolve_dependency_imports = match (
        inputs.dependency_interfaces,
        dependency_operation_resources.as_ref(),
        buffers.import_target_dependency_module_id.as_ref(),
    ) {
        (Some(_), Some(resources), Some(_)) => Some(ComputeOperation::indirect_spec(
            device,
            graph,
            resources,
            passes,
            DEPENDENCY_IMPORTS_RESOLVE,
            &buffers.import_dispatch_args,
        )?),
        _ => None,
    };
    let clear_dependency_module_lookup_call_collection = clear_dependency_module_lookup
        .as_ref()
        .map(|operation| {
            operation.invocation(graph, DEPENDENCY_PAGE_CALL_COLLECTION.clear_module_lookup)
        })
        .transpose()?;
    let build_dependency_module_lookup_call_collection = build_dependency_module_lookup
        .as_ref()
        .map(|operation| {
            operation.invocation(graph, DEPENDENCY_PAGE_CALL_COLLECTION.build_module_lookup)
        })
        .transpose()?;
    let resolve_dependency_imports_call_collection = resolve_dependency_imports
        .as_ref()
        .map(|operation| {
            operation.invocation(graph, DEPENDENCY_PAGE_CALL_COLLECTION.resolve_imports)
        })
        .transpose()?;

    let mut import_edge_resources = resources.clone();
    import_edge_resources.buffer("gParams", &resolve_import_params);
    let clear_import_edge_set = ComputeOperation::direct_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_EDGE_SET_CLEAR,
        layout.import_record_capacity_u32.saturating_mul(2).max(1),
    )?;
    let build_import_edge_set = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_EDGE_SET_BUILD,
        &buffers.import_dispatch_args,
    )?;
    let validate_import_cycles = ComputeOperation::indirect_spec(
        device,
        graph,
        &import_edge_resources,
        passes,
        IMPORT_CYCLES_VALIDATE,
        &buffers.import_dispatch_args,
    )?;

    Ok(ModuleIndex {
        scatter_module_records,
        module_record_params,
        clear_module_lookup,
        build_module_keys,
        module_dispatch_params,
        module_dispatch,
        validate_modules,
        clear_dependency_module_lookup,
        build_dependency_module_lookup,
        resolve_dependency_imports,
        clear_dependency_module_lookup_call_collection,
        build_dependency_module_lookup_call_collection,
        resolve_dependency_imports_call_collection,
        scatter_import_records,
        resolve_imports,
        clear_import_edge_set,
        build_import_edge_set,
        validate_import_cycles,
        module_lookup_params,
        import_resolve_params: resolve_import_params,
        retained_params,
    })
}
